#!/bin/bash
set -euo pipefail
# Never enable shell tracing: this step handles GitHub Actions secrets.
for name in DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD DEVELOPER_ID_APPLICATION DEVELOPER_TEAM_ID NOTARY_APPLE_ID NOTARY_APP_PASSWORD; do
  [[ -n "${!name:-}" ]] || { echo "Missing GitHub Actions secret: $name" >&2; exit 1; }
done
[[ "$DEVELOPER_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo 'Invalid Apple team ID'; exit 1; }
[[ "$DEVELOPER_ID_APPLICATION" == "Developer ID Application: "*" ($DEVELOPER_TEAM_ID)" ]] || { echo 'Expected matching Developer ID Application identity'; exit 1; }
umask 077
keychain="$RUNNER_TEMP/liberator-signing.keychain-db"
certificate="$RUNNER_TEMP/liberator-signing.p12"
password=$(openssl rand -hex 32)
echo "::add-mask::$password"
printf '%s' "$DEVELOPER_ID_P12_BASE64" | base64 --decode > "$certificate"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 7200 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$certificate" -P "$DEVELOPER_ID_P12_PASSWORD" -A -t cert -f pkcs12 -k "$keychain"
rm -f "$certificate"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
security default-keychain -d user -s "$keychain"
xcrun notarytool store-credentials liberator-ci --keychain "$keychain" --apple-id "$NOTARY_APPLE_ID" --team-id "$DEVELOPER_TEAM_ID" --password "$NOTARY_APP_PASSWORD"
