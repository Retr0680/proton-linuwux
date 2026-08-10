/*
 * LinUwUx hooks for Wine ntdll Unix signal handling.
 *
 * Original LinUwUx patch by LinUwUx.
 * Robustness and compatibility rework by xshaduwulfx
 * for the Proton LinUwUx project.
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

#ifndef LINUWUX_HOOKS_INCLUDED
#define LINUWUX_HOOKS_INCLUDED

/* This will point to the game's memory region where syscall spoofing is happening. */
uint64_t TargetSysHandler = 0;
uint64_t SyscallBypassMagic = 0x1337133713371337;

/* Spoofed CPUID values - set based on CPU vendor. */
static unsigned int spoof_leaf40000000_eax;
static unsigned int spoof_leaf40000000_ebx;
static unsigned int spoof_leaf40000000_ecx;
static unsigned int spoof_leaf40000000_edx;

static unsigned int spoof_leaf40000001_eax;
static unsigned int spoof_leaf40000001_ebx;
static unsigned int spoof_leaf40000001_ecx;
static unsigned int spoof_leaf40000001_edx;

static unsigned int spoof_leaf1_eax;
static unsigned int spoof_leaf1_ebx;
static unsigned int spoof_leaf1_ecx;
static unsigned int spoof_leaf1_edx;

/**
 * Patch KUSER_SHARED_DATA with spoofed values.
 */
static void patch_kuser_shared_data(void)
{
    UINT8 *kuser = (UINT8 *)0x000000007FFE0000UL;

    /* Make memory writable. */
    size_t page_size = sysconf(_SC_PAGESIZE);
    void *page_start = (void *)((uintptr_t)0x000000007FFE0000UL & ~(page_size - 1));

    if (mprotect(page_start, page_size, PROT_READ | PROT_WRITE) == -1)
    {
        MESSAGE("Failed to make kuser_shared_data writable: %s\n", strerror(errno));
        return;
    }

    memcpy((void *)(kuser + 0x30),
           "\x43\x00\x3A\x00\x5C\x00\x57\x00\x69\x00\x6E\x00\x64\x00\x6F\x00"
           "\x77\x00\x73\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
           "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
           "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
           "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
           "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
           "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
           "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
           "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
           "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
           "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
           "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
           "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
           "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
           "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
           "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
           "\x00\x00\x00\x00",
           0x104);

    *(UINT64 *)(kuser + 0x260) = 0x0100006658;
    *(UINT32 *)(kuser + 0x268) = 0x090001;
    *(UINT32 *)(kuser + 0x26C) = 0x0A;
    *(UINT32 *)(kuser + 0x270) = 0x00;

    /* ProcessorFeatures */
    *(UINT32 *)(kuser + 0x274) = 0x01010000;
    *(UINT32 *)(kuser + 0x278) = 0x010000;
    *(UINT32 *)(kuser + 0x27C) = 0x010101;
    *(UINT32 *)(kuser + 0x280) = 0x010101;
    *(UINT32 *)(kuser + 0x284) = 0x0100;
    *(UINT32 *)(kuser + 0x288) = 0x01010101;
    *(UINT32 *)(kuser + 0x28C) = 0x0;
    *(UINT32 *)(kuser + 0x290) = 0x01;
    *(UINT32 *)(kuser + 0x294) = 0x01000101;
    *(UINT32 *)(kuser + 0x298) = 0x01010101;
    *(UINT32 *)(kuser + 0x29C) = 0x010001;
    *(UINT32 *)(kuser + 0x2A0) = 0x0;
    *(UINT32 *)(kuser + 0x2A4) = 0x0;
    *(UINT32 *)(kuser + 0x2A8) = 0x0;
    *(UINT32 *)(kuser + 0x2AC) = 0x0;
    *(UINT32 *)(kuser + 0x2B0) = 0x1;

    /* Disable specific features (byte-level patches). */
    *(UINT8 *)(kuser + 0x290) = 0x0; /* Disable MONITORX support */
    *(UINT8 *)(kuser + 0x294) = 0x0; /* Disable RDTSCP support */
    *(UINT8 *)(kuser + 0x295) = 0x0; /* Disable RDPID support */
    *(UINT8 *)(kuser + 0x297) = 0x0; /* Disable RDRAND support */

    if (getenv("PROTON_AVX") == NULL ||
        (getenv("PROTON_AVX") != NULL && strcmp(getenv("PROTON_AVX"), "1")) != 0)
    {
        /* XSAVE related stuff */
        *(UINT8 *)(kuser + 0x285) = 0x0; /* Disable XSAVE support */
        *(UINT8 *)(kuser + 0x29B) = 0x0; /* Disable AVX support */
        *(UINT8 *)(kuser + 0x29C) = 0x0; /* Disable AVX2 support */
    }

    *(UINT64 *)(kuser + 0x3D8) = 0x0; /* EnabledFeatures */
    *(UINT64 *)(kuser + 0x3E0) = 0x0; /* EnabledVolatileFeatures */
    *(UINT32 *)(kuser + 0x3EC) = 0x0; /* ControlFlags */
    memset((void *)(kuser + 0x3F0), 0x00, 0x200); /* Features */
    *(UINT64 *)(kuser + 0x5F0) = 0x0; /* EnabledSupervisorFeatures */
    *(UINT64 *)(kuser + 0x5F8) = 0x0; /* AlignedFeatures */
    memset((void *)(kuser + 0x604), 0x00, 0x200); /* AllFeatures */
    *(UINT64 *)(kuser + 0x808) = 0x0; /* EnabledUserVisibleSupervisorFeatures */
    *(UINT64 *)(kuser + 0x810) = 0x0; /* ExtendedFeatureDisableFeatures */

    *(UINT64 *)(kuser + 0x2D0) = 0x320A0000000110;
    *(UINT64 *)(kuser + 0x2E8) = 0x0100007FB10B;
    *(UINT32 *)(kuser + 0x2F4) = 0x0;
    *(UINT64 *)(kuser + 0x36C) = 0x0;
    *(UINT64 *)(kuser + 0x374) = 0x0;
    *(UINT32 *)(kuser + 0x37C) = 0x1;
    *(UINT64 *)(kuser + 0x3C0) = 0x83000100000010;

    *(UINT32 *)(kuser + 0xFFC) = 0x13371337;

    /* Patch usage of syscalls:
     * 0 = syscalls take slow route, everything gets hooked
     * 1 = syscalls take fast route unless ntdll.dll gets modified (default)
     */
    /* kuser[0x308] = 1; */
}

