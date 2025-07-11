#!/bin/bash
set -euo pipefail

# Generate domain prefix from BASE_DN
export DC_PART=$(echo "$BASE_DN" | grep -o 'dc=[^,]*' | head -1 | cut -d= -f2)
export HASHED_PASSWORD="${HASHED_PASSWORD:-$(slappasswd -s "${ADMIN_PASSWORD}")}"

# Ensure correct permissions
mkdir -p /var/lib/ldap
chown -R ldap:ldap /var/lib/ldap

# Render slapd.conf from template
envsubst '${BASE_DN} ${DC_PART} ${HASHED_PASSWORD}' \
  < /usr/local/etc/openldap/templates/slapd.conf.template > /tmp/slapd.conf

echo "[INFO] Validating slapd.conf"
if ! slaptest -f /tmp/slapd.conf -u; then
    echo "[ERROR] slapd.conf is invalid"
    cat /tmp/slapd.conf
    exit 1
fi

# Only initialize if config does not exist
if [ ! -f /etc/openldap/slapd.d/cn=config.ldif ]; then
  echo "[INFO] Generating slapd.d config from slapd.conf"
  slaptest -f /tmp/slapd.conf -F /etc/openldap/slapd.d
else
  echo "[INFO] Reusing existing slapd.d config"
fi

# Render and apply bootstrap.ldif (database content)
if [ ! -f /tmp/bootstrap.ldif ]; then
  envsubst '${BASE_DN} ${ADMIN_PASSWORD} ${DC_PART} ${ORGANIZATION}' \
    < /usr/local/etc/openldap/templates/bootstrap.ldif.template \
    > /tmp/bootstrap.ldif
fi

echo "[INFO] Validating bootstrap.ldif"
if ! slapadd -u -v -F /etc/openldap/slapd.d -n 1 -l /tmp/bootstrap.ldif; then
    echo "[ERROR] bootstrap.ldif did not validate – aborting"
    exit 1
fi

echo "[INFO] Importing bootstrap.ldif..."
if ! slapadd -q -F /etc/openldap/slapd.d -n 1 -l /tmp/bootstrap.ldif; then
    echo "[ERROR] bootstrap import failed – giving up"
    exit 1
fi

# Import initial data
DB_DIR="/var/lib/ldap"
if [ -z "$(ls -A "$DB_DIR")" ]; then
  echo "[INFO] Populating LDAP database..."
  slapadd -F /etc/openldap/slapd.d -n 1 -l /tmp/bootstrap.ldif
fi

chown -R ldap:ldap /etc/openldap /var/lib/ldap

exec /usr/local/libexec/slapd -h "ldap:/// ldapi:///" -u ldap -g ldap -d 0
