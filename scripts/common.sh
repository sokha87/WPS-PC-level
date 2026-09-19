# common.sh — shared helpers, sourced by the other scripts. Not executable.
#
# proot-distro has moved its rootfs directory between versions, so nothing here
# hardcodes that path: containers are created through proot-distro itself, and
# the rootfs is located by looking for it rather than by assuming.

# find_rootfs <alias> -> prints the rootfs path, or returns 1
find_rootfs() {
  local distro="$1" base="$PREFIX/var/lib/proot-distro" d
  for d in "$base/installed-rootfs/$distro" \
           "$base/installed-rootfs/$distro/root" \
           "$base/$distro"; do
    [ -d "$d/usr/bin" ] && { printf '%s' "$d"; return 0; }
  done
  # Fall back to searching, in case a future version moves it again.
  d="$(find "$base" -maxdepth 4 -type d -name bin -path "*$distro*/usr/bin" \
       2>/dev/null | head -n1)"
  [ -n "$d" ] && { printf '%s' "${d%/usr/bin}"; return 0; }
  return 1
}

# ensure_distro <alias> — install the container unless it is already there.
# Three layers, because no single check works across proot-distro versions:
# ask proot-distro, then look for the rootfs, then just try the install and
# treat "already exists" as success.
ensure_distro() {
  local distro="$1" tmp rc

  if proot-distro list --installed 2>/dev/null | grep -qw -- "$distro"; then
    return 0
  fi
  if find_rootfs "$distro" >/dev/null 2>&1; then
    return 0
  fi

  # Streamed, not captured: the first install pulls a few hundred MB and the
  # progress bar is the only sign it is working.
  tmp="$(mktemp)"
  proot-distro install "$distro" 2>&1 | tee "$tmp"
  rc="${PIPESTATUS[0]}"
  if [ "$rc" -eq 0 ] || grep -qi 'already exists' "$tmp"; then
    rm -f "$tmp"; return 0
  fi
  rm -f "$tmp"; return 1
}
