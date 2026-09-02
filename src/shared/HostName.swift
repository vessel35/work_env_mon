import Foundation

/// 사용자가 직접 적어 넣는 주소를 다듬고 검사한다.
enum HostName {

    struct ParseError: Error {
        var line: Int      // 1 부터 센다
        var message: String
    }

    /// 붙여 넣은 주소에서 실제 호스트 이름만 남긴다.
    /// "https://www.netflix.com/browse?x=1" 처럼 적어도 받아 준다.
    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces).lowercased()

        if let range = text.range(of: "://") {
            text = String(text[range.upperBound...])
        }
        if let slash = text.firstIndex(of: "/") {
            text = String(text[..<slash])
        }
        for separator in ["?", "#"] {
            if let index = text.firstIndex(of: Character(separator)) {
                text = String(text[..<index])
            }
        }
        // 사용자 이름이나 포트 번호가 붙어 있으면 떼어 낸다.
        if let at = text.lastIndex(of: "@") {
            text = String(text[text.index(after: at)...])
        }
        if let colon = text.firstIndex(of: ":") {
            text = String(text[..<colon])
        }
        while text.hasSuffix(".") {
            text.removeLast()
        }
        return text
    }

    /// 막아도 되는 주소인지 본다. 문제가 있으면 사람이 읽을 수 있는 이유를 돌려준다.
    static func validationMessage(for host: String) -> String? {
        if host.isEmpty { return "주소가 비어 있습니다." }
        if host.count > 253 { return "주소가 너무 깁니다." }
        if host == "localhost" { return "localhost 는 막을 수 없습니다. 이 기기 자신을 가리키는 이름입니다." }

        // 숫자로 된 주소는 hosts 파일에서 이름 자리에 쓸 수 없다.
        var v4 = in_addr()
        var v6 = in6_addr()
        if inet_pton(AF_INET, host, &v4) == 1 || inet_pton(AF_INET6, host, &v6) == 1 {
            return "IP 주소가 아니라 도메인 이름을 적어 주세요."
        }

        guard host.contains(".") else {
            return "점이 없는 이름은 막을 수 없습니다. netflix.com 처럼 적어 주세요."
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        if host.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "영문 소문자와 숫자, 점, 붙임표만 쓸 수 있습니다."
        }
        for label in host.split(separator: ".", omittingEmptySubsequences: false) {
            if label.isEmpty { return "점이 잇달아 있거나 빠진 부분이 있습니다." }
            if label.count > 63 { return "주소의 한 마디가 너무 깁니다." }
            if label.hasPrefix("-") || label.hasSuffix("-") {
                return "붙임표로 시작하거나 끝나는 마디가 있습니다."
            }
        }
        return nil
    }

    /// hosts 파일은 하위 도메인을 한 번에 막지 못한다.
    /// 그래서 적어 준 주소와 www. 를 붙인 형태를 함께 막아 준다.
    static func expand(_ host: String) -> [String] {
        if host.hasPrefix("www.") {
            let bare = String(host.dropFirst(4))
            return bare.contains(".") ? [host, bare] : [host]
        }
        return [host, "www." + host]
    }

    /// 한 줄에 하나씩 적은 주소 목록을 읽는다. 빈 줄과 # 로 시작하는 줄은 건너뛴다.
    static func parseList(_ text: String) throws -> [String] {
        var hosts: [String] = []
        var seen = Set<String>()

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let host = normalize(line)
            if let message = validationMessage(for: host) {
                throw ParseError(line: index + 1, message: message)
            }
            if seen.insert(host).inserted {
                hosts.append(host)
            }
        }
        return hosts
    }

    static func format(_ hosts: [String]) -> String {
        hosts.joined(separator: "\n")
    }
}
