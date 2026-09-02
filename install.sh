#!/bin/bash
#
# YouTubeGuard 를 설치한다. 관리자 권한이 필요하다.
#
#   ./build.sh          (일반 권한으로 먼저 빌드)
#   sudo ./install.sh   (설치)
#
set -euo pipefail

cd "$(dirname "$0")"
SOURCE_DIR="$(pwd)"

DAEMON_LABEL="com.vincent.ytguard.daemon"
AGENT_LABEL="com.vincent.ytguard.menubar"

DAEMON_BIN="/usr/local/libexec/ytguardd"
APP_DEST="/Applications/YouTubeGuard.app"
SUPPORT_DIR="/Library/Application Support/YouTubeGuard"
CONFIG_DIR="${SUPPORT_DIR}/user"
CONFIG_FILE="${CONFIG_DIR}/config.json"
LOG_DIR="/Library/Logs/YouTubeGuard"

PF_ANCHOR="/etc/pf.anchors/ytguard"
PF_CONF="/etc/pf.conf"
PF_BEGIN="# >>> YouTubeGuard 앵커 시작 >>>"
PF_END="# <<< YouTubeGuard 앵커 끝 <<<"

HOSTS_BACKUP="/etc/hosts.ytguard-backup"

fail() { echo "오류: $*" >&2; exit 1; }

# launchctl bootout 은 정리가 끝나기 전에 돌아온다.
# 곧바로 다시 등록하면 "Input/output error" 로 거절당하므로 사라질 때까지 기다린다.
wait_until_gone() {
    local target="$1"
    local i
    for i in $(seq 1 40); do
        launchctl print "$target" >/dev/null 2>&1 || return 0
        sleep 0.25
    done
    return 1
}

# 그래도 어긋나는 경우가 있어 몇 번 다시 시도한다.
bootstrap_with_retry() {
    local domain="$1"
    local plist="$2"
    local errfile="/tmp/ytguard-bootstrap-$$.err"
    local i
    for i in 1 2 3 4 5; do
        if launchctl bootstrap "$domain" "$plist" 2>"$errfile"; then
            rm -f "$errfile"
            return 0
        fi
        sleep 1
    done
    echo "    launchctl 이 알려 온 이유: $(tr -d '\n' < "$errfile")" >&2
    rm -f "$errfile"
    return 1
}

# ---------------------------------------------------------------- 사전 확인

[ "$(id -u)" -eq 0 ] || fail "sudo ./install.sh 처럼 관리자 권한으로 실행해 주세요."

[ -n "${SUDO_USER:-}" ] || fail "sudo 로 실행해 주세요. 로그인한 사용자를 알아내지 못했습니다."
REAL_USER="$SUDO_USER"
REAL_UID="$(id -u "$REAL_USER")"

[ -x "build/ytguardd" ] || fail "build/ytguardd 가 없습니다. 먼저 일반 권한으로 ./build.sh 를 실행해 주세요."
[ -d "build/YouTubeGuard.app" ] || fail "build/YouTubeGuard.app 이 없습니다. 먼저 ./build.sh 를 실행해 주세요."

echo "==> 설치를 시작합니다. 대상 사용자: ${REAL_USER}"

if ! dseditgroup -o checkmember -m "$REAL_USER" admin >/dev/null 2>&1; then
    echo "    알림: ${REAL_USER} 는 admin 그룹이 아닙니다."
    echo "          메뉴 바에서 설정을 바꾸려면 admin 그룹에 들어 있어야 합니다."
fi

# ------------------------------------------------- 이미 돌고 있는 것 내리기

# 다시 설치하는 경우를 위해 먼저 내리고, 완전히 정리될 때까지 기다린다.
# 실행 중인 앱 번들을 지운 채로 두지 않기 위해서다.
# 데몬을 내려도 hosts 파일의 차단 구간은 그대로 남으므로,
# 설치하는 동안 차단이 잠시 풀리는 일은 없다.
if launchctl print "system/${DAEMON_LABEL}" >/dev/null 2>&1; then
    echo "==> 이미 설치되어 있어 먼저 내립니다"
    launchctl bootout "system/${DAEMON_LABEL}" >/dev/null 2>&1 || true
    wait_until_gone "system/${DAEMON_LABEL}" || fail "이전 데몬이 정리되지 않습니다. 잠시 뒤 다시 실행해 주세요."
fi
if launchctl print "gui/${REAL_UID}/${AGENT_LABEL}" >/dev/null 2>&1; then
    launchctl bootout "gui/${REAL_UID}/${AGENT_LABEL}" >/dev/null 2>&1 || true
    wait_until_gone "gui/${REAL_UID}/${AGENT_LABEL}" || fail "이전 메뉴 바 앱이 정리되지 않습니다. 잠시 뒤 다시 실행해 주세요."
fi

# ---------------------------------------------------------------- hosts 백업

if [ ! -f "$HOSTS_BACKUP" ]; then
    cp /etc/hosts "$HOSTS_BACKUP"
    echo "==> /etc/hosts 를 ${HOSTS_BACKUP} 에 백업했습니다"
else
    echo "==> hosts 백업이 이미 있어 그대로 둡니다: ${HOSTS_BACKUP}"
fi

# ---------------------------------------------------------------- 파일 설치

echo "==> 데몬을 놓습니다: ${DAEMON_BIN}"
mkdir -p "$(dirname "$DAEMON_BIN")"
install -m 755 -o root -g wheel build/ytguardd "$DAEMON_BIN"

