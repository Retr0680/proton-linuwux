#!/usr/bin/env python3

from pathlib import Path
import sys


def fail(message):
    raise SystemExit(f"Error: {message}")


if len(sys.argv) != 2:
    fail("usage: apply_bpf_backend.py <signal_x86_64.c>")

p = Path(sys.argv[1])

if not p.is_file():
    fail(f"file not found: {p}")

s = p.read_text()


# ------------------------------------------------------------
# 1. Disable SUD and add legacy seccomp/BPF headers.
# ------------------------------------------------------------

sud_anchor = "static LONG syscall_dispatch_enabled = TRUE;"

if s.count(sud_anchor) != 1:
    fail(
        "expected exactly one SUD enable anchor, "
        f"found {s.count(sud_anchor)}"
    )

headers_and_backend = """#ifdef __linux__
# include <fcntl.h>
# include <linux/filter.h>
# include <linux/seccomp.h>
# include <linux/audit.h>
#endif

static LONG syscall_dispatch_enabled = FALSE; /* LinUwUx uses legacy seccomp/BPF */
"""

s = s.replace(sud_anchor, headers_and_backend, 1)


# ------------------------------------------------------------
# 2. Add Wine's legacy seccomp/BPF syscall trapping backend.
# ------------------------------------------------------------

process_anchor = "void signal_init_process(void)"

if s.count(process_anchor) != 1:
    fail(
        "expected exactly one signal_init_process anchor, "
        f"found {s.count(process_anchor)}"
    )

if "static void install_bpf(struct sigaction *sig_act)" in s:
    fail("install_bpf is already present")

bpf_backend = r"""#ifdef __linux__
#ifndef NATIVE_SYSCALL_ADDRESS_START
#define NATIVE_SYSCALL_ADDRESS_START 0x700000000000
#endif

static int sc_seccomp(unsigned int operation, unsigned int flags, void *args)
{
#ifndef __NR_seccomp
#   define __NR_seccomp 317
#endif
    return syscall(__NR_seccomp, operation, flags, args);
}
#endif

static void check_bpf_jit_enable(void)
{
    char enabled;
    int fd;

    fd = open("/proc/sys/net/core/bpf_jit_enable", O_RDONLY);
    if (fd == -1)
    {
        WARN_(seh)("Could not open /proc/sys/net/core/bpf_jit_enable.\n");
        return;
    }

    if (read(fd, &enabled, sizeof(enabled)) == sizeof(enabled))
    {
        TRACE_(seh)("enabled %#x.\n", enabled);

        if (enabled != '1')
            ERR_(seh)("BPF JIT is not enabled in the kernel, enable it to reduce syscall emulation overhead.\n");
    }
    else
    {
        WARN_(seh)("Could not read /proc/sys/net/core/bpf_jit_enable.\n");
    }
    close(fd);
}

static void install_bpf(struct sigaction *sig_act)
{
#ifdef __linux__
#   ifndef SECCOMP_FILTER_FLAG_SPEC_ALLOW
#       define SECCOMP_FILTER_FLAG_SPEC_ALLOW (1UL << 2)
#   endif

#   ifndef SECCOMP_SET_MODE_FILTER
#       define SECCOMP_SET_MODE_FILTER 1
#   endif

    static const BYTE syscall_trap_test[] =
    {
        0x48, 0x89, 0xf8,   /* mov %rdi, %rax */
        0x0f, 0x05,         /* syscall */
        0xc3,               /* retq */
    };
    static const unsigned int flags = SECCOMP_FILTER_FLAG_SPEC_ALLOW;

    static struct sock_filter filter[] =
    {
        /* Allow i386. */
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
        BPF_JUMP (BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_X86_64, 1, 0),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),

        /* Native libs are loaded at high addresses. */
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, instruction_pointer) + 4),
        BPF_JUMP(BPF_JMP | BPF_JGT | BPF_K, NATIVE_SYSCALL_ADDRESS_START >> 32, 0, 8),

        /* High addresses may be top-down allocations, trap those */
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, 0x7fff, 1, 0),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, instruction_pointer)),
        BPF_JUMP(BPF_JMP | BPF_JGE | BPF_K, 0xfe000000, 1, 0),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
        BPF_JUMP(BPF_JMP | BPF_JGE | BPF_K, 0xffff0000, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_TRAP),

        /* Allow wine64-preloader */
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, instruction_pointer)),
        BPF_JUMP(BPF_JMP | BPF_JGE | BPF_K, 0x7d400000, 1, 0),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_TRAP),
        BPF_JUMP(BPF_JMP | BPF_JGE | BPF_K, 0x7d402000, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_TRAP),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };

    long (*test_syscall)(long sc_number);
    struct sock_fprog prog;
    NTSTATUS status;

    if ((ULONG_PTR)sc_seccomp < NATIVE_SYSCALL_ADDRESS_START
            || (ULONG_PTR)syscall < NATIVE_SYSCALL_ADDRESS_START)
    {
        ERR_(seh)("Native libs are being loaded in low addresses, sc_seccomp %p, syscall %p, not installing seccomp.\n",
                sc_seccomp, syscall);
        ERR_(seh)("The known reasons are /proc/sys/vm/legacy_va_layout set to 1 or 'ulimit -s' being 'unlimited'.\n");
        return;
    }

    sig_act->sa_sigaction = sigsys_handler;
    memset(&prog, 0, sizeof(prog));

    sigaction(SIGSYS, sig_act, NULL);

    test_syscall = mmap((void *)0x600000000000, 0x1000,
            PROT_EXEC | PROT_READ | PROT_WRITE,
            MAP_FIXED_NOREPLACE | MAP_PRIVATE | MAP_ANON, -1, 0);

    if (test_syscall != (void *)0x600000000000)
    {
        int ret;

        ERR("Could not allocate test syscall, falling back to seccomp presence check, test_syscall %p, errno %d.\n",
                test_syscall, errno);

        if (test_syscall != MAP_FAILED)
            munmap(test_syscall, 0x1000);

        if ((ret = prctl(PR_GET_SECCOMP, 0, NULL, 0, 0)))
        {
            if (ret == 2)
                TRACE_(seh)("Seccomp filters already installed.\n");
            else
                ERR_(seh)("Seccomp filters cannot be installed, ret %d, error %s.\n",
                        ret, strerror(errno));
            return;
        }
    }
    else
    {
        memcpy(test_syscall, syscall_trap_test, sizeof(syscall_trap_test));
        status = test_syscall(0xffff);
        munmap(test_syscall, 0x1000);

        if (status == STATUS_INVALID_PARAMETER)
        {
            TRACE_(seh)("Seccomp filters already installed.\n");
            return;
        }

        if (status != -ENOSYS && (status != -1 || errno != ENOSYS))
        {
            ERR_(seh)("Unexpected status %#x, errno %d.\n", status, errno);
            return;
        }
    }

    TRACE_(seh)("Installing seccomp filters.\n");

    prog.len = ARRAY_SIZE(filter);
    prog.filter = filter;

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0))
    {
        ERR_(seh)("prctl(PR_SET_NO_NEW_PRIVS, ...): %s.\n", strerror(errno));
        return;
    }

    if (sc_seccomp(SECCOMP_SET_MODE_FILTER, flags, &prog))
    {
        ERR_(seh)("prctl(PR_SET_SECCOMP, ...): %s.\n", strerror(errno));
        return;
    }

    check_bpf_jit_enable();
#else
    WARN_(seh)("Built without seccomp.\n");
#endif
}

"""

