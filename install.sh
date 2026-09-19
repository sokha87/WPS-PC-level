#!/data/data/com.termux/files/usr/bin/bash
#
# install.sh — set up desktop-class WPS Office (Linux/arm64) on Android.
#
# Run this INSIDE TERMUX (the F-Droid / GitHub build, not the Play Store one).
# No root required.
#
#   bash install.sh
#
# Environment overrides:
#   PROFILE=slim|desktop   slim (default) builds a WPS-only environment with no
#                          desktop; desktop builds a full XFCE session
#   FONTS=minimal|full     minimal (default) is Latin+Khmer; full adds CJK
#   TRIM=1|0               strip docs, man pages and system locales (default 1)
#   TRIM_MUI=en_US         comma-separated WPS UI languages to keep
#   DISTRO=debian          proot-distro alias to use
#   WPS_DEB_URL=<url>      exact .deb to install instead of the probe list
#   WPS_DEB_FILE=<path>    a .deb you downloaded yourself (skips all downloading)
#   SKIP_APK_HINT=1        don't print the Termux:X11 companion-app reminder
#
set -euo pipefail

DISTRO="${DISTRO:-debian}"
PROFILE="${PROFILE:-slim}"     # slim = WPS only; desktop = full XFCE
FONTS="${FONTS:-minimal}"      # minimal = Latin+Khmer; full = adds CJK (+330 MB)
TRIM="${TRIM:-1}"              # drop docs/man/locales after install
TRIM_MUI="${TRIM_MUI:-}"       # WPS UI languages to keep, e.g. "en_US"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/common.sh
. "$HERE/scripts/common.sh"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- sanity checks

[ -d /data/data/com.termux/files/usr ] || die "This must be run inside Termux."

case "$PROFILE" in slim|desktop) ;; *) die "PROFILE must be 'slim' or 'desktop'" ;; esac
case "$FONTS"   in minimal|full) ;; *) die "FONTS must be 'minimal' or 'full'"   ;; esac

case "$(uname -m)" in
  aarch64|arm64) ;;
  *) die "WPS Office for Linux is only published for arm64. This device reports $(uname -m)." ;;
esac

if [ "$PROFILE" = slim ]; then need_mb=4000; else need_mb=6000; fi
avail_kb="$(df -Pk "$HOME" | awk 'NR==2 {print $4}')"
if [ "${avail_kb:-0}" -lt $(( need_mb * 1024 )) ]; then
  warn "Only $((avail_kb / 1024)) MB free. A '$PROFILE' build needs about ${need_mb} MB."
  warn "Free some space, or this will fail partway through."
  printf 'Continue anyway? [y/N] '; read -r a; [ "${a:-n}" = y ] || exit 1
fi

# ------------------------------------------------------------ termux packages

log "Updating Termux packages"
yes '' | pkg update -y >/dev/null || warn "pkg update reported errors; continuing"

log "Installing Termux packages (proot-distro, X11 server, audio)"
pkg install -y proot-distro x11-repo curl >/dev/null
# x11-repo adds an apt source; its packages don't resolve until the index is refreshed
pkg update -y >/dev/null 2>&1 || true
pkg install -y termux-x11-nightly pulseaudio >/dev/null

# ------------------------------------------------------------- debian rootfs

# proot-distro decides whether the container exists -- a directory check is
# wrong, because where it keeps rootfs has changed between versions.
log "Ensuring the $DISTRO container exists (first run downloads a few hundred MB)"
ensure_distro "$DISTRO" || die "proot-distro could not install '$DISTRO'"

# ---------------------------------------------- fetch the WPS .deb (Termux side)
# Downloading here rather than inside proot: Termux's network stack is faster and
# the file lands on shared storage, so a failed container run doesn't re-download.

DEB_DIR="$HOME/.cache/pc-wps"
mkdir -p "$DEB_DIR"

