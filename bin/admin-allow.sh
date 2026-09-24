#!/usr/bin/env bash
# Chooses which computers may open the admin panel (https://<server>:8443).
# The panel's Security page does the same; this is the way back in if you locked yourself out
# or your laptop got a new address.
#
# Usage:
#   sudo admin-allow.sh                 show the list
#   sudo admin-allow.sh add             allow the computer you are SSH'd in from
#   sudo admin-allow.sh add 10.21.4.57  allow one address (or a range, like 10.21.4.0/24)
#   sudo admin-allow.sh remove 10.21.4.57
set -euo pipefail

ALLOW_FILE="/etc/5cs045/admin-allow.conf"
[[ $EUID -eq 0 ]] || { echo "ERROR: run this with sudo" >&2; exit 1; }

entries() {
  [[ -f "$ALLOW_FILE" ]] || return 0
  awk '$1 == "allow" { sub(/;$/, "", $2); if ($2 != "127.0.0.1" && $2 != "::1") print $2 }' "$ALLOW_FILE"
}

# The address of the SSH connection that ran sudo
my_address() {
  local ip="${SSH_CLIENT:-}"; ip="${ip%% *}"
  [[ -n "$ip" ]] || ip="$(who -m 2>/dev/null | sed -n 's/.*(\(.*\)).*/\1/p')"
  echo "$ip"
}

valid() {
  local a="$1" ip bits
  ip="${a%/*}"
  bits="${a#*/}"
  [[ "$a" == */* ]] || bits=""
  if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    IFS=. read -r o1 o2 o3 o4 <<<"$ip"
    (( o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 )) || return 1
    [[ -z "$bits" ]] || { [[ "$bits" =~ ^[0-9]+$ ]] && (( bits >= 8 && bits <= 32 )); }
  elif [[ "$ip" =~ ^[0-9a-fA-F:]+$ && "$ip" == *:* ]]; then
    [[ -z "$bits" ]] || { [[ "$bits" =~ ^[0-9]+$ ]] && (( bits >= 8 && bits <= 128 )); }
  else
    return 1
  fi
}

write() {
  local old tmp
  install -d -m 755 "$(dirname "$ALLOW_FILE")"
  old="$(cat "$ALLOW_FILE" 2>/dev/null || true)"
  tmp="$(mktemp)"
  {
    echo "# Addresses allowed to open the admin panel. Written by the panel (Security page)"
    echo "# or bin/admin-allow.sh. The server itself is always allowed."
    echo "allow 127.0.0.1;"
    echo "allow ::1;"
    local e
    for e in "$@"; do echo "allow ${e};"; done
    echo "deny all;"
  } > "$tmp"
  install -m 644 "$tmp" "$ALLOW_FILE"
  rm -f "$tmp"
  if ! nginx -t >/dev/null 2>&1; then
    printf '%s\n' "$old" > "$ALLOW_FILE"
    echo "ERROR: nginx rejected the new list, so nothing was changed. See: sudo nginx -t" >&2
    exit 1
  fi
  if [[ -d /run/systemd/system ]]; then systemctl reload nginx; else nginx -s reload; fi
}

mapfile -t LIST < <(entries)
case "${1:-list}" in
  list)
    ;;
  add)
    addr="${2:-$(my_address)}"
    [[ -n "$addr" ]] || { echo "ERROR: could not tell which computer you are on. Give the address: $0 add 10.21.4.57" >&2; exit 1; }
    valid "$addr" || { echo "ERROR: '$addr' is not an IP address or range (like 10.21.4.57 or 10.21.4.0/24)" >&2; exit 1; }
    if printf '%s\n' "${LIST[@]}" | grep -qxF -- "$addr"; then
      echo "${addr} is already allowed."
    else
      LIST+=("$addr")
      write "${LIST[@]}"
      echo "Allowed ${addr}."
    fi
    ;;
  remove)
    addr="${2:-}"
    [[ -n "$addr" ]] || { echo "Usage: $0 remove <address>" >&2; exit 1; }
    KEEP=()
    for e in "${LIST[@]}"; do [[ "$e" == "$addr" ]] || KEEP+=("$e"); done
    [[ ${#KEEP[@]} -lt ${#LIST[@]} ]] || { echo "${addr} is not on the list."; exit 0; }
    LIST=("${KEEP[@]}")
    write "${LIST[@]}"
    echo "Removed ${addr}."
    ;;
  *)
    echo "Usage: $0 [list | add [address] | remove <address>]" >&2
    exit 1
    ;;
esac

echo ""
echo "Computers that may open the admin panel:"
if [[ ${#LIST[@]} -eq 0 ]]; then
  echo "  (none yet, only the server itself. Add yours with: sudo $0 add)"
else
  printf '  %s\n' "${LIST[@]}"
fi