s = s.replace(process_anchor, bpf_backend + process_anchor, 1)


# ------------------------------------------------------------
# 3. Install BPF at the end of signal_init_process().
# ------------------------------------------------------------

start = s.find(process_anchor)

if start == -1:
    fail("signal_init_process disappeared after BPF insertion")

return_anchor = "\n    return;\n\n error:\n"
return_count = s.count(return_anchor, start)

if return_count != 1:
    fail(
        "expected exactly one final return/error anchor "
        f"in signal_init_process, found {return_count}"
    )

return_pos = s.find(return_anchor, start)

install_call = """
#ifdef __linux__
    install_bpf(&sig_act);
#endif
"""

s = s[:return_pos] + install_call + s[return_pos:]


# ------------------------------------------------------------
# 4. Sanity checks.
# ------------------------------------------------------------

checks = {
    "native syscall address": "#define NATIVE_SYSCALL_ADDRESS_START 0x700000000000",
    "fcntl header": "# include <fcntl.h>",
    "seccomp header": "# include <linux/seccomp.h>",
    "BPF header": "# include <linux/filter.h>",
    "audit header": "# include <linux/audit.h>",
    "SUD disabled": "static LONG syscall_dispatch_enabled = FALSE;",
    "sc_seccomp": "static int sc_seccomp(unsigned int operation",
    "install_bpf": "static void install_bpf(struct sigaction *sig_act)",
    "install_bpf call": "install_bpf(&sig_act);",
}

for name, needle in checks.items():
    if needle not in s:
        fail(f"LinUwUx BPF transformation missing: {name}")

if "static LONG syscall_dispatch_enabled = TRUE;" in s:
    fail("SUD enable anchor remained after transformation")

p.write_text(s)
