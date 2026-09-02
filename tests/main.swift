import Foundation

// 공용 코드(스케줄 판정, 규칙 문장 해석)를 확인하는 작은 검사 프로그램.
// 루트 권한이 필요 없어 빌드 직후 바로 돌려 볼 수 있다.

var failures = 0
var checks = 0

func check(_ condition: Bool, _ label: String) {
    checks += 1
    if condition {
        print("  통과  \(label)")
    } else {
        failures += 1
        print("  실패  \(label)")
    }
}

func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    checks += 1
    if actual == expected {
        print("  통과  \(label)")
    } else {
        failures += 1
        print("  실패  \(label)")
        print("        기대한 값: \(expected)")
        print("        받은 값:   \(actual)")
    }
}

func section(_ title: String) { print("\n[\(title)]") }

/// 검사에 쓸 시각을 만든다. 2026년 9월 2일은 수요일이다.
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    return cal.date(from: DateComponents(year: year, month: month, day: day,
                                         hour: hour, minute: minute))!
}

// MARK: 규칙 문장 해석

section("규칙 문장 해석")

do {
    let rules = try RuleText.parse("평일 09:00-18:00")
    equal(rules.count, 1, "한 줄이면 규칙 하나")
    equal(rules[0].days, [1, 2, 3, 4, 5], "평일은 월요일부터 금요일까지")
    equal(rules[0].start.text, "09:00", "시작 시각")
    equal(rules[0].durationMinutes, 540, "구간 길이는 9시간")
    check(!rules[0].crossesMidnight, "자정을 넘지 않음")
} catch {
    check(false, "평일 규칙을 읽지 못했습니다: \(error)")
}

do {
    let rules = try RuleText.parse("매일 23:00-06:00")
    check(rules[0].crossesMidnight, "끝 시각이 앞서면 자정을 넘는 구간")
    equal(rules[0].durationMinutes, 420, "23시부터 다음 날 6시까지는 7시간")
    equal(rules[0].days.count, 7, "매일은 요일 일곱 개")
} catch {
    check(false, "자정을 넘는 규칙을 읽지 못했습니다: \(error)")
}

do {
    let rules = try RuleText.parse("월,수,금 20:00-23:30")
    equal(rules[0].days, [1, 3, 5], "쉼표로 나열한 요일")
} catch {
    check(false, "나열 표기를 읽지 못했습니다: \(error)")
}

do {
    let rules = try RuleText.parse("금-월 22:00-02:00")
    equal(rules[0].days, [1, 5, 6, 7], "금요일에서 월요일까지는 주를 넘어 이어짐")
} catch {
    check(false, "주를 넘는 요일 범위를 읽지 못했습니다: \(error)")
}

do {
    let rules = try RuleText.parse("""
    # 주석은 건너뜁니다

    평일 09:00-12:00
    주말 14:00~16:00
    """)
    equal(rules.count, 2, "주석과 빈 줄은 세지 않음")
    equal(rules[1].days, [6, 7], "주말은 토요일과 일요일")
    equal(rules[1].end.text, "16:00", "물결표도 구간 구분으로 받아 줌")
} catch {
    check(false, "여러 줄을 읽지 못했습니다: \(error)")
}

// 잘못된 입력은 몇 번째 줄인지와 함께 거절해야 한다
do {
    _ = try RuleText.parse("평일 25:00-26:00")
    check(false, "25시는 거절해야 합니다")
} catch let e as RuleText.ParseError {
    equal(e.line, 1, "잘못된 시각은 1번째 줄에서 걸림")
} catch {
    check(false, "예상하지 못한 오류 종류")
}

do {
    _ = try RuleText.parse("평일 09:00-18:00\n엉뚱 09:00-10:00")
    check(false, "없는 요일은 거절해야 합니다")
} catch let e as RuleText.ParseError {
    equal(e.line, 2, "잘못된 요일은 2번째 줄에서 걸림")
} catch {
    check(false, "예상하지 못한 오류 종류")
}

do {
    let rules = try RuleText.parse("평일 09:00-09:00")
    equal(rules[0].durationMinutes, 1440, "시작과 끝이 같으면 하루 종일")
} catch {
    check(false, "하루 종일 규칙을 읽지 못했습니다: \(error)")
}

do {
    let rules = try RuleText.parse("주말 00:00-24:00")
    equal(rules[0].durationMinutes, 1440, "24:00 은 자정을 뜻함")
    equal(rules[0].end.text, "00:00", "24:00 은 00:00 으로 맞춰짐")
} catch {
    check(false, "24:00 표기를 읽지 못했습니다: \(error)")
}

