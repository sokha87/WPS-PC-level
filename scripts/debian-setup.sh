#!/bin/bash
#
# debian-setup.sh — runs INSIDE the proot Debian container.
# Builds a WPS-only Linux environment. Invoked by ../install.sh.
#
# PROFILE=slim     (default) no desktop: a 200 KB window manager and WPS. Nothing else.
# PROFILE=desktop            full XFCE session, for when you want a general Linux desktop.
#
# FONTS=minimal    (default) Latin + Khmer
# FONTS=full                 adds CJK (Noto CJK alone is ~330 MB)
#
# TRIM=1           (default) drop docs, man pages and system locales after install
# TRIM_MUI=""               comma-separated WPS UI languages to KEEP, e.g. "en_US".
#                           Empty leaves every language pack in place.
#
set -euo pipefail

log()  { printf '\033[1;34m  ->\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  [!]\033[0m %s\n' "$*" >&2; }

PROFILE="${PROFILE:-slim}"
FONTS="${FONTS:-minimal}"
TRIM="${TRIM:-1}"
TRIM_MUI="${TRIM_MUI:-}"

export DEBIAN_FRONTEND=noninteractive
STAGE=/root/pc-wps
DEB="$STAGE/wps-office_arm64.deb"
[ -f "$DEB" ] || { echo "missing $DEB" >&2; exit 1; }

# Package names drift between Debian releases (libasound2 -> libasound2t64,
# libtiff5 -> libtiff6, ...). A single apt-get with one bad name installs
# nothing, so fall back to installing the list one package at a time and just
# report the ones this release doesn't have.
apt_try() {
  if apt-get install -y --no-install-recommends "$@" >/dev/null 2>&1; then
    return 0
  fi
  local pkg missing=()
  for pkg in "$@"; do
    apt-get install -y --no-install-recommends "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  [ ${#missing[@]} -eq 0 ] || warn "not available on this release: ${missing[*]}"
}

# Install the first candidate that exists, for packages that have several
# possible names or where any one of a set will do.
apt_first() {
  local pkg
  for pkg in "$@"; do
    if apt-get install -y --no-install-recommends "$pkg" >/dev/null 2>&1; then
      echo "$pkg"; return 0
    fi
  done
  return 1
}

size_now() { du -sm / --exclude=/proc --exclude=/sys --exclude=/dev 2>/dev/null | cut -f1; }

log "Refreshing apt"
apt-get update -y


# ----------------------------------------------------------------- the session
# This is where slim earns its name. The desktop profile pulls xfce4 and its
# dependency tree; slim pulls a window manager whose entire job is to give WPS
# a title bar so its dialogs can be moved and resized.

if [ "$PROFILE" = desktop ]; then
  log "Installing the XFCE desktop (PROFILE=desktop)"
  apt-get install -y --no-install-recommends xfce4 dbus-x11 || {
    echo "failed to install the XFCE desktop" >&2; exit 1; }
  apt_try xfce4-terminal xfce4-settings x11-xserver-utils xdg-utils mesa-utils
  WM=xfce4-session
else
  log "Installing a minimal single-app session (PROFILE=slim)"
  apt-get install -y --no-install-recommends dbus-x11 || {
    echo "failed to install dbus-x11" >&2; exit 1; }
  # matchbox is built for exactly this: one app, no desktop, no panel, no icons.
  WM="$(apt_first matchbox-window-manager jwm openbox)" || {
    echo "no window manager available (tried matchbox, jwm, openbox)" >&2; exit 1; }
  log "window manager: $WM"
  apt_try x11-xserver-utils
fi

echo "$WM" > /etc/pc-wps-wm
echo "$PROFILE" > /etc/pc-wps-profile

# --------------------------------------------------------------- shared deps

log "Installing X11 and audio support libraries"
apt_try libgl1 libglu1-mesa libegl1 \
        pulseaudio-utils ca-certificates \
        desktop-file-utils shared-mime-info

log "Installing fonts (FONTS=$FONTS)"
apt_try fontconfig fonts-liberation fonts-dejavu-core fonts-khmeros fonts-khmeros-core
if [ "$FONTS" = full ]; then
  apt_try fonts-noto-core fonts-noto-cjk
else
  # Noto Core is ~40 MB and covers most scripts; Noto CJK is ~330 MB and is the
  # single largest thing in a font install, so it only comes with FONTS=full.
  apt_try fonts-noto-core
fi

