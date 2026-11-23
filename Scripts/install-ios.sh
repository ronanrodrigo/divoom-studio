#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ -z "${DIVOOM_DEVELOPMENT_TEAM:-}" || -z "${DIVOOM_DEVICE_ID:-}" ]]; then
  print -u2 'Defina DIVOOM_DEVELOPMENT_TEAM e DIVOOM_DEVICE_ID para assinar e instalar no seu iPhone.'
  print -u2 'O Xcode deve ter uma conta Apple válida, e o iPhone deve estar desbloqueado, confiável e em Developer Mode.'
  exit 2
fi
xcodegen generate
xcodebuild -project DivoomStudio.xcodeproj -scheme DivoomStudioMobile \
  -configuration Debug -derivedDataPath build -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM="$DIVOOM_DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates build
APP_PATH="$PWD/build/Build/Products/Debug-iphoneos/Divoom Studio.app"
xcrun devicectl device install app --device "$DIVOOM_DEVICE_ID" "$APP_PATH"
xcrun devicectl device process launch --device "$DIVOOM_DEVICE_ID" dev.ronanrodrigo.DivoomStudioMobile
