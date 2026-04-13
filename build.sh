#!/bin/sh

# Скрипт сборки: автоматическая упаковка модуля Box в zip-файл
VERSION=$(cat module.prop | grep 'version=' | awk -F '=' '{print $2}' | tr -d '\r')
zip -r -o -X -ll box-${VERSION}.zip ./ -x '.git/*' -x 'CHANGELOG.md' -x 'update.json' -x 'build.sh' -x '.github/*' -x 'LICENSE'