#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
if [[ $# -gt 0 ]]; then
	BINARY=$1
elif [[ -x "$SCRIPT_DIR/openvpn-admin" ]]; then
	BINARY="$SCRIPT_DIR/openvpn-admin"
else
	BINARY="$SCRIPT_DIR/../openvpn-admin"
fi
INSTALL_PATH=/usr/local/bin/openvpn-admin
ENV_FILE=/etc/openvpn/openvpn-admin
SERVICE_FILE=/etc/systemd/system/openvpn-admin.service

if [[ "$EUID" -ne 0 ]]; then
	echo "Run this installer as root (for example: sudo $0)." >&2
	exit 1
fi
if [[ "$(uname -s)" != Linux ]] || ! command -v systemctl >/dev/null; then
	echo "This installer requires Linux with systemd." >&2
	exit 1
fi
if [[ ! -x "$BINARY" ]]; then
	echo "Executable not found: $BINARY" >&2
	echo "Build openvpn-admin for the target Linux architecture first." >&2
	exit 1
fi

install -o root -g root -m 0755 "$BINARY" "$INSTALL_PATH"
if [[ ! -d /etc/openvpn ]]; then
	install -d -o root -g root -m 0755 /etc/openvpn
fi

group_name=$(awk '$1 == "group" {print $2; exit}' /etc/openvpn/server/server.conf 2>/dev/null || true)
if [[ -z "$group_name" ]]; then
	if getent group nogroup >/dev/null; then
		group_name=nogroup
	elif getent group nobody >/dev/null; then
		group_name=nobody
	fi
fi
if [[ -n "$group_name" ]] && getent group "$group_name" >/dev/null; then
	group_id=$(getent group "$group_name" | cut -d: -f3)
	password_mode=0640
	install -o root -g "$group_name" -m "$password_mode" /dev/null /etc/openvpn/psw-file.tmp
	if [[ ! -e /etc/openvpn/psw-file ]]; then
		mv /etc/openvpn/psw-file.tmp /etc/openvpn/psw-file
	else
		rm -f /etc/openvpn/psw-file.tmp
		chown root:"$group_name" /etc/openvpn/psw-file
		chmod "$password_mode" /etc/openvpn/psw-file
	fi
	for path in /etc/openvpn/psw-file.meta.json /etc/openvpn/psw-file.lock; do
		if [[ -e "$path" ]]; then
			chown root:"$group_name" "$path"
			chmod 0640 "$path"
		fi
	done
else
	group_id=
	password_mode=0600
	install -m "$password_mode" /dev/null /etc/openvpn/psw-file.tmp
	if [[ ! -e /etc/openvpn/psw-file ]]; then
		mv /etc/openvpn/psw-file.tmp /etc/openvpn/psw-file
	else
		rm -f /etc/openvpn/psw-file.tmp
		chown root:root /etc/openvpn/psw-file
		chmod "$password_mode" /etc/openvpn/psw-file
	fi
fi

if [[ ! -d /etc/openvpn ]]; then
	install -d -o root -g root -m 0755 /etc/openvpn
fi
if [[ ! -e "$ENV_FILE" ]]; then
	install -o root -g root -m 0600 /dev/null "$ENV_FILE"
fi
chmod 0600 "$ENV_FILE"

set_env() {
	local key=$1 value=$2
	if grep -q "^${key}=" "$ENV_FILE"; then
		sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
	else
		printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
	fi
}

if ! grep -q '^ADMIN_PASSWORD=.' "$ENV_FILE"; then
	command -v openssl >/dev/null || { echo "openssl is required to generate the admin password." >&2; exit 1; }
	admin_password=$(openssl rand -hex 32)
	set_env ADMIN_PASSWORD "$admin_password"
	echo "Initial admin password: $admin_password"
fi
set_env LISTEN_ADDR "${LISTEN_ADDR:-0.0.0.0:8088}"
set_env PSW_FILE /etc/openvpn/psw-file
set_env OPENVPN_STATUS_FILE /etc/openvpn/server/openvpn-status.log
if [[ -n "${CLIENT_FILE:-}" ]]; then
	set_env CLIENT_FILE "$CLIENT_FILE"
elif ! grep -q '^CLIENT_FILE=' "$ENV_FILE"; then
	set_env CLIENT_FILE /root/client.ovpn
fi
set_env PSW_FILE_MODE "$password_mode"
if [[ -n "$group_id" ]]; then
	set_env PSW_FILE_GID "$group_id"
else
	sed -i '/^PSW_FILE_GID=/d' "$ENV_FILE"
fi

install -m 0644 "$SCRIPT_DIR/openvpn-admin.service" "$SERVICE_FILE"
if systemctl list-unit-files psw-admin.service --no-legend 2>/dev/null | grep -q '^psw-admin.service'; then
	systemctl disable --now psw-admin.service
fi
systemctl daemon-reload
systemctl enable --now openvpn-admin.service
listen_addr=$(sed -n 's/^LISTEN_ADDR=//p' "$ENV_FILE" | tail -n 1)

echo "Installed and started openvpn-admin.service."
echo "Web UI: http://${listen_addr:-0.0.0.0:8088}"
