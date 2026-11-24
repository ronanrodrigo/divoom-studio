#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodegen generate
DIVOOM_IOS_DESTINATION="${DIVOOM_IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 18 Pro}"
xcodebuild -project DivoomStudio.xcodeproj -scheme DivoomStudioMobile -configuration Debug -derivedDataPath build -destination "$DIVOOM_IOS_DESTINATION" CODE_SIGNING_ALLOWED=NO test
