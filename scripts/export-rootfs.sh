#!/data/data/com.termux/files/usr/bin/bash
#
# export-rootfs.sh — package the built WPS environment into one file.
#
# This is the "WPS joined with Linux" artifact: a single compressed rootfs you
# can copy to another device (or keep as a backup) and restore in a couple of
# minutes instead of rebuilding from scratch. It is the same idea as Xiaomi's
# mslgrootfs, just built by you rather than shipped in a ROM.
#
#   bash scripts/export-rootfs.sh [output-file]
#
# Default output: /sdcard/Download/wps-rootfs-<date>.tar.<ext>
#
set -euo pipefail

DISTRO="${DISTRO:-debian}"
ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$ROOTFS" ] || die "No '$DISTRO' container found. Run install.sh first."
[ -x "$ROOTFS/usr/bin/wps" ] || warn "WPS not found in the container — exporting anyway"

# zstd compresses this kind of tree much faster than xz at a similar ratio.
if command -v zstd >/dev/null || pkg install -y zstd >/dev/null 2>&1; then
  EXT=tar.zst; COMP=(zstd -19 -T0)
else
  EXT=tar.gz;  COMP=(gzip -9)
  warn "zstd unavailable; falling back to gzip (slower, larger)"
fi

OUT="${1:-/sdcard/Download/wps-rootfs-$(date +%Y%m%d).$EXT}"
OUTDIR="$(dirname "$OUT")"

if [ ! -d "$OUTDIR" ]; then
  die "$OUTDIR does not exist. For /sdcard paths run 'termux-setup-storage' first."
fi
[ -w "$OUTDIR" ] || die "$OUTDIR is not writable. Run 'termux-setup-storage' and grant access."

# proot-distro gained a backup subcommand that handles ownership and symlinks
# correctly; prefer it and only hand-roll the tar when it isn't there.
if proot-distro backup --help >/dev/null 2>&1; then
  log "Exporting with proot-distro backup"
  proot-distro backup --output "$OUT" "$DISTRO"
else
  log "Exporting with tar (proot-distro backup unavailable)"
  tar -C "$ROOTFS" -cf - \
      --exclude='./tmp/*' --exclude='./var/cache/apt/archives/*' \
      --exclude='./var/lib/apt/lists/*' --exclude='./root/pc-wps/*.deb' \
      . | "${COMP[@]}" > "$OUT"
fi

log "Wrote $OUT ($(du -h "$OUT" | cut -f1))"
cat <<MSG

  To restore it on this or another device:

      bash scripts/import-rootfs.sh "$OUT"

MSG
