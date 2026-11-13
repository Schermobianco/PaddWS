[<img src="../../docs/flags/it.svg" alt="" height="14"> Italiano](README.md) · [<img src="../../docs/flags/gb.svg" alt="" height="14"> **English**](README.en.md)

# forge: the release build machine

*forge* is a Debian virtual machine with Docker that builds the whole release: checks, executables,
web version, C64, MiSTer core and the Deck SD card image. It is the usual way to make a release; the
GitHub Actions are the alternative (`build_ongithub.bat`, and `check_ongithub.bat` for the checks
only). On the PC you run `build_onforge.bat`, which:

1. starts forge if it is off (VMware Workstation, `vmrun`, no window);
2. sends it the sources of the current commit, with the repository line endings like the CI checkout;
3. waits for forge to run the checks and build the packages (`build.sh`);
4. copies the packages back into `dist\`;
5. shuts forge down again, if it was the one that started it.

Options: `-Publish` (publishes the release of the tag with `gh`), `-PublishOnly` (publishes the
packages already in `dist\`, without rebuilding), `-NoCheck`, `-CheckOnly`, `-SkipMister`, `-KeepVm`. To try files that are not committed yet there is `check_onforge.bat`
(`-Synth` to run the MiSTer synthesis too).

Script messages and comments are in Italian, like the rest of the code.

## Creating forge

### With VMware Workstation, automatically

You need a Windows 10 or 11 PC with:

- VMware Workstation (free for personal use);
- Python 3.9 or later and git;
- the OpenSSH client (Windows already has it);
- about 100 GB of free disk space;
- enough RAM to give 16 GB to the VM.

From the root of the repository:

```bat
create_forge.bat
```

In a few minutes (six or seven, download included), without asking anything, it:

1. downloads the Debian 13 cloud image (about 300 MB) and checks its SHA-512; it stays in
   `%LOCALAPPDATA%\PaddWS\forge` for next time;
2. turns it into the VM disk, 80 GB, in `Documents\Virtual Machines\forge`;
3. starts the VM with a small CD for cloud-init, which creates the user `forge` with the PC's ssh key
   (`~/.ssh/id_ed25519`, created if missing) and passwordless `sudo`;
4. runs `setup.sh`, which installs Docker and sets up the console;
5. shuts the VM down, removes the CD, adds `Host forge` to `~/.ssh/config` (the old version is kept
   in `config.bak`) and writes `forge.local.psd1` in the root of the repository.

From then on `build_onforge.bat` is all you need. The first build downloads the Quartus image (about
3 GB) and builds the `paddws-build` image, so it takes longer: a little under an hour. From the
second time on only what changed is rebuilt.

`create_forge.bat --help` lists the options. The most useful ones:

| option | default | |
|---|---|---|
| `--dir FOLDER` | `Documents\Virtual Machines\forge` | where the VM goes |
| `--cpus N` | half of the PC's processors, 8 at most | the MiSTer synthesis uses all of them |
| `--memory MB` | 16384 | Quartus does not fit in less than 8192 |
| `--disk GB` | 80 | the disk grows as needed, it does not take all the space at once |
| `--console-password` | | asks for a password to log in from the VM console; without it, only `ssh forge` works |
| `--deck` | | also prepares the Deck image cache (a few hours, see below) |

The VM does not show up in the VMware library by itself: to see it, *File → Open* and the file
`forge.vmx`. To start over, delete it from VMware (*Manage → Delete from Disk*) and run
`create_forge.bat` again.

The IP address comes from the DHCP of the VMware NAT network and usually stays the same. If it
changes, `build_onforge.bat` asks VMware for it, goes on with the new one and reminds you to fix
`HostName` in `~/.ssh/config`.

### By hand, on another machine

forge can also be a VM in another program (Hyper-V, VirtualBox, Proxmox) or any Debian 13 computer
reachable with ssh. You need:

1. Debian 13 without a desktop, with the SSH server: 8 cores, 16 GB of RAM, 80 GB of disk;
2. a user with passwordless `sudo`, as root:
   `echo "USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/USER`;
