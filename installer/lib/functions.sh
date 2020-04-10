#!/usr/bin/env bash

os_pkg_install() { DEBIAN_FRONTEND=noninteractive apt install -y "${@}"; }
os_pkg_repo_update() { DEBIAN_FRONTEND=noninteractive apt update; }
os_pkg_system_update() { DEBIAN_FRONTEND=noninteractive apt upgrade -y; }

update_system() {
  os_pkg_repo_update
  os_pkg_system_update
}

enable_unattended_updates() {
  echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
  os_pkg_install unattended-upgrades apt-listchanges
  os_svc_init enable unattended-upgrades
  os_svc restart unattended-upgrades

  local upgrade_reboot_cron_file="${HOME:-/root}/upgrade-reboot-cron"
cat << 'UPGRADEREBOOTCRON' > "${upgrade_reboot_cron_file}"
#!/usr/bin/env bash

DEBIAN_FRONTEND=noninteractive apt clean -y || true
package_list=/var/run/reboot-required.pkgs
if [ -s "${package_list}" ] && [ "$(cat ${package_list}" | wc -l)" != "0" ]; then
  reboot
fi
UPGRADEREBOOTCRON
  chmod +x "${upgrade_reboot_cron_file}"

  add_cronjob "$((RANDOM % 60)) 2 * * 6 ${upgrade_reboot_cron_file}"
}

os_firewall() { ufw "${@}"; }
os_svc() { service "${2}" "${1}"; }
os_svc_init() { systemctl "${@}"; }

ensure_services_restarted() {
  local services=("${@}")
  for service in "${services[@]}"; do
    os_svc restart "${service}" && log "restarted '${service}'" || log "did not restart '${service}'"
  done
}

log() { echo "# [$(date)] $*"; }
die() { log "$*" >&2; exit 1; }

generate_passwd() { < /dev/urandom tr -dc '_A-Z-a-z-0-9@#' | head -c8; }
is_command_present() { command -v "${1}" >/dev/null 2>&1; }
is_root() { [ "$(id -u)" = "0" ]; }

add_cronjob() {
  local cron_line="${*}"
  (
    crontab -l 2>/dev/null || true
    echo "${cron_line}"
  ) | crontab -
}

define_persisted_env_variable() {
  local name="${1}"; shift
  local value="${*}"

  ensure_key_value_present /etc/profile "export ${name}" "${value}"
  eval "export ${name}='${value}'"
}

ensure_key_value_present() {
  local file="${1}"; shift
  local key="${1}"; shift
  local value="${*}"

  local tmp_file; tmp_file="$(mktemp)"
  if [ -f "${file}" ]; then
    grep -v "^${key}=" "${file}" > "${tmp_file}"
    cp "${file}"{,"$(date +%s).bak"}
    cp -f "${tmp_file}" "${file}"
  else
    mkdir -p "$(dirname "${file}")"
  fi

  echo "${key}=${value}" >> "${file}"
}

write_file_from_encoded_var() {
  local var_name="${1}"
  local file_name="${2}"
  echo "${!var_name}" | base64 -d > "${file_name}"
}

generate_self_signed_cert() {
  local fqdn="${1}"
  local key="${2}"
  local cert="${3}"

  is_command_present openssl || os_pkg_install openssl
  openssl req -newkey rsa:4096 \
    -x509 -sha256 -days 3650 -nodes \
    -out "${cert}" \
    -keyout "${key}" \
    -subj "/C=NA/ST=None/L=None/O=None/OU=None/CN=${fqdn}"
}
