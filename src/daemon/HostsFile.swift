import Foundation

/// /etc/hosts 안에 표시선으로 감싼 구간을 두고, 그 안쪽만 넣었다 뺐다 한다.
/// 사용자가 직접 적어 둔 다른 줄은 건드리지 않는다.
enum HostsFile {

    static let beginMarker = "# >>> YouTubeGuard 차단 구간 시작 >>>"
    static let endMarker = "# <<< YouTubeGuard 차단 구간 끝 <<<"
    static let notice = "# 이 구간은 YouTubeGuard 가 자동으로 관리합니다. 직접 고치지 마세요."

    enum HostsError: Error, LocalizedError {
        case writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .writeFailed(let detail): return "hosts 파일을 쓰지 못했습니다: \(detail)"
            }
        }
    }

    static func read() -> String {
        (try? String(contentsOfFile: Paths.hostsFile, encoding: .utf8)) ?? ""
    }

    /// 우리 구간을 걷어 낸 나머지를 돌려준다.
    /// 어떤 경우에도 마지막이 줄바꿈 하나로 끝나도록 맞춘다.
    /// 그래야 뒤에 차단 구간을 붙여도 마지막 줄에 들러붙지 않는다.
    static func stripped(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")

        if let begin = lines.firstIndex(where: { $0.hasPrefix(beginMarker) }) {
            if let end = lines[begin...].firstIndex(where: { $0.hasPrefix(endMarker) }) {
                lines.removeSubrange(begin...end)
            } else {
                // 끝 표시선이 사라진 경우. 그 뒤는 모두 우리가 넣은 것으로 보고 지운다.
                lines.removeSubrange(begin...)
            }
        }

        // 구간을 들어내면서 생긴 빈 줄이 쌓이지 않게 정리한다.
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        if lines.isEmpty { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    static func makeBlock(hostnames: [String]) -> String {
        var lines = [beginMarker, notice]
        for name in hostnames {
            lines.append("0.0.0.0\t\(name)")
            lines.append("::\t\(name)")
        }
        lines.append(endMarker)
        return lines.joined(separator: "\n")
    }

    /// hostnames 를 주면 차단 구간을 넣고, nil 을 주면 걷어 낸다.
    /// 실제로 내용이 달라졌을 때만 파일을 쓰고 true 를 돌려준다.
    @discardableResult
    static func apply(hostnames: [String]?) throws -> Bool {
        let current = read()
        let base = stripped(current)

        let desired: String
        if let hostnames = hostnames, !hostnames.isEmpty {
            desired = base + makeBlock(hostnames: hostnames) + "\n"
        } else {
            desired = base
        }

        if desired == current { return false }
        try write(desired)
        return true
    }

    /// 임시 파일에 쓰고 제자리로 옮긴다. 중간에 멈춰도 hosts 파일이 깨지지 않는다.
    private static func write(_ text: String) throws {
        let tempPath = "/etc/.hosts.ytguard.\(getpid())"
        let tempURL = URL(fileURLWithPath: tempPath)

        do {
            try text.write(to: tempURL, atomically: false, encoding: .utf8)
        } catch {
            throw HostsError.writeFailed(error.localizedDescription)
        }

        // hosts 파일은 root:wheel 소유에 0644 여야 한다.
        try? FileManager.default.setAttributes([
            .posixPermissions: 0o644,
            .ownerAccountID: 0,
            .groupOwnerAccountID: 0,
        ], ofItemAtPath: tempPath)

        if rename(tempPath, Paths.hostsFile) != 0 {
            let reason = String(cString: strerror(errno))
            try? FileManager.default.removeItem(atPath: tempPath)
            throw HostsError.writeFailed(reason)
        }
    }

    /// 지금 차단 구간이 들어가 있는지.
    static func isApplied() -> Bool {
        read().contains(beginMarker)
    }
}
