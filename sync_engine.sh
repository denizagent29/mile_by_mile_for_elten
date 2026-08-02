#!/usr/bin/env bash
# Копирует движок игры (lib/mile_by_mile) в elten_app/lib/mile_by_mile.
# Elten-приложение — самодостаточная папка (пакуется целиком), поэтому
# держим отдельную копию engine внутри неё. Запускать после любых правок
# в lib/mile_by_mile, перед коммитом.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf elten_app/lib/mile_by_mile
cp -r lib/mile_by_mile elten_app/lib/mile_by_mile
echo "elten_app/lib/mile_by_mile синхронизирован с lib/mile_by_mile"