do {
    _ = try RuleText.parse("평일 25:00-26:00")
    check(false, "25시는 여전히 거절해야 합니다")
} catch {
    check(true, "24 를 넘는 시각은 거절")
}

// MARK: 규칙을 다시 문장으로

section("규칙을 문장으로 되돌리기")

equal(RuleText.formatDays([1, 2, 3, 4, 5, 6, 7]), "매일", "일곱 요일은 매일")
equal(RuleText.formatDays([1, 2, 3, 4, 5]), "평일", "다섯 요일은 평일")
equal(RuleText.formatDays([6, 7]), "주말", "토일은 주말")
equal(RuleText.formatDays([1, 3, 5]), "월,수,금", "떨어진 요일은 쉼표로")
equal(RuleText.formatDays([2, 3, 4]), "화-목", "이어진 세 요일은 범위로")
equal(RuleText.formatDays([1, 2]), "월,화", "이어진 두 요일은 범위로 묶지 않음")

do {
    let original = "평일 09:00-18:00\n주말 14:00-16:00\n월,수 21:00-23:00"
    let restored = RuleText.format(try RuleText.parse(original))
    equal(restored, original, "문장에서 규칙으로 바꾼 뒤 되돌려도 같음")
} catch {
    check(false, "되돌리기에 실패했습니다: \(error)")
}

// MARK: 스케줄 판정

section("스케줄 판정")

let weekdayRule = BlockRule(days: [1, 2, 3, 4, 5],
                            start: DayTime(hour: 9, minute: 0),
                            end: DayTime(hour: 18, minute: 0))

equal(Schedule.isoWeekday(of: date(2026, 9, 2, 12, 0)), 3, "2026년 9월 2일은 수요일")
equal(Schedule.isoWeekday(of: date(2026, 9, 6, 12, 0)), 7, "2026년 9월 6일은 일요일")

var config = Config.default
config.rules = [weekdayRule]

do {  // 구간 한가운데
    let d = Schedule.decide(config: config, now: date(2026, 9, 2, 10, 0))
    check(d.blocking, "수요일 10시는 차단 구간 안")
    equal(d.reason, .schedule, "이유는 스케줄")
    equal(d.until, date(2026, 9, 2, 18, 0), "그날 18시에 풀림")
}

do {  // 시작 시각은 포함
    let d = Schedule.decide(config: config, now: date(2026, 9, 2, 9, 0))
    check(d.blocking, "시작 시각 09:00 은 차단에 들어감")
}

do {  // 끝 시각은 제외
    let d = Schedule.decide(config: config, now: date(2026, 9, 2, 18, 0))
    check(!d.blocking, "끝 시각 18:00 은 이미 풀린 상태")
    equal(d.nextChange, date(2026, 9, 3, 9, 0), "다음 차단은 목요일 9시")
}

do {  // 주말
    let d = Schedule.decide(config: config, now: date(2026, 9, 5, 10, 0))
    check(!d.blocking, "토요일은 평일 규칙에 걸리지 않음")
    equal(d.nextChange, date(2026, 9, 7, 9, 0), "다음 차단은 월요일 9시")
}

section("자정을 넘는 구간")

var nightConfig = Config.default
nightConfig.rules = [BlockRule(days: [1, 2, 3, 4, 5, 6, 7],
                               start: DayTime(hour: 23, minute: 0),
                               end: DayTime(hour: 6, minute: 0))]

do {
    let d = Schedule.decide(config: nightConfig, now: date(2026, 9, 3, 1, 0))
    check(d.blocking, "새벽 1시는 전날 23시에 시작한 구간 안")
    equal(d.until, date(2026, 9, 3, 6, 0), "그날 아침 6시에 풀림")
}

do {
    let d = Schedule.decide(config: nightConfig, now: date(2026, 9, 3, 12, 0))
    check(!d.blocking, "낮 12시는 구간 밖")
    equal(d.nextChange, date(2026, 9, 3, 23, 0), "다음 차단은 그날 23시")
}

section("겹치는 구간 합치기")

var overlapConfig = Config.default
overlapConfig.rules = [
    BlockRule(days: [3], start: DayTime(hour: 9, minute: 0), end: DayTime(hour: 13, minute: 0)),
    BlockRule(days: [3], start: DayTime(hour: 12, minute: 0), end: DayTime(hour: 18, minute: 0)),
]

do {
    let d = Schedule.decide(config: overlapConfig, now: date(2026, 9, 2, 12, 30))
    check(d.blocking, "겹치는 두 구간 사이에서도 차단")
    equal(d.until, date(2026, 9, 2, 18, 0), "합쳐진 구간의 끝인 18시까지")
}

