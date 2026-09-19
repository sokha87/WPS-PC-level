# Why "WPS Office PC" shows *"The current version is too low. Please upgrade the ROM version…"*

## What that app actually is

The APK you sideloaded is **`com.xiaomi.wpslauncher`**, published on APKMirror as
*"WPS Office PC" by **Xiaomi Inc.***

It is **not** an office suite. It is a ~few-MB **launcher shim**. The real thing it
launches is the **Linux (arm64) build of WPS Office**, running inside a **Linux
container that ships as part of the tablet's HyperOS ROM**.

Xiaomi's public device tree for this feature
([`Fuutao/android_device_xiaomi_wps`](https://github.com/Fuutao/android_device_xiaomi_wps))
makes the split obvious — it is a **board-level** component, containing:

| Component | What it is |
|---|---|
| `mslgrootfs/` | the Linux **guest root filesystem** image (multiple GB) |
| `mslgservice/` | the Android system service that boots and talks to the container |
| `sepolicy/` | SELinux policy allowing that service to exist |
| `BoardConfig.mk`, `config.mk` | wired into the **device build**, not into the APK |

So the pieces that do the work live in `/system` (and in the super partition) of a
supported tablet. They are flashed with the ROM. They are not, and cannot be, inside
a 10 MB APK from APKMirror.

## What the toast means

On launch, `com.xiaomi.wpslauncher` asks the platform whether the container runtime
exists and is new enough. On your phone that check returns "no", and the launcher
emits exactly the toast in your screenshot. It is not a bug, a broken install, or a
missing permission — it is the app correctly reporting that **the OS underneath it
does not have the feature**.

## Why it can never work on a phone

1. **Wrong device class.** PC-level WPS shipped only on tablets — Xiaomi Pad 6 /
   6 Pro (HyperOS `V816.0.4.0`+), Pad 6 Max, Pad 7 series, Pad 8 / 8 Pro. Xiaomi has
   never shipped it to a phone, on HyperOS 2 or 3.
2. **Partition space.** The Linux guest needs several GB *inside the system
   partition*. Xiaomi enlarged the Pad 6 Max system partition to ~11.5 GB precisely
   for this; older Pads capped at ~8.5 GB and were dropped for that reason. A phone
   ROM has no such reserve.
3. **Missing system service + SELinux policy.** Even with infinite space, `mslgservice`
   and its sepolicy are not present in your ROM, and adding them means rebuilding the
   ROM — not installing an APK.

**Spoofing `build.prop` does not help.** At best you get past the version toast and
then hit a hard failure, because there is no container and no guest rootfs to start.
That is why no working "patch" for this APK exists anywhere.

## What *does* work

Run **the same thing Xiaomi runs** — desktop WPS Office for Linux/arm64 — in a
container you provide yourself, instead of one the ROM provides. No root required.
That is what this repository sets up. See the [README](../README.md).
