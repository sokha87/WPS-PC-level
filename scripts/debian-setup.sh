#!/bin/bash
#
# debian-setup.sh — runs INSIDE the proot Debian container.
# Installs an XFCE session, fonts, and WPS Office for Linux (arm64).
# Invoked by ../install.sh; you normally don't run this by hand.
#
set -euo pipefail

log()  { printf '\033[1;34m  ->\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  [!]\033[0m %s\n' "$*" >&2; }

export DEBIAN_FRONTEND=noninteractive

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
STAGE=/root/pc-wps
DEB="$STAGE/wps-office_arm64.deb"

[ -f "$DEB" ] || { echo "missing $DEB" >&2; exit 1; }

log "Refreshing apt"
apt-get update -y

log "Installing desktop, X11 and audio packages"
# xfce4 is the one package we genuinely cannot proceed without.
apt-get install -y --no-install-recommends xfce4 dbus-x11 || {
  echo "failed to install the XFCE desktop" >&2; exit 1; }
apt_try xfce4-terminal xfce4-settings \
        x11-xserver-utils xdg-utils \
        libgl1 libglu1-mesa libegl1 mesa-utils \
        pulseaudio-utils ca-certificates curl \
        desktop-file-utils shared-mime-info

log "Installing fonts (Latin, CJK, Khmer) so documents render correctly"
apt_try fonts-liberation fonts-dejavu-core fonts-noto-core \
        fonts-noto-cjk fonts-khmeros fonts-khmeros-core

# WPS's .deb was built against older Debian and asks for library sonames that
# current Debian no longer ships under those exact names. Install the modern
# equivalents and provide the old sonames as symlinks, then force the install.
log "Installing WPS runtime dependencies"
apt_try libcups2 libcups2t64 libxss1 libnss3 libasound2 libasound2t64 \
        libxcomposite1 libxcursor1 libxdamage1 libxi6 libxrandr2 libxtst6 \
        libgtk-3-0 libgtk-3-0t64 libatk1.0-0 libatk1.0-0t64 libcairo2 \
        libpango-1.0-0 libfontconfig1 libfreetype6 libpng16-16 \
        libjpeg62-turbo libxml2 libtiff6 libtiff5

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
link_compat libssl.so.1.1    'libssl.so.*'
link_compat libcrypto.so.1.1 'libcrypto.so.*'
ldconfig

log "Installing WPS Office (this unpacks ~1 GB, be patient)"
if ! apt-get install -y "$DEB"; then
  warn "apt refused the package; forcing and repairing dependencies"
  dpkg -i --force-depends "$DEB" || true
  apt-get -f install -y || warn "apt -f install left some deps unsatisfied; WPS often still runs"
fi

command -v wps >/dev/null || { echo "WPS did not install — /usr/bin/wps is missing" >&2; exit 1; }

log "Installing the session launcher"
install -m 0755 "$STAGE/start-wps-session" /usr/local/bin/start-wps-session

# Autostart WPS when the XFCE desktop comes up, unless launched in app mode.
install -d /root/.config/autostart
cat > /root/.config/autostart/wps-office.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=WPS Office
Exec=/usr/bin/wps
Terminal=false
X-GNOME-Autostart-enabled=true
DESKTOP

# proot has no functional hardware GL; force the software rasteriser so WPS's
# Qt/GTK surfaces don't fall over on first paint.
cat > /etc/profile.d/pc-wps.sh <<'PROFILE'
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export QT_X11_NO_MITSHM=1
export _JAVA_AWT_WM_NONREPARENTING=1
PROFILE

log "Trimming apt caches"
apt-get clean
rm -rf /var/lib/apt/lists/*

log "Container setup complete"
