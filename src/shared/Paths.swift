import Foundation

/// 설치 후 실제로 사용되는 파일 경로들.
/// 데몬(root)과 메뉴 바 앱(사용자)이 같은 경로를 바라보게 하기 위해 한곳에 모아 둔다.
enum Paths {
    static let bundleID = "com.vincent.ytguard"

    /// 설정 파일. 메뉴 바 앱이 쓰고 데몬이 읽는다.
    /// 설치 스크립트가 admin 그룹에 쓰기 권한을 주므로 관리자 비밀번호 없이 변경할 수 있다.
    static let supportDir = "/Library/Application Support/YouTubeGuard"

    /// 설정만 따로 담는 하위 폴더. 이 폴더에만 admin 그룹 쓰기 권한을 준다.
    /// 상태 파일과 로그는 루트만 쓸 수 있는 곳에 남겨 둔다.
    static let userConfigDir = supportDir + "/user"
    static let configFile = userConfigDir + "/config.json"

    /// 현재 차단 상태. 데몬만 쓰고 메뉴 바 앱은 읽기만 한다.
    static let stateFile = supportDir + "/state.json"

    /// 방화벽에 넣을 IP 목록 (pf 를 켠 경우에만 사용).
    static let pfTableFile = supportDir + "/pf-addresses.txt"

    static let logDir = "/Library/Logs/YouTubeGuard"
    static let logFile = logDir + "/daemon.log"

    static let hostsFile = "/etc/hosts"
    static let pfAnchorFile = "/etc/pf.anchors/ytguard"
    static let pfAnchorName = "ytguard"

    static let appPath = "/Applications/YouTubeGuard.app"
    static let daemonBinary = "/usr/local/libexec/ytguardd"
}
