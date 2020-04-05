#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
INSTALL_ROOT="$(dirname "${SCRIPT_DIR}")"
JITSIRC_PATH="${INSTALL_ROOT}/jitsiinstallrc"
CONFIG_PATH="${INSTALL_ROOT}/configs"

main() {
  [ "$(id -u)" = "0" ] || die "This script must be executed as root!"
  [ -s "${JITSIRC_PATH}" ] || die "jitsi installer config not found at '${JITSIRC_PATH}'!"

  # shellcheck source=./jitsirc
  source "${JITSIRC_PATH}"

  set -u

  os_pkg_install curl
  log "Setup hostname..."; setup_hostname
  log "Setup firewall..."; setup_firewall
  log "Update system..."; update_system
  log "Configure systemd process limits..."; configure_systemd_process_limits

  log "Invoking pre install hooks..."; invoke_hook "pre_install"

  log "Install dependencies..."; install_dependencies
  log "Install Jitsi..."; install_jitsi
  log "Setup Jitsi SIP dialin..."; install_phone_dialin
  log "Install SSL certificate..."; install_ssl_certificate
  log "Enable Jitsi user authentication..."; enable_authentication
  log "Tweaking Jitsi config..."; tweak_config

  log "Ensure Jitsi started..."; ensure_jitsi_started
  log "Validate Jitsi install..."; validate_jitsi_install

  log "Invoking post install hooks..."; invoke_hook "post_install"
  log "Persisting post install hooks..."; persist_hook "post_install" "reboot"
}

setup_hostname() {
  hostnamectl set-hostname "$(get_fully_qualified_hostname)"
  echo "127.0.1.1 $(get_fully_qualified_hostname) $(get_hostname)" >> /etc/hosts
}

setup_firewall() {
  os_firewall allow http
  os_firewall allow https
  os_firewall allow in 10000:20000/udp

  [ "${FIREWALL_ENABLE_SSH:-}" != "true" ] || os_firewall allow OpenSSH
  os_firewall --force enable
  os_svc restart ufw
}

configure_systemd_process_limits() {
  ensure_key_value_present /etc/systemd/system.conf "DefaultLimitNOFILE" "65000"
  ensure_key_value_present /etc/systemd/system.conf "DefaultLimitNPROC" "65000"
  ensure_key_value_present /etc/systemd/system.conf "DefaultTasksMax" "65000"
  os_svc_init daemon-reload
}

update_system() {
  os_pkg_repo_update
  os_pkg_system_update
}

install_dependencies() {
  install_java
  install_nginx

  os_pkg_install debconf-utils curl
}

install_java() {
  os_pkg_install openjdk-8-jre-headless
  define_persisted_env_variable "JAVA_HOME" "$(dirname "$(dirname "$(readlink -e "$(command -v java)")")")"
}

install_nginx() {
  os_pkg_install nginx
  os_svc_init enable nginx
  os_svc start nginx
}

install_jitsi() {
  echo 'deb https://download.jitsi.org stable/' >> /etc/apt/sources.list.d/jitsi-stable.list
  curl -s https://download.jitsi.org/jitsi-key.gpg.key | apt-key add -
  os_pkg_install apt-transport-https
  os_pkg_repo_update

  echo "jitsi-videobridge2 jitsi-videobridge/jvb-hostname string $(get_fully_qualified_hostname)" | debconf-set-selections
  echo "jitsi-videobridge2 jitsi-videobridge/jvbsecret password $(generate_passwd)" | debconf-set-selections
  os_pkg_install jitsi-meet
}

install_ssl_certificate() {
  if [ -n "${SSL_LETSENCRYPT_EMAIL:-}" ]; then
    echo -e "${SSL_LETSENCRYPT_EMAIL}\n" | /usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh
    return $?
  fi

  local fqdn; fqdn=$(get_fully_qualified_hostname)
  local certificate_dir="/etc/ssl/live/${fqdn}"
  mkdir -p "${certificate_dir}"

  local cert_key="${certificate_dir}/privkey.pem"
  local cert_crt="${certificate_dir}/fullchain.pem"
  if [ -n "${SSL_CERTIFICATE_KEY:-}" ] && [ -n "${SSL_CERTIFICATE_CRT:-}" ]; then
    write_file_from_encoded_var "SSL_CERTIFICATE_KEY" "${cert_key}"
    write_file_from_encoded_var "SSL_CERTIFICATE_CRT" "${cert_crt}"
  else
    generate_self_signed_cert "${fqdn}" "${cert_key}" "${cert_crt}"
  fi

  /bin/bash "${CONFIG_PATH}/ssl/configure-certificate.sh" "${fqdn}"
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

install_phone_dialin() {
  [ "${DIALIN_SIP_ACCOUNT_UID:-}" ] && [ -n "${DIALIN_SIP_PASSWORD:-}" ] && [ -n "${DIALIN_PSTN_NUMBERS:-}" ] || return 0

  echo "jigasi jigasi/sip-account string ${DIALIN_SIP_ACCOUNT_UID}" | debconf-set-selections
  echo "jigasi jigasi/sip-password password ${DIALIN_SIP_PASSWORD}" | debconf-set-selections

  os_pkg_install jigasi
  # TODO: Configure dial in url and conference mapper
  echo '{
    "message":"Phone numbers available.",
    "numbers": {"Worldwide":[' "\"${DIALIN_PSTN_NUMBERS//,/\",\"}\"" ']},
    "numbersEnabled":true
  }' > /usr/share/jitsi-meet/static/phoneNumberList.json
}

