#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodegen generate
xcodebuild -project DivoomStudio.xcodeproj -scheme DivoomStudio -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
APP_PATH="$PWD/build/Build/Products/Release/Divoom Studio.app"
# Sign in a temporary local directory: file providers can reattach FinderInfo
# between removing extended attributes and codesign's resource validation.
DIVOOM_STAGE=$(mktemp -d /private/tmp/divoom-sign.XXXXXX)
trap 'rm -rf "$DIVOOM_STAGE"' EXIT
DIVOOM_STAGED_APP="$DIVOOM_STAGE/Divoom Studio.app"
ditto --norsrc --noextattr "$APP_PATH" "$DIVOOM_STAGED_APP"
xattr -cr "$DIVOOM_STAGED_APP"
codesign --force --deep --options runtime --sign - "$DIVOOM_STAGED_APP"
codesign --verify --deep --strict "$DIVOOM_STAGED_APP"
ditto --norsrc --noextattr "$DIVOOM_STAGED_APP" "$APP_PATH"
xattr -dr com.apple.FinderInfo "$APP_PATH" 2>/dev/null || true
codesign --verify --deep --strict "$APP_PATH"
print "App: $APP_PATH"
