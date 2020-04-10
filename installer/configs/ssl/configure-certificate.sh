#!/usr/bin/env bash

# Based on jitsi-meet letsencrypt certificate installer
# https://github.com/jitsi/jitsi-meet/blob/master/resources/install-letsencrypt-cert.sh

DOMAIN="${1}"

CERT_KEY="/etc/ssl/live/$DOMAIN/privkey.pem"
CERT_CRT="/etc/ssl/live/$DOMAIN/fullchain.pem"

if [ -f /etc/nginx/sites-enabled/$DOMAIN.conf ] ; then
  echo "Configuring nginx"

  CONF_FILE="/etc/nginx/sites-available/$DOMAIN.conf"
  CERT_KEY_ESC=$(echo $CERT_KEY | sed 's/\./\\\./g')
  CERT_KEY_ESC=$(echo $CERT_KEY_ESC | sed 's/\//\\\//g')
  sed -i "s/ssl_certificate_key\ \/etc\/jitsi\/meet\/.*key/ssl_certificate_key\ $CERT_KEY_ESC/g" \
      $CONF_FILE
  CERT_CRT_ESC=$(echo $CERT_CRT | sed 's/\./\\\./g')
  CERT_CRT_ESC=$(echo $CERT_CRT_ESC | sed 's/\//\\\//g')
  sed -i "s/ssl_certificate\ \/etc\/jitsi\/meet\/.*crt/ssl_certificate\ $CERT_CRT_ESC/g" \
      $CONF_FILE

  service nginx reload

  TURN_CONFIG="/etc/turnserver.conf"
  if [ -f $TURN_CONFIG ] && grep -q "jitsi-meet coturn config" "$TURN_CONFIG" ; then
      echo "Configuring turnserver"
      sed -i "s/cert=\/etc\/jitsi\/meet\/.*crt/cert=$CERT_CRT_ESC/g" $TURN_CONFIG
      sed -i "s/pkey=\/etc\/jitsi\/meet\/.*key/pkey=$CERT_KEY_ESC/g" $TURN_CONFIG

      service coturn restart
  fi
elif [ -f /etc/apache2/sites-enabled/$DOMAIN.conf ] ; then
  echo "Configuring apache2"

  CONF_FILE="/etc/apache2/sites-available/$DOMAIN.conf"
  CERT_KEY_ESC=$(echo $CERT_KEY | sed 's/\./\\\./g')
  CERT_KEY_ESC=$(echo $CERT_KEY_ESC | sed 's/\//\\\//g')
  sed -i "s/SSLCertificateKeyFile\ \/etc\/jitsi\/meet\/.*key/SSLCertificateKeyFile\ $CERT_KEY_ESC/g" \
      $CONF_FILE
  CERT_CRT_ESC=$(echo $CERT_CRT | sed 's/\./\\\./g')
  CERT_CRT_ESC=$(echo $CERT_CRT_ESC | sed 's/\//\\\//g')
  sed -i "s/SSLCertificateFile\ \/etc\/jitsi\/meet\/.*crt/SSLCertificateFile\ $CERT_CRT_ESC/g" \
      $CONF_FILE

  service apache2 reload
else
  service jitsi-videobridge stop

  echo "Configuring jetty"

  CERT_P12="/etc/jitsi/videobridge/$DOMAIN.p12"
  CERT_JKS="/etc/jitsi/videobridge/$DOMAIN.jks"
  # create jks from  certs
  openssl pkcs12 -export \
      -in $CERT_CRT -inkey $CERT_KEY -passout pass:changeit > $CERT_P12
  keytool -importkeystore -destkeystore $CERT_JKS \
      -srckeystore $CERT_P12 -srcstoretype pkcs12 \
      -noprompt -storepass changeit -srcstorepass changeit

  service jitsi-videobridge start
fi
