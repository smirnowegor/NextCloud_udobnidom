#!/bin/bash
# Скрипт быстрой настройки Nextcloud после миграции на HTTP-LAN схему

set -e

NC_PATH="/var/www/nextcloud"
PHP_USER="www-data"

echo "=== Настройка Nextcloud (occ) ==="
cd $NC_PATH

# 1. Прокси и домены
sudo -u $PHP_USER php occ config:system:set trusted_proxies 0 --value="192.168.2.206"
sudo -u $PHP_USER php occ config:system:set overwriteprotocol --value="https"
sudo -u $PHP_USER php occ config:system:set overwritehost --value="nextcloud.udobnidom.ru"
sudo -u $PHP_USER php occ config:system:set overwrite.cli.url --value="https://nextcloud.udobnidom.ru"

# 2. Collabora (Richdocuments)
sudo -u $PHP_USER php occ config:app:set richdocuments wopi_url --value="http://192.168.2.145:9980"
sudo -u $PHP_USER php occ config:app:set richdocuments public_wopi_url --value="https://collabora.udobnidom.ru" --update-only
sudo -u $PHP_USER php occ config:app:set richdocuments disable_certificate_verification --value="no"

# 3. Passwords (фикс Failed to fetch)
sudo -u $PHP_USER php occ config:app:set passwords service/security --value="smalldb"
sudo -u $PHP_USER php occ config:app:delete passwords passwords/localdb/type || true

echo "=== Перезапуск сервисов ==="
systemctl daemon-reload
systemctl restart nginx notify_push whiteboard nextcloud-spreed-signaling

echo "=== Проверка Docker (Collabora) ==="
docker stop collabora-code || true
docker rm collabora-code || true
docker run -d --name collabora-code \
  -p 9980:9980 \
  -e "domain=nextcloud\\.udobnidom\\.ru" \
  -e "server_name=collabora\\.udobnidom\\.ru" \
  -e "extra_params=--o:ssl.enable=false --o:ssl.termination=true" \
  collabora/code

echo "Готово! Проверьте доступность по https://nextcloud.udobnidom.ru/status.php"
