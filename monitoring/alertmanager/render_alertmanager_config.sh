#!/bin/bash
set -uo pipefail
source "$HOME/.alertmanager_secrets"

sudo sed \
  -e "s|__SMTP_PASSWORD__|${SMTP_PASSWORD}|" \
  -e "s|__TELEGRAM_BOT_TOKEN__|${TELEGRAM_BOT_TOKEN}|" \
  /etc/alertmanager/alertmanager.yml.template | sudo tee /etc/alertmanager/alertmanager.yml > /dev/null

sudo systemctl restart alertmanager
