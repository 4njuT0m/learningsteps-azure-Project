#!/usr/bin/env bash
# Sets up the LearningSteps API on vm-api (Part 1): uvicorn as a systemd service
# on 127.0.0.1:8000, with nginx on port 80 in front of it.
#
# Run on vm-api after cloning this repo to /opt/learningsteps:
#   sudo git clone https://github.com/4njuT0m/learningsteps-azure-Project.git /opt/learningsteps
#   sudo bash /opt/learningsteps/infra-part1/vm-setup/setup-vm-api.sh
#
# It asks for the ls_app password (the same one used in setup-vm-db.sh).
# Safe to run again.
set -euo pipefail

APP_DIR="/opt/learningsteps"
APP_USER="learningsteps"
DB_HOST="10.0.2.4"         # private IP of vm-db
DB_NAME="learning_journal"
DB_USER="ls_app"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo." >&2
  exit 1
fi
if [ "$REPO_DIR" != "$APP_DIR" ]; then
  echo "Clone the repo to ${APP_DIR} first and run the script from there." >&2
  exit 1
fi

read -rsp "Password for database user ${DB_USER}: " DB_PASSWORD
echo
if [ -z "$DB_PASSWORD" ]; then
  echo "Password must not be empty." >&2
  exit 1
fi

echo "==> Installing packages"
apt-get update
apt-get install -y python3-venv nginx git

echo "==> Creating service user ${APP_USER} (no login shell)"
id -u "$APP_USER" > /dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USER"

echo "==> Python virtual environment and dependencies"
python3 -m venv "${APP_DIR}/venv"
"${APP_DIR}/venv/bin/pip" install -r "${APP_DIR}/api/requirements.txt"

echo "==> Writing ${APP_DIR}/.env (permissions 600)"
(
  umask 077
  printf 'DATABASE_URL=postgresql://%s:%s@%s:5432/%s\n' "$DB_USER" "$DB_PASSWORD" "$DB_HOST" "$DB_NAME" > "${APP_DIR}/.env"
)
chown -R "${APP_USER}:${APP_USER}" "$APP_DIR"
chmod 600 "${APP_DIR}/.env"

echo "==> systemd service"
install -m 644 "${SCRIPT_DIR}/learningsteps.service" /etc/systemd/system/learningsteps.service
systemctl daemon-reload
systemctl enable learningsteps
systemctl restart learningsteps

echo "==> nginx reverse proxy"
install -m 644 "${SCRIPT_DIR}/nginx-learningsteps.conf" /etc/nginx/sites-available/learningsteps
ln -sf /etc/nginx/sites-available/learningsteps /etc/nginx/sites-enabled/learningsteps
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

echo "==> Checks"
for _ in $(seq 1 15); do
  code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/docs || true)"
  [ "$code" = "200" ] && break
  sleep 1
done
echo "GET /docs through nginx: ${code}"
echo "GET /entries: $(curl -s http://127.0.0.1/entries)"
systemctl is-active learningsteps nginx
