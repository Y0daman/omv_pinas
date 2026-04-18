#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  Local:
    ./securityHardening.sh -u USER [-p PASSWORD]

  Remote:
    ./securityHardening.sh -u USER [-p PASSWORD] --ip IP

Options:
  -u, --user USER         Target username to harden SSH for (required)
  -p, --password PASSWORD Optional password used for ssh/sudo automation
      --identity PATH      Optional SSH private key to use for remote login
      --ip IP             Remote target IP (if omitted, harden local machine)
      --allow-password-on-lan  Allow password login from RFC1918 LAN ranges (default)
      --no-password-on-lan     Do not allow password login on LAN
  -h, --help              Show this help

What this script does:
  1) Verifies SSH key login for the target user (local or remote).
  2) If key login is missing, asks whether to use an existing key or generate a new one,
     then tries to install the selected public key with ssh-copy-id.
  3) If key login still cannot be verified, asks whether to continue without disabling
     PasswordAuthentication.
  4) Applies hardening (Ubuntu/Debian):
     - SSH hardening: disable root login, prefer key auth, tighten auth settings.
     - By default allows password login only from LAN (RFC1918); internet stays key-only.
     - fail2ban for sshd.
     - Geo firewall: allow LAN + Sweden IPv4 ranges, drop other inbound.
     - Restrictive IPv6 input policy (allow local/established, drop the rest).
     - Daily auto-refresh timer for Sweden IP ranges.
     - Installs report command: sudo /usr/local/sbin/geo-firewall-report.sh <days>

Notes:
  - Local mode asks for a final confirmation before changes.
  - If --password is omitted, ssh/sudo may prompt interactively.
EOF
}

log() {
  printf '[+] %s\n' "$*"
}

warn() {
  printf '[!] %s\n' "$*" >&2
}

die() {
  printf '[x] %s\n' "$*" >&2
  exit 1
}

KEY_CHECK_STATUS="skipped"
KEY_INSTALL_STATUS="skipped"
CONFIRM_STATUS="skipped"
HARDEN_STATUS="skipped"
PACKAGES_INSTALL_STATUS="skipped"
APPLY_SSH_HARDENING_STATUS="skipped"
CONFIGURED_FAIL2BAN_STATUS="skipped"
SCRIPTS_INSTALLED_STATUS="skipped"
SERVICES_INSTALLED_STATUS="skipped"
LAN_PASSWORD_LOGIN_STATUS="skipped"
SHOW_SUMMARY="0"

if [[ -t 1 ]]; then
  CLR_RED='\033[31m'
  CLR_GREEN='\033[32m'
  CLR_YELLOW='\033[33m'
  CLR_BLUE='\033[34m'
  CLR_RESET='\033[0m'
else
  CLR_RED=''
  CLR_GREEN=''
  CLR_YELLOW=''
  CLR_BLUE=''
  CLR_RESET=''
fi

colorize_status() {
  local s="$1"
  case "$s" in
    success|allowed|"allowed (password auth enabled globally)")
      printf '%b%s%b' "$CLR_GREEN" "$s" "$CLR_RESET"
      ;;
    failed|disabled)
      printf '%b%s%b' "$CLR_RED" "$s" "$CLR_RESET"
      ;;
    skipped)
      printf '%b%s%b' "$CLR_YELLOW" "$s" "$CLR_RESET"
      ;;
    *)
      printf '%b%s%b' "$CLR_BLUE" "$s" "$CLR_RESET"
      ;;
  esac
}

