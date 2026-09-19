#!/data/data/com.termux/files/usr/bin/bash
#
# install-autostart.sh — start WPS automatically when the phone boots.
#
# Uses Termux:Boot, the companion app that runs scripts in ~/.termux/boot/
# after the device finishes booting. No root required.
#
#   bash scripts/install-autostart.sh              # warm start (recommended)
#   BOOT_MODE=full bash scripts/install-autostart.sh
#   BOOT_APP=et bash scripts/install-autostart.sh
#   bash scripts/install-autostart.sh --uninstall
#
# BOOT_MODE=warm (default)
#   On boot, bring up the container, the X server and WPS, but leave the
#   Termux:X11 window closed. WPS is already running and rendering; opening
#   the Termux:X11 app puts it on screen instantly. Nothing appears over
#   whatever you were doing.
#
# BOOT_MODE=full
#   Also foreground the Termux:X11 window, so the phone boots straight into
#   WPS. See the Android background-activity caveat printed at the end.
#
# BOOT_APP=writer|et|wpp|pdf|desktop|default   which app to start (default: default)
#
set -euo pipefail

BOOT_MODE="${BOOT_MODE:-warm}"
BOOT_APP="${BOOT_APP:-default}"
BOOT_DIR="$HOME/.termux/boot"
HOOK="$BOOT_DIR/10-pcwps"
LOG="$HOME/.cache/pc-wps/boot.log"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ -d /data/data/com.termux/files/usr ] || die "This must be run inside Termux."

if [ "${1:-}" = --uninstall ]; then
  if [ -e "$HOOK" ]; then rm -f "$HOOK"; log "Removed $HOOK — WPS will no longer start on boot."
  else log "No boot hook installed; nothing to do."; fi
  exit 0
fi

case "$BOOT_MODE" in warm|full) ;; *) die "BOOT_MODE must be 'warm' or 'full'" ;; esac
case "$BOOT_APP" in
  default|desktop|writer|wps|et|wpp|pdf) ;;
  *) die "BOOT_APP must be one of: default desktop writer et wpp pdf" ;;
esac

command -v pcwps >/dev/null || die "pcwps is not installed. Run install.sh first."

if ! pm list packages 2>/dev/null | grep -q 'com\.termux\.boot'; then
  cat >&2 <<'MSG'
[x] Termux:Boot is not installed.

    It is a separate companion app — the piece that actually runs anything at
    boot. Get the APK from:

        https://f-droid.org/packages/com.termux.boot/
        https://github.com/termux/termux-boot/releases

    Install it, OPEN IT ONCE (it does nothing visible, but it will not run
    your scripts until it has been launched at least once), then re-run this.
MSG
  exit 1
fi

# The boot hook itself. Termux:Boot runs each executable in ~/.termux/boot/ in
# name order once the device has booted.
mkdir -p "$BOOT_DIR" "$(dirname "$LOG")"

if [ "$BOOT_MODE" = warm ]; then WINDOW_FLAG=" --no-window"; else WINDOW_FLAG=""; fi

cat > "$HOOK" <<HOOKEOF
#!/data/data/com.termux/files/usr/bin/bash
#
# Starts WPS at boot. Written by scripts/install-autostart.sh.
# Remove this file (or run install-autostart.sh --uninstall) to stop it.
#
# Without a wake lock Android suspends Termux moments after boot and the
# session dies before WPS has finished starting.
termux-wake-lock

# Give the system a moment to settle; storage and networking are not
# necessarily ready the instant Termux:Boot fires.
sleep 10

exec pcwps ${BOOT_APP}${WINDOW_FLAG} --quiet >> "$LOG" 2>&1
HOOKEOF

chmod 0700 "$HOOK"

log "Installed $HOOK"
log "  mode: $BOOT_MODE    app: $BOOT_APP    log: $LOG"

cat <<'MSG'

  Two things Android will otherwise undo for you:

  1. Exempt Termux from battery optimisation
       Settings -> Apps -> Termux -> Battery -> Unrestricted
     You already have DontKillMyApp installed — use it to check this stuck.

  2. Allow Termux to autostart
     On HyperOS/MIUI, ColorOS, OneUI and friends this is a separate toggle
     from battery optimisation, usually under Settings -> Apps -> Permissions
     -> Autostart (or "Auto-launch").

MSG

if [ "$BOOT_MODE" = full ]; then
  cat <<'MSG'
  BOOT_MODE=full caveat: since Android 10, an app cannot bring an activity to
  the foreground from the background without permission. To make the window
  actually appear at boot, grant Termux:X11 "Display over other apps"
  (Settings -> Apps -> Termux:X11 -> Display over other apps).

  If it still does not surface, that is the OS refusing the activity start,
  not this script — WPS is running regardless, so opening the Termux:X11 app
  shows it immediately. BOOT_MODE=warm avoids the problem entirely.

MSG
fi

cat <<MSG
  Test it without rebooting:

      bash $HOOK

  Then check $LOG, and reboot once you are happy.

MSG
