import Foundation

/// 규칙 목록과 현재 시각으로 "지금 차단해야 하는가"를 판정한다.
enum Schedule {


    /// 전체 스위치를 끌 때 함께 고르는 기한.
    ///
    /// 기한 없이 끄면 한 번의 선택이 며칠씩 조용히 이어진다.
    /// 그래서 계속 꺼 두는 것은 따로 골라야만 되도록 두었다.
    enum DisableSpan: CaseIterable {
        case today      // 오늘이 끝날 때까지
        case week       // 이레 뒤 자정까지
        case forever    // 직접 켤 때까지

        var title: String {
            switch self {
            case .today: return "오늘 하루"
            case .week: return "일주일"
            case .forever: return "계속"
            }
        }

        var confirmTitle: String {
            switch self {
            case .today: return "오늘 하루 동안 차단 기능을 끌까요?"
            case .week: return "일주일 동안 차단 기능을 끌까요?"
            case .forever: return "차단 기능을 계속 꺼 둘까요?"
            }
        }

        /// 저절로 다시 켜지는 시각. 계속 꺼 두는 경우에는 nil.
        func expiry(from now: Date) -> Date? {
            let midnight = calendar.startOfDay(for: now)
            switch self {
            case .today: return calendar.date(byAdding: .day, value: 1, to: midnight)
            case .week: return calendar.date(byAdding: .day, value: 7, to: midnight)
            case .forever: return nil
            }
        }
    }

    struct Interval {
        var start: Date
        var end: Date
        func contains(_ d: Date) -> Bool { d >= start && d < end }
    }

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        return c
    }

    /// Calendar 의 요일 번호(일요일이 1)를 월요일이 1 인 번호로 바꾼다.
    static func isoWeekday(of date: Date) -> Int {
        let w = calendar.component(.weekday, from: date)
        return ((w + 5) % 7) + 1
    }

    /// 기준 시각 주변으로 규칙을 펼쳐서 실제 구간 목록을 만든다.
    /// 자정을 넘는 규칙과 겹치는 규칙을 모두 다루기 위해 앞뒤로 여유를 둔다.
    static func intervals(rules: [BlockRule], around now: Date) -> [Interval] {
        let cal = calendar
        guard let today = cal.date(from: cal.dateComponents([.year, .month, .day], from: now)) else {
            return []
        }

        var raw: [Interval] = []
        for offset in -2...9 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = isoWeekday(of: day)
            for rule in rules where rule.isValid && rule.days.contains(weekday) {
                guard let start = cal.date(bySettingHour: rule.start.hour,
                                           minute: rule.start.minute,
                                           second: 0,
                                           of: day) else { continue }
                let end = start.addingTimeInterval(TimeInterval(rule.durationMinutes * 60))
                raw.append(Interval(start: start, end: end))
            }
        }
        return merge(raw)
    }

    /// 겹치거나 맞닿은 구간을 하나로 합친다. 합쳐 두면 경계 계산이 단순해진다.
    static func merge(_ intervals: [Interval]) -> [Interval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var out: [Interval] = []
        for iv in sorted {
            if var last = out.last, iv.start <= last.end {
                if iv.end > last.end {
                    last.end = iv.end
                    out[out.count - 1] = last
                }
            } else {
                out.append(iv)
            }
        }
        return out
    }

    /// 스케줄만 놓고 봤을 때의 판정 결과.
    struct ScheduleVerdict {
        var blocking: Bool
        var until: Date?       // 지금 구간이 끝나는 시각 (차단 중일 때)
        var nextChange: Date?  // 다음으로 상태가 바뀌는 시각
    }

    static func evaluateRules(_ rules: [BlockRule], now: Date) -> ScheduleVerdict {
        let ivs = intervals(rules: rules, around: now)
        if let current = ivs.first(where: { $0.contains(now) }) {
            return ScheduleVerdict(blocking: true, until: current.end, nextChange: current.end)
        }
        let nextStart = ivs.first(where: { $0.start > now })?.start
        return ScheduleVerdict(blocking: false, until: nil, nextChange: nextStart)
    }

    /// 전체 스위치와 즉시 차단/일시 해제까지 반영한 최종 판정.
    /// 우선순위는 전체 스위치, 즉시 차단, 일시 해제, 스케줄 순이다.
    static func decide(config: Config, now: Date) -> (blocking: Bool, reason: BlockState.Reason, until: Date?, nextChange: Date?) {
        // 기한을 붙여 꺼 둔 경우에는 그 시각이 다음 변화가 된다.
        guard config.isEnabled(at: now) else {
            let expiry = config.disabledExpiry(at: now)
            return (false, .disabled, expiry, expiry)
        }

        if let forced = config.forceBlockUntil, forced > now {
            // 즉시 차단이 끝난 뒤에는 스케줄로 돌아가므로, 그 시점이 다음 변화가 된다.
            return (true, .forced, forced, forced)
        }

        if let snooze = config.snoozeUntil, snooze > now {
            return (false, .snoozed, snooze, snooze)
        }

        let v = evaluateRules(config.rules, now: now)
        return (v.blocking, v.blocking ? .schedule : .idle, v.until, v.nextChange)
    }
}