/*
 * Detect the host CPU vendor and initialize spoofed CPUID values.
 */
static void detect_cpu_vendor(void)
{
    unsigned int eax, ebx, ecx, edx;
    int avx = 0;

    if (getenv("PROTON_AVX") != NULL &&
        strcmp(getenv("PROTON_AVX"), "1") == 0)
        avx = 1;

    __asm__ volatile(
        "cpuid"
        : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx)
        : "a"(0)
        : "memory"
    );

    if (ebx == 0x756E6547 && edx == 0x49656E69 && ecx == 0x6C65746E)
    {
        /* GenuineIntel */
        spoof_leaf1_eax = 0x000A0655;
        spoof_leaf1_ebx = 0x00200800;

        if (avx)
            spoof_leaf1_ecx = 0x7BFAFBFF;
        else
            spoof_leaf1_ecx = 0x01FAEBFF;

        spoof_leaf1_edx = 0xBFEBFBFF;

        spoof_leaf40000000_eax = 0x40000001;
        spoof_leaf40000000_ebx = 0x65707948;
        spoof_leaf40000000_ecx = 0x67624472;
        spoof_leaf40000000_edx = 0;

        spoof_leaf40000001_eax = 0x30237648;
        spoof_leaf40000001_ebx = 0;
        spoof_leaf40000001_ecx = 0;
        spoof_leaf40000001_edx = 0;
    }
    else if (ebx == 0x68747541 && edx == 0x69746E65 && ecx == 0x444D4163)
    {
        /* AuthenticAMD */
        spoof_leaf1_eax = 0x00A20F12;
        spoof_leaf1_ebx = 0x00100800;

        if (avx)
            spoof_leaf1_ecx = 0x7AD8320B;
        else
            spoof_leaf1_ecx = 0x00F8220B;

        spoof_leaf1_edx = 0x178BFBFF;

        spoof_leaf40000000_eax = 0x40000001;
        spoof_leaf40000000_ebx = 0x706D6953;
        spoof_leaf40000000_ecx = 0x7653656C;
        spoof_leaf40000000_edx = 0x2020206D;

        spoof_leaf40000001_eax = 0x30237648;
        spoof_leaf40000001_ebx = 0;
        spoof_leaf40000001_ecx = 0;
        spoof_leaf40000001_edx = 0;
    }

    /* Sorry Zhaoxin/Hygon CPU owners :( */
}