print_summary() {
  [[ "$SHOW_SUMMARY" == "1" ]] || return 0
  printf '\n=== securityHardening summary ===\n'
  printf 'key_check: %b\n' "$(colorize_status "$KEY_CHECK_STATUS")"
  printf 'key_install: %b\n' "$(colorize_status "$KEY_INSTALL_STATUS")"
  printf 'packages_install: %b\n' "$(colorize_status "$PACKAGES_INSTALL_STATUS")"
  printf 'apply_ssh_hardening: %b\n' "$(colorize_status "$APPLY_SSH_HARDENING_STATUS")"
  printf 'configured_fail2ban: %b\n' "$(colorize_status "$CONFIGURED_FAIL2BAN_STATUS")"
  printf 'scripts_installed: %b\n' "$(colorize_status "$SCRIPTS_INSTALLED_STATUS")"
  printf 'services_installed: %b\n' "$(colorize_status "$SERVICES_INSTALLED_STATUS")"
  printf 'lan_password_login: %b\n' "$(colorize_status "$LAN_PASSWORD_LOGIN_STATUS")"
}

trap print_summary EXIT

ask_yes_no() {
  local prompt="$1"
  local default_no="${2:-1}"
  local reply

  if [[ "$default_no" == "1" ]]; then
    read -r -p "$prompt [y/N]: " reply
    [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
  else
    read -r -p "$prompt [Y/n]: " reply
    [[ -z "$reply" || "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
  fi
}

list_pubkeys() {
  local c
  for c in "$HOME"/.ssh/*.pub; do
    [[ -f "$c" ]] && printf '%s\n' "$c"
  done
}

select_or_generate_pubkey_interactive() {
  local -a keys
  local i choice gen_idx

  mapfile -t keys < <(list_pubkeys)
  (( ${#keys[@]} > 0 )) || return 1

  echo "Available public keys:"
  i=1
  for key in "${keys[@]}"; do
    echo "  ${i}) ${key}"
    ((i++))
  done
  gen_idx=$(( ${#keys[@]} + 1 ))
  echo "  ${gen_idx}) GENERATE NEW KEY"

  while true; do
    read -r -p "Choose key number: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      if (( choice >= 1 && choice <= ${#keys[@]} )); then
        SELECTED_PUBKEY="${keys[$((choice-1))]}"
        return 0
      fi
      if (( choice == gen_idx )); then
        generate_new_key_interactive
        return 0
      fi
    fi
    warn "Invalid selection. Enter a number between 1 and ${gen_idx}."
  done
}

generate_new_key_interactive() {
  local key_path comment default_comment

  read -r -p "Private key path [~/.ssh/id_ed25519]: " key_path
  key_path="${key_path:-~/.ssh/id_ed25519}"
  key_path="${key_path/#\~/$HOME}"

  default_comment="${USER}@$(hostname)-$(date +%Y%m%d)"
  read -r -p "Key comment [${default_comment}]: " comment
  comment="${comment:-$default_comment}"

  mkdir -p "$(dirname "$key_path")"
  ssh-keygen -t ed25519 -a 100 -f "$key_path" -C "$comment"

  SELECTED_PUBKEY="${key_path}.pub"
  [[ -f "$SELECTED_PUBKEY" ]] || die "Generated key missing: $SELECTED_PUBKEY"
  if [[ -z "$IDENTITY_FILE" ]]; then
    IDENTITY_FILE="$key_path"
  fi
}

ensure_pubkey_for_install() {
  local -a keys

  if [[ -n "$SELECTED_PUBKEY" && -f "$SELECTED_PUBKEY" ]]; then
    return 0
  fi

  if [[ -n "$IDENTITY_FILE" && -f "${IDENTITY_FILE}.pub" ]]; then
    SELECTED_PUBKEY="${IDENTITY_FILE}.pub"
    return 0
  fi

  mapfile -t keys < <(list_pubkeys)
  if (( ${#keys[@]} == 0 )); then
    warn "No local SSH public keys found in ~/.ssh/*.pub"
    if ask_yes_no "Generate a new SSH key now?" 1; then
      generate_new_key_interactive
      return 0
    fi
    die "Cannot continue without a public key to install."
  fi

  echo "SSH key login is not verified on target."
  select_or_generate_pubkey_interactive || die "No public keys available"
  if [[ -z "$IDENTITY_FILE" ]]; then
    IDENTITY_FILE="${SELECTED_PUBKEY%.pub}"
  fi
}

emit_hardening_payload() {
  cat <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

HARDEN_USER="$1"
DISABLE_PASSWORD_AUTH="$2"
ALLOW_PASSWORD_ON_LAN="$3"

if [[ "$DISABLE_PASSWORD_AUTH" == "yes" ]]; then
  PASS_AUTH_VALUE="no"
else
  PASS_AUTH_VALUE="yes"
fi

echo "[STEP] Installing required packages (fail2ban, ipset, iptables-persistent, curl)"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y fail2ban ipset iptables-persistent netfilter-persistent curl

echo "[STEP] Applying SSH hardening settings"

install -d -m 755 /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/99-hardening.conf <<EOF
PermitRootLogin no
PasswordAuthentication ${PASS_AUTH_VALUE}
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 20
AllowUsers ${HARDEN_USER}
EOF

if [[ "$ALLOW_PASSWORD_ON_LAN" == "yes" && "$PASS_AUTH_VALUE" == "no" ]]; then
  cat >>/etc/ssh/sshd_config.d/99-hardening.conf <<'EOF'

Match Address 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
  PasswordAuthentication yes
  KbdInteractiveAuthentication yes
EOF
fi

sshd -t
systemctl restart ssh

echo "[STEP] Configuring fail2ban for sshd"

install -d -m 755 /etc/fail2ban/jail.d
cat >/etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = systemd
maxretry = 4
findtime = 10m
bantime = 1h
bantime.increment = true
bantime.factor = 2
bantime.max = 1d
EOF

systemctl enable --now fail2ban

echo "[STEP] Writing GeoIP firewall scripts and whitelist templates"

install -d -m 755 /etc/firewall
cat >/etc/firewall/geo-whitelist-v4.txt <<'EOF'
# One IPv4 or CIDR per line to always allow before geoblock.
# Examples:
# 203.0.113.10
# 198.51.100.0/24
EOF

cat >/etc/firewall/geo-whitelist-v6.txt <<'EOF'
# One IPv6 or CIDR per line to always allow before geoblock.
# Examples:
# 2001:db8::10
# 2001:db8:1234::/48
EOF

cat >/usr/local/sbin/update-se-firewall.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SE_URL="https://www.ipdeny.com/ipblocks/data/countries/se.zone"
TMP_SET="se_ipv4_new"
MAIN_SET="se_ipv4"
WL4_FILE="/etc/firewall/geo-whitelist-v4.txt"
WL6_FILE="/etc/firewall/geo-whitelist-v6.txt"

ipset create "$TMP_SET" hash:net family inet -exist
ipset flush "$TMP_SET"

while IFS= read -r cidr; do
  [[ -z "$cidr" ]] && continue
  [[ "$cidr" =~ ^# ]] && continue
  ipset add "$TMP_SET" "$cidr" -exist
done < <(curl -fsSL "$SE_URL")

ipset create "$MAIN_SET" hash:net family inet -exist
ipset swap "$TMP_SET" "$MAIN_SET"
ipset destroy "$TMP_SET" || true

iptables -N GEOFILTER 2>/dev/null || true
iptables -F GEOFILTER
iptables -A GEOFILTER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
iptables -A GEOFILTER -i lo -j RETURN
iptables -A GEOFILTER -s 10.0.0.0/8 -j RETURN
iptables -A GEOFILTER -s 172.16.0.0/12 -j RETURN
iptables -A GEOFILTER -s 192.168.0.0/16 -j RETURN

if [[ -f "$WL4_FILE" ]]; then
  while IFS= read -r cidr; do
    [[ -z "$cidr" ]] && continue
    [[ "$cidr" =~ ^# ]] && continue
    iptables -A GEOFILTER -s "$cidr" -j RETURN
  done < "$WL4_FILE"
fi

iptables -A GEOFILTER -m set --match-set "$MAIN_SET" src -j RETURN
iptables -A GEOFILTER -m limit --limit 12/min --limit-burst 30 -j LOG --log-prefix "GEO-DROP4 " --log-level 4
iptables -A GEOFILTER -j DROP
iptables -C INPUT -j GEOFILTER 2>/dev/null || iptables -I INPUT 1 -j GEOFILTER

ip6tables -N GEO6FILTER 2>/dev/null || true
ip6tables -F GEO6FILTER
ip6tables -A GEO6FILTER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
ip6tables -A GEO6FILTER -i lo -j RETURN
ip6tables -A GEO6FILTER -s fc00::/7 -j RETURN
ip6tables -A GEO6FILTER -s fe80::/10 -j RETURN

if [[ -f "$WL6_FILE" ]]; then
  while IFS= read -r cidr; do
    [[ -z "$cidr" ]] && continue
    [[ "$cidr" =~ ^# ]] && continue
    ip6tables -A GEO6FILTER -s "$cidr" -j RETURN
  done < "$WL6_FILE"
fi

ip6tables -A GEO6FILTER -m limit --limit 12/min --limit-burst 30 -j LOG --log-prefix "GEO-DROP6 " --log-level 4
ip6tables -A GEO6FILTER -j DROP
ip6tables -C INPUT -j GEO6FILTER 2>/dev/null || ip6tables -I INPUT 1 -j GEO6FILTER

ipset save > /etc/iptables/ipset.rules
netfilter-persistent save >/dev/null 2>&1 || true
EOF
chmod 755 /usr/local/sbin/update-se-firewall.sh

cat >/usr/local/sbin/geo-firewall-report.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

arg="${1:-1}"
if [[ "$arg" =~ ^[0-9]+$ ]]; then
  since="${arg} days ago"
else
  since="$arg"
fi

echo "Geo firewall report since: $since"
echo

echo "Top IPv4 blocked sources (GEO-DROP4):"
journalctl -k --since "$since" --no-pager | grep "GEO-DROP4" | grep -oE "SRC=([0-9]{1,3}\\.){3}[0-9]{1,3}" | cut -d= -f2 | sort | uniq -c | sort -nr | head -n 25 || true
echo
echo "Top IPv6 blocked sources (GEO-DROP6):"
journalctl -k --since "$since" --no-pager | grep "GEO-DROP6" | grep -oE "SRC=[0-9a-fA-F:]+" | cut -d= -f2 | sort | uniq -c | sort -nr | head -n 25 || true
echo
echo "Recent block events:"
journalctl -k --since "$since" --no-pager | grep -E "GEO-DROP4|GEO-DROP6" | tail -n 30 || true
EOF
chmod 755 /usr/local/sbin/geo-firewall-report.sh

cat >/etc/systemd/system/update-se-firewall.service <<'EOF'
[Unit]
Description=Update Sweden GeoIP firewall set and rules
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/update-se-firewall.sh
EOF

cat >/etc/systemd/system/update-se-firewall.timer <<'EOF'
[Unit]
Description=Refresh Sweden GeoIP firewall set daily

[Timer]
OnBootSec=3min
OnUnitActiveSec=24h
Persistent=true

[Install]
WantedBy=timers.target
EOF

cat >/etc/systemd/system/ipset-restore.service <<'EOF'
[Unit]
Description=Restore ipset rules
Before=netfilter-persistent.service
DefaultDependencies=no
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'ipset restore < /etc/iptables/ipset.rules || true'

[Install]
WantedBy=multi-user.target
EOF

/usr/local/sbin/update-se-firewall.sh
systemctl daemon-reload
systemctl enable --now update-se-firewall.timer
systemctl enable ipset-restore.service
systemctl restart netfilter-persistent || true

echo "[STEP] Hardening tasks completed"
echo "Hardening complete. PasswordAuthentication=${PASS_AUTH_VALUE}"
EOS
}

USER_NAME=""
PASSWORD=""
TARGET_IP=""
IDENTITY_FILE=""
SELECTED_PUBKEY=""
ALLOW_PASSWORD_ON_LAN="yes"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--user)
      USER_NAME="${2:-}"
      shift 2
      ;;
    -p|--password)
      PASSWORD="${2:-}"
      shift 2
      ;;
    --ip)
      TARGET_IP="${2:-}"
      shift 2
      ;;
    --identity)
      IDENTITY_FILE="${2:-}"
      shift 2
      ;;
    --allow-password-on-lan)
      ALLOW_PASSWORD_ON_LAN="yes"
      shift
      ;;
    --no-password-on-lan)
      ALLOW_PASSWORD_ON_LAN="no"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$USER_NAME" ]] || die "--user is required"
SHOW_SUMMARY="1"

MODE="local"
if [[ -n "$TARGET_IP" ]]; then
  MODE="remote"
fi

if [[ -n "$PASSWORD" ]] && ! command -v sshpass >/dev/null 2>&1; then
  warn "Password provided but sshpass is not installed. Falling back to interactive prompts."
fi

if [[ -n "$IDENTITY_FILE" ]]; then
  [[ -f "$IDENTITY_FILE" ]] || die "--identity file not found: $IDENTITY_FILE"
fi

ssh_remote_base_opts() {
  local -a opts
  opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
  if [[ -n "$IDENTITY_FILE" ]]; then
    opts+=(-i "$IDENTITY_FILE" -o IdentitiesOnly=yes)
  fi
  printf '%s\n' "${opts[@]}"
}

discover_remote_identity() {
  local key pub
  [[ -n "$IDENTITY_FILE" ]] && return 0

  for key in "$HOME/.ssh"/*; do
    [[ -f "$key" ]] || continue
    [[ "$key" == *.pub ]] && continue
    [[ "$key" == *known_hosts* ]] && continue
    [[ "$key" == *config ]] && continue
    pub="${key}.pub"
    [[ -f "$pub" ]] || continue

    if ssh -i "$key" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 "${USER_NAME}@${TARGET_IP}" true >/dev/null 2>&1; then
      IDENTITY_FILE="$key"
      log "Detected working SSH key: $IDENTITY_FILE"
      return 0
    fi
  done

  return 1
}

check_key_login_remote() {
  local -a opts
  mapfile -t opts < <(ssh_remote_base_opts)
  ssh "${opts[@]}" "${USER_NAME}@${TARGET_IP}" true >/dev/null 2>&1
}

check_key_login_local() {
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "${USER_NAME}@localhost" true >/dev/null 2>&1
}

install_key_remote() {
  local pubkey=""
  ensure_pubkey_for_install
  pubkey="$SELECTED_PUBKEY"
  [[ -n "$pubkey" ]] || die "No SSH public key found in ~/.ssh/*.pub"
  log "Installing SSH key (${pubkey}) on ${USER_NAME}@${TARGET_IP}"
  local -a opts
  opts=(-o StrictHostKeyChecking=accept-new)
  if [[ -n "$IDENTITY_FILE" ]]; then
    opts+=(-o IdentitiesOnly=yes -i "$IDENTITY_FILE")
  fi
  if [[ -n "$PASSWORD" ]] && command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$PASSWORD" ssh-copy-id -i "$pubkey" "${opts[@]}" "${USER_NAME}@${TARGET_IP}"
  else
    ssh-copy-id -i "$pubkey" "${opts[@]}" "${USER_NAME}@${TARGET_IP}"
  fi
}

install_key_local() {
  local pubkey
  ensure_pubkey_for_install
  pubkey="$SELECTED_PUBKEY"
  [[ -n "$pubkey" ]] || die "No SSH public key found in ~/.ssh/*.pub"
  log "Installing SSH key (${pubkey}) on ${USER_NAME}@localhost"
  if [[ -n "$PASSWORD" ]] && command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$PASSWORD" ssh-copy-id -i "$pubkey" -o StrictHostKeyChecking=accept-new "${USER_NAME}@localhost"
  else
    ssh-copy-id -i "$pubkey" -o StrictHostKeyChecking=accept-new "${USER_NAME}@localhost"
  fi
}

DISABLE_PASSWORD_AUTH="yes"

if [[ "$MODE" == "remote" ]]; then
  log "Mode: remote (${TARGET_IP})"
  log "Checking SSH key login"
  discover_remote_identity || true
  if ! check_key_login_remote; then
    KEY_CHECK_STATUS="failed"
    warn "No verified key login for ${USER_NAME}@${TARGET_IP}"
    log "Trying to install SSH key"
    if install_key_remote; then
      KEY_INSTALL_STATUS="success"
    else
      KEY_INSTALL_STATUS="failed"
    fi
    discover_remote_identity || true
  else
    KEY_CHECK_STATUS="success"
    KEY_INSTALL_STATUS="skipped"
  fi

  if ! check_key_login_remote; then
    KEY_CHECK_STATUS="failed"
    warn "Key login still not verified."
    if ask_yes_no "Run all hardening but KEEP PasswordAuthentication enabled?" 1; then
      DISABLE_PASSWORD_AUTH="no"
      CONFIRM_STATUS="success"
    else
      CONFIRM_STATUS="failed"
      die "Aborted (no verified key login)."
    fi
  else
    KEY_CHECK_STATUS="success"
    if ask_yes_no "SSH key verified for ${USER_NAME}@${TARGET_IP}. Continue with hardening?" 1; then
      CONFIRM_STATUS="success"
    else
      CONFIRM_STATUS="failed"
      die "Aborted by user."
    fi
  fi
else
  log "Mode: local"
  log "Checking SSH key login"
  if ! check_key_login_local; then
    KEY_CHECK_STATUS="failed"
    warn "No verified key login for ${USER_NAME}@localhost"
    log "Trying to install SSH key"
    if install_key_local; then
      KEY_INSTALL_STATUS="success"
    else
      KEY_INSTALL_STATUS="failed"
    fi
  else
    KEY_CHECK_STATUS="success"
    KEY_INSTALL_STATUS="skipped"
  fi

  if ! check_key_login_local; then
    KEY_CHECK_STATUS="failed"
    warn "Key login still not verified."
    if ask_yes_no "Run all hardening but KEEP PasswordAuthentication enabled?" 1; then
      DISABLE_PASSWORD_AUTH="no"
      CONFIRM_STATUS="success"
    else
      CONFIRM_STATUS="failed"
      die "Aborted (no verified key login)."
    fi
  else
    KEY_CHECK_STATUS="success"
  fi

  if ! ask_yes_no "You are about to harden THIS local machine. Continue?" 1; then
    CONFIRM_STATUS="failed"
    die "Aborted by user."
  fi
  CONFIRM_STATUS="success"
fi

if [[ "$DISABLE_PASSWORD_AUTH" == "no" ]]; then
  LAN_PASSWORD_LOGIN_STATUS="allowed (password auth enabled globally)"
elif [[ "$ALLOW_PASSWORD_ON_LAN" == "yes" ]]; then
  LAN_PASSWORD_LOGIN_STATUS="allowed"
else
  LAN_PASSWORD_LOGIN_STATUS="disabled"
fi

run_local() {
  log "Applying hardening locally"
  if [[ -n "$PASSWORD" ]]; then
    if { printf '%s\n' "$PASSWORD"; emit_hardening_payload; } | sudo -S -p '' bash -s -- "$USER_NAME" "$DISABLE_PASSWORD_AUTH" "$ALLOW_PASSWORD_ON_LAN"; then
      HARDEN_STATUS="success"
      PACKAGES_INSTALL_STATUS="success"
      APPLY_SSH_HARDENING_STATUS="success"
      CONFIGURED_FAIL2BAN_STATUS="success"
      SCRIPTS_INSTALLED_STATUS="success"
      SERVICES_INSTALLED_STATUS="success"
    else
      HARDEN_STATUS="failed"
      PACKAGES_INSTALL_STATUS="failed"
      APPLY_SSH_HARDENING_STATUS="failed"
      CONFIGURED_FAIL2BAN_STATUS="failed"
      SCRIPTS_INSTALLED_STATUS="failed"
      SERVICES_INSTALLED_STATUS="failed"
      die "Hardening failed"
    fi
  else
    if emit_hardening_payload | sudo bash -s -- "$USER_NAME" "$DISABLE_PASSWORD_AUTH" "$ALLOW_PASSWORD_ON_LAN"; then
      HARDEN_STATUS="success"
      PACKAGES_INSTALL_STATUS="success"
      APPLY_SSH_HARDENING_STATUS="success"
      CONFIGURED_FAIL2BAN_STATUS="success"
      SCRIPTS_INSTALLED_STATUS="success"
      SERVICES_INSTALLED_STATUS="success"
    else
      HARDEN_STATUS="failed"
      PACKAGES_INSTALL_STATUS="failed"
      APPLY_SSH_HARDENING_STATUS="failed"
      CONFIGURED_FAIL2BAN_STATUS="failed"
      SCRIPTS_INSTALLED_STATUS="failed"
      SERVICES_INSTALLED_STATUS="failed"
      die "Hardening failed"
    fi
  fi
}

run_remote() {
  log "Applying hardening on ${TARGET_IP}"
  local -a ssh_opts
  ssh_opts=(-T -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
  if [[ -n "$IDENTITY_FILE" ]]; then
    ssh_opts+=(-o IdentitiesOnly=yes -i "$IDENTITY_FILE")
  fi
  if [[ -n "$PASSWORD" ]] && command -v sshpass >/dev/null 2>&1; then
    if { printf '%s\n' "$PASSWORD"; emit_hardening_payload; } | \
      sshpass -p "$PASSWORD" ssh "${ssh_opts[@]}" "${USER_NAME}@${TARGET_IP}" \
      "sudo -S -p '' bash -s -- '$USER_NAME' '$DISABLE_PASSWORD_AUTH' '$ALLOW_PASSWORD_ON_LAN'"; then
      HARDEN_STATUS="success"
      PACKAGES_INSTALL_STATUS="success"
      APPLY_SSH_HARDENING_STATUS="success"
      CONFIGURED_FAIL2BAN_STATUS="success"
      SCRIPTS_INSTALLED_STATUS="success"
      SERVICES_INSTALLED_STATUS="success"
    else
      HARDEN_STATUS="failed"
      PACKAGES_INSTALL_STATUS="failed"
      APPLY_SSH_HARDENING_STATUS="failed"
      CONFIGURED_FAIL2BAN_STATUS="failed"
      SCRIPTS_INSTALLED_STATUS="failed"
      SERVICES_INSTALLED_STATUS="failed"
      die "Hardening failed on remote host"
    fi
  else
    if emit_hardening_payload | \
      ssh "${ssh_opts[@]}" "${USER_NAME}@${TARGET_IP}" \
      "sudo -n bash -s -- '$USER_NAME' '$DISABLE_PASSWORD_AUTH' '$ALLOW_PASSWORD_ON_LAN'"; then
      HARDEN_STATUS="success"
      PACKAGES_INSTALL_STATUS="success"
      APPLY_SSH_HARDENING_STATUS="success"
      CONFIGURED_FAIL2BAN_STATUS="success"
      SCRIPTS_INSTALLED_STATUS="success"
      SERVICES_INSTALLED_STATUS="success"
    else
      HARDEN_STATUS="failed"
      PACKAGES_INSTALL_STATUS="failed"
      APPLY_SSH_HARDENING_STATUS="failed"
      CONFIGURED_FAIL2BAN_STATUS="failed"
      SCRIPTS_INSTALLED_STATUS="failed"
      SERVICES_INSTALLED_STATUS="failed"
      die "Hardening failed on remote host (try --password if sudo needs password)"
    fi
  fi
}

if [[ "$MODE" == "remote" ]]; then
  run_remote
else
  run_local
fi

log "Done"
