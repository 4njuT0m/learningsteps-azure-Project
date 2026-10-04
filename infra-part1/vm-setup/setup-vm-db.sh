#!/usr/bin/env bash
# Sets up PostgreSQL on vm-db for LearningSteps (Part 1).
#
# Run on vm-db from a clone of this repo:
#   sudo bash learningsteps-azure-Project/infra-part1/vm-setup/setup-vm-db.sh
#
# It asks for the ls_app password. Use the same password for setup-vm-api.sh.
# Safe to run again: it skips what already exists.
set -euo pipefail

API_IP="10.0.1.4"          # private IP of vm-api
DB_IP="10.0.2.4"           # private IP of vm-db
DB_NAME="learning_journal"
DB_USER="ls_app"
PG_DIR="/etc/postgresql/16/main"

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

read -rsp "Password for database user ${DB_USER}: " DB_PASSWORD
echo
if [ -z "$DB_PASSWORD" ]; then
  echo "Password must not be empty." >&2
  exit 1
fi
case "$DB_PASSWORD" in
  *"'"*|*"@"*|*"/"*|*":"*) echo "Use letters and numbers only (for example: openssl rand -hex 24)." >&2; exit 1 ;;
esac

echo "==> Installing PostgreSQL"
apt-get update
apt-get install -y postgresql
if [ ! -d "$PG_DIR" ]; then
  echo "Expected ${PG_DIR} (PostgreSQL 16 on Ubuntu 24.04). Check the installed version." >&2
  exit 1
fi

cd /tmp   # avoids "could not change directory" warnings when running as postgres

echo "==> Creating user ${DB_USER} and database ${DB_NAME}"
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1; then
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE ROLE ${DB_USER} WITH LOGIN"
fi
# The password goes in through stdin, so it is not visible in the process list.
sudo -u postgres psql -v ON_ERROR_STOP=1 -q << SQL
ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
SQL
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER}"
fi

echo "==> Listening on localhost and ${DB_IP} only"
sed -i "s/^#\?listen_addresses = .*/listen_addresses = 'localhost,${DB_IP}'/" "${PG_DIR}/postgresql.conf"

echo "==> Allowing only ${DB_USER} from ${API_IP} in pg_hba.conf"
HBA_LINE="host    ${DB_NAME}    ${DB_USER}    ${API_IP}/32    scram-sha-256"
grep -qxF "$HBA_LINE" "${PG_DIR}/pg_hba.conf" || echo "$HBA_LINE" >> "${PG_DIR}/pg_hba.conf"

echo "==> Restarting PostgreSQL and enabling it on boot"
systemctl restart postgresql
systemctl enable postgresql
until pg_isready -h localhost -q; do sleep 1; done

echo "==> Creating the entries table as ${DB_USER}"
PGPASSWORD="$DB_PASSWORD" psql -h localhost -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
  -f "${REPO_DIR}/database_setup.sql"

echo "==> Checks"
grep -n "^listen_addresses" "${PG_DIR}/postgresql.conf"
ss -tlnp | grep 5432
echo "Done. Test from vm-api: psql -h ${DB_IP} -U ${DB_USER} -d ${DB_NAME} -c '\\dt'"