static int linuwux_handle_cpuid(siginfo_t *siginfo, ucontext_t *ucontext)
{
    unsigned int leaf;
    unsigned int subleaf;
    unsigned char *rip;

    rip = (unsigned char *)ucontext->uc_mcontext.gregs[REG_RIP];
    leaf = ucontext->uc_mcontext.gregs[REG_RAX];
    subleaf = ucontext->uc_mcontext.gregs[REG_RCX];

    if ((siginfo->si_code == SI_KERNEL || leaf == 0x336933) &&
        rip[0] == 0x0f && rip[1] == 0xa2)
    {
        switch (leaf)
        {
            case 1:
                ucontext->uc_mcontext.gregs[REG_RAX] = spoof_leaf1_eax;
                ucontext->uc_mcontext.gregs[REG_RBX] = spoof_leaf1_ebx;
                ucontext->uc_mcontext.gregs[REG_RCX] =
                spoof_leaf1_ecx | (TargetSysHandler ? 0 : (0x1 << 31));
                ucontext->uc_mcontext.gregs[REG_RDX] = spoof_leaf1_edx;
                break;

            case 0x40000000:
                ucontext->uc_mcontext.gregs[REG_RAX] = spoof_leaf40000000_eax;
                ucontext->uc_mcontext.gregs[REG_RBX] = spoof_leaf40000000_ebx;
                ucontext->uc_mcontext.gregs[REG_RCX] = spoof_leaf40000000_ecx;
                ucontext->uc_mcontext.gregs[REG_RDX] = spoof_leaf40000000_edx;
                break;

            case 0x40000001:
                ucontext->uc_mcontext.gregs[REG_RAX] = spoof_leaf40000001_eax;
                ucontext->uc_mcontext.gregs[REG_RBX] = spoof_leaf40000001_ebx;
                ucontext->uc_mcontext.gregs[REG_RCX] = spoof_leaf40000001_ecx;
                ucontext->uc_mcontext.gregs[REG_RDX] = spoof_leaf40000001_edx;
                break;

            case 0x80000002:
                ucontext->uc_mcontext.gregs[REG_RAX] = 0x756E6544;
                ucontext->uc_mcontext.gregs[REG_RBX] = 0x4F774F76;
                ucontext->uc_mcontext.gregs[REG_RCX] = 0x55504320;
                ucontext->uc_mcontext.gregs[REG_RDX] = 0x31204020;
                break;

            case 0x80000003:
                ucontext->uc_mcontext.gregs[REG_RAX] = 0x20373333;
                ucontext->uc_mcontext.gregs[REG_RBX] = 0x007A4847;
                ucontext->uc_mcontext.gregs[REG_RCX] = 0x00000000;
                ucontext->uc_mcontext.gregs[REG_RDX] = 0x00000000;
                break;

            case 0x80000004:
                ucontext->uc_mcontext.gregs[REG_RAX] = 0x0;
                ucontext->uc_mcontext.gregs[REG_RBX] = 0x0;
                ucontext->uc_mcontext.gregs[REG_RCX] = 0x0;
                ucontext->uc_mcontext.gregs[REG_RDX] = 0x0;
                break;

            case 0x336933:
                MESSAGE("Spoofing CPUID leaf %x\n", leaf);
                TargetSysHandler = ucontext->uc_mcontext.gregs[REG_RCX];
                patch_kuser_shared_data();
                ucontext->uc_mcontext.gregs[REG_RAX] = 0x0;
                ucontext->uc_mcontext.gregs[REG_RBX] = 0x0;
                ucontext->uc_mcontext.gregs[REG_RCX] = 0x0;
                ucontext->uc_mcontext.gregs[REG_RDX] = 0x0;
                break;

            case 0x336967:
                MESSAGE("Setting Faketime to %llx... \n",
                        ucontext->uc_mcontext.gregs[REG_RCX]);
                SERVER_START_REQ( set_faketime )
                {
                    req->faketime = ucontext->uc_mcontext.gregs[REG_RCX];
                    wine_server_call( req );
                }
                SERVER_END_REQ;
                ucontext->uc_mcontext.gregs[REG_RAX] = 0x0;
                ucontext->uc_mcontext.gregs[REG_RBX] = 0x0;
                ucontext->uc_mcontext.gregs[REG_RCX] = 0x0;
                ucontext->uc_mcontext.gregs[REG_RDX] = 0x0;
                break;

            default:
                syscall(SYS_arch_prctl, ARCH_SET_CPUID, 1);

                __asm__ volatile(
                    "cpuid"
                    : "=a"(ucontext->uc_mcontext.gregs[REG_RAX]),
                                 "=b"(ucontext->uc_mcontext.gregs[REG_RBX]),
                                 "=c"(ucontext->uc_mcontext.gregs[REG_RCX]),
                                 "=d"(ucontext->uc_mcontext.gregs[REG_RDX])
                                 : "a"(leaf), "c"(subleaf)
                                 : "memory"
                );

                syscall(SYS_arch_prctl, ARCH_SET_CPUID, 0);
                break;
        }

        ucontext->uc_mcontext.gregs[REG_RIP] += 2;
        return 1;
    }

    return 0;
}

#endif /* LINUWUX_HOOKS_INCLUDED */
