#!/usr/bin/env bash

SCRIPT_DIR="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
CONFIG_PATH="${PROJECT_ROOT}/configs"

# shellcheck source=./functions.sh
source "${SCRIPT_DIR}/functions.sh"

is_hook_provided() {
  local name="${1}"
  [ -n "$(hook_content "${name}")" ]
}

invoke_hook() {
  local name="${1}"

  is_hook_provided "${name}" || return 0

  curl -sL "$(hook_content "${name}")"
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
  add_cronjob "@${event} $(command -v curl) -sL '$(hook_content "${name}")'"
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

setup_hostname() {
  hostnamectl set-hostname "$(get_fully_qualified_hostname)"
  echo "127.0.1.1 $(get_fully_qualified_hostname) $(get_hostname)" >> /etc/hosts
}

configure_systemd_process_limits() {
  ensure_key_value_present /etc/systemd/system.conf "DefaultLimitNOFILE" "65000"
  ensure_key_value_present /etc/systemd/system.conf "DefaultLimitNPROC" "65000"
  ensure_key_value_present /etc/systemd/system.conf "DefaultTasksMax" "65000"
  os_svc_init daemon-reload
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

install_java() {
  os_pkg_install openjdk-8-jre-headless
  define_persisted_env_variable "JAVA_HOME" "$(dirname "$(dirname "$(readlink -e "$(command -v java)")")")"
}
