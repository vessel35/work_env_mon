import Foundation

/// 규칙을 사람이 읽고 고칠 수 있는 한 줄짜리 문장으로 주고받는다.
/// 예: "월-금 09:00-18:00", "매일 00:00-06:00", "월,수,금 20:00-23:30"
enum RuleText {

    static let dayNames = ["월", "화", "수", "목", "금", "토", "일"]

    struct ParseError: Error {
        var line: Int      // 1 부터 센다
        var message: String
    }

    // MARK: 규칙 -> 문장

    static func format(_ rules: [BlockRule]) -> String {
        rules.map { format($0) }.joined(separator: "\n")
    }

    static func format(_ rule: BlockRule) -> String {
        "\(formatDays(rule.days)) \(rule.start.text)-\(rule.end.text)"
    }

    static func formatDays(_ days: [Int]) -> String {
        let sorted = Array(Set(days)).sorted()
        if sorted == [1, 2, 3, 4, 5, 6, 7] { return "매일" }
        if sorted == [1, 2, 3, 4, 5] { return "평일" }
        if sorted == [6, 7] { return "주말" }

        // 이어지는 요일은 범위로 묶고, 떨어진 것은 쉼표로 나열한다.
        var chunks: [String] = []
        var index = 0
        while index < sorted.count {
            var last = index
            while last + 1 < sorted.count && sorted[last + 1] == sorted[last] + 1 { last += 1 }
            let from = dayNames[sorted[index] - 1]
            let to = dayNames[sorted[last] - 1]
            if last - index >= 2 {
                chunks.append("\(from)-\(to)")
            } else if last - index == 1 {
                chunks.append(from)
                chunks.append(to)
            } else {
                chunks.append(from)
            }
            index = last + 1
        }
        return chunks.joined(separator: ",")
    }

    // MARK: 문장 -> 규칙

    /// 여러 줄을 한 번에 읽는다. 빈 줄과 # 로 시작하는 줄은 건너뛴다.
    static func parse(_ text: String) throws -> [BlockRule] {
        var rules: [BlockRule] = []
        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            rules.append(try parseLine(line, lineNumber: index + 1))
        }
        return rules
    }

    static func parseLine(_ line: String, lineNumber: Int) throws -> BlockRule {
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard fields.count >= 2 else {
            throw ParseError(line: lineNumber,
                             message: "요일과 시간을 함께 적어 주세요. 예: 월-금 09:00-18:00")
        }

        let timeField = fields[fields.count - 1]
        let dayField = fields[0..<(fields.count - 1)].joined()

        let days = try parseDays(dayField, lineNumber: lineNumber)
        let (start, end) = try parseTimeRange(timeField, lineNumber: lineNumber)

        let rule = BlockRule(days: days, start: start, end: end)
        guard rule.isValid else {
            throw ParseError(line: lineNumber, message: "시작 시각과 끝 시각이 같아 구간의 길이가 0 입니다.")
        }
        return rule
    }

    static func parseDays(_ field: String, lineNumber: Int) throws -> [Int] {
        // 자동 고침이 붙임표를 긴 줄표로 바꾼 경우까지 받아 준다.
        let normalized = field
            .replacingOccurrences(of: "요일", with: "")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
        switch normalized {
        case "매일", "날마다": return [1, 2, 3, 4, 5, 6, 7]
        case "평일", "주중": return [1, 2, 3, 4, 5]
        case "주말": return [6, 7]
        default: break
        }

        var days = Set<Int>()
        for token in normalized.split(separator: ",").map({ String($0).trimmingCharacters(in: .whitespaces) }) {
            if token.isEmpty { continue }
            let bounds = token.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
            if bounds.count == 1 {
                days.insert(try dayNumber(bounds[0], lineNumber: lineNumber))
            } else if bounds.count == 2 {
                let from = try dayNumber(bounds[0], lineNumber: lineNumber)
                let to = try dayNumber(bounds[1], lineNumber: lineNumber)
                // 금-월 처럼 주를 넘어가는 표기도 받아 준다.
                var d = from
                while true {
                    days.insert(d)
                    if d == to { break }
                    d = d % 7 + 1
                }
            } else {
                throw ParseError(line: lineNumber, message: "요일 표기를 이해할 수 없습니다: \(token)")
            }
        }

        guard !days.isEmpty else {
            throw ParseError(line: lineNumber, message: "요일이 비어 있습니다.")
        }
        return days.sorted()
    }

    static func dayNumber(_ token: String, lineNumber: Int) throws -> Int {
        let key = String(token.prefix(1))
        guard let index = dayNames.firstIndex(of: key) else {
            throw ParseError(line: lineNumber,
                             message: "요일은 월 화 수 목 금 토 일 중에서 적어 주세요. 받은 값: \(token)")
        }
        return index + 1
    }

    static func parseTimeRange(_ field: String, lineNumber: Int) throws -> (DayTime, DayTime) {
        let normalized = field
            .replacingOccurrences(of: "~", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
        let parts = normalized.split(separator: "-").map(String.init)
        guard parts.count == 2,
              let start = DayTime(text: parts[0]),
              let end = DayTime(text: parts[1]) else {
            throw ParseError(line: lineNumber,
                             message: "시간은 09:00-18:00 처럼 적어 주세요. 받은 값: \(field)")
        }
        return (start, end)
    }

    /// 편집 창에 처음 보여 줄 안내문.
    static let helpText = """
    # 한 줄에 차단 구간 하나를 적습니다.
    # 요일은 월 화 수 목 금 토 일, 매일, 평일, 주말 을 쓸 수 있습니다.
    # 끝 시각이 시작 시각보다 앞서면 자정을 넘어 다음 날까지 이어집니다.
    # 시작과 끝을 같게 적으면 그 요일 하루 종일이 됩니다. (예: 주말 00:00-00:00)
    #
    # 예)
    #   평일 09:00-18:00
    #   월,수,금 20:00-23:00
    #   매일 23:00-06:00
    """
}
