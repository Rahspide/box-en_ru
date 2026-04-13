#!/bin/sh

# Build script: automatically package the Box module into a zip file
VERSION=$(cat module.prop | grep 'version=' | awk -F '=' '{print $2}' | tr -d '\r')
zip -r -o -X -ll box-${VERSION}.zip ./ -x '.git/*' -x 'CHANGELOG.md' -x 'update.json' -x 'build.sh' -x '.github/*' -x 'LICENSE'