#!/bin/bash
# Nextcloud Hub 10 (v33) High-Performance Installation Script
# Optimized for LAN (Debian 13) with external Caddy Proxy
# Includes: Collabora, Passwords, Notify Push, Whiteboard, Signaling
# 06.04.2026 - Final Working Version

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

echo "=== Starting Nextcloud Installation (High Performance) ==="

# 1. System & PHP 8.4
apt update && apt upgrade -y
apt install -y nginx mariadb-server redis-server php8.4-fpm php8.4-mysql php8.4-gd php8.4-curl \
    php8.4-mbstring php8.4-intl php8.4-gmp php8.4-bcmath php8.4-xml php8.4-zip php8.4-redis \
    php8.4-imagick php8.4-bz2 curl unzip sudo docker.io nodejs npm git

# 2. Database
mariadb -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mariadb -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mariadb -e "FLUSH PRIVILEGES;"

# 3. Nextcloud Core
cd /var/www
curl -o nextcloud.zip https://download.nextcloud.com/server/releases/latest.zip
unzip nextcloud.zip && rm nextcloud.zip
chown -R www-data:www-data /var/www/nextcloud

# 4. Nginx (LAN HTTP Mode)
cat > /etc/nginx/conf.d/nextcloud.conf <<EOF
upstream php-handler { server unix:/run/php/php8.4-fpm.sock; }
server {
    listen 80;
    server_name $NC_DOMAIN;
    root /var/www/nextcloud;
    index index.php;
    client_max_body_size 10G;

    location / { rewrite ^ /index.php\$request_uri; }
    
    # High Performance Backend
    location ^~ /push {
        proxy_pass http://127.0.0.1:7867;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
    }

    location ~ \.php(?:$|/) {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param HTTPS on;
        fastcgi_pass php-handler;
    }
}
EOF
systemctl restart nginx

# 5. Nextcloud Install & Apps
cd /var/www/nextcloud
sudo -u www-data php occ maintenance:install --database "mysql" --database-name "$DB_NAME" --database-user "$DB_USER" --database-pass "$DB_PASS" --admin-user "$ADMIN_USER" --admin-pass "$ADMIN_PASS"

# Install Apps
sudo -u www-data php occ app:install notify_push
sudo -u www-data php occ app:install richdocuments
sudo -u www-data php occ app:install passwords
sudo -u www-data php occ app:install whiteboard
sudo -u www-data php occ app:install spreed

# 6. High Performance Config (The "udobnidom" Way)
sudo -u www-data php occ config:system:set trusted_proxies 0 --value="$CADDY_IP"
sudo -u www-data php occ config:system:set overwriteprotocol --value="https"
sudo -u www-data php occ config:system:set overwritehost --value="$NC_DOMAIN"
sudo -u www-data php occ config:system:set overwrite.cli.url --value="https://$NC_DOMAIN"

# Passwords Fix (No HIBP external check to avoid Failed to fetch)
sudo -u www-data php occ config:app:set passwords service/security --value="smalldb"

# Collabora (Docker)
docker run -d --name collabora-code --restart always -p 9980:9980 \
  -e "domain=$NC_DOMAIN" -e "server_name=$COLLAB_DOMAIN" \
  -e "extra_params=--o:ssl.enable=false --o:ssl.termination=true" collabora/code

sudo -u www-data php occ config:app:set richdocuments wopi_url --value="http://$NEXTCLOUD_IP:9980"
sudo -u www-data php occ config:app:set richdocuments public_wopi_url --value="https://$COLLAB_DOMAIN"
sudo -u www-data php occ config:app:set richdocuments disable_certificate_verification --value="no"

# 7. Systemd Services (HPB)

# Nextcloud Talk Signaling (Spreed)
if [ ! -f "/usr/bin/nextcloud-spreed-signaling" ]; then
    apt install -y nextcloud-spreed-signaling
fi

cat > /etc/nextcloud-spreed-signaling/server.conf <<EOF
[http]
listen = 127.0.0.1:8080
[app]
debug = false
[sessions]
hashkey = $(openssl rand -hex 32)
blockkey = $(openssl rand -hex 32)
[backend]
backends = backend-1
[backend-1]
url = http://127.0.0.1
secret = $(openssl rand -hex 32)
EOF

systemctl enable --now nextcloud-spreed-signaling

# Notify Push
cat > /etc/systemd/system/notify_push.service <<EOF
[Unit]
Description=Nextcloud notify_push
After=network.target

[Service]
ExecStart=/var/www/nextcloud/apps/notify_push/bin/x86_64/notify_push /var/www/nextcloud/config/config.php
Environment=PORT=7867
Environment=NEXTCLOUD_URL=http://127.0.0.1
User=www-data
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# Whiteboard Server
if [ ! -d "/opt/whiteboard-server" ]; then
    git clone https://github.com/nextcloud/whiteboard-server.git /opt/whiteboard-server
    cd /opt/whiteboard-server && npm install
fi

cat > /etc/systemd/system/whiteboard.service <<EOF
[Unit]
Description=Nextcloud Whiteboard WebSocket Server
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/whiteboard-server
Environment=NODE_ENV=production
Environment=HOST=0.0.0.0
Environment=PORT=3002
Environment=NEXTCLOUD_URL=http://127.0.0.1
Environment=JWT_SECRET_KEY=$(openssl rand -base64 32)
ExecStart=/usr/bin/node websocket_server/main.js
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now notify_push whiteboard

# 8. Final Nextcloud App Config for HPB
cd /var/www/nextcloud
sudo -u www-data php occ config:app:set spreed signaling_servers --value='[{"url":"https://'"$NC_DOMAIN"'/standalone-signaling/","hideInternalServer":true}]'
sudo -u www-data php occ config:app:set whiteboard server_url --value="https://$NC_DOMAIN/whiteboard/"

echo "=== Done! Nextcloud is ready at https://$NC_DOMAIN ==="
echo "Admin User: $ADMIN_USER"
echo "Admin Pass: $ADMIN_PASS"