section("전체 스위치와 임시 조작")

do {
    var off = config
    off.enabled = false
    let d = Schedule.decide(config: off, now: date(2026, 9, 2, 10, 0))
    check(!d.blocking, "전체 스위치를 끄면 차단하지 않음")
    equal(d.reason, .disabled, "이유는 전체 꺼짐")
}

do {
    var snoozed = config
    snoozed.snoozeUntil = date(2026, 9, 2, 11, 0)
    let d = Schedule.decide(config: snoozed, now: date(2026, 9, 2, 10, 0))
    check(!d.blocking, "일시 해제 중에는 스케줄을 무시함")
    equal(d.reason, .snoozed, "이유는 일시 해제")

    let after = Schedule.decide(config: snoozed, now: date(2026, 9, 2, 11, 30))
    check(after.blocking, "일시 해제가 끝나면 스케줄로 돌아옴")
}

do {
    var forced = config
    forced.forceBlockUntil = date(2026, 9, 5, 12, 0)
    let d = Schedule.decide(config: forced, now: date(2026, 9, 5, 11, 0))
    check(d.blocking, "즉시 차단은 스케줄 밖에서도 막음")
    equal(d.reason, .forced, "이유는 즉시 차단")
}

do {
    var both = config
    both.forceBlockUntil = date(2026, 9, 2, 11, 0)
    both.snoozeUntil = date(2026, 9, 2, 12, 0)
    let d = Schedule.decide(config: both, now: date(2026, 9, 2, 10, 0))
    check(d.blocking, "즉시 차단이 일시 해제보다 앞섬")
}

do {
    var off = config
    off.enabled = false
    off.forceBlockUntil = date(2026, 9, 2, 12, 0)
    let d = Schedule.decide(config: off, now: date(2026, 9, 2, 10, 0))
    check(!d.blocking, "전체 스위치가 꺼져 있으면 즉시 차단도 동작하지 않음")
}

// MARK: hosts 파일 다루기

section("hosts 파일 구간 넣고 빼기")

let sampleHosts = """
##
# Host Database
##
127.0.0.1\tlocalhost
255.255.255.255\tbroadcasthost
::1\tlocalhost
"""

let withBlock = HostsFile.stripped(sampleHosts) + HostsFile.makeBlock(hostnames: ["youtube.com", "youtu.be"]) + "\n"
check(withBlock.contains("0.0.0.0\tyoutube.com"), "차단 구간에 주소가 들어감")
check(withBlock.contains("::\tyoutu.be"), "IPv6 쪽도 함께 막음")
check(withBlock.contains("127.0.0.1\tlocalhost"), "원래 있던 줄은 그대로 남음")

let removed = HostsFile.stripped(withBlock)
check(!removed.contains("youtube.com"), "구간을 걷어 내면 차단 주소가 사라짐")
check(removed.contains("broadcasthost"), "걷어 낸 뒤에도 원래 줄은 남음")
equal(removed.trimmingCharacters(in: .whitespacesAndNewlines),
      sampleHosts.trimmingCharacters(in: .whitespacesAndNewlines),
      "넣었다 빼면 원래 내용으로 돌아옴")

// 끝 표시선이 사라진 경우에도 정리되어야 한다
let brokenBlock = HostsFile.stripped(sampleHosts) + HostsFile.beginMarker + "\n0.0.0.0\tyoutube.com\n"
check(!HostsFile.stripped(brokenBlock).contains("youtube.com"), "끝 표시선이 없어도 구간을 걷어 냄")

// MARK: 차단 대상 목록

section("차단 대상 목록")

var mediaOff = Config.default
mediaOff.blockMediaHosts = false
mediaOff.hardenDoH = false
let coreOnly = Blocklist.hostnames(config: mediaOff)
check(coreOnly.contains("www.youtube.com"), "기본 목록에 YouTube 가 들어감")
check(!coreOnly.contains("googlevideo.com"), "영상 호스트를 끄면 목록에서 빠짐")
check(!coreOnly.contains("dns.google"), "암호화 DNS 대응을 끄면 목록에서 빠짐")
check(!coreOnly.contains("www.google.com"), "구글 검색은 막지 않음")
check(!coreOnly.contains("gmail.com"), "지메일은 막지 않음")

let full = Blocklist.hostnames(config: Config.default)
check(full.contains("googlevideo.com"), "기본값에서는 영상 호스트도 막음")
check(full.contains("dns.google"), "기본값에서는 암호화 DNS 대응도 켜짐")
equal(full.count, Set(full).count, "목록에 중복이 없음")

// MARK: 상태 문구

section("상태 문구")