resolve_deb() {
  if [ -n "${WPS_DEB_FILE:-}" ]; then
    [ -f "$WPS_DEB_FILE" ] || die "WPS_DEB_FILE=$WPS_DEB_FILE does not exist"
    cp -f "$WPS_DEB_FILE" "$DEB_DIR/wps-office_arm64.deb"
    return 0
  fi

  local existing
  existing="$(find "$DEB_DIR" -maxdepth 1 -name '*.deb' -size +100M 2>/dev/null | head -n1)"
  if [ -n "$existing" ]; then
    log "Reusing already-downloaded $(basename "$existing")"
    [ "$existing" = "$DEB_DIR/wps-office_arm64.deb" ] || mv -f "$existing" "$DEB_DIR/wps-office_arm64.deb"
    return 0
  fi

  local urls=()
  if [ -n "${WPS_DEB_URL:-}" ]; then
    urls=("$WPS_DEB_URL")
  else
    # First choice is the Pi-Apps mirror on GitHub Releases: same package, but
    # served from a host that is neither geo-restricted nor hotlink-protected.
    # WPS's own CDN answers 403 to most of the world and rotates its paths
    # without notice, so it is a fallback, not the primary.
    urls=(
      "https://github.com/Pi-Apps-Coders/files/releases/download/large-files/wps-office_11.1.0.11720_arm64.deb"
      "https://wdl1.cache.wps.cn/wps/download/ep/Linux2019/11720/wps-office_11.1.0.11720_arm64.deb"
      "https://wps-linux-personal.wpscdn.cn/wps/download/ep/Linux2019/11723/wps-office_11.1.0.11723_arm64.deb"
      "https://wps-linux-personal.wpscdn.cn/wps/download/ep/Linux2019/11711/wps-office_11.1.0.11711_arm64.deb"
    )
  fi

  # A bare curl gets 403 from WPS's CDN; it wants to look like a browser that
  # arrived from their download page. Harmless for the GitHub mirror.
  local UA='Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'

  try_url() {
    log "Trying $1"
    if curl -fL --retry 3 --retry-delay 2 -C - \
            -A "$UA" -e 'https://linux.wps.cn/' \
            -o "$DEB_DIR/wps-office_arm64.deb.part" "$1"; then
      mv -f "$DEB_DIR/wps-office_arm64.deb.part" "$DEB_DIR/wps-office_arm64.deb"
      return 0
    fi
    warn "Failed: $1"
    return 1
  }

  local u
  for u in "${urls[@]}"; do
    try_url "$u" && return 0
  done

  # Last automated resort: ask WPS's own download page what the current arm64
  # link is, rather than guessing at version numbers.
  if [ -z "${WPS_DEB_URL:-}" ]; then
    log "Asking linux.wps.cn for a current arm64 link"
    local page found
    for page in "https://linux.wps.cn/" "https://www.wps.cn/product/wpslinux"; do
      while IFS= read -r found; do
        [ -n "$found" ] || continue
        try_url "$found" && return 0
      done < <(curl -fsSL --max-time 30 -A "$UA" "$page" 2>/dev/null \
               | grep -Eo 'https?://[A-Za-z0-9._~/-]+arm64\.deb' | sort -u | head -5)
    done
  fi

  return 1
}

if ! resolve_deb; then
  rm -f "$DEB_DIR/wps-office_arm64.deb.part"
  cat >&2 <<'MSG'

[x] Could not download WPS Office for Linux (arm64).

    Every mirror refused. Download the package by hand and point the installer
    at it — any of these sources carries the same arm64 build:

      * https://github.com/Pi-Apps-Coders/files/releases/tag/large-files
        (wps-office_11.1.0.11720_arm64.deb — the Pi-Apps mirror, usually the
         one that works outside China)
      * https://linux.wps.cn/  — the official page, "ARM64 / 麒麟·飞腾" build
      * https://github.com/koesherbacon/WPS-Office — community .deb mirror

    Then:

      1. Put the file on your phone, e.g. /sdcard/Download/
      2. Re-run:
           termux-setup-storage      # once, to grant storage access
           WPS_DEB_FILE=/sdcard/Download/wps-office_11.1.0.11720_arm64.deb bash install.sh

    Or pass a link directly:

           WPS_DEB_URL="https://..." bash install.sh

MSG
  exit 1
fi

log "WPS package ready: $(du -h "$DEB_DIR/wps-office_arm64.deb" | cut -f1)"

# ------------------------------------------------- stage files into the rootfs

# Bind the scripts and the package into the container instead of copying them
# into its rootfs: no rootfs path to get wrong, and no second 350 MB copy.
log "Running in-container setup (PROFILE=$PROFILE, FONTS=$FONTS — takes a while)"
proot-distro login "$DISTRO" \
  --bind "$HERE/scripts:/mnt/pc-wps-scripts" \
  --bind "$DEB_DIR:/mnt/pc-wps-deb" \
  -- /bin/bash -c \
  "PROFILE='$PROFILE' FONTS='$FONTS' TRIM='$TRIM' TRIM_MUI='$TRIM_MUI' \
   /bin/bash /mnt/pc-wps-scripts/debian-setup.sh"

# ---------------------------------------------------------- install launcher

log "Installing the 'pcwps' launcher"
sed "s|@DISTRO@|$DISTRO|g" "$HERE/scripts/pcwps.in" > "$PREFIX/bin/pcwps"
chmod 0755 "$PREFIX/bin/pcwps"

printf '%b' "
\033[1;32mDone.\033[0m

  Start it with:    \033[1mpcwps\033[0m          (WPS Writer)
                    \033[1mpcwps et\033[0m       (Spreadsheets)
                    \033[1mpcwps wpp\033[0m      (Presentation)
                    \033[1mpcwps pdf\033[0m      (PDF reader)
  Stop it with:     \033[1mpcwps stop\033[0m
  Home-screen icon: \033[1mbash scripts/install-shortcuts.sh\033[0m
  Start on boot:    \033[1mbash scripts/install-autostart.sh\033[0m
  Package it up:    \033[1mbash scripts/export-rootfs.sh\033[0m

"

if [ -z "${SKIP_APK_HINT:-}" ]; then
  cat <<'MSG'
  One more thing: you need the Termux:X11 *companion app* installed
  (the `termux-x11-nightly` package alone is only the server side).
  Grab the arm64 APK from:
      https://github.com/termux/termux-x11/releases
  Install it, then run `pcwps` — the desktop appears in that app.

MSG
fi
