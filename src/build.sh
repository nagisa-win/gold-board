#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

product="国内金价.app"
mkdir -p build
scratch=$(mktemp -d "$PWD/build/.compile.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
bundle="$scratch/$product"
mkdir -p "$bundle/Contents/MacOS"
cp Info.plist "$bundle/Contents/Info.plist"
if [ -d Resources ]; then
    mkdir -p "$bundle/Contents/Resources"
    cp -R Resources/. "$bundle/Contents/Resources/"
fi
/usr/bin/plutil -replace LSMinimumSystemVersion -string 12.0 "$bundle/Contents/Info.plist"

# 版本号优先取环境变量，其次取最近的 git tag，最后回退 0.0.0；
# 只写进构建出来的 bundle，仓库里的 Info.plist 保持不动。
version="${GOLDFLOAT_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
[ -n "$version" ] || version="0.0.0"
build="${GOLDFLOAT_BUILD:-$(git rev-list --count HEAD 2>/dev/null)}"
[ -n "$build" ] || build="1"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$version" "$bundle/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$build" "$bundle/Contents/Info.plist"

# 源码分散在 model / feature / ui / support 子目录，统一收集后一次编译
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find . -name '*.swift' -not -path './build/*' | sort)

for cpu in arm64 x86_64; do
    xcrun swiftc -O -target "$cpu-apple-macos12.0" -module-name GoldFloat \
        -module-cache-path "$PWD/build/.modulecache" \
        "${sources[@]}" -o "$scratch/$cpu"
done
xcrun lipo -create "$scratch/arm64" "$scratch/x86_64" \
    -output "$bundle/Contents/MacOS/GoldFloat"
/usr/bin/codesign --force --sign - "$bundle"
/usr/bin/codesign --verify --strict --all-architectures "$bundle"
/usr/bin/ditto "$bundle" "build/$product"
printf '构建完成：%s/build/%s\n' "$PWD" "$product"
