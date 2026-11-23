#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodegen generate
xcodebuild -project DivoomStudio.xcodeproj -scheme DivoomStudioMobile -configuration Debug -derivedDataPath build -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
print "Simulator app: $PWD/build/Build/Products/Debug-iphonesimulator/Divoom Studio.app"