let blockingState = BlockState(blocking: true, enabled: true, reason: .schedule,
                               activeUntil: date(2026, 9, 2, 18, 0),
                               nextChange: date(2026, 9, 2, 18, 0),
                               heartbeat: date(2026, 9, 2, 10, 0),
                               hostsApplied: true, pfApplied: false,
                               blockedHostCount: 40, lastError: nil)
equal(StatusText.headline(blockingState, now: date(2026, 9, 2, 10, 0)),
      "차단 중 · 18:00에 풀립니다", "차단 중 문구")

let idleState = BlockState(blocking: false, enabled: true, reason: .idle,
                           activeUntil: nil, nextChange: date(2026, 9, 3, 9, 0),
                           heartbeat: date(2026, 9, 2, 20, 0),
                           hostsApplied: false, pfApplied: false,
                           blockedHostCount: 0, lastError: nil)
equal(StatusText.headline(idleState, now: date(2026, 9, 2, 20, 0)),
      "허용 중 · 내일 09:00부터 차단", "허용 중 문구")

equal(StatusText.remainingLabel(until: date(2026, 9, 2, 11, 30), now: date(2026, 9, 2, 10, 0)),
      "1시간 30분", "남은 시간 표기")
equal(StatusText.remainingLabel(until: date(2026, 9, 2, 10, 30), now: date(2026, 9, 2, 10, 0)),
      "30분", "한 시간 미만은 분으로만")

check(!StatusText.isDaemonResponsive(blockingState, now: date(2026, 9, 2, 12, 0)),
      "심장 박동이 오래되면 응답하지 않는 것으로 봄")
check(StatusText.isDaemonResponsive(blockingState, now: date(2026, 9, 2, 10, 0)),
      "방금 갱신했으면 정상")


// MARK: 서비스 고르기

section("서비스 고르기")

do {
    var only = Config.default
    only.services = ["netflix"]
    only.blockMediaHosts = false
    only.hardenDoH = false
    let names = Blocklist.hostnames(config: only)
    check(names.contains("www.netflix.com"), "넷플릭스만 고르면 넷플릭스가 들어감")
    check(!names.contains("www.youtube.com"), "고르지 않은 YouTube 는 빠짐")
    check(!names.contains("nflxvideo.net"), "영상 호스트를 끄면 넷플릭스 영상 주소도 빠짐")
}

do {
    var many = Config.default
    many.services = ["youtube", "netflix", "disneyplus"]
    many.hardenDoH = false
    let names = Blocklist.hostnames(config: many)
    check(names.contains("www.youtube.com"), "여러 서비스를 함께 고를 수 있음")
    check(names.contains("www.netflix.com"), "넷플릭스도 함께")
    check(names.contains("www.disneyplus.com"), "디즈니+도 함께")
    check(names.contains("nflxvideo.net"), "영상 호스트를 켜면 넷플릭스 영상 주소도 들어감")
    equal(names.count, Set(names).count, "여러 서비스를 골라도 중복이 없음")
}

do {
    var unknown = Config.default
    unknown.services = ["youtube", "없는서비스"]
    unknown.hardenDoH = false
    let names = Blocklist.hostnames(config: unknown)
    check(names.contains("www.youtube.com"), "모르는 이름표가 섞여도 나머지는 그대로 동작")
}

do {
    var none = Config.default
    none.services = []
    none.customHosts = []
    none.hardenDoH = false
    equal(Blocklist.hostnames(config: none).count, 0, "아무것도 고르지 않으면 막을 주소가 없음")
}

// 쇼핑이나 검색처럼 함께 막히면 곤란한 곳은 목록에 없어야 한다
do {
    var everything = Config.default
    everything.services = Services.all.map { $0.id }
    let names = Set(Blocklist.hostnames(config: everything))
    for safe in ["www.google.com", "gmail.com", "www.amazon.com", "amazon.com",
                 "www.coupang.com", "coupang.com", "www.apple.com", "icloud.com"] {
        check(!names.contains(safe), "\(safe) 는 막지 않음")
    }
}

equal(Services.all.count, Set(Services.all.map { $0.id }).count, "서비스 이름표에 중복이 없음")
check(Services.service(id: "youtube") != nil, "이름표로 서비스를 찾을 수 있음")
check(Services.service(id: "없음") == nil, "없는 이름표는 찾지 못함")
equal(Services.names(ids: ["netflix", "tving"]), ["넷플릭스", "티빙"], "보여 줄 이름으로 바꿈")

// MARK: 직접 적어 넣는 주소

section("직접 적어 넣는 주소")

