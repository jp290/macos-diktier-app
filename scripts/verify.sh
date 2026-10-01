#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' Resources/Info.plist)
mkdir -p .build/verification
if ! swift test -j 4 > .build/verification/unit-tests.log 2>&1; then
    tail -35 .build/verification/unit-tests.log
    exit 1
fi
codesign --verify --deep --strict "dist/$app_name.app"
python3 scripts/verify_audio.py
printf 'VERIFY PASS: unit tests, app signature, German/English code-switching, audio pipeline and warm model reuse\n'
