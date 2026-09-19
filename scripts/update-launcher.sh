#!/data/data/com.termux/files/usr/bin/bash
#
# update-launcher.sh — apply repo changes without rebuilding the container.
#
#   git pull && bash scripts/update-launcher.sh
#
# `git pull` updates this repository, but the things that actually run live
# outside it: pcwps is generated into $PREFIX/bin, and start-wps-session is
# installed inside the container. This copies both across again. It touches no
# packages, so it takes a second rather than half an hour.
#
set -euo pipefail

DISTRO="${DISTRO:-debian}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ -d /data/data/com.termux/files/usr ] || die "This must be run inside Termux."
[ -f "$HERE/scripts/pcwps.in" ] || die "Run this from inside the WPS-PC-level checkout."

log "Regenerating the 'pcwps' launcher"
sed "s|@DISTRO@|$DISTRO|g" "$HERE/scripts/pcwps.in" > "$PREFIX/bin/pcwps"
chmod 0755 "$PREFIX/bin/pcwps"

log "Updating the session launcher inside the container"
if proot-distro login "$DISTRO" --bind "$HERE/scripts:/mnt/pc-wps-scripts" -- \
     /bin/bash -c 'install -m 0755 /mnt/pc-wps-scripts/start-wps-session \
                                   /usr/local/bin/start-wps-session'; then
  log "Done — run 'pcwps' to start WPS"
else
  warn "Could not update the container copy; the pcwps launcher was still updated."
  warn "If the container is missing entirely, run: bash install.sh"
fi
