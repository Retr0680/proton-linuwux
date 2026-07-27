# Proton-LinUwUx

Custom Proton builds patched with "LinUwUx.patch" from **cs.rin.ru**: [A Hypervisor(-less) Denuvo bypass for Linux](https://cs.rin.ru/forum/viewtopic.php?f=10&t=159989).

## Features

- **Proton-CachyOS** latest x86_64 builds patched in order to make HV bypass working on Linux.
- **Proton-GE** latest x86_64 builds patched in order to make HV bypass working on Linux.

**NO additional performance tweaking nor other changes have been done apart LinUwUx's patching!**

## Downloads

Grab the latest patched builds from the [Releases](../../releases) section.

## Credits

- **LinUwUx Team**
- **DenuvOwO Team**
- **GloriousEggroll**
- **CachyOS Team**
- **Valve** (Proton)

## FAQ

**How do I install these Proton builds?**

Download the archive from the Releases section and extract it to your Steam compatibility folder (usually ~/.steam/root/compatibilitytools.d/). Restart Steam.

**What is the difference between Proton-CachyOS and Proton-GE?**

Both are patched for the HV bypass, but they are based on different underlying upstream projects (CachyOS builds or Proton-GE).

**Do these work on immutable distros (like Steam Deck, Fedora Silverblue, Bazzite)?**

Yes, but since the root file system is read-only, you must place the compatibility tool inside your home directory (~/.steam/root/compatibilitytools.d/ or ~/.local/share/Steam/compatibilitytools.d/). Do not try to write to /usr/share/steam.

**Does the hypervisor bypass work on ARM devices?**

No. Translators like FEX-Emu lack cpuid_fault support and only handle user-mode instructions. Denuvo also checks things that emulators cannot spoof, like floating point division accuracy. ARM users should look into traditional cracks or offline activations instead.

**Does it work with all Denuvo games?**

The goal is to bypass Hypervisor checks, but compatibility depends on the specific game and Denuvo updates. Check the original thread on cs.rin.ru and the specific game threads to see if an hypervisor crack is available for them.

**Is there a risk of getting banned?**

Use these patches at your own risk. Modifying Proton files or bypassing anti-tamper systems can violate Steam's Terms of Service.
