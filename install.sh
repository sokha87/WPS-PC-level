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
ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"
HERE="$(cd "$(dirname "$0")" && pwd)"

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

if [ -d "$ROOTFS" ]; then
  log "proot-distro '$DISTRO' already installed — reusing it"
else
  log "Installing $DISTRO rootfs (this downloads a few hundred MB)"
  proot-distro install "$DISTRO"
fi

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
    # WPS rotates these paths and version numbers without notice. If every
    # candidate 404s, download the arm64 .deb yourself and re-run with
    # WPS_DEB_FILE=/path/to/wps-office_*_arm64.deb
    urls=(
      "https://wps-linux-personal.wpscdn.cn/wps/download/ep/Linux2019/11723/wps-office_11.1.0.11723_arm64.deb"
      "https://wps-linux-personal.wpscdn.cn/wps/download/ep/Linux2019/11719/wps-office_11.1.0.11719_arm64.deb"
      "https://wps-linux-personal.wpscdn.cn/wps/download/ep/Linux2019/11711/wps-office_11.1.0.11711_arm64.deb"
    )
  fi

  local u
  for u in "${urls[@]}"; do
    log "Trying $u"
    if curl -fL --retry 3 --retry-delay 2 -C - -o "$DEB_DIR/wps-office_arm64.deb.part" "$u"; then
      mv -f "$DEB_DIR/wps-office_arm64.deb.part" "$DEB_DIR/wps-office_arm64.deb"
      return 0
    fi
    warn "Failed: $u"
  done
  return 1
}

if ! resolve_deb; then
  rm -f "$DEB_DIR/wps-office_arm64.deb.part"
  cat >&2 <<'MSG'

[x] Could not download WPS Office for Linux (arm64).

    WPS changes these download paths often, and some of their CDN hosts are
    geo-restricted. Do this instead:

      1. On any machine, get the arm64 .deb from https://www.wps.cn/product/wpslinux
         (the "ARM64 / 麒麟·飞腾" build — file name looks like
          wps-office_11.1.0.XXXXX_arm64.deb, roughly 300-400 MB).
      2. Put it on your phone, e.g. /sdcard/Download/
      3. Re-run:
           termux-setup-storage      # once, to grant storage access
           WPS_DEB_FILE=/sdcard/Download/wps-office_11.1.0.XXXXX_arm64.deb bash install.sh

MSG
  exit 1
fi

log "WPS package ready: $(du -h "$DEB_DIR/wps-office_arm64.deb" | cut -f1)"

# ------------------------------------------------- stage files into the rootfs

log "Staging setup scripts into the $DISTRO rootfs"
install -d "$ROOTFS/root/pc-wps"
install -m 0755 "$HERE/scripts/debian-setup.sh" "$ROOTFS/root/pc-wps/debian-setup.sh"
install -m 0755 "$HERE/scripts/start-wps-session" "$ROOTFS/root/pc-wps/start-wps-session"
cp -f "$DEB_DIR/wps-office_arm64.deb" "$ROOTFS/root/pc-wps/wps-office_arm64.deb"

log "Running in-container setup (PROFILE=$PROFILE, FONTS=$FONTS — takes a while)"
proot-distro login "$DISTRO" -- /bin/bash -c \
  "PROFILE='$PROFILE' FONTS='$FONTS' TRIM='$TRIM' TRIM_MUI='$TRIM_MUI' \
   /bin/bash /root/pc-wps/debian-setup.sh"

# free the staged copy; the .deb is installed now
rm -f "$ROOTFS/root/pc-wps/wps-office_arm64.deb"

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