# WPS's .deb was built against older Debian and asks for library sonames that
# current Debian no longer ships under those exact names. Install the modern
# equivalents and provide the old sonames as symlinks, then force the install.
log "Installing WPS runtime dependencies"
# libwebp and libtiff are what WPS's PDF export actually needs -- without them
# it installs and runs but fails on export. x11-utils and wmctrl are what its
# window handling expects to find.
apt_try libcups2 libcups2t64 libxss1 libnss3 libasound2 libasound2t64 \
        libxcomposite1 libxcursor1 libxdamage1 libxi6 libxrandr2 libxtst6 \
        libgtk-3-0 libgtk-3-0t64 libatk1.0-0 libatk1.0-0t64 libcairo2 \
        libpango-1.0-0 libfontconfig1 libfreetype6 libpng16-16 \
        libjpeg62-turbo libxml2 libtiff6 libtiff5 libwebp7 libwebp6 \
        x11-utils wmctrl

LIBDIR=/usr/lib/aarch64-linux-gnu
link_compat() {  # link_compat <wanted soname> <glob of what we actually have>
  local want="$1" have
  [ -e "$LIBDIR/$want" ] && return 0
  have="$(ls -1 "$LIBDIR"/$2 2>/dev/null | sort -V | tail -n1 || true)"
  if [ -n "$have" ]; then
    ln -sf "$have" "$LIBDIR/$want"
    log "compat: $want -> $(basename "$have")"
  fi
}
link_compat libtiff.so.5     'libtiff.so.*'
link_compat libwebp.so.6     'libwebp.so.*'
link_compat libssl.so.1.1    'libssl.so.*'
link_compat libcrypto.so.1.1 'libcrypto.so.*'
ldconfig

SIZE_PRE_WPS="$(size_now)"

log "Installing WPS Office (unpacks around 1 GB, be patient)"
if ! apt-get install -y "$DEB"; then
  warn "apt refused the package; forcing and repairing dependencies"
  dpkg -i --force-depends "$DEB" || true
  apt-get -f install -y || warn "apt -f install left some deps unsatisfied; WPS often still runs"
fi

command -v wps >/dev/null || { echo "WPS did not install — /usr/bin/wps is missing" >&2; exit 1; }

log "Installing the session launcher"
install -m 0755 "$STAGE/start-wps-session" /usr/local/bin/start-wps-session

if [ "$PROFILE" = desktop ]; then
  install -d /root/.config/autostart
  cat > /root/.config/autostart/wps-office.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=WPS Office
Exec=/usr/bin/wps
Terminal=false
X-GNOME-Autostart-enabled=true
DESKTOP
fi

# proot has no functional hardware GL; force the software rasteriser so WPS's
# Qt/GTK surfaces don't fall over on first paint.
cat > /etc/profile.d/pc-wps.sh <<'PROFILE_SH'
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export QT_X11_NO_MITSHM=1
export _JAVA_AWT_WM_NONREPARENTING=1
PROFILE_SH

# ------------------------------------------------------------------- trimming

log "Trimming apt caches"
apt-get clean
rm -rf /var/lib/apt/lists/*

if [ "$TRIM" = 1 ]; then
  log "Trimming documentation, man pages and unused system locales"
  rm -rf /usr/share/doc /usr/share/man /usr/share/info /usr/share/lintian
  # Keep C/POSIX and English; WPS reads its own translations from its own tree.
  find /usr/share/locale -mindepth 1 -maxdepth 1 -type d \
       ! -name 'en*' ! -name 'C*' -exec rm -rf {} + 2>/dev/null || true
fi

WPS_ROOT=/opt/kingsoft/wps-office
if [ -n "$TRIM_MUI" ] && [ -d "$WPS_ROOT/office6/mui" ]; then
  log "Trimming WPS language packs, keeping: $TRIM_MUI"
  keep=",$TRIM_MUI,"
  for d in "$WPS_ROOT"/office6/mui/*/; do
    name="$(basename "$d")"
    case "$keep" in
      *",$name,"*) ;;
      # default_* holds the fallback strings; removing it leaves a blank UI.
      *) case "$name" in default*) ;; *) rm -rf "$d" ;; esac ;;
    esac
  done
fi

SIZE_END="$(size_now)"

log "Container setup complete"
printf '     base+deps: %s MB\n     WPS adds:  %s MB\n     total:     %s MB\n' \
  "$SIZE_PRE_WPS" "$(( SIZE_END - SIZE_PRE_WPS ))" "$SIZE_END"
