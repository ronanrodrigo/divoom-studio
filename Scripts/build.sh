#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodegen generate
xcodebuild -project DivoomStudio.xcodeproj -scheme DivoomStudio -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
APP_PATH="$PWD/build/Build/Products/Release/Divoom Studio.app"
# File-provider workspaces may add Finder metadata rejected by codesign.
# Remove metadata only from this generated bundle, then ad-hoc sign for local use.
xattr -cr "$APP_PATH"
codesign --force --deep --options runtime --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
print "App: $APP_PATH"
