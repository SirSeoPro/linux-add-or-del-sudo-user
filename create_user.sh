#!/bin/bash

set -euo pipefail

# ─── Параметры ──────────────────────────────────────
USERNAME="${1:-}"
SSH_KEY_FILE="${2:-}"

# ─── Проверка аргументов ────────────────────────────
if [[ -z "$USERNAME" || -z "$SSH_KEY_FILE" ]]; then
  echo "Использование: $0 <имя_пользователя> <путь_к_файлу_ssh_ключа>"
  echo "Пример:        $0 john /tmp/john_id_rsa.pub"
  exit 1
fi

if [[ ! -f "$SSH_KEY_FILE" ]]; then
  echo "Ошибка: файл ключа не найден: $SSH_KEY_FILE"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: скрипт нужно запускать от root (sudo)"
  exit 1
fi

# ─── Создание пользователя ──────────────────────────
if id "$USERNAME" &>/dev/null; then
  echo "Пользователь '$USERNAME' уже существует, пропускаем создание."
else
  useradd -m -s /bin/bash "$USERNAME"
  echo "Пользователь '$USERNAME' создан."
fi

# ─── Добавление в группу sudo ───────────────────────
usermod -aG sudo "$USERNAME"
echo "Пользователь '$USERNAME' добавлен в группу sudo."

# ─── Настройка SSH ключа ────────────────────────────
HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6)
SSH_DIR="$HOME_DIR/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"

# Добавляем ключ только если его ещё нет
KEY_CONTENT=$(cat "$SSH_KEY_FILE")
if grep -qsF "$KEY_CONTENT" "$AUTH_KEYS" 2>/dev/null; then
  echo "SSH ключ уже присутствует в authorized_keys, пропускаем."
else
  echo "$KEY_CONTENT" >> "$AUTH_KEYS"
  echo "SSH ключ добавлен в $AUTH_KEYS."
fi

# ─── Права доступа ──────────────────────────────────
chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_KEYS"
chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
echo "Права доступа настроены."

# ─── Готово ─────────────────────────────────────────
echo ""
echo "✓ Пользователь : $USERNAME"
echo "✓ Sudo         : да"
echo "✓ SSH ключ     : $AUTH_KEYS"
