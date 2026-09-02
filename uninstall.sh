#!/bin/bash
#
# YouTubeGuard 를 지운다. 관리자 권한이 필요하다.
#
#   sudo ./uninstall.sh
#
set -euo pipefail

DAEMON_LABEL="com.vincent.ytguard.daemon"
AGENT_LABEL="com.vincent.ytguard.menubar"

DAEMON_BIN="/usr/local/libexec/ytguardd"
APP_DEST="/Applications/YouTubeGuard.app"
SUPPORT_DIR="/Library/Application Support/YouTubeGuard"
LOG_DIR="/Library/Logs/YouTubeGuard"

PF_ANCHOR="/etc/pf.anchors/ytguard"
PF_CONF="/etc/pf.conf"
PF_BEGIN="# >>> YouTubeGuard 앵커 시작 >>>"
PF_END="# <<< YouTubeGuard 앵커 끝 <<<"

HOSTS_BACKUP="/etc/hosts.ytguard-backup"

fail() { echo "오류: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "sudo ./uninstall.sh 처럼 관리자 권한으로 실행해 주세요."

REAL_USER="${SUDO_USER:-}"
REAL_UID=""
[ -n "$REAL_USER" ] && REAL_UID="$(id -u "$REAL_USER")"

echo "==> 자동 실행 등록을 뗍니다"
if [ -n "$REAL_UID" ]; then
    launchctl bootout "gui/${REAL_UID}/${AGENT_LABEL}" >/dev/null 2>&1 || true
fi
launchctl bootout "system/${DAEMON_LABEL}" >/dev/null 2>&1 || true

echo "==> 차단을 모두 풉니다"
if [ -x "$DAEMON_BIN" ]; then
    "$DAEMON_BIN" --clear || echo "    경고: 차단을 푸는 데 실패했습니다. /etc/hosts 를 직접 확인해 주세요."
else
    echo "    데몬이 없어 건너뜁니다. /etc/hosts 를 직접 확인해 주세요."
fi

echo "==> 방화벽 앵커를 걷어 냅니다"
pfctl -a ytguard -t ytguard -T flush >/dev/null 2>&1 || true
pfctl -a ytguard -F rules >/dev/null 2>&1 || true

if grep -qF "$PF_BEGIN" "$PF_CONF" 2>/dev/null; then
    # 표시선 사이의 줄만 지운다. 다른 설정은 건드리지 않는다.
    awk -v b="$PF_BEGIN" -v e="$PF_END" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        !skip   { print }
    ' "$PF_CONF" > /tmp/pf.conf.ytguard.$$

    if pfctl -n -f /tmp/pf.conf.ytguard.$$ >/dev/null 2>&1; then
        cat /tmp/pf.conf.ytguard.$$ > "$PF_CONF"
        echo "    ${PF_CONF} 에서 앵커 등록을 지웠습니다"
    else
        echo "    경고: 지운 뒤의 ${PF_CONF} 가 문법 검사를 통과하지 못해 그대로 두었습니다."
    fi
    rm -f /tmp/pf.conf.ytguard.$$
fi
rm -f "$PF_ANCHOR"

echo "==> 파일을 지웁니다"
rm -f "/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
rm -f "/Library/LaunchAgents/${AGENT_LABEL}.plist"
rm -f "$DAEMON_BIN"
rm -rf "$APP_DEST"
rm -rf "$SUPPORT_DIR"
rm -rf "$LOG_DIR"

echo
echo "지우기가 끝났습니다."
if [ -f "$HOSTS_BACKUP" ]; then
    echo "설치 전 hosts 백업은 그대로 남겨 두었습니다: ${HOSTS_BACKUP}"
    echo "필요 없으면 sudo rm ${HOSTS_BACKUP} 로 지우세요."
fi
if [ -f "${PF_CONF}.ytguard-backup" ]; then
    echo "설치 전 pf 설정 백업: ${PF_CONF}.ytguard-backup"
fi
