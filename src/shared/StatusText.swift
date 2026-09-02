import Foundation

/// 상태를 사람이 읽는 문장으로 바꾼다. 데몬과 메뉴 바 앱이 같은 표현을 쓰도록 모아 두었다.
enum StatusText {

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = format
        return f
    }

    /// 오늘 안이면 시각만, 내일 이후면 요일을 함께 보여 준다.
    static func timeLabel(_ date: Date, now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        if cal.isDate(date, inSameDayAs: now) {
            return formatter("HH:mm").string(from: date)
        }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now),
           cal.isDate(date, inSameDayAs: tomorrow) {
            return "내일 " + formatter("HH:mm").string(from: date)
        }
        return formatter("M월 d일(E) HH:mm").string(from: date)
    }

    /// 남은 시간을 "1시간 20분" 처럼 적는다.
    static func remainingLabel(until date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let minutes = (seconds + 59) / 60
        if minutes < 60 { return "\(minutes)분" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)시간" : "\(hours)시간 \(rest)분"
    }

    /// 메뉴 맨 위에 붙는 한 줄.
    static func headline(_ state: BlockState?, now: Date = Date()) -> String {
        guard let state = state else {
            return "상태를 읽지 못했습니다"
        }
        switch state.reason {
        case .disabled:
            return "차단 기능이 꺼져 있습니다"
        case .schedule:
            if let until = state.activeUntil {
                return "차단 중 · \(timeLabel(until, now: now))에 풀립니다"
            }
            return "차단 중"
        case .forced:
            if let until = state.activeUntil {
                return "즉시 차단 중 · \(remainingLabel(until: until, now: now)) 남음"
            }
            return "즉시 차단 중"
        case .snoozed:
            if let until = state.activeUntil {
                return "일시 해제 중 · \(remainingLabel(until: until, now: now)) 뒤 복귀"
            }
            return "일시 해제 중"
        case .idle:
            if let next = state.nextChange {
                return "허용 중 · \(timeLabel(next, now: now))부터 차단"
            }
            return "허용 중 · 예정된 차단 없음"
        }
    }

    /// 메뉴 바 아이콘 위에 마우스를 올렸을 때 나오는 설명.
    static func tooltip(_ state: BlockState?, now: Date = Date()) -> String {
        guard let state = state else {
            return "YouTubeGuard · 데몬과 연결되지 않았습니다"
        }
        var lines = ["YouTubeGuard", headline(state, now: now)]
        if state.blocking {
            lines.append("막는 중인 주소 \(state.blockedHostCount) 개" + (state.pfApplied ? " · 방화벽 함께 적용" : ""))
        }
        if let error = state.lastError, !error.isEmpty {
            lines.append("문제: \(error)")
        }
        if now.timeIntervalSince(state.heartbeat) > 60 {
            lines.append("데몬이 \(Int(now.timeIntervalSince(state.heartbeat)))초째 응답하지 않습니다")
        }
        return lines.joined(separator: "\n")
    }

    /// 데몬이 응답하고 있는지. 메뉴 바 아이콘을 흐리게 표시할지 판단할 때 쓴다.
    static func isDaemonResponsive(_ state: BlockState?, now: Date = Date()) -> Bool {
        guard let state = state else { return false }
        return now.timeIntervalSince(state.heartbeat) < 60
    }
}
