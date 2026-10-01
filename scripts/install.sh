#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' Resources/Info.plist)
if [ ! -d "dist/$app_name.app" ]; then scripts/build.sh; fi
destination="$HOME/Applications/$app_name.app"
mkdir -p "$HOME/Applications"
if [ -d "$destination" ]; then
    mv "$destination" "$HOME/Applications/$app_name.backup-$(date +%Y%m%d-%H%M%S).app"
fi
ditto "dist/$app_name.app" "$destination"
codesign --verify --deep --strict "$destination"
printf 'INSTALL PASS: %s\n' "$destination"