equal(HostName.normalize("https://www.netflix.com/browse?x=1"), "www.netflix.com", "주소에서 호스트만 남김")
equal(HostName.normalize("  HTTP://Example.COM:8080/path  "), "example.com", "대소문자와 포트, 경로를 정리함")
equal(HostName.normalize("news.example.com."), "news.example.com", "끝에 붙은 점을 떼어 냄")

check(HostName.validationMessage(for: "netflix.com") == nil, "평범한 주소는 통과")
check(HostName.validationMessage(for: "localhost") != nil, "localhost 는 거절")
check(HostName.validationMessage(for: "192.168.0.1") != nil, "IP 주소는 거절")
check(HostName.validationMessage(for: "점없는이름") != nil, "점이 없으면 거절")
check(HostName.validationMessage(for: "-bad.com") != nil, "붙임표로 시작하는 마디는 거절")
check(HostName.validationMessage(for: "two..dots.com") != nil, "점이 잇달으면 거절")

equal(HostName.expand("netflix.com"), ["netflix.com", "www.netflix.com"], "적어 준 주소에 www 를 붙여 함께 막음")
equal(HostName.expand("www.netflix.com"), ["www.netflix.com", "netflix.com"], "www 로 적어도 짧은 쪽을 함께 막음")
equal(HostName.expand("m.netflix.com"), ["m.netflix.com", "www.m.netflix.com"], "하위 도메인도 그대로 다룸")

do {
    let hosts = try HostName.parseList("""
    # 직접 적은 목록
    https://www.disneyplus.com/home

    tving.com
    tving.com
    """)
    equal(hosts, ["www.disneyplus.com", "tving.com"], "주석과 빈 줄, 중복을 걸러 냄")
} catch {
    check(false, "목록을 읽지 못했습니다: \(error)")
}

do {
    _ = try HostName.parseList("netflix.com\nlocalhost")
    check(false, "잘못된 줄은 거절해야 합니다")
} catch let e as HostName.ParseError {
    equal(e.line, 2, "몇 번째 줄이 잘못됐는지 알려 줌")
} catch {
    check(false, "예상하지 못한 오류 종류")
}

do {
    var custom = Config.default
    custom.services = []
    custom.hardenDoH = false
    custom.customHosts = ["example.com"]
    let names = Blocklist.hostnames(config: custom)
    equal(names, ["example.com", "www.example.com"], "직접 적은 주소가 그대로 막힘")
}

// MARK: 예전 설정 파일 읽기

section("예전 설정 파일 읽기")

do {
    // 서비스 목록이 없던 시절의 설정 파일
    let old = """
    {
      "blockMediaHosts" : true,
      "enabled" : true,
      "hardenDoH" : false,
      "rules" : [ { "days" : [ 1, 2 ], "end" : "18:00", "start" : "09:00" } ],
      "usePacketFilter" : false
    }
    """
    let config = try JSONStore.makeDecoder().decode(Config.self, from: Data(old.utf8))
    equal(config.services, ["youtube"], "빠진 서비스 목록은 YouTube 로 채움")
    equal(config.customHosts, [], "빠진 주소 목록은 비워 둠")
    equal(config.rules.count, 1, "원래 있던 규칙은 그대로 남음")
    equal(config.enabled, true, "원래 있던 값도 그대로 남음")
    check(Blocklist.hostnames(config: config).contains("www.youtube.com"),
          "예전 설정으로도 YouTube 가 그대로 막힘")
} catch {
    check(false, "예전 설정 파일을 읽지 못했습니다: \(error)")
}

do {
    // 항목이 거의 없는 설정 파일도 기본값으로 채워져야 한다
    let bare = "{}"
    let config = try JSONStore.makeDecoder().decode(Config.self, from: Data(bare.utf8))
    equal(config.services, ["youtube"], "빈 설정도 기본값으로 채움")
    equal(config.enabled, true, "빈 설정의 전체 스위치는 켜짐")
} catch {
    check(false, "빈 설정을 읽지 못했습니다: \(error)")
}

do {
    // 넣었다 뺐다 해도 내용이 그대로여야 한다
    var config = Config.default
    config.services = ["netflix", "tving"]
    config.customHosts = ["example.com"]
    let data = try JSONStore.makeEncoder().encode(config)
    let restored = try JSONStore.makeDecoder().decode(Config.self, from: data)
    equal(restored, config, "저장했다 읽어도 설정이 그대로임")
} catch {
    check(false, "설정을 저장했다 읽지 못했습니다: \(error)")
}

// MARK: 마무리

print("\n검사 \(checks) 개 가운데 \(failures) 개 실패")
exit(failures == 0 ? 0 : 1)
