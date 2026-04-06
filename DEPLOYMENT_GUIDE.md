# Deployment Guide: Nextcloud + Collabora + Passwords (Single Caddy Proxy)

Этот гайд описывает проверенную конфигурацию для развертывания Nextcloud в связке с Collabora Online и приложением Passwords, где внешним шлюзом (SSL) выступает один сервер Caddy, а всё внутреннее взаимодействие в локальной сети (LAN) происходит по HTTP.

## 1. Архитектура
*   **External Proxy (Caddy, 192.168.2.206):** Единственная точка терминации SSL (HTTPS). Проксирует запросы на внутренние HTTP-порты.
*   **Nextcloud Container (CT103, 192.168.2.145):**
    *   **Nginx:** Слушает порт `80` (HTTP). Проксирует на PHP-FPM.
    *   **Collabora (Docker):** Слушает порт `9980` (HTTP).
    *   **Notify Push:** Порт `7867` (HTTP).
    *   **Whiteboard:** Порт `3002` (HTTP).

## 2. Конфигурация Caddy (192.168.2.206)
Файл `/etc/caddy/Caddyfile`:
```caddy
nextcloud.udobnidom.ru {
    import security_headers
    # Проксирование основных сервисов по HTTP
    handle_path /standalone-signaling/* {
        reverse_proxy http://192.168.2.145:8080
    }
    handle_path /whiteboard/* {
        reverse_proxy http://192.168.2.145:3002
    }
    reverse_proxy http://192.168.2.145:80 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-Proto https
    }
}

collabora.udobnidom.ru {
    import security_headers
    reverse_proxy http://192.168.2.145:9980 {
        header_up X-Real-IP {header.CF-Connecting-IP}
    }
}
```

## 3. Настройка Nginx в CT103 (192.168.2.145)
Ключевые моменты в `/etc/nginx/conf.d/nextcloud.conf`:
*   Добавить `listen 80;` в блок `server`.
*   Убрать или закомментировать редиректы с 80 на 443 внутри контейнера.
*   `fastcgi_param HTTPS on;` должен остаться, чтобы Nextcloud знал, что внешний клиент на HTTPS.

## 4. Настройка Collabora (Docker в CT103)
Запуск контейнера без внутреннего SSL (терминация на Caddy):
```bash
docker run -d --name collabora-code \
  -p 9980:9980 \
  -e "domain=nextcloud\\.udobnidom\\.ru" \
  -e "server_name=collabora\\.udobnidom\\.ru" \
  -e "extra_params=--o:ssl.enable=false --o:ssl.termination=true" \
  collabora/code
```

## 5. Настройка Nextcloud (occ)
```bash
# Collabora (Richdocuments)
sudo -u www-data php occ config:app:set richdocuments wopi_url --value="http://192.168.2.145:9980"
sudo -u www-data php occ config:app:set richdocuments public_wopi_url --value="https://collabora.udobnidom.ru"
sudo -u www-data php occ config:app:set richdocuments disable_certificate_verification --value="no"

# Passwords (фикс Failed to fetch)
# Используем локальную базу, чтобы избежать таймаутов при проверке внешних API (HIBP)
sudo -u www-data php occ config:app:set passwords service/security --value="smalldb"
sudo -u www-data php occ config:app:delete passwords passwords/localdb/type

# Proxy & Protocol
sudo -u www-data php occ config:system:set trusted_proxies 0 --value="192.168.2.206"
sudo -u www-data php occ config:system:set overwriteprotocol --value="https"
```

## 6. High-Performance Backend (HPB)

Для максимальной производительности Talk (Spreed), уведомлений и доски (Whiteboard) используются следующие компоненты:

### Nextcloud Talk Signaling
*   **Сервис:** `nextcloud-spreed-signaling`
*   **Порт:** `8080` (HTTP)
*   **Caddy:** Проксирует `/standalone-signaling/` -> `http://192.168.2.145:8080`

### Notify Push (Client Push)
*   **Сервис:** `notify_push.service`
*   **Порт:** `7867` (HTTP)
*   **Caddy:** Обрабатывается через Nginx (`location /push`) или напрямую.

### Whiteboard
*   **Сервис:** `whiteboard.service`
*   **Порт:** `3002` (HTTP)
*   **Caddy:** Проксирует `/whiteboard/` -> `http://192.168.2.145:3002`

## 7. Установка с нуля (Автоматизация)
В репозитории подготовлен скрипт `install.sh`, который:
1.  Устанавливает все зависимости (PHP 8.4, MariaDB 11.8, Redis 8, Nginx).
2.  Настраивает базу данных и Nextcloud.
3.  Разворачивает Collabora в Docker.
4.  Устанавливает и настраивает все HPB сервисы (Signaling, Whiteboard, Push).
5.  Применяет патч для приложения Passwords (отключение HIBP таймаутов).

---
*Документация обновлена 06.04.2026. Конфигурация проверена и является стабильной.*
