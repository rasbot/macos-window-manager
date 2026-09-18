#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
app_dir="${project_dir}/dist/WindowDock.app"
contents_dir="${app_dir}/Contents"

cd "${project_dir}"
export SWIFTPM_MODULECACHE_OVERRIDE="${project_dir}/.build/swiftpm-module-cache"
export CLANG_MODULE_CACHE_PATH="${project_dir}/.build/clang-module-cache"
swift build -c release

mkdir -p "${contents_dir}/MacOS" "${contents_dir}/Resources"
cp ".build/release/WindowDock" "${contents_dir}/MacOS/WindowDock"
cp "Resources/Info.plist" "${contents_dir}/Info.plist"
chmod +x "${contents_dir}/MacOS/WindowDock"
# Keep a stable designated requirement across local ad-hoc development builds.
# Without this, the requirement is the binary hash and macOS invalidates the
# Accessibility grant every time the executable changes.
codesign \
    --force \
    --deep \
    --sign - \
    --requirements '=designated => identifier "dev.rasbot.WindowDock"' \
    "${app_dir}"

echo "Created ${app_dir}"
