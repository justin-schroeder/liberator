#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mode=${1:-local}
mkdir -p build
identity=${DEVELOPER_ID_APPLICATION:-}
team=${DEVELOPER_TEAM_ID:-}
if [[ "$mode" == release ]]; then
  [[ -n "$identity" && "$team" =~ ^[A-Z0-9]{10}$ ]] || { echo 'Set DEVELOPER_ID_APPLICATION and DEVELOPER_TEAM_ID to your installed signing identity.' >&2; exit 1; }
  archs=(arm64 x86_64)
else
  identity=-; team=''; archs=(arm64)
  [[ "$mode" != universal ]] || archs=(arm64 x86_64)
fi
# A local build deliberately cannot activate the root daemon.
printf 'enum BuildIdentity { static let teamID = "%s" }\n' "$team" > build/BuildIdentity.swift
app="$PWD/build/Liberator.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Library/HelperTools" "$app/Contents/Library/LaunchDaemons"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/B24Nose.png "$app/Contents/Resources/B24Nose.png"
cp Resources/AgedPanel.png "$app/Contents/Resources/AgedPanel.png"
cp Resources/AgedPanelBare.png "$app/Contents/Resources/AgedPanelBare.png"
cp Resources/app.liberator.mac.helper.plist "$app/Contents/Library/LaunchDaemons/"
for arch in "${archs[@]}"; do
  xcrun swiftc -swift-version 5 -O -target "$arch-apple-macosx14.0" -parse-as-library Sources/Core.swift Sources/Privilege.swift Sources/Benchmark.swift Sources/RadarState.swift Sources/Model.swift Sources/Theme.swift Sources/RadarView.swift Sources/App.swift build/BuildIdentity.swift -framework SwiftUI -framework AppKit -framework ExecutionPolicy -framework ServiceManagement -framework Security -o "build/Liberator-$arch"
  xcrun swiftc -swift-version 5 -O -target "$arch-apple-macosx14.0" -parse-as-library Sources/Core.swift Sources/Privilege.swift Sources/Helper.swift build/BuildIdentity.swift -framework Foundation -framework ServiceManagement -framework Security -o "build/LiberatorHelper-$arch"
done
bins=(); helpers=()
for arch in "${archs[@]}"; do bins+=("build/Liberator-$arch"); helpers+=("build/LiberatorHelper-$arch"); done
if [[ ${#archs[@]} -gt 1 ]]; then
  xcrun lipo -create "${bins[@]}" -output "$app/Contents/MacOS/Liberator"
  xcrun lipo -create "${helpers[@]}" -output "$app/Contents/Library/HelperTools/LiberatorHelper"
else
  cp "${bins[0]}" "$app/Contents/MacOS/Liberator"
  cp "${helpers[0]}" "$app/Contents/Library/HelperTools/LiberatorHelper"
fi
mkdir -p build/AppIcon.iconset
xcrun swift Resources/Icon.swift "$PWD/build/AppIcon.iconset"
cp build/AppIcon.iconset/icon_512x512.png "$app/Contents/Resources/DockIcon.png"
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
signflags=(--force --options runtime --sign "$identity")
[[ "$mode" != release ]] || signflags+=(--timestamp)
codesign "${signflags[@]}" --identifier app.liberator.mac.helper "$app/Contents/Library/HelperTools/LiberatorHelper"
codesign "${signflags[@]}" --entitlements Resources/entitlements.plist "$app"
codesign --verify --deep --strict --verbose=1 "$app"
echo "Built $app ($mode)"
