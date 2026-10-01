#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=14.0
mkdir -p .build/vendor dist
app_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' Resources/Info.plist)
app_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' Resources/Info.plist)
archive_name="${app_name// /-}"
source_map="$PWD=/src"
swift_path_flags=(-Xcc "-ffile-prefix-map=$source_map"
    -Xswiftc -file-prefix-map -Xswiftc "$source_map"
    -Xswiftc -debug-prefix-map -Xswiftc "$source_map")

if command -v cmake >/dev/null 2>&1; then
    cmake_cmd=(cmake)
elif command -v uv >/dev/null 2>&1; then
    cmake_cmd=(uv tool run --from cmake cmake)
elif [ -x /opt/homebrew/bin/uv ]; then
    cmake_cmd=(/opt/homebrew/bin/uv tool run --from cmake cmake)
else
    printf 'CMake fehlt. Installiere CMake oder uv und starte scripts/build.sh erneut.\n' >&2
    exit 1
fi

archive=.build/vendor/whisper-v1.9.4.tar.gz
if [ ! -f "$archive" ]; then
    curl -fsSL --retry 2 https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.9.4.tar.gz -o "$archive"
fi
printf '57e280cee375ab02425b806ad5146b99f6eb9357e3c2b31357c8a6af2e2e44ae  %s\n' "$archive" | shasum -a 256 -c -
if [ ! -d .build/vendor/whisper.cpp-1.9.4 ]; then tar -xzf "$archive" -C .build/vendor; fi
"${cmake_cmd[@]}" -S .build/vendor/whisper.cpp-1.9.4 -B .build/whisper-engine \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF \
    "-DCMAKE_C_FLAGS=-ffile-prefix-map=$source_map" "-DCMAKE_CXX_FLAGS=-ffile-prefix-map=$source_map" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
"${cmake_cmd[@]}" --build .build/whisper-engine --target whisper-cli -j 4
swift build --package-path Engine -c release --product flow-qwen -j 4 "${swift_path_flags[@]}"
python3 scripts/portable_resources.py Engine/.build/release Engine/.build/release.yaml

"${cmake_cmd[@]}" -S Engine/.build/checkouts/mlx-swift/Source/Cmlx/mlx -B .build/mlx-metal \
    -DMLX_BUILD_TESTS=OFF -DMLX_BUILD_EXAMPLES=OFF -DMLX_METAL_JIT=ON \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
"${cmake_cmd[@]}" --build .build/mlx-metal --target mlx-metallib -j 4
swift build -c release -j 4 "${swift_path_flags[@]}"
swift scripts/icon.swift .build/Flow.iconset
iconutil -c icns .build/Flow.iconset -o .build/Flow.icns

staging="$(mktemp -d "$PWD/dist/.app-build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/$app_name.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Licenses"
cp ".build/release/$app_executable" "$app/Contents/MacOS/$app_executable"
cp .build/whisper-engine/bin/whisper-cli "$app/Contents/MacOS/whisper-cli"
cp Engine/.build/release/flow-qwen "$app/Contents/MacOS/flow-qwen"
cp .build/mlx-metal/mlx/backend/metal/kernels/mlx.metallib "$app/Contents/Resources/default.metallib"
for resource in Engine/.build/release/*.bundle; do
    cp -R "$resource" "$app/Contents/Resources/"
done
cp .build/Flow.icns "$app/Contents/Resources/Flow.icns"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp .build/vendor/whisper.cpp-1.9.4/LICENSE "$app/Contents/Resources/Licenses/whisper.cpp.txt"
cp Engine/.build/checkouts/mlx-audio-swift/LICENSE "$app/Contents/Resources/Licenses/mlx-audio-swift.txt"
cp Engine/.build/checkouts/mlx-swift/LICENSE "$app/Contents/Resources/Licenses/mlx-swift.txt"
cp Resources/THIRD_PARTY.md "$app/Contents/Resources/Licenses/THIRD_PARTY.md"
cp LICENSE "$app/Contents/Resources/Licenses/LICENSE.txt"
for dependency in Engine/.build/checkouts/*; do
    while IFS= read -r notice; do
        relative="${notice#"$dependency"/}"
        destination="$app/Contents/Resources/Licenses/$(basename "$dependency")/$relative"
        mkdir -p "$(dirname "$destination")"
        cp "$notice" "$destination"
    done < <(rg --files "$dependency" -g 'LICENSE*' -g 'NOTICE*' -g 'COPYING*')
done
xcrun strip -S "$app/Contents/MacOS/$app_executable" "$app/Contents/MacOS/whisper-cli" "$app/Contents/MacOS/flow-qwen"
codesign --force --sign - "$app/Contents/MacOS/whisper-cli"
codesign --force --sign - "$app/Contents/MacOS/flow-qwen"
codesign --force --sign - --entitlements Resources/Entitlements.plist "$app"
codesign --verify --deep --strict "$app"
if [ -d "dist/$app_name.app" ]; then
    rm -rf "dist/$app_name.previous.app"
    mv "dist/$app_name.app" "dist/$app_name.previous.app"
fi
mv "$app" "dist/$app_name.app"
ditto -c -k --sequesterRsrc --keepParent "dist/$app_name.app" "dist/$archive_name.zip"
printf 'BUILD PASS: dist/%s.app\n' "$app_name"
