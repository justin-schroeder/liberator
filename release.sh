#!/bin/bash
# Build, notarize, staple and assess before creating the public release artifact.
set -euo pipefail
cd "$(dirname "$0")"
: "${DEVELOPER_ID_APPLICATION:?Set the installed Developer ID Application identity}"
: "${DEVELOPER_TEAM_ID:?Set your ten-character Apple team ID}"
: "${NOTARY_KEYCHAIN_PROFILE:?Store notarization credentials with notarytool first, then set the profile name}"
./build.sh release
./test.sh
app="$PWD/build/Liberator.app"
mkdir -p build/notary build/dmg-stage
# ditto creates a resource-preserving archive without temporary audit data.
ditto -c -k --keepParent "$app" build/notary/Liberator.zip
xcrun notarytool submit build/notary/Liberator.zip --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
ditto "$app" build/dmg-stage/Liberator.app
ln -sfn /Applications build/dmg-stage/Applications
cp DISTRIBUTION.md build/dmg-stage/'Read me first.txt'
hdiutil create -volname Liberator -srcfolder build/dmg-stage -ov -format UDZO build/Liberator-0.1.0.dmg
codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" build/Liberator-0.1.0.dmg
xcrun notarytool submit build/Liberator-0.1.0.dmg --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
xcrun stapler staple build/Liberator-0.1.0.dmg
xcrun stapler validate build/Liberator-0.1.0.dmg
shasum -a 256 build/Liberator-0.1.0.dmg > build/Liberator-0.1.0.dmg.sha256
printf 'Release artifact: %s\n' "$PWD/build/Liberator-0.1.0.dmg"