3. from the PC:
   - the ssh key on the VM:
     `type %USERPROFILE%\.ssh\id_ed25519.pub | ssh USER@IP "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"`;
   - a `Host forge` entry in `~/.ssh/config` with `HostName IP` and `User USER`;
   - then `scp tools/forge/setup.sh forge:` and `ssh forge sudo sh setup.sh`, and a reboot for the
     console font;
4. in the root of the repository, `forge.local.psd1` (not versioned):

   ```powershell
   @{
       Host = 'forge'
       Vmx  = 'D:\VM\forge\forge.vmx'   # VMware only: lets build_onforge.bat start and stop it
   }
   ```

   Without `Vmx`, start forge by hand before `build_onforge.bat`.

### Cache for the Deck image

The Deck SD card image starts from Raspberry Pi OS Lite and uses a kernel and a Mesa built on
purpose. They are prepared once, in `~/forge/deck-cache`, by `deck-cache.sh`:

- `lite.img`: Raspberry Pi OS Lite Trixie armhf (about 600 MB to download);
- `kernel.tar`: the Deck kernel, cross-compiled (about twenty minutes);
- `mesa.tar`: Mesa without LLVM, compiled on an emulated ARM (more than an hour).

Do it together with the VM with `create_forge.bat --deck`, or later: `build_onforge.bat -KeepVm`,
which leaves forge on with the sources, then `ssh forge sh forge/src/tools/forge/deck-cache.sh`
(from the forge console, just `forge-deck`). If it stops halfway, run it again: what is already
done is not redone. Without the cache the release only skips the Deck image.

## What forge does

`build.sh`:

1. builds the `paddws-build` image from the `Dockerfile` (only the first time and when it changes):
   Ubuntu 22.04 like the CI Linux runners, with
   - Rust with the Linux x86_64, aarch64 and armv7 (cross-compiled), Windows (MinGW) and wasm32 targets;
   - PowerShell for `tools/build-web.ps1`;
   - cc65;
   - Python with the dependencies of the Python version and pytest;
2. in the `forge-build` container (`build-all.sh`) it runs:
   - the CI checks: clippy `-D warnings` and the Rust tests, the C64 test bench against the Rust
     core, the MiSTer traces, pytest;
   - the Windows, Linux x86_64, aarch64 and armv7 packages (glibc 2.36 at most, for Raspberry Pi OS
     Bookworm 64 and 32 bit), web, Python and C64;
3. synthesizes the MiSTer core with Quartus (`mister/synth.sh`, image pinned by digest in
   `mister/quartus-image.txt`) and makes the SD card zip;
4. if the Deck cache is there, builds the Deck SD card image from the armv7 package,
   `paddws-X.Y.Z-deck-pi2.img.xz` ([deploy/raspberry/deck](../../deploy/raspberry/deck/README.en.md),
   about 10 minutes, with `sudo`).

The packages stay in `~/forge/out` with `BUILD.txt` (version, commit, result). The crates and the
`target` folder stay in the Docker volumes `forge-cargo` and `forge-target`: from the second time on
only what changed is rebuilt. With 8 cores and 16 GB a full release takes about twenty minutes,
three quarters of them for Quartus.

## Console

`status.sh` shows:

- the FORGE banner;
- the work in progress (build or Quartus phase, elapsed time);
- the last build and the last synthesis (worst slack, FPGA resources);
- the images;
- CPU, memory and disk.

The first console shows it live from boot; login is on the second one (Alt+F2). At every login,
`ssh forge` included, you get the commands:

- `forge-stato`: live view, Ctrl+C to quit;
- `forge-build`: rebuilds the release from the sources in `~/forge/src`;
- `forge-sintesi`: the MiSTer core only;
- `forge-deck`: prepares the Deck image cache.
