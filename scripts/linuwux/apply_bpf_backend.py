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
# 2. Make the LinUwUx SIGSYS handler compatible with legacy BPF.
#
# GE/Proton's SUD patch stack has existed in variants both with
# and without the !syscall_dispatch_enabled retry fallback.
# LinUwUx disables SUD globally, so that fallback must never
# survive in the BPF-transformed handler: retrying the trapped
# syscall would simply trigger SIGSYS again forever.
#
# The legacy install_bpf() probe uses syscall 0xffff and expects
# the SIGSYS handler to return STATUS_INVALID_PARAMETER when a
# seccomp filter is already active.
# ------------------------------------------------------------

linuwux_sigsys_anchor = "if (linuwux_handle_sigsys(sigcontext))"

if s.count(linuwux_sigsys_anchor) != 1:
    fail(
        "expected exactly one LinUwUx SIGSYS handler anchor, "
        f"found {s.count(linuwux_sigsys_anchor)}"
    )

handler_pos = s.find(linuwux_sigsys_anchor)
handler_start = s.rfind("static void sigsys_handler(", 0, handler_pos)

if handler_start == -1:
    fail("could not locate LinUwUx sigsys_handler start")

handler_end_anchor = "\n}\n"
handler_end = s.find(handler_end_anchor, handler_pos)

if handler_end == -1:
    fail("could not locate LinUwUx sigsys_handler end")

handler_end += len(handler_end_anchor)
handler = s[handler_start:handler_end]

# Old SUD behaviour is invalid once LinUwUx switches the backend
# to legacy seccomp/BPF.  Do not remove the surrounding Linux
# preprocessor guard because it also contains the EOS workaround.
stale_sud_fallback = """    if (!syscall_dispatch_enabled)
    {
        prctl( PR_SET_SYSCALL_USER_DISPATCH, PR_SYS_DISPATCH_OFF, 0, 0, 0 );
        RIP_sig(ucontext) -= 2;  /* retry the syscall */
        return;
    }

"""

stale_count = handler.count(stale_sud_fallback)

if stale_count > 1:
    fail(
        "expected at most one stale SUD SIGSYS fallback, "
        f"found {stale_count}"
    )

if stale_count == 1:
    handler = handler.replace(stale_sud_fallback, "", 1)

probe = """    if (RAX_sig(ucontext) == 0xffff)
    {
        /* Test syscall from the Unix side (install_bpf). */
        RAX_sig(ucontext) = STATUS_INVALID_PARAMETER;
        return;
    }
"""

eos_anchor = (
    "    /* HACK: The EOS version of easy anti cheat executes linux syscalls"
)

if handler.count(eos_anchor) != 1:
    fail(
        "expected exactly one EOS syscall workaround anchor, "
        f"found {handler.count(eos_anchor)}"
    )

probe_count = handler.count(probe)

if probe_count == 0:
    # The probe belongs inside the existing Linux block, directly
    # before the EOS workaround.  Preserve that guard rather than
    # manufacturing a second #ifdef/#endif pair.
    linux_eos_anchor = "#ifdef __linux__\n" + eos_anchor

    if handler.count(linux_eos_anchor) != 1:
        fail(
            "expected Linux EOS block immediately after SUD fallback "
            "removal"
        )

    handler = handler.replace(
        linux_eos_anchor,
        "#ifdef __linux__\n" + probe + "\n" + eos_anchor,
        1,
    )

elif probe_count != 1:
    fail(
        "expected at most one legacy BPF 0xffff probe, "
        f"found {probe_count}"
    )

if "if (!syscall_dispatch_enabled)" in handler:
    fail("stale SUD retry fallback remained in LinUwUx sigsys_handler")

if handler.count("RAX_sig(ucontext) == 0xffff") != 1:
    fail("LinUwUx sigsys_handler does not contain exactly one 0xffff probe")

if handler.count("RAX_sig(ucontext) = STATUS_INVALID_PARAMETER;") != 1:
    fail(
        "LinUwUx sigsys_handler does not contain exactly one "
        "STATUS_INVALID_PARAMETER probe result"
    )

if "linuwux_handle_sigsys(sigcontext)" not in handler:
    fail("LinUwUx SIGSYS hook disappeared during BPF conversion")

if "__wine_syscall_dispatcher_prolog_end_ptr" not in handler:
    fail("normal Wine syscall dispatcher redirect disappeared")

# Verify topology: probe and EOS must remain together inside the
# same existing Linux preprocessor block.
probe_pos = handler.find(probe)
eos_pos = handler.find(eos_anchor)
linux_pos = handler.rfind("#ifdef __linux__", 0, probe_pos)
linux_end = handler.find("#endif", eos_pos)

if linux_pos == -1 or linux_end == -1:
    fail("legacy BPF probe/EOS Linux guard is incomplete")

if not (linux_pos < probe_pos < eos_pos < linux_end):
    fail("legacy BPF probe and EOS workaround are not in the same Linux block")

s = s[:handler_start] + handler + s[handler_end:]


# ------------------------------------------------------------
# 3. Add Wine's legacy seccomp/BPF syscall trapping backend.
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
# 4. Install BPF at the end of signal_init_process().
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
# 5. Sanity checks.
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
    "LinUwUx SIGSYS hook": "linuwux_handle_sigsys(sigcontext)",
    "legacy BPF probe": "RAX_sig(ucontext) == 0xffff",
    "legacy BPF probe result": "RAX_sig(ucontext) = STATUS_INVALID_PARAMETER;",
}

for name, needle in checks.items():
    if needle not in s:
        fail(f"LinUwUx BPF transformation missing: {name}")

if "static LONG syscall_dispatch_enabled = TRUE;" in s:
    fail("SUD enable anchor remained after transformation")

if "LINUWUX_SKIP_BPF_BOOTSTRAP" in s:
    fail("diagnostic BPF bootstrap bypass remained after transformation")

p.write_text(s)
