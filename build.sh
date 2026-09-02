#!/bin/bash
#
# YouTubeGuard 를 빌드한다. 관리자 권한은 필요하지 않다.
# 결과물은 build/ 아래에 놓인다.
#
set -euo pipefail

cd "$(dirname "$0")"

ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos13.0"
BUILD="build"
APP="${BUILD}/YouTubeGuard.app"

echo "==> 이전 결과물을 지웁니다"
rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "==> 검사 프로그램을 빌드하고 돌립니다"
swiftc -target "$TARGET" -o "${BUILD}/ytguard-tests" \
    src/shared/*.swift \
    src/daemon/HostsFile.swift \
    tests/main.swift
"${BUILD}/ytguard-tests"

echo
echo "==> 차단 데몬을 빌드합니다"
swiftc -O -target "$TARGET" -o "${BUILD}/ytguardd" \
    src/shared/*.swift \
    src/daemon/*.swift

echo "==> 메뉴 바 앱을 빌드합니다"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
swiftc -O -target "$TARGET" -o "${APP}/Contents/MacOS/YouTubeGuard" \
    src/shared/*.swift \
    src/menubar/*.swift \
    -framework Cocoa
cp src/menubar/Info.plist "${APP}/Contents/Info.plist"

echo "==> 서명합니다"
# 배포용 인증서 없이 이 기기에서만 쓰는 서명이다.
codesign --force --sign - --timestamp=none "${BUILD}/ytguardd"
codesign --force --sign - --timestamp=none "${APP}"

echo
echo "빌드가 끝났습니다."
echo "  데몬        ${BUILD}/ytguardd"
echo "  메뉴 바 앱  ${APP}"
echo
echo "설치하려면 sudo ./install.sh 를 실행하세요."
