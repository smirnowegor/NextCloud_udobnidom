#!/bin/bash
# Nextcloud Hub 10 (v33) Zero-Touch Installation Script for Debian 13 / Ubuntu 24
# Optimized for LAN deployment with external Caddy Proxy
# Based on c-rieger.de logic + local LAN fixes (06.04.2026)

set -e

# --- Configuration ---
NC_DOMAIN="nextcloud.udobnidom.ru"
COLLAB_DOMAIN="collabora.udobnidom.ru"
CADDY_IP="192.168.2.206"
NEXTCLOUD_IP=$(hostname -I | awk '{print $1}')
DB_NAME="nextcloud"
DB_USER="nextcloud"
DB_PASS=$(openssl rand -base64 16)
ADMIN_USER="admin"
ADMIN_PASS=$(openssl rand -base64 16)

echo "=== Starting Nextcloud Installation ==="
echo "Target IP: $NEXTCLOUD_IP"
echo "Proxy IP: $CADDY_IP"

# 1. System Updates & Dependencies
apt update && apt upgrade -y
apt install -y nginx mariadb-server redis-server php8.4-fpm php8.4-mysql php8.4-gd php8.4-curl \
    php8.4-mbstring php8.4-intl php8.4-gmp php8.4-bcmath php8.4-xml php8.4-zip php8.4-redis \
    php8.4-imagick php8.4-bz2 curl unzip sudo docker.io

# 2. Database Setup
mariadb -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mariadb -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mariadb -e "FLUSH PRIVILEGES;"

# 3. Nextcloud Download & Extract
cd /var/www
curl -o nextcloud.zip https://download.nextcloud.com/server/releases/latest.zip
unzip nextcloud.zip
rm nextcloud.zip
chown -R www-data:www-data /var/www/nextcloud

# 4. Nginx Configuration (HTTP-only for LAN)
cat > /etc/nginx/conf.d/nextcloud.conf <<EOF
upstream php-handler {
    server unix:/run/php/php8.4-fpm.sock;
}
server {
    listen 80;
    server_name $NC_DOMAIN;
    root /var/www/nextcloud;
    index index.php;
    client_max_body_size 10G;

    location / {
        rewrite ^ /index.php\$request_uri;
    }

    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:\$|/) { return 404; }
    location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console) { return 404; }

    location ~ \.php(?:$|/) {
        fastcgi_split_path_info ^(.+?\.php)(/.*)\$;
        set \$path_info \$fastcgi_path_info;
        try_files \$fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param HTTPS on;
        fastcgi_pass php-handler;
    }
}
EOF
systemctl restart nginx

# 5. Nextcloud Installation (occ)
cd /var/www/nextcloud
sudo -u www-data php occ maintenance:install \
    --database "mysql" --database-name "$DB_NAME" \
    --database-user "$DB_USER" --database-pass "$DB_PASS" \
    --admin-user "$ADMIN_USER" --admin-pass "$ADMIN_PASS"

# 6. Post-Install Optimization & Proxy Setup
sudo -u www-data php occ config:system:set trusted_proxies 0 --value="$CADDY_IP"
sudo -u www-data php occ config:system:set overwriteprotocol --value="https"
sudo -u www-data php occ config:system:set overwritehost --value="$NC_DOMAIN"
sudo -u www-data php occ config:system:set trusted_domains 0 --value="$NC_DOMAIN"
sudo -u www-data php occ config:system:set trusted_domains 1 --value="$NEXTCLOUD_IP"

# 7. Collabora Online (Docker)
docker run -d --name collabora-code --restart always \
  -p 9980:9980 \
  -e "domain=$NC_DOMAIN" \
  -e "server_name=$COLLAB_DOMAIN" \
  -e "extra_params=--o:ssl.enable=false --o:ssl.termination=true" \
  collabora/code

# 8. Passwords App & Security Fix
sudo -u www-data php occ app:install passwords || true
sudo -u www-data php occ config:app:set passwords service/security --value="smalldb"

echo "=== Installation Complete ==="
echo "Admin User: $ADMIN_USER"
echo "Admin Pass: $ADMIN_PASS"
echo "Nextcloud: https://$NC_DOMAIN"
