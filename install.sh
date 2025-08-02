#!/bin/bash

# Проверка аргументов
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "❌ Использование: ./install_remna_node.sh <SELF_STEAL_DOMAIN> <SSL_CERT>"
    echo "Пример:"
    echo "./install_remna_node.sh steel.example.com \"-----BEGIN CERTIFICATE-----\\n...\""
    exit 1
fi

SELF_STEAL_DOMAIN="$1"
SSL_CERT="$2"
APP_PORT="2222"
SELF_STEAL_PORT="9443"

echo "🧩 Установка зависимостей: curl, iptables, ipset, docker, docker-compose"
sudo apt update
sudo apt install -y curl iptables ipset ca-certificates gnupg lsb-release

# Установка Docker
if ! command -v docker >/dev/null; then
    echo "⬇️ Установка Docker..."
    curl -fsSL https://get.docker.com | sh
fi

# Установка Docker Compose Plugin (если не установлен)
if ! docker compose version >/dev/null 2>&1; then
    echo "⬇️ Установка Docker Compose plugin..."
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p $DOCKER_CONFIG/cli-plugins
    curl -SL https://github.com/docker/compose/releases/download/v2.27.1/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
    chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
fi

echo "📁 Создание директории /opt/remnanode"
mkdir -p /opt/remnanode && cd /opt/remnanode

echo "📝 Создание .env для RemnaNode"
cat > .env <<EOF
APP_PORT=${APP_PORT}
SSL_CERT=${SSL_CERT}
EOF

echo "📝 Создание docker-compose.yml для RemnaNode"
cat > docker-compose.yml <<EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    restart: always
    network_mode: host
    env_file:
      - .env
EOF

echo "🚀 Запуск RemnaNode контейнера"
docker compose up -d

echo "✅ RemnaNode установлен. Продолжите добавление в панели, указав:"
echo " - IP сервера"
echo " - Порт: ${APP_PORT}"

echo "📁 Создание директории /opt/selfsteel"
mkdir -p /opt/selfsteel && cd /opt/selfsteel

echo "📝 Создание .env для Selfsteel"
cat > .env <<EOF
SELF_STEAL_DOMAIN=${SELF_STEAL_DOMAIN}
SELF_STEAL_PORT=${SELF_STEAL_PORT}
EOF

echo "📝 Создание Caddyfile"
cat > Caddyfile <<EOF
{
    https_port {\$SELF_STEAL_PORT}
    default_bind 127.0.0.1
    servers {
        listener_wrappers {
            proxy_protocol {
                allow 127.0.0.1/32
            }
            tls
        }
    }
    auto_https disable_redirects
}

http://{\$SELF_STEAL_DOMAIN} {
    bind 0.0.0.0
    redir https://{\$SELF_STEAL_DOMAIN}{uri} permanent
}

https://{\$SELF_STEAL_DOMAIN} {
    root * /var/www/html
    try_files {path} /index.html
    file_server
}

:{\$SELF_STEAL_PORT} {
    tls internal
    respond 204
}

:80 {
    bind 0.0.0.0
    respond 204
}
EOF

echo "📝 Создание docker-compose.yml для Selfsteel"
cat > docker-compose.yml <<EOF
services:
  caddy:
    image: caddy:2.9.1
    container_name: caddy-remnawave
    restart: unless-stopped
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ../html:/var/www/html
      - ./logs:/var/log/caddy
      - caddy_data_selfsteal:/data
      - caddy_config_selfsteal:/config
    env_file:
      - .env
    network_mode: "host"

volumes:
  caddy_data_selfsteal:
  caddy_config_selfsteal:
EOF

echo "📁 Создание заглушки index.html"
mkdir -p /opt/html
echo "<h1>Welcome to ${SELF_STEAL_DOMAIN}</h1>" > /opt/html/index.html

echo "🚀 Запуск Selfsteel контейнера (Caddy)"
docker compose up -d

echo "✅ Установка завершена!"