ensure_jitsi_started() {
  local services=(jicofo jitsi-videobridge2 prosody jigasi nginx)
  for service in "${services[@]}"; do
    os_svc restart "${service}" && log "restarted '${service}'" || log "did not restart '${service}'"
  done
}

enable_authentication() {
  [ -n "${JITSI_MEETING_CREATOR_USERNAME:-}" ] && [ -n "${JITSI_MEETING_CREATOR_PASSWORD:-}" ] || return 0

  local fqdn; fqdn=$(get_fully_qualified_hostname)
  local jicofo_secret; jicofo_secret=$(grep -e '^JICOFO_SECRET=.*' /etc/jitsi/jicofo/config | cut -d '=' -f2)
  local turn_secret; turn_secret=$(generate_passwd)
  sed "s/JITSI_DOMAIN_NAME/${fqdn}/g;
       s/JICOFO_SECRET/${jicofo_secret}/g;
       s/TURN_SECRET/${turn_secret}/g" \
    "${CONFIG_PATH}/auth/prosody.cfg.lua" > "/etc/prosody/conf.avail/${fqdn}.cfg.lua"

  sed "s/JITSI_DOMAIN_NAME/${fqdn}/g" \
    "${CONFIG_PATH}/auth/meet-config.js" > "/etc/jitsi/meet/${fqdn}-config.js"

  ensure_key_value_present /etc/jitsi/jicofo/sip-communicator.properties \
    "org.jitsi.jicofo.auth.URL" "XMPP:${fqdn}"

  prosodyctl register "${JITSI_MEETING_CREATOR_USERNAME}" "${fqdn}" "${JITSI_MEETING_CREATOR_PASSWORD}"
}

tweak_config() {
  [ -z "${JITSI_WATERMARK_IMAGE_URL:-}" ] || \
    curl -Ls "${JITSI_WATERMARK_IMAGE_URL:-}" -o /usr/share/jitsi-meet/images/watermark.png

  local fqdn; fqdn=$(get_fully_qualified_hostname)
  local js_config_file="/etc/jitsi/meet/${fqdn}-config.js"
  [ -z "${JITSI_ENABLE_WELCOME_PAGE:-}" ] || \
    update_colon_separated_value "${js_config_file}" \
      "enableWelcomePage" "${JITSI_ENABLE_WELCOME_PAGE}"

  [ -z "${JITSI_START_AUDIO_MUTED:-}" ] || \
    update_colon_separated_value "${js_config_file}" \
      "startAudioMuted" "${JITSI_START_AUDIO_MUTED}"

  [ -z "${JITSI_START_VIDEO_MUTED:-}" ] || \
    update_colon_separated_value "${js_config_file}" \
      "startVideoMuted" "${JITSI_START_VIDEO_MUTED}"

  [ -z "${JITSI_REQUIRE_DISPLAY_NAME:-}" ] || \
    update_colon_separated_value "${js_config_file}" \
      "requireDisplayName" "${JITSI_REQUIRE_DISPLAY_NAME}"
}

update_colon_separated_value() {
  local file="${1}"
  local key="${2}"
  local value="${3}"

  sed -Ei "s/^(\s*)([\/#]*\s*)(${key}\s*:\s*)(.+?)(\s*),$/\1\3${value}\5,/" "${file}"
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

define_persisted_env_variable() {
  local name="${1}"; shift
  local value="${*}"

  ensure_key_value_present /etc/profile "export ${name}" "${value}"
  eval "export ${name}='${value}'"
}

validate_jitsi_install() {
  if ! curl -sfL "https://$(get_fully_qualified_hostname)"; then
    log "Cannot establish secure connection (is the certificate trusted?)"
    curl -sfLk "https://$(get_fully_qualified_hostname)"
  fi
}

is_hook_provided() {
  local name="${1}"
  [ -n "$(hook_content "${name}")" ]
}

invoke_hook() {
  local name="${1}"

  is_hook_provided "${name}" || return 0

  is_command_present curl || os_pkg_install curl
  curl -sL "$(hook_content "${name}")"
  log "Waiting for ${HOOKS_WAIT_TIME:-} seconds..."
  sleep ${HOOKS_WAIT_TIME:-0}
}

hook_content() {
  local name="${1}"
  local var_name="HOOKS_${name^^}_URL"
  echo "${!var_name:-}"
}

persist_hook() {
  local name="${1}"
  local event="${2}"

  is_hook_provided "${name}" || return 0
  (
    crontab -l 2>/dev/null || true
    echo "@${event} $(command -v curl) -sL '$(hook_content "${name}")'"
  ) | crontab -
}

get_fully_qualified_hostname() {
  local ec2_hostname
  ec2_hostname=$(curl --connect-timeout 1 -s http://169.254.169.254/2019-10-01/meta-data/public-hostname || true)
  ec2_hostname=${ec2_hostname:-$(hostname)}

  echo "${FULLY_QUALIFIED_HOSTNAME:-${ec2_hostname}}"
}

get_hostname() {
  local fqdn; fqdn=$(get_fully_qualified_hostname)
  echo "${fqdn%%.*}"
}

generate_passwd() { < /dev/urandom tr -dc '_A-Z-a-z-0-9@#' | head -c8; }
is_command_present() { command -v "${1}" >/dev/null 2>&1; }

os_pkg_install() { DEBIAN_FRONTEND=noninteractive apt install -y "${@}"; }
os_pkg_repo_update() { apt update; }
os_pkg_system_update() { apt upgrade -y; }
os_firewall() { ufw "${@}"; }
os_svc() { service "${2}" "${1}"; }
os_svc_init() { systemctl "${@}"; }

log() { echo "# [$(date)] $*"; }
die() { log "$*" >&2; exit 1; }

main "${@}"
