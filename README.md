# WPS PC-level on Android (without a Xiaomi Pad)

**Short answer to "why won't it open":** the app you sideloaded,
`com.xiaomi.wpslauncher` ("WPS Office PC" by Xiaomi on APKMirror), is a thin
launcher for a **Linux container that ships inside the HyperOS ROM of specific
Xiaomi tablets**. Your phone's ROM has no such container, so the launcher refuses
to start and shows:

> The current version is too low. Please upgrade the ROM version to experience…

There is no patch, no permission, and no `build.prop` edit that fixes this — the
multi-gigabyte Linux guest image and its system service are flashed with the tablet
ROM, not bundled in the APK. Full breakdown, with sources:
**[docs/why-the-xiaomi-apk-fails.md](docs/why-the-xiaomi-apk-fails.md)**.

**What this repo does instead:** runs the *same software Xiaomi runs* — the real
**WPS Office for Linux (arm64)** desktop build — inside a Debian container you own,
on any arm64 Android device. **No root required.**

---

## What you get

Genuine desktop WPS Writer / Spreadsheets / Presentation / PDF — the Linux build,
not the mobile app — with keyboard, mouse and external-display support through
Termux:X11.

By default you get **only that**. No desktop, no panel, no file manager, no
terminal, no wallpaper — you tap the launcher and WPS is the window. This is the
same shape as Xiaomi's own `mslgrootfs`: a Linux image whose entire purpose is to
hold one application.

### Two profiles

| | `PROFILE=slim` (default) | `PROFILE=desktop` |
|---|---|---|
| Session | WPS alone, on a ~200 KB window manager | full XFCE desktop |
| Also installed | nothing else | panel, file manager, terminal, settings |
| Install size | **~1.5–1.8 GB** | ~3.5–4.5 GB |
| Use when | you only ever want WPS | you want a general Linux desktop too |

Roughly where the slim build's space goes: Debian base ~120 MB, X11 + GTK
libraries ~350 MB, fonts ~50 MB (or ~380 MB with `FONTS=full`), and WPS itself
~1 GB — WPS is the floor, and nothing in this repo can shrink it much.

`install.sh` prints the measured sizes at the end of the build, so you will see
the real numbers for your device rather than these estimates.

### Build knobs

```bash
bash install.sh                  # slim: WPS only, Latin + Khmer fonts
PROFILE=desktop bash install.sh  # full XFCE desktop as well
FONTS=full bash install.sh       # add CJK fonts (Noto CJK alone is ~330 MB)
TRIM=0 bash install.sh           # keep docs, man pages and system locales
TRIM_MUI=en_US bash install.sh   # keep only the English WPS UI language pack
```

## Requirements

| | |
|---|---|
| CPU | arm64 (`aarch64`) — effectively every phone since ~2016 |
| Android | 7.0+ |
| Free storage | **~4 GB** for a slim build, ~6 GB for a desktop build |
| RAM | 4 GB works; 6 GB+ is comfortable |
| Root | **not needed** |

## Install

