import Foundation

/// pf 방화벽으로 IP 를 직접 막는 보조 수단.
/// 브라우저가 자체 암호화 DNS 를 써서 hosts 파일을 건너뛰는 경우를 잡기 위한 것이다.
/// 구글의 공용 주소와 겹칠 수 있어 기본값은 꺼짐이며, 설정에서 켜야 동작한다.
enum PacketFilter {

    private static var enableToken: String?

    static var isPFEnabled: Bool {
        let r = Shell.run("/sbin/pfctl", ["-s", "info"])
        return r.stdout.contains("Status: Enabled")
    }

    /// pf 를 켜고 참조 토큰을 받아 둔다.
    /// 다른 시스템 기능도 pf 를 함께 쓰므로, 우리가 끄지 않고 토큰만 반납한다.
    static func enable() {
        guard enableToken == nil else { return }
        let r = Shell.run("/sbin/pfctl", ["-E"])
        // 토큰은 표준 오류로 "Token : 1234567890" 처럼 나온다.
        for line in r.stderr.components(separatedBy: "\n") where line.contains("Token") {
            let parts = line.components(separatedBy: ":")
            if parts.count == 2 {
                enableToken = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        log("pf 를 켰습니다. 토큰: \(enableToken ?? "받지 못함")")
    }

    static func releaseEnableToken() {
        guard let token = enableToken else { return }
        Shell.run("/sbin/pfctl", ["-X", token])
        enableToken = nil
    }

    /// 앵커에 규칙을 올린다. 규칙 자체는 표(table)가 비어 있으면 아무것도 막지 않는다.
    static func loadAnchorRules() {
        guard FileManager.default.fileExists(atPath: Paths.pfAnchorFile) else {
            log("pf 앵커 파일이 없습니다: \(Paths.pfAnchorFile)")
            return
        }
        let r = Shell.run("/sbin/pfctl", ["-a", Paths.pfAnchorName, "-f", Paths.pfAnchorFile])
        if !r.succeeded {
            log("pf 앵커를 올리지 못했습니다: \(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    /// 차단 대상의 주소를 조회한다. hosts 파일을 거치지 않도록 공개 DNS 에 직접 묻는다.
    static func resolveAddresses(targets: [String]) -> [String] {
        var found = Set<String>()
        let servers = ["@1.1.1.1", "@8.8.8.8"]

        for host in targets {
            for server in servers {
                var gotAny = false
                for recordType in ["A", "AAAA"] {
                    let r = Shell.run("/usr/bin/dig",
                                      ["+short", "+time=2", "+tries=1", server, recordType, host],
                                      timeout: 8)
                    guard r.succeeded else { continue }
                    for line in r.stdout.components(separatedBy: "\n") {
                        let value = line.trimmingCharacters(in: .whitespaces)
                        if isIPAddress(value) {
                            found.insert(value)
                            gotAny = true
                        }
                    }
                }
                if gotAny { break }  // 이 서버에서 답을 받았으면 다음 서버는 묻지 않는다
            }
        }
        return found.sorted()
    }

    private static func isIPAddress(_ text: String) -> Bool {
        if text.isEmpty { return false }
        var v4 = in_addr()
        if inet_pton(AF_INET, text, &v4) == 1 { return true }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, text, &v6) == 1 { return true }
        return false
    }

    /// 조회한 주소를 표에 채워 넣어 실제로 막기 시작한다.
    @discardableResult
    static func block(targets: [String]) -> Int {
        enable()
        loadAnchorRules()

        let addresses = resolveAddresses(targets: targets)
        guard !addresses.isEmpty else {
            log("pf: 조회된 주소가 없어 IP 차단은 건너뜁니다.")
            return 0
        }

        let text = addresses.joined(separator: "\n") + "\n"
        try? text.write(toFile: Paths.pfTableFile, atomically: true, encoding: .utf8)

        let r = Shell.run("/sbin/pfctl",
                          ["-a", Paths.pfAnchorName, "-t", Paths.pfAnchorName,
                           "-T", "replace", "-f", Paths.pfTableFile])
        if !r.succeeded {
            log("pf 표를 갱신하지 못했습니다: \(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
            return 0
        }
        log("pf: 주소 \(addresses.count) 개를 막았습니다.")
        return addresses.count
    }

    /// 표를 비워서 IP 차단을 푼다. 앵커와 pf 자체는 그대로 둔다.
    static func unblock() {
        Shell.run("/sbin/pfctl", ["-a", Paths.pfAnchorName, "-t", Paths.pfAnchorName, "-T", "flush"])
    }

    /// 표에 들어 있는 주소 개수.
    static func blockedAddressCount() -> Int {
        let r = Shell.run("/sbin/pfctl", ["-a", Paths.pfAnchorName, "-t", Paths.pfAnchorName, "-T", "show"])
        guard r.succeeded else { return 0 }
        return r.stdout.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }
}
