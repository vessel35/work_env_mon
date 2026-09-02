import Foundation

/// 루트 권한으로 도는 본체.
/// 설정 파일을 지켜보다가 차단할 시간이 되면 hosts 파일에 차단 구간을 넣고,
/// 시간이 지나면 다시 걷어 낸다.
final class Daemon {

    private let tickInterval: TimeInterval = 3
    private let pfRefreshInterval: TimeInterval = 30 * 60
    private let stateWriteInterval: TimeInterval = 20

    private var stopRequested = false
    private var lastGoodConfig = Config.default
    private var reportedConfigError = false

    private var pfBlocking = false
    private var pfAddressCount = 0
    private var lastPFRefresh = Date.distantPast

    private var lastWrittenState: BlockState?
    private var lastStateWrite = Date.distantPast

    // MARK: 준비

    private func prepareFilesystem() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Paths.supportDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o755])
        // 설정 폴더만 admin 그룹이 쓸 수 있게 둔다. 그래야 메뉴 바 앱이
        // 관리자 비밀번호 없이 설정을 바꿀 수 있다. (80 번이 admin 그룹)
        try? fm.createDirectory(atPath: Paths.userConfigDir, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o775, .groupOwnerAccountID: 80],
                              ofItemAtPath: Paths.userConfigDir)
        try? fm.createDirectory(atPath: Paths.logDir, withIntermediateDirectories: true)

        if !fm.fileExists(atPath: Paths.configFile) {
            var config = Config.default
            config.updatedAt = Date()
            try? JSONStore.save(config, to: Paths.configFile)
            try? fm.setAttributes([.posixPermissions: 0o664, .groupOwnerAccountID: 80],
                                  ofItemAtPath: Paths.configFile)
            log("기본 설정 파일을 만들었습니다: \(Paths.configFile)")
        }
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            source.setEventHandler { [weak self] in self?.stopRequested = true }
            source.resume()
            signalSources.append(source)
        }
    }

    private var signalSources: [DispatchSourceSignal] = []

    // MARK: 설정 읽기

    private func loadConfig() -> Config {
        do {
            let config = try JSONStore.load(Config.self, from: Paths.configFile)
            if reportedConfigError {
                log("설정 파일을 다시 읽었습니다.")
                reportedConfigError = false
            }
            lastGoodConfig = config
            return config
        } catch {
            if !reportedConfigError {
                log("설정 파일을 읽지 못해 직전 설정을 그대로 씁니다: \(error.localizedDescription)")
                reportedConfigError = true
            }
            return lastGoodConfig
        }
    }

    // MARK: 한 번의 판단과 적용

    private func tick() {
        let now = Date()
        let config = loadConfig()
        let decision = Schedule.decide(config: config, now: now)

        var errorMessage: String?
        let hostnames = decision.blocking ? Blocklist.hostnames(config: config) : nil

        // 누가 hosts 파일을 직접 고쳐 차단 구간을 지웠더라도
        // 여기서 매번 견주어 보므로 곧바로 되돌아온다.
        do {
            if try HostsFile.apply(hostnames: hostnames) {
                Shell.flushDNSCache()
                log(decision.blocking
                    ? "차단을 걸었습니다. (\(decision.reason.rawValue), 주소 \(hostnames?.count ?? 0) 개)"
                    : "차단을 풀었습니다. (\(decision.reason.rawValue))")
            }
        } catch {
            errorMessage = error.localizedDescription
            log("hosts 파일 처리에 실패했습니다: \(error.localizedDescription)")
        }

        updatePacketFilter(config: config, blocking: decision.blocking, now: now)

        let state = BlockState(
            blocking: decision.blocking,
            enabled: config.enabled,
            reason: decision.reason,
            activeUntil: decision.until,
            nextChange: decision.nextChange,
            heartbeat: now,
            hostsApplied: decision.blocking && errorMessage == nil,
            pfApplied: pfBlocking,
            blockedHostCount: hostnames?.count ?? 0,
            lastError: errorMessage
        )
        writeStateIfNeeded(state, now: now)
    }

    private func updatePacketFilter(config: Config, blocking: Bool, now: Date) {
        let shouldBlock = blocking && config.usePacketFilter

        if shouldBlock {
            if !pfBlocking || now.timeIntervalSince(lastPFRefresh) > pfRefreshInterval {
                // YouTube 주소는 자주 바뀌므로 차단을 시작할 때와 30 분마다 다시 조회한다.
                pfAddressCount = PacketFilter.block(targets: Blocklist.packetFilterTargets(config: config))
                lastPFRefresh = now
                pfBlocking = pfAddressCount > 0
            }
        } else if pfBlocking {
            PacketFilter.unblock()
            pfBlocking = false
            pfAddressCount = 0
            log("방화벽 차단을 풀었습니다.")
        }
    }

    private func writeStateIfNeeded(_ state: BlockState, now: Date) {
        // 심장 박동만 달라진 경우까지 매번 쓰면 디스크를 괜히 건드린다.
        let contentChanged: Bool = {
            guard var previous = lastWrittenState else { return true }
            previous.heartbeat = state.heartbeat
            return previous != state
        }()
        guard contentChanged || now.timeIntervalSince(lastStateWrite) > stateWriteInterval else { return }

        do {
            try JSONStore.save(state, to: Paths.stateFile)
            try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                   ofItemAtPath: Paths.stateFile)
            lastWrittenState = state
            lastStateWrite = now
        } catch {
            log("상태 파일을 쓰지 못했습니다: \(error.localizedDescription)")
        }
    }

    // MARK: 실행

    func run() {
        prepareFilesystem()
        installSignalHandlers()
        log("데몬을 시작했습니다.")

        while !stopRequested {
            tick()
            sleepUntilNextTick()
        }

        // 데몬을 멈춰서 차단이 풀리면 안 되므로 hosts 구간은 그대로 둔다.
        // 완전히 지우려면 ytguardd --clear 를 쓴다.
        PacketFilter.releaseEnableToken()
        log("데몬을 멈췄습니다. 차단 구간은 그대로 둡니다.")
    }

    /// 다음 차례까지 기다린다.
    /// 통째로 자면 멈추라는 신호를 받고도 몇 초 뒤에야 빠져나가게 되고,
    /// 그 사이에 다시 등록하려 하면 launchd 가 같은 이름표를 거절한다.
    /// 그래서 잘게 나누어 자면서 중간중간 확인한다.
    private func sleepUntilNextTick() {
        let slice = 0.1
        var remaining = tickInterval
        while remaining > 0 && !stopRequested {
            Thread.sleep(forTimeInterval: min(slice, remaining))
            remaining -= slice
        }
    }
}