1. **Install Termux** from [F-Droid](https://f-droid.org/packages/com.termux/) or
   [GitHub releases](https://github.com/termux/termux/releases).
   *Not the Play Store build* — it is years out of date and `pkg` will fail.

2. **Install the Termux:X11 companion app** — the arm64 APK from
   [termux/termux-x11 releases](https://github.com/termux/termux-x11/releases).
   This is the window that the Linux desktop draws into. You already have APKMirror
   Installer, so sideloading it is one tap.

3. **Run the installer**, in Termux:

   ```bash
   pkg install -y git
   git clone https://github.com/sokha87/WPS-PC-level
   cd WPS-PC-level
   bash install.sh
   ```

   Budget 20–40 minutes on a decent connection. Most of it is downloading the
   Debian rootfs and the ~350 MB WPS package.

## Use

```bash
pcwps           # WPS Writer (on a desktop build: the XFCE desktop)
pcwps writer    # WPS Writer
pcwps et        # Spreadsheets
pcwps wpp       # Presentation
pcwps pdf       # PDF reader
pcwps desktop   # the XFCE desktop (desktop builds only)
pcwps stop      # shut the session down

pcwps --no-window writer   # start WPS but leave the window closed
pcwps show                 # bring an already-running session to the front
```

Run `pcwps`, then switch to the **Termux:X11** app — WPS is drawing in there.
Leave Termux running in the background (its notification must stay alive).
For a home-screen icon instead of a typed command, see
[Putting an icon on the home screen](#putting-an-icon-on-the-home-screen).

Your phone's storage is reachable from inside the container at `/mnt/sdcard` once
you have run `termux-setup-storage` in Termux, so you can open documents from
Downloads and save back to them.

---

## Putting an icon on the home screen

```bash
bash scripts/install-shortcuts.sh
bash scripts/install-shortcuts.sh --uninstall
```

This needs **[Termux:Widget](https://f-droid.org/packages/com.termux.widget/)** —
another companion app, the one that turns scripts in `~/.shortcuts/` into
home-screen icons. The installer checks for it and stops with the download links
if it is missing.

It writes one shortcut per WPS app (Writer, Sheets, Slides, PDF — skipping any
your build doesn't ship) and **copies the real icons out of the WPS installation
inside the container**, so they are the actual application icons, not
approximations drawn here.

Then place them yourself — Android does not let an app put icons on the home
screen on its own:

> Long-press the home screen → **Widgets** → **Termux:Widget**
> · *Termux shortcut* — one icon for one app, add one per app
> · *Termux widget* — a small tile listing all of them

Tapping an icon starts WPS and brings up the window. Tapping it again while WPS
is running **surfaces the existing session** rather than restarting it, and
tapping a different app's icon opens that app alongside the running one instead
of tearing the session down. This matters if you also use the boot hook below:
the warm start leaves WPS running with no window, and a tap is then just an
instant window.

## Starting WPS on boot

```bash
bash scripts/install-autostart.sh              # warm start (recommended)
BOOT_MODE=full bash scripts/install-autostart.sh
BOOT_APP=et    bash scripts/install-autostart.sh
bash scripts/install-autostart.sh --uninstall
```

This needs **[Termux:Boot](https://f-droid.org/packages/com.termux.boot/)** — a
third companion app, separate from Termux and Termux:X11. Install it and **open it
once**; until it has been launched at least one time it will not run anything.
The installer checks for it and stops with the download links if it is missing.

| | `BOOT_MODE=warm` (default) | `BOOT_MODE=full` |
|---|---|---|
| On boot | container, X server and WPS all start | same, plus the window is brought to the front |
| You see | nothing — your home screen as usual | WPS, on screen |
| Opening Termux:X11 later | WPS is already there, instantly | — |

**Warm is the recommendation.** WPS is genuinely running and drawing; the only
thing deferred is the window. You get the startup time back without anything
appearing over what you were doing.

### Android will fight you on this

Three settings decide whether a boot hook survives, and none of them are this
repo's to set:

1. **Battery optimisation** — Settings → Apps → Termux → Battery → *Unrestricted*.
   Without it Android suspends Termux seconds after boot and the session dies
   half-started. You already have DontKillMyApp — use it to confirm this sticks.
2. **Autostart** — on HyperOS/MIUI, ColorOS and OneUI this is a *separate* toggle
   from battery optimisation, usually Settings → Apps → Permissions → Autostart.
3. **`BOOT_MODE=full` only:** since Android 10 an app cannot foreground an
   activity from the background without permission. Grant Termux:X11 *Display
   over other apps*, or the window will not surface — WPS will still be running,
   so opening Termux:X11 shows it immediately. Warm mode sidesteps this entirely.

The hook holds a `termux-wake-lock` (released by `pcwps stop`) and waits 10
seconds before starting, because storage is not always mounted the instant
Termux:Boot fires. Test it without rebooting:

```bash
bash ~/.termux/boot/10-pcwps
cat ~/.cache/pc-wps/boot.log
```

## Reusing the build on another device

Once it works, package the whole environment into one file and restore it
elsewhere in a couple of minutes instead of rebuilding:

```bash
bash scripts/export-rootfs.sh              # -> /sdcard/Download/wps-rootfs-<date>.tar.zst
bash scripts/import-rootfs.sh <that-file>  # on the other device
```

That archive is your own equivalent of Xiaomi's shipped guest image — WPS and the
Linux it needs, fused into one artifact.

## If the WPS download fails

`install.sh` probes a few known WPS CDN paths. WPS rotates those URLs and version
numbers without notice, and some of their hosts are geo-restricted — **if all
candidates 404 or time out, that is expected, not a bug in the script.** Fetch the
package yourself and point the installer at it:

1. Get the **arm64** build from <https://www.wps.cn/product/wpslinux> — the
   ARM64 / 麒麟·飞腾 download, named `wps-office_11.1.0.XXXXX_arm64.deb`.
2. Put it in `/sdcard/Download/` on the phone.
3. ```bash
   termux-setup-storage
   WPS_DEB_FILE=/sdcard/Download/wps-office_11.1.0.XXXXX_arm64.deb bash install.sh
   ```

You can also pass a direct link with `WPS_DEB_URL=…`.

## Troubleshooting

**"The Termux:X11 companion app is not installed"** — step 2 above. The
`termux-x11-nightly` *package* is only the server half; the APK is the window.

**Black window in Termux:X11** — the desktop is still starting (first launch can
take 30s). If it stays black, `pcwps stop`, then `pcwps` again.

**WPS starts then dies immediately** — almost always a missing library. Check it
directly:

```bash
proot-distro login debian -- /bin/bash -lc 'ldd /usr/bin/wps | grep "not found"'
```

`scripts/debian-setup.sh` already symlinks the usual suspects (`libtiff.so.5`,
`libssl.so.1.1`, `libcrypto.so.1.1`) to their modern equivalents. Anything else it
reports, install with `apt-get install` inside the container.

**Text renders as boxes** — a missing font. Khmer, CJK and Latin faces are installed
by default; add more with `apt-get install fonts-…` inside the container.

**No sound** — PulseAudio didn't start. `pcwps stop`, then `pcwps`.

**The home-screen icon does nothing** — Termux:Widget only reads `~/.shortcuts`
when that directory is not group- or world-readable. The installer sets `700`,
but if you have recreated it by hand, `chmod 700 ~/.shortcuts` and re-add the
widget.

**The icons are generic Termux icons** — no matching PNG was found in the
container. `find $PREFIX/var/lib/proot-distro/installed-rootfs/debian/usr/share/icons -name '*wps*'`
shows what your WPS build actually ships; drop a 192×192 PNG at
`~/.shortcuts/icons/<shortcut name>.png` to set one yourself.

**Nothing starts on boot** — check `~/.cache/pc-wps/boot.log` first; if it is
empty, Termux:Boot never ran the hook. Either the app has never been opened
(it must be launched once after install), or Android killed Termux before the
hook finished — see the three settings under
[Starting WPS on boot](#starting-wps-on-boot).

**Slow** — proot has no hardware GL, so everything is software-rendered
(`LIBGL_ALWAYS_SOFTWARE=1`). It is usable for documents, not for animation-heavy
presentations. On a rooted device, a real container (chroot) is substantially
faster.

**Want it even smaller?** The remaining bulk is WPS itself. `TRIM_MUI=en_US`
drops the UI language packs you don't use, which is worth a few hundred MB.
Beyond that you would be deleting templates and clip-art out of
`/opt/kingsoft/wps-office/office6/` by hand — possible, but you are trading
robustness for a few hundred more MB, and an update puts it all back.

**Reclaim the space:**

```bash
pcwps stop
proot-distro remove debian
rm -f $PREFIX/bin/pcwps ~/.cache/pc-wps/*.deb
```

## How this differs from tiny_computer

[tiny_computer](https://github.com/Cateners/tiny_computer) gives you a full
general-purpose Debian desktop — convenient, but you are carrying a whole desktop
environment you never asked for, and WPS is one icon inside it.

The slim profile here inverts that: the Linux is an implementation detail with
nothing in it but WPS's dependencies, and WPS is the application you launch. Use
tiny_computer if you want a Linux desktop on your phone. Use this if you want WPS
and would rather not be given a desktop.

## Layout

```
install.sh                         run this in Termux — orchestrates everything
scripts/debian-setup.sh            runs inside the container: XFCE, fonts, WPS
scripts/start-wps-session          runs inside the container: starts the session
scripts/pcwps.in                   template for the `pcwps` launcher
scripts/install-shortcuts.sh       install/remove the home-screen shortcuts
scripts/install-autostart.sh       install/remove the Termux:Boot hook
scripts/export-rootfs.sh           package the built environment into one file
scripts/import-rootfs.sh           restore that file on another device
docs/why-the-xiaomi-apk-fails.md   why com.xiaomi.wpslauncher can't work here
```

## Status

Written against Termux (F-Droid build), `proot-distro` Debian, Termux:X11 nightly
and WPS Office for Linux 11.1.0.x arm64. **The scripts are shell-checked but have
not been run end-to-end on a device** — I have no Android hardware, and the WPS CDN
is unreachable from where this was written, so the download URLs in particular are
unverified. If a step fails, the error will name the stage; open an issue or fix it
in place.
