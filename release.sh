#!/bin/bash
# Build, notarize, staple and assess before creating the public release artifact.
set -euo pipefail
cd "$(dirname "$0")"
: "${DEVELOPER_ID_APPLICATION:?Set the installed Developer ID Application identity}"
: "${DEVELOPER_TEAM_ID:?Set your ten-character Apple team ID}"
: "${NOTARY_KEYCHAIN_PROFILE:?Store notarization credentials with notarytool first, then set the profile name}"
export RELEASE_VERSION=${RELEASE_VERSION:?Set RELEASE_VERSION to a version such as 0.1.0}
# NOTARY_KEYCHAIN optionally names the keychain file holding the profile (CI uses a temporary keychain).
notary=(xcrun notarytool submit --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait)
[[ -z "${NOTARY_KEYCHAIN:-}" ]] || notary+=(--keychain "$NOTARY_KEYCHAIN")
./build.sh release
./test.sh
app="$PWD/build/Liberator.app"
rm -rf build/dmg-stage
mkdir -p build/notary build/dmg-stage
# ditto creates a resource-preserving archive without temporary audit data.
ditto -c -k --keepParent "$app" build/notary/Liberator.zip
"${notary[@]}" build/notary/Liberator.zip
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
ditto "$app" build/dmg-stage/Liberator.app
ln -sfn /Applications build/dmg-stage/Applications
cp DISTRIBUTION.md build/dmg-stage/'Read me first.txt'
hdiutil create -volname Liberator -srcfolder build/dmg-stage -ov -format UDZO build/Liberator.dmg
codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" build/Liberator.dmg
"${notary[@]}" build/Liberator.dmg
xcrun stapler staple build/Liberator.dmg
xcrun stapler validate build/Liberator.dmg
codesign --verify --strict build/Liberator.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 build/Liberator.dmg
(cd build && shasum -a 256 Liberator.dmg > Liberator.dmg.sha256)
printf 'Release artifact: %s\n' "$PWD/build/Liberator.dmg"
