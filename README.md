# Nextcloud LAN Deployment Repository

Этот репозиторий содержит актуальные конфигурационные файлы и инструкции для развертывания Nextcloud в упрощенной LAN-схеме с одним внешним HTTPS-прокси (Caddy).

## Структура
*   `configs/caddy/`: Конфигурация внешнего прокси.
*   `configs/nginx/`: Конфигурация веб-сервера внутри контейнера (CT103).
*   `configs/systemd/`: Unit-файлы для notify_push, whiteboard и signaling.
*   `configs/nextcloud/`: Бэкап config.php и параметры Collabora.
*   `scripts/`: Скрипты автоматизации настройки.
*   `DEPLOYMENT_GUIDE.md`: Пошаговая инструкция по развертыванию с нуля.

## Быстрый старт
Для применения настроек Nextcloud внутри контейнера используйте:
`bash scripts/setup_nextcloud.sh`
