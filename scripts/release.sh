#!/bin/bash
# 本地构建 → 打包 DMG → 上传 GitHub Release
# 用法: scripts/release.sh 1.0.1
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:-}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "用法: scripts/release.sh <版本号>   例如 scripts/release.sh 1.0.1" >&2
    exit 1
fi

tag="v$version"
command -v gh >/dev/null || { echo "需要 gh CLI 并已登录" >&2; exit 1; }
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "工作区不干净，先提交或清理再发版" >&2
    exit 1
fi

build_number="$(git rev-list --count HEAD)"
echo "== 构建 v$version (build $build_number) =="
# 版本号通过环境变量交给 build.sh，仓库里的 Info.plist 始终不动
GOLDFLOAT_VERSION="$version" GOLDFLOAT_BUILD="$build_number" make build

echo "== 打包 DMG =="
mkdir -p dist
stage="$(mktemp -d)"
cp -R "src/build/国内金价.app" "$stage/"
ln -s /Applications "$stage/Applications"
dmg="dist/GoldFloat-$version.dmg"
hdiutil create -quiet -volname "国内金价" -srcfolder "$stage" -ov -format UDZO "$dmg"
rm -rf "$stage"
shasum -a 256 "$dmg" | tee "$dmg.sha256"

# 先把 main 推上去：tag 指向的 commit 必须在远端可达
if git remote get-url origin >/dev/null 2>&1; then
    git push origin HEAD:main
fi

if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "== tag $tag 已存在，直接复用 =="
else
    git tag -a "$tag" -m "国内金价 $version"
    git push origin "$tag"
fi

notes="$(mktemp)"
{
    echo "### 安装"
    echo
    echo "1. 下载 \`GoldFloat-$version.dmg\`，双击打开"
    echo "2. 把 \`国内金价\` 拖进 Applications"
    echo "3. 首次运行若提示“已损坏”，在终端执行：\`xattr -dr com.apple.quarantine /Applications/国内金价.app\`"
    echo
    echo "应用为 adhoc 签名、未做公证，所以需要第 3 步；可用随附的 \`.sha256\` 校验下载完整性。"
} > "$notes"

if gh release view "$tag" >/dev/null 2>&1; then
    echo "== Release $tag 已存在，覆盖资产 =="
    gh release upload "$tag" "$dmg" "$dmg.sha256" --clobber
else
    gh release create "$tag" "$dmg" "$dmg.sha256" \
        --title "国内金价 $tag" --notes-file "$notes"
fi
rm -f "$notes"

# 覆盖安装到 /Applications，本地不再保留 .app 副本
echo "== 安装到 /Applications =="
osascript -e 'quit app "国内金价"' >/dev/null 2>&1 || true
sleep 1
rm -rf "/Applications/国内金价.app"
ditto "src/build/国内金价.app" "/Applications/国内金价.app"
xattr -dr com.apple.quarantine "/Applications/国内金价.app" 2>/dev/null || true
rm -rf "src/build/国内金价.app"
open "/Applications/国内金价.app"

echo "== 完成：$(gh release view "$tag" --json url -q .url) =="
