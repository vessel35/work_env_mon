import Foundation

// MARK: - 시간 표현

/// 하루 안의 시각(분 단위). 자정을 0 으로 둔다.
struct DayTime: Codable, Equatable, Comparable {
    var hour: Int
    var minute: Int

    var minutesFromMidnight: Int { hour * 60 + minute }

    static func < (a: DayTime, b: DayTime) -> Bool {
        a.minutesFromMidnight < b.minutesFromMidnight
    }

    var text: String { String(format: "%02d:%02d", hour, minute) }

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// "09:00" 또는 "9:00" 형태를 읽는다. 형식이 어긋나면 nil.
    init?(text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...24).contains(h), (0...59).contains(m) else { return nil }
        // 자정을 뜻하는 24:00 표기를 받아 00:00 으로 맞춘다.
        // 00:00-24:00 은 시작과 끝이 같아지므로 하루 종일 구간이 된다.
        guard h < 24 || m == 0 else { return nil }
        self.hour = h == 24 ? 0 : h
        self.minute = m
    }

    // JSON 에는 "09:00" 문자열로 담는다.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = DayTime(text: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "시각 형식이 올바르지 않습니다: \(raw)"))
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(text)
    }
}

// MARK: - 차단 규칙

/// 차단 구간 하나. days 는 월요일이 1, 일요일이 7 이다.
/// end 가 start 보다 앞서거나 같으면 자정을 넘어 다음 날까지 이어지는 것으로 본다.
struct BlockRule: Codable, Equatable {
    var days: [Int]
    var start: DayTime
    var end: DayTime

    /// 자정을 넘어가는 구간인지.
    var crossesMidnight: Bool { end <= start }

    /// 구간 길이(분). 시작과 끝이 같으면 하루 종일(1440분)로 본다.
    var durationMinutes: Int {
        let d = end.minutesFromMidnight - start.minutesFromMidnight
        return d > 0 ? d : d + 24 * 60
    }

    var isValid: Bool {
        !days.isEmpty && days.allSatisfy { (1...7).contains($0) } && durationMinutes > 0
    }
}

// MARK: - 설정

/// 사용자가 바꿀 수 있는 값들. 메뉴 바 앱이 쓰고 데몬이 읽는다.
struct Config: Codable, Equatable {
    /// 차단 기능 전체 스위치. 꺼 두면 어떤 규칙도 적용하지 않는다.
    var enabled: Bool
    var rules: [BlockRule]

    /// 막을 서비스의 이름표 목록. Services.all 에 있는 것 가운데 고른다.
    var services: [String]
    /// 직접 적어 넣은 주소. 서비스 목록에 없는 곳을 막을 때 쓴다.
    var customHosts: [String]

    /// 이 시각까지는 스케줄을 무시하고 통과시킨다(일시 해제).
    var snoozeUntil: Date?
    /// 이 시각까지는 스케줄과 무관하게 차단한다(즉시 차단).
    var forceBlockUntil: Date?

    /// 영상 전송에 쓰이는 호스트까지 함께 막을지.
    var blockMediaHosts: Bool
    /// 브라우저가 암호화 DNS 로 hosts 파일을 우회하지 못하도록,
    /// 차단 시간 동안만 주요 DoH 주소를 함께 막을지.
    var hardenDoH: Bool
    /// pf 방화벽으로 IP 수준 차단을 함께 걸지. 기본은 꺼짐.
    var usePacketFilter: Bool

    var updatedAt: Date?

    static let `default` = Config(
        enabled: true,
        rules: [BlockRule(days: [1, 2, 3, 4, 5],
                          start: DayTime(hour: 9, minute: 0),
                          end: DayTime(hour: 18, minute: 0))],
        services: ["youtube"],
        customHosts: [],
        snoozeUntil: nil,
        forceBlockUntil: nil,
        blockMediaHosts: true,
        hardenDoH: true,
        usePacketFilter: false,
        updatedAt: nil
    )
}

extension Config {
    /// 예전 판이 쓴 설정 파일에는 없는 항목이 있을 수 있다.
    /// 빠진 항목은 기본값으로 채워서, 새 판으로 올려도 설정을 잃지 않게 한다.
    /// 이 초기화 메서드는 확장에 두어야 항목을 나열해 만드는 방식이 그대로 남는다.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Config.default

        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? fallback.enabled
        rules = try container.decodeIfPresent([BlockRule].self, forKey: .rules) ?? fallback.rules
        services = try container.decodeIfPresent([String].self, forKey: .services) ?? fallback.services
        customHosts = try container.decodeIfPresent([String].self, forKey: .customHosts) ?? fallback.customHosts
        snoozeUntil = try container.decodeIfPresent(Date.self, forKey: .snoozeUntil)
        forceBlockUntil = try container.decodeIfPresent(Date.self, forKey: .forceBlockUntil)
        blockMediaHosts = try container.decodeIfPresent(Bool.self, forKey: .blockMediaHosts) ?? fallback.blockMediaHosts
        hardenDoH = try container.decodeIfPresent(Bool.self, forKey: .hardenDoH) ?? fallback.hardenDoH
        usePacketFilter = try container.decodeIfPresent(Bool.self, forKey: .usePacketFilter) ?? fallback.usePacketFilter
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

// MARK: - 상태

/// 지금 차단 중인지와 그 이유. 데몬이 쓰고 메뉴 바 앱이 읽는다.
struct BlockState: Codable, Equatable {
    enum Reason: String, Codable {
        case disabled      // 전체 스위치가 꺼져 있음
        case schedule      // 스케줄에 걸려 차단 중
        case forced        // 사용자가 즉시 차단을 눌렀음
        case snoozed       // 사용자가 일시 해제했음
        case idle          // 스케줄 밖이라 통과
    }

    var blocking: Bool
    var enabled: Bool
    var reason: Reason
    /// 지금 상태가 유지되는 끝 시각. 예정된 변화가 없으면 nil.
    var activeUntil: Date?
    /// 다음으로 상태가 바뀌는 시각.
    var nextChange: Date?
    /// 데몬이 마지막으로 살아 있음을 기록한 시각.
    var heartbeat: Date
    var hostsApplied: Bool
    var pfApplied: Bool
    var blockedHostCount: Int
    var lastError: String?
}

// MARK: - JSON 읽고 쓰기

enum JSONStore {
    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func load<T: Decodable>(_ type: T.Type, from path: String) throws -> T {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try makeDecoder().decode(type, from: data)
    }

    /// 임시 파일에 먼저 쓰고 옮긴다. 도중에 죽어도 반쯤 쓰인 파일이 남지 않는다.
    static func save<T: Encodable>(_ value: T, to path: String) throws {
        let data = try makeEncoder().encode(value)
        let url = URL(fileURLWithPath: path)
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(getpid())")
        try data.write(to: tmp, options: .atomic)

        // 기존 파일의 권한을 유지한다. 설정 파일은 admin 그룹이 쓸 수 있어야 한다.
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: path) {
            var keep: [FileAttributeKey: Any] = [:]
            if let p = attrs[.posixPermissions] { keep[.posixPermissions] = p }
            if let g = attrs[.groupOwnerAccountID] { keep[.groupOwnerAccountID] = g }
            try? fm.setAttributes(keep, ofItemAtPath: tmp.path)
        }
        if fm.fileExists(atPath: path) {
            _ = try fm.replaceItemAt(url, withItemAt: tmp)
        } else {
            // 처음 만드는 경우에는 바꿔치기할 대상이 없으므로 그대로 옮긴다.
            try fm.moveItem(at: tmp, to: url)
        }
    }
}