echo "==> 메뉴 바 앱을 놓습니다: ${APP_DEST}"
rm -rf "$APP_DEST"
cp -R build/YouTubeGuard.app "$APP_DEST"
chown -R root:wheel "$APP_DEST"

echo "==> 폴더와 설정 파일을 준비합니다"
mkdir -p "$SUPPORT_DIR" "$LOG_DIR"
chown root:wheel "$SUPPORT_DIR" "$LOG_DIR"
chmod 755 "$SUPPORT_DIR" "$LOG_DIR"

# 설정 폴더만 admin 그룹이 쓸 수 있게 둔다.
# 그래야 메뉴 바 앱이 관리자 비밀번호 없이 설정을 바꿀 수 있다.
mkdir -p "$CONFIG_DIR"
chown root:admin "$CONFIG_DIR"
chmod 775 "$CONFIG_DIR"

if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" <<'JSON'
{
  "blockMediaHosts" : true,
  "customHosts" : [ ],
  "enabled" : true,
  "hardenDoH" : true,
  "rules" : [
    {
      "days" : [ 1, 2, 3, 4, 5 ],
      "end" : "18:00",
      "start" : "09:00"
    }
  ],
  "services" : [ "youtube" ],
  "usePacketFilter" : false
}
JSON
    echo "    기본 설정을 만들었습니다: 평일 09:00-18:00"
else
    echo "    설정 파일이 이미 있어 그대로 둡니다: ${CONFIG_FILE}"
fi
chown root:admin "$CONFIG_FILE"
chmod 664 "$CONFIG_FILE"

# ---------------------------------------------------------------- pf 앵커

echo "==> 방화벽 앵커를 준비합니다"
mkdir -p /etc/pf.anchors
install -m 644 -o root -g wheel pf/ytguard.anchor "$PF_ANCHOR"

if grep -qF "$PF_BEGIN" "$PF_CONF"; then
    echo "    ${PF_CONF} 에 이미 등록되어 있습니다"
else
    cp "$PF_CONF" "${PF_CONF}.ytguard-backup"
    {
        echo ""
        echo "$PF_BEGIN"
        echo "anchor \"ytguard\""
        echo "load anchor \"ytguard\" from \"${PF_ANCHOR}\""
        echo "$PF_END"
    } >> "$PF_CONF"

    # 문법이 어긋나면 원래대로 되돌린다. pf 설정이 깨지면 다른 기능까지 말썽이 난다.
    if pfctl -n -f "$PF_CONF" >/dev/null 2>&1; then
        echo "    ${PF_CONF} 에 앵커를 등록했습니다 (백업: ${PF_CONF}.ytguard-backup)"
    else
        cp "${PF_CONF}.ytguard-backup" "$PF_CONF"
        echo "    경고: 앵커 등록이 문법 검사를 통과하지 못해 되돌렸습니다."
        echo "          방화벽 차단 기능은 쓸 수 없지만 나머지는 정상 동작합니다."
    fi
fi

# 앵커는 표가 비어 있으면 아무것도 막지 않는다. 지금은 비어 있는 상태로 올려 둔다.
pfctl -a ytguard -f "$PF_ANCHOR" >/dev/null 2>&1 || true

# ---------------------------------------------------------------- launchd 등록

echo "==> 자동 실행을 등록합니다"
install -m 644 -o root -g wheel "launchd/${DAEMON_LABEL}.plist" "/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
install -m 644 -o root -g wheel "launchd/${AGENT_LABEL}.plist" "/Library/LaunchAgents/${AGENT_LABEL}.plist"

# 이전 것은 맨 앞에서 이미 내려 두었다. 여기서는 등록만 한다.
launchctl enable "system/${DAEMON_LABEL}" 2>/dev/null || true
if bootstrap_with_retry system "/Library/LaunchDaemons/${DAEMON_LABEL}.plist"; then
    echo "    차단 데몬을 띄웠습니다"
else
    fail "차단 데몬을 등록하지 못했습니다. 잠시 뒤 sudo ./install.sh 를 다시 실행해 주세요."
fi

if bootstrap_with_retry "gui/${REAL_UID}" "/Library/LaunchAgents/${AGENT_LABEL}.plist"; then
    echo "    메뉴 바 앱을 띄웠습니다"
else
    echo "    경고: 메뉴 바 앱을 등록하지 못했습니다."
    echo "          차단은 정상 동작합니다. 응용 프로그램 폴더의 YouTubeGuard 를 직접 실행해 보세요."
fi

# ---------------------------------------------------------------- 마무리

sleep 3
echo
echo "설치가 끝났습니다."
echo

if launchctl print "system/${DAEMON_LABEL}" >/dev/null 2>&1; then
    "$DAEMON_BIN" --status 2>/dev/null || echo "상태를 아직 읽지 못했습니다. 잠시 뒤 ${DAEMON_BIN} --status 로 확인해 주세요."
else
    echo "경고: 차단 데몬이 등록되어 있지 않습니다."
fi

echo
if pgrep -f "/Applications/YouTubeGuard.app" >/dev/null 2>&1; then
    echo "메뉴 바 앱이 돌고 있습니다. 각 화면 오른쪽 위의 방패 표시기로 상태를 볼 수 있습니다."
else
    echo "메뉴 바 앱이 보이지 않습니다. 응용 프로그램 폴더의 YouTubeGuard 를 실행해 주세요."
fi
echo "지우려면 sudo ./uninstall.sh 를 실행하세요."
