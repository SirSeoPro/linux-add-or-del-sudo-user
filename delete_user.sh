#!/bin/bash

set -euo pipefail

# ─── Параметры ──────────────────────────────────────
USERNAME="${1:-}"
REMOVE_HOME="${2:-}"   # передай --remove-home чтобы удалить /home

# ─── Проверка аргументов ────────────────────────────
if [[ -z "$USERNAME" ]]; then
  echo "Использование: $0 <имя_пользователя> [--remove-home]"
  echo "Пример:        $0 john"
  echo "Пример:        $0 john --remove-home"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: скрипт нужно запускать от root (sudo)"
  exit 1
fi

# ─── Защита системных пользователей ────────────────
PROTECTED_USERS=("root" "daemon" "bin" "sys" "nobody")
for protected in "${PROTECTED_USERS[@]}"; do
  if [[ "$USERNAME" == "$protected" ]]; then
    echo "Ошибка: удаление системного пользователя '$USERNAME' запрещено."
    exit 1
  fi
done

# ─── Проверка существования ─────────────────────────
if ! id "$USERNAME" &>/dev/null; then
  echo "Ошибка: пользователь '$USERNAME' не найден."
  exit 1
fi

# ─── Проверка активных сессий ───────────────────────
ACTIVE_SESSIONS=$(who | awk '{print $1}' | grep -c "^${USERNAME}$" || true)
if [[ "$ACTIVE_SESSIONS" -gt 0 ]]; then
  echo "Предупреждение: пользователь '$USERNAME' сейчас залогинен ($ACTIVE_SESSIONS сессий)."
  read -rp "Продолжить всё равно? [y/N]: " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Отменено."
    exit 0
  fi
  # Завершаем процессы пользователя перед удалением
  pkill -u "$USERNAME" || true
  sleep 1
fi

# ─── Бэкап домашней директории ──────────────────────
HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6)
BACKUP_PATH="/var/backups/${USERNAME}_home_$(date +%Y%m%d_%H%M%S).tar.gz"

if [[ -d "$HOME_DIR" ]]; then
  echo "Создаём бэкап домашней директории → $BACKUP_PATH"
  tar -czf "$BACKUP_PATH" -C "$(dirname "$HOME_DIR")" \
      "$(basename "$HOME_DIR")" 2>/dev/null || true
  echo "Бэкап создан: $BACKUP_PATH"
fi

# ─── Удаление пользователя ──────────────────────────
if [[ "$REMOVE_HOME" == "--remove-home" ]]; then
  userdel -r "$USERNAME"
  echo "Пользователь '$USERNAME' и его домашняя директория удалены."
else
  userdel "$USERNAME"
  echo "Пользователь '$USERNAME' удалён. Домашняя директория сохранена: $HOME_DIR"
fi

# ─── Удаление из sudoers (если есть отдельная запись) ─
SUDOERS_FILE="/etc/sudoers.d/$USERNAME"
if [[ -f "$SUDOERS_FILE" ]]; then
  rm -f "$SUDOERS_FILE"
  echo "Файл sudoers.d/$USERNAME удалён."
fi

# ─── Готово ─────────────────────────────────────────
echo ""
echo "✓ Пользователь удалён : $USERNAME"
if [[ -f "$BACKUP_PATH" ]]; then
  echo "✓ Бэкап сохранён      : $BACKUP_PATH"
fi
if [[ "$REMOVE_HOME" != "--remove-home" && -d "$HOME_DIR" ]]; then
  echo "  Домашняя директория : $HOME_DIR (не тронута)"
fi
