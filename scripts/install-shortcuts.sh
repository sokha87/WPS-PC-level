#!/data/data/com.termux/files/usr/bin/bash
#
# install-shortcuts.sh — put WPS icons on the Android home screen.
#
# Uses Termux:Widget, the companion app that turns scripts in ~/.shortcuts/
# into home-screen shortcuts and widgets. No root required.
#
#   bash scripts/install-shortcuts.sh
#   bash scripts/install-shortcuts.sh --uninstall
#
# Icons are copied out of the WPS installation inside the container, so they
# are the real application icons rather than something approximated here.
#
set -euo pipefail

DISTRO="${DISTRO:-debian}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/common.sh
. "$HERE/common.sh"
SHORTCUTS="$HOME/.shortcuts"
ICONS="$SHORTCUTS/icons"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ -d /data/data/com.termux/files/usr ] || die "This must be run inside Termux."

# name|pcwps mode|icon keyword
ENTRIES=(
  "WPS Writer|writer|wps"
  "WPS Sheets|et|et"
  "WPS Slides|wpp|wpp"
  "WPS PDF|pdf|pdf"
)

if [ "${1:-}" = --uninstall ]; then
  for e in "${ENTRIES[@]}"; do
    name="${e%%|*}"
    rm -f "$SHORTCUTS/$name" "$ICONS/$name.png"
  done
  rm -f "$SHORTCUTS/WPS Desktop" "$ICONS/WPS Desktop.png"
  log "Removed the WPS shortcuts. Drag the icons off your home screen to finish."
  exit 0
fi

command -v pcwps >/dev/null || die "pcwps is not installed. Run install.sh first."
ROOTFS="$(find_rootfs "$DISTRO")" || die "No '$DISTRO' container found. Run install.sh first."

# Android package-visibility rules often hide other apps from `pm list
# packages` when it is run from Termux, so a negative result here means
# "could not tell", not "not installed". Warn and carry on: the shortcuts are
# harmless if the app turns out to be missing.
if ! pm list packages 2>/dev/null | grep -q 'com\.termux\.widget'; then
  warn "Could not confirm Termux:Widget is installed (Android may be hiding it)."
  warn "If the icons never appear, install it from:"
  warn "  https://f-droid.org/packages/com.termux.widget/"
  warn "  https://github.com/termux/termux-widget/releases"
fi

# Termux:Widget refuses to read ~/.shortcuts if it is group- or world-readable.
mkdir -p "$SHORTCUTS" "$ICONS"
chmod 700 "$SHORTCUTS"

# ------------------------------------------------------------------- icons
# WPS installs its icons into the usual hicolor theme. Pick the largest size
# available for each app; fall back to whatever the package ships in its own
# resource tree.
find_icon() {  # find_icon <keyword> -> path inside the rootfs, or empty
  local kw="$1" best="" best_px=0 px f
  while IFS= read -r f; do
    px="$(printf '%s\n' "$f" | sed -n 's#.*/hicolor/\([0-9]\+\)x[0-9]\+/.*#\1#p')"
    px="${px:-0}"
    if [ "$px" -gt "$best_px" ]; then best="$f"; best_px="$px"; fi
  done < <(find "$ROOTFS/usr/share/icons/hicolor" \
                \( -name "*${kw}main*.png" -o -name "*office-${kw}*.png" \) \
                -print 2>/dev/null)

  if [ -z "$best" ]; then
    best="$(find "$ROOTFS/opt/kingsoft/wps-office" -name "*${kw}*.png" 2>/dev/null \
            | grep -iv 'template\|splash' | sort | tail -n1 || true)"
  fi
  printf '%s' "$best"
}

# --------------------------------------------------------------- shortcuts

made=0
for e in "${ENTRIES[@]}"; do
  IFS='|' read -r name mode kw <<< "$e"

  # Skip apps this WPS build doesn't ship (the PDF reader is not always there).
  case "$mode" in
    writer) bin=wps ;;
    pdf)    bin=wpspdf ;;
    *)      bin="$mode" ;;
  esac
  [ -x "$ROOTFS/usr/bin/$bin" ] || { warn "skipping $name — /usr/bin/$bin not in the container"; continue; }

  cat > "$SHORTCUTS/$name" <<HOOKEOF
#!/data/data/com.termux/files/usr/bin/bash
# $name — home-screen shortcut written by scripts/install-shortcuts.sh
exec pcwps $mode
HOOKEOF
  chmod 700 "$SHORTCUTS/$name"

  icon="$(find_icon "$kw")"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    cp -f "$icon" "$ICONS/$name.png"
  else
    warn "no icon found for $name — it will use the default Termux icon"
  fi
  made=$(( made + 1 ))
done

# On a desktop build, offer the full session too.
if [ "$(cat "$ROOTFS/etc/pc-wps-profile" 2>/dev/null || echo slim)" = desktop ]; then
  cat > "$SHORTCUTS/WPS Desktop" <<'HOOKEOF'
#!/data/data/com.termux/files/usr/bin/bash
exec pcwps desktop
HOOKEOF
  chmod 700 "$SHORTCUTS/WPS Desktop"
  made=$(( made + 1 ))
fi

[ "$made" -gt 0 ] || die "No shortcuts created — is WPS actually installed in the container?"

log "Created $made shortcut(s) in $SHORTCUTS"
ls -1 "$SHORTCUTS" | sed 's/^/     /'

cat <<'MSG'

  To put them on your home screen:

    Long-press the home screen -> Widgets -> Termux:Widget
      "Termux shortcut"  — a single icon for one app (add one per app)
      "Termux widget"    — a small list of all of them in one tile

  Android does not let an app create home-screen icons by itself, so this last
  step is yours. Once placed, tapping an icon starts WPS and brings up the
  window; tapping it again while WPS is running just surfaces the window
  instead of restarting anything.

MSG