// MARK: - 명령별 동작

func clearEverything() {
    do {
        let changed = try HostsFile.apply(hostnames: nil)
        PacketFilter.unblock()
        PacketFilter.releaseEnableToken()
        Shell.flushDNSCache()
        print(changed ? "hosts 파일의 차단 구간을 지웠습니다." : "지울 차단 구간이 없었습니다.")
    } catch {
        FileHandle.standardError.write(Data("차단 구간을 지우지 못했습니다: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

func printStatus() {
    guard let state = try? JSONStore.load(BlockState.self, from: Paths.stateFile) else {
        print("상태 파일을 읽지 못했습니다. 데몬이 돌고 있는지 확인해 주세요.")
        exit(1)
    }
    let now = Date()
    print(StatusText.headline(state, now: now))
    print("차단 여부: \(state.blocking ? "차단" : "허용")")
    print("전체 스위치: \(state.enabled ? "켜짐" : "꺼짐")")
    print("hosts 구간: \(HostsFile.isApplied() ? "들어가 있음" : "없음")")
    print("방화벽: \(state.pfApplied ? "적용 중" : "미적용")")
    if let error = state.lastError { print("문제: \(error)") }
    let age = Int(now.timeIntervalSince(state.heartbeat))
    print("마지막 갱신: \(age)초 전")
}

func printUsage() {
    print("""
    ytguardd — YouTubeGuard 차단 데몬 (루트 권한 필요)

      ytguardd            데몬으로 계속 실행합니다. launchd 가 이 방식으로 띄웁니다.
      ytguardd --clear    hosts 파일의 차단 구간과 방화벽 차단을 모두 지웁니다.
      ytguardd --status   지금 상태를 보여 줍니다.
    """)
}

// MARK: - 시작 지점

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    printUsage()
    exit(0)
}

guard getuid() == 0 else {
    FileHandle.standardError.write(Data("ytguardd 는 루트 권한으로 실행해야 합니다.\n".utf8))
    exit(1)
}

switch arguments.first {
case "--clear":
    clearEverything()
case "--status":
    printStatus()
case .some(let unknown):
    FileHandle.standardError.write(Data("알 수 없는 옵션입니다: \(unknown)\n".utf8))
    printUsage()
    exit(2)
case nil:
    // 전역에 붙들어 두어야 신호 처리기가 살아 있는 객체를 가리킨다.
    let daemon = Daemon()
    daemon.run()
}
