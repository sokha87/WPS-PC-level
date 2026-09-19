#!/data/data/com.termux/files/usr/bin/bash
#
# import-rootfs.sh — restore a rootfs made by export-rootfs.sh.
#
#   bash scripts/import-rootfs.sh /sdcard/Download/wps-rootfs-YYYYMMDD.tar.zst
#
# Installs the container and the `pcwps` launcher, so a second device needs no
# rebuild: extract and run.
#
set -euo pipefail

DISTRO="${DISTRO:-debian}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/common.sh
. "$HERE/scripts/common.sh"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

ARCHIVE="${1:-}"
[ -n "$ARCHIVE" ] || die "usage: bash scripts/import-rootfs.sh <archive>"
[ -f "$ARCHIVE" ] || die "$ARCHIVE not found"

case "$(uname -m)" in
  aarch64|arm64) ;;
  *) die "This rootfs is arm64; this device reports $(uname -m)." ;;
esac

log "Installing Termux prerequisites"
pkg install -y proot-distro x11-repo >/dev/null
pkg update -y >/dev/null 2>&1 || true
pkg install -y termux-x11-nightly pulseaudio >/dev/null
case "$ARCHIVE" in *.zst) pkg install -y zstd >/dev/null ;; esac

if ROOTFS="$(find_rootfs "$DISTRO")"; then
  printf 'A "%s" container already exists and will be replaced. Continue? [y/N] ' "$DISTRO"
  read -r a; [ "${a:-n}" = y ] || exit 1
  proot-distro remove "$DISTRO" || rm -rf "$ROOTFS"
fi

if proot-distro restore --help >/dev/null 2>&1; then
  log "Restoring with proot-distro"
  proot-distro restore "$ARCHIVE"
else
  log "Restoring with tar"
  ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"
  mkdir -p "$ROOTFS"
  case "$ARCHIVE" in
    *.zst) zstd -dc "$ARCHIVE" | tar -C "$ROOTFS" -xf - ;;
    *.gz)  gzip -dc "$ARCHIVE" | tar -C "$ROOTFS" -xf - ;;
    *)     tar -C "$ROOTFS" -xf "$ARCHIVE" ;;
  esac
fi

ROOTFS="$(find_rootfs "$DISTRO")" || die "Restore finished but no rootfs was found."
[ -x "$ROOTFS/usr/local/bin/start-wps-session" ] || \
  die "That archive has no WPS session in it — was it made by export-rootfs.sh?"

log "Installing the 'pcwps' launcher"
sed "s|@DISTRO@|$DISTRO|g" "$HERE/scripts/pcwps.in" > "$PREFIX/bin/pcwps"
chmod 0755 "$PREFIX/bin/pcwps"

log "Done — run 'pcwps' to start WPS"
