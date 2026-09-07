#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
[[ -f build/BuildIdentity.swift ]] || printf 'enum BuildIdentity { static let teamID = "" }\n' > build/BuildIdentity.swift
xcrun swiftc -swift-version 5 -g -parse-as-library Sources/Core.swift Tests/CoreTests.swift -o build/CoreTests
build/CoreTests
if [[ -x build/Liberator.app/Contents/Library/HelperTools/LiberatorHelper && -z "${DEVELOPER_TEAM_ID:-}" ]]; then
  if build/Liberator.app/Contents/Library/HelperTools/LiberatorHelper; then
    echo 'FAIL: local helper must refuse to start' >&2; exit 1
  fi
  echo 'PASS: unsigned/local helper fails closed'
fi
xcrun swiftc -swift-version 5 -g -parse-as-library Sources/Core.swift Sources/Privilege.swift Sources/Benchmark.swift Sources/RadarState.swift Sources/Model.swift build/BuildIdentity.swift Tests/WorkflowTests.swift -framework SwiftUI -framework AppKit -framework ExecutionPolicy -framework ServiceManagement -framework Security -o build/WorkflowTests
build/WorkflowTests
xcrun swiftc -swift-version 5 -g -parse-as-library Sources/Core.swift Sources/RadarState.swift Tests/RadarTests.swift -o build/RadarTests
build/RadarTests

python3 Tests/ReleaseTests.py
