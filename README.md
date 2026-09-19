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
not the mobile app — in a resizable XFCE desktop, with keyboard, mouse and
external-display support through Termux:X11.

## Requirements

| | |
|---|---|
| CPU | arm64 (`aarch64`) — effectively every phone since ~2016 |
| Android | 7.0+ |
| Free storage | **~6 GB** (Debian ~1.5 GB, WPS ~1 GB, plus working room) |
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
pcwps           # full XFCE desktop; WPS starts automatically
pcwps writer    # just WPS Writer
pcwps et        # just Spreadsheets
pcwps wpp       # just Presentation
pcwps pdf       # just the PDF reader
pcwps stop      # shut the session down
```

Run `pcwps`, then switch to the **Termux:X11** app — the desktop is there. Leave
Termux running in the background (its notification must stay alive).

Your phone's storage is reachable from inside the container at `/mnt/sdcard` once
you have run `termux-setup-storage` in Termux, so you can open documents from
Downloads and save back to them.

---

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

**Slow** — proot has no hardware GL, so everything is software-rendered
(`LIBGL_ALWAYS_SOFTWARE=1`). It is usable for documents, not for animation-heavy
presentations. On a rooted device, a real container (chroot) is substantially
faster.

**Reclaim the space:**

```bash
pcwps stop
proot-distro remove debian
rm -f $PREFIX/bin/pcwps ~/.cache/pc-wps/*.deb
```

## Want it without the command line?

[**tiny_computer**](https://github.com/Cateners/tiny_computer) is a packaged
Android app that does essentially this — click-to-run Debian desktop, no root, no
terminal. If you would rather tap an APK than run an installer, use that instead;
this repo exists for when you want the pieces visible and editable.

## Layout

```
install.sh                         run this in Termux — orchestrates everything
scripts/debian-setup.sh            runs inside the container: XFCE, fonts, WPS
scripts/start-wps-session          runs inside the container: starts the session
scripts/pcwps.in                   template for the `pcwps` launcher
docs/why-the-xiaomi-apk-fails.md   why com.xiaomi.wpslauncher can't work here
```

## Status

Written against Termux (F-Droid build), `proot-distro` Debian, Termux:X11 nightly
and WPS Office for Linux 11.1.0.x arm64. **The scripts are shell-checked but have
not been run end-to-end on a device** — I have no Android hardware, and the WPS CDN
is unreachable from where this was written, so the download URLs in particular are
unverified. If a step fails, the error will name the stage; open an issue or fix it
in place.
