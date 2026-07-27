# Proton-LinUwUx

Custom Proton builds patched with "**LinUwUx.patch**" from [cs.rin.ru](https://cs.rin.ru/forum/viewtopic.php?f=10&t=159989).

## Features

- **Proton-CachyOS** latest x86_64 builds patched in order to make HV bypass working on Linux.
- **Proton-GE** latest x86_64 builds patched in order to make HV bypass working on Linux.

**NO additional performance tweaking nor other changes have been done apart LinUwUx's patching!**

## Downloads

Grab the latest patched builds from the [Releases](../../releases) section.

## FAQ

### How do I install and use these Proton builds?

- **On Steam:**
  1. Extract the builds to your Steam compatibility folder (`~/.steam/root/compatibilitytools.d/`, `~/.local/share/Steam/compatibilitytools.d/` or `~/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d/`).
  2. Restart Steam.
  3. Right-click your game, go to **Properties > Compatibility**, check **Force the use of a specific Steam Play compatibility tool**, and select your build.

- **On Faugus Launcher:**
  1. Extract the builds to the same Steam compatibility folder as above.
  2. If using the Flatpak version of Faugus, open **Flatseal**, select Faugus, go to **Filesystems > Other files**, and add the path where you extracted the builds.
  3. Open `~/.var/app/io.github.Faugus.faugus-launcher/data/faugus-launcher/games.json`, find your game, locate `"runner"`, and paste the absolute path to your custom Proton folder inside the quotes. (Remember to repeat this step each time you add a new game or modify launch options both for new and already existing games).

### What is the difference between Proton-CachyOS and Proton-GE?
Both are patched for the HV bypass, but they are based on different underlying upstream projects (CachyOS builds or Proton-GE). 

### Do these work on immutable distros (like Steam Deck, Fedora Silverblue, Bazzite)?
Yes, but since the root file system is read-only, you must place the compatibility tool inside your home directory (`~/.steam/root/compatibilitytools.d/`, `~/.local/share/Steam/compatibilitytools.d/` or `~/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d/`). Do not try to write to `/usr/share/steam`.

### Does the hypervisor bypass work on ARM devices?
No. Translators like FEX-Emu lack `cpuid_fault` support and only handle user-mode instructions. Denuvo also checks things that emulators cannot spoof, like floating point division accuracy. ARM users should look into traditional cracks or offline activations instead.

### Does it work with all Denuvo games?
The goal is to bypass Hypervisor checks, but compatibility depends on the specific game and Denuvo updates. Check the original thread on [cs.rin.ru](https://cs.rin.ru/forum/viewtopic.php?f=10&t=159989) and the specific game threads to see if an hypervisor crack is available for them.

### Is there a risk of getting banned?
Use these patches at your own risk. Modifying Proton files or bypassing anti-tamper systems can violate Steam's Terms of Service.

## Credits

- **LinUwUx Team**
- **DenuvOwO Team**
- **GloriousEggroll**
- **CachyOS Team**
- **Valve** (Proton)
