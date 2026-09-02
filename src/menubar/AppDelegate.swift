import Cocoa

/// 메뉴 바 아이콘과 메뉴를 맡는다.
/// 상태는 데몬이 남긴 파일에서 읽고, 사용자의 조작은 설정 파일에 적는다.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    /// 표시기에서 여는 메뉴. 상태 항목에 붙은 메뉴를 그대로 다시 열면
    /// 이미 붙어 있는 메뉴를 두 곳에서 쓰게 되므로 따로 둔다.
    /// 항목을 채우는 곳이 menuNeedsUpdate 하나뿐이라 내용은 늘 같다.
    private let indicatorMenu = NSMenu()
    private let editor = ScheduleEditor()
    private var timer: Timer?
    private var state: BlockState?
    private var lastIconState: IconState?
    private let indicator = ScreenIndicator()
    private var currentImage: NSImage?

    /// 메뉴 바에서 아이콘이 앉을 자리를 기억하는 이름.
    /// 이 이름을 주어야 사용자가 Command 키로 옮겨 둔 자리가 다음 실행에도 남는다.
    private static let autosaveName = "YouTubeGuardStatusItem"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = Self.autosaveName
        statusItem.button?.imagePosition = .imageOnly
        menu.delegate = self
        statusItem.menu = menu

        indicatorMenu.delegate = self
        indicator.menu = indicatorMenu
        indicator.isVisible = showsScreenIndicator

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    /// 화면 표시기를 띄울지에 대한 설정.
    /// 메뉴 바 자리가 모자라 아이콘이 잘리는 경우가 많아 기본값을 켜짐으로 둔다.
    private var showsScreenIndicator: Bool {
        get { UserDefaults.standard.object(forKey: "ShowScreenIndicator") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "ShowScreenIndicator") }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    // MARK: 상태 읽어 아이콘 바꾸기

    /// 아이콘이 나타내는 상태. 이 값이 달라질 때만 그림을 다시 넣는다.
    /// 모양과 색을 함께 다르게 두어, 색을 구별하기 어려운 경우에도
    /// 방패의 생김새만으로 알아볼 수 있다. 도형은 IconArt 에 있다.
    private enum IconState: Equatable {
        case unresponsive   // 데몬이 응답하지 않음
        case disabled       // 차단 기능이 꺼져 있음
        case blocking       // 지금 막고 있음
        case idle           // 켜져 있지만 지금은 허용 시간

        var art: IconArt.State {
            switch self {
            case .unresponsive: return .unresponsive
            case .disabled: return .off
            case .blocking: return .blocking
            case .idle: return .allowed
            }
        }

        var accessibilityDescription: String {
            switch self {
            case .unresponsive: return "YouTubeGuard, 데몬 응답 없음"
            case .disabled: return "YouTubeGuard, 차단 기능 꺼짐"
            case .blocking: return "YouTubeGuard, 차단 중"
            case .idle: return "YouTubeGuard, 켜짐, 지금은 허용 시간"
            }
        }

        /// 메뉴 바에 올릴 그림. 18pt 는 메뉴 바 아이콘이 앉는 크기다.
        func makeImage(pointSize: CGFloat = 18) -> NSImage {
            let image = IconArt.statusImage(art, pointSize: pointSize)
            image.accessibilityDescription = accessibilityDescription
            return image
        }
    }

    private func refresh() {
        state = ConfigAccess.loadState()
        guard let button = statusItem.button else { return }

        let now = Date()
        let iconState: IconState
        if !StatusText.isDaemonResponsive(state, now: now) {
            iconState = .unresponsive
        } else if state?.enabled != true {
            iconState = .disabled
        } else if state?.blocking == true {
            iconState = .blocking
        } else {
            iconState = .idle
        }

        // 매번 그림을 다시 넣으면 화면마다 메뉴 바가 계속 다시 그려진다.
        // 실제로 상태가 달라졌을 때만 손댄다.
        if iconState != lastIconState {
            currentImage = iconState.makeImage()
            button.image = currentImage
            // 색을 직접 입힌 그림이므로 덧칠이 끼어들지 않게 비워 둔다.
            button.contentTintColor = nil
            lastIconState = iconState
        }

        // 설명 글은 다시 그리는 일이 없으므로 매번 갱신해도 괜찮다.
        let tooltip = StatusText.tooltip(state, now: now)
        button.toolTip = tooltip
        indicator.update(image: currentImage, tooltip: tooltip)
    }

    // MARK: 메뉴 만들기

    func menuNeedsUpdate(_ menu: NSMenu) {
        state = ConfigAccess.loadState()
        menu.removeAllItems()

        let now = Date()
        menu.addItem(disabledItem(StatusText.headline(state, now: now)))
        if let targets = blockTargetSummary() {
            menu.addItem(disabledItem(targets))
        }

        if !StatusText.isDaemonResponsive(state, now: now) {
            menu.addItem(disabledItem("차단 데몬이 응답하지 않습니다. 설치 상태를 확인해 주세요."))
        }
        if !ConfigAccess.isWritable {
            menu.addItem(disabledItem("설정 파일에 쓸 권한이 없어 바꿀 수 없습니다."))
        }

        menu.addItem(.separator())

        let enabled = state?.enabled ?? false
        menu.addItem(actionItem(enabled ? "차단 기능 끄기…" : "차단 기능 켜기…",
                                #selector(toggleEnabled)))

        menu.addItem(durationSubmenu(title: "지금 바로 차단",
                                     minutes: [30, 60, 120, 240],
                                     action: #selector(forceBlock(_:))))

        menu.addItem(durationSubmenu(title: "잠시 풀어 두기",
                                     minutes: [5, 15, 30, 60],
                                     action: #selector(snooze(_:))))

        // 임시 조작이 걸려 있을 때만 되돌리는 항목을 보여 준다.
        switch state?.reason {
        case .forced:
            menu.addItem(actionItem("즉시 차단 그만두기…", #selector(cancelForce)))
        case .snoozed:
            menu.addItem(actionItem("일시 해제 그만두기…", #selector(cancelSnooze)))
        default:
            break
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("차단 시간 편집…", #selector(openTimeEditor)))
        menu.addItem(actionItem("차단 대상 편집…", #selector(openTargetEditor)))
        menu.addItem(actionItem(showsScreenIndicator ? "화면 표시기 감추기" : "모든 화면에 표시기 띄우기",
                                #selector(toggleScreenIndicator)))
        menu.addItem(actionItem("기록 보기", #selector(openLog)))
        menu.addItem(.separator())
        menu.addItem(actionItem("메뉴 바에서 닫기…", #selector(quitApp)))
    }

    /// 지금 무엇을 막도록 되어 있는지 한 줄로 간추린다.
    private func blockTargetSummary() -> String? {
        guard let config = ConfigAccess.loadConfig() else { return nil }
        var parts = Services.names(ids: config.services)
        if !config.customHosts.isEmpty {
            parts.append("직접 추가한 주소 \(config.customHosts.count) 개")
        }
        guard !parts.isEmpty else { return "막을 대상이 하나도 없습니다" }
        return "막는 대상: " + parts.joined(separator: ", ")
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func durationSubmenu(title: String, minutes: [Int], action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for m in minutes {
            let item = NSMenuItem(title: durationLabel(m) + "…", action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = m
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func durationLabel(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)분" : "\(minutes / 60)시간"
    }

    // MARK: 조작. 모두 확인 대화상자를 거친다.

    @objc private func toggleEnabled() {
        let enabled = state?.enabled ?? false

        if enabled {
            let extra = state?.blocking == true
                ? "\n\n지금 차단 중이므로 곧바로 풀립니다."
                : ""
            guard Dialogs.confirm(
                title: "차단 기능을 끌까요?",
                message: "정해진 시간이 되어도 YouTube 를 막지 않습니다.\(extra)",
                proceedTitle: "끄기",
                destructive: true) else { return }

            apply { config in
                config.enabled = false
                config.forceBlockUntil = nil
            }
        } else {
            guard Dialogs.confirm(
                title: "차단 기능을 켤까요?",
                message: "정해 둔 시간이 되면 YouTube 접속을 막습니다.\n지금이 그 시간에 들어 있다면 곧바로 막힙니다.",
                proceedTitle: "켜기") else { return }

            apply { config in
                config.enabled = true
                config.snoozeUntil = nil
            }
        }
    }

    @objc private func forceBlock(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let note = state?.enabled == true
            ? ""
            : "\n\n차단 기능이 꺼져 있어 함께 켭니다."

        guard Dialogs.confirm(
            title: "지금부터 \(durationLabel(minutes)) 동안 막을까요?",
            message: "\(StatusText.timeLabel(until)) 까지 YouTube 에 접속할 수 없습니다.\(note)",
            proceedTitle: "막기") else { return }

        apply { config in
            config.enabled = true
            config.forceBlockUntil = until
            config.snoozeUntil = nil
        }
    }

    @objc private func snooze(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))

        guard Dialogs.confirm(
            title: "\(durationLabel(minutes)) 동안 잠시 풀까요?",
            message: "\(StatusText.timeLabel(until)) 까지는 정해진 시간이라도 막지 않습니다.\n그 뒤에는 저절로 원래대로 돌아옵니다.",
            proceedTitle: "풀기",
            destructive: true) else { return }

        apply { config in
            config.snoozeUntil = until
            config.forceBlockUntil = nil
        }
    }

    @objc private func cancelForce() {
        guard Dialogs.confirm(
            title: "즉시 차단을 그만둘까요?",
            message: "남은 시간을 없애고 정해진 시간표대로 돌아갑니다.",
            proceedTitle: "그만두기",
            destructive: true) else { return }
        apply { $0.forceBlockUntil = nil }
    }

    @objc private func cancelSnooze() {
        guard Dialogs.confirm(
            title: "일시 해제를 그만둘까요?",
            message: "곧바로 정해진 시간표대로 돌아갑니다. 지금이 차단 시간이면 다시 막힙니다.",
            proceedTitle: "그만두기") else { return }
        apply { $0.snoozeUntil = nil }
    }

    /// 메뉴 바 자리가 모자라 아이콘이 잘리는 경우를 위해,
    /// 화면마다 떠 있는 표시기를 켜고 끈다. 차단 동작에는 영향이 없다.
    @objc private func toggleScreenIndicator() {
        let turnOn = !showsScreenIndicator
        showsScreenIndicator = turnOn
        indicator.isVisible = turnOn
        if turnOn {
            Dialogs.info(title: "화면 표시기를 띄웠습니다",
                         message: "연결된 모든 화면의 오른쪽 위에 작은 방패가 나타납니다.\n눌러서 메뉴를 열 수 있고, 이 메뉴에서 다시 감출 수 있습니다.")
        }
    }

    @objc private func openTimeEditor() {
        openEditor(tab: "time")
    }

    @objc private func openTargetEditor() {
        openEditor(tab: "target")
    }

    private func openEditor(tab: String) {
        editor.show(tab: tab) { [weak self] in
            self?.refresh()
        }
    }

    @objc private func openLog() {
        guard FileManager.default.fileExists(atPath: Paths.logFile) else {
            Dialogs.info(title: "기록이 아직 없습니다",
                         message: "데몬이 처음 움직이고 나면 \(Paths.logFile) 에 쌓입니다.")
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: Paths.logFile))
    }

    @objc private func quitApp() {
        guard Dialogs.confirm(
            title: "메뉴 바 아이콘을 닫을까요?",
            message: "차단 자체는 그대로 이어집니다. 아이콘만 사라집니다.\n다시 보려면 응용 프로그램 폴더의 YouTubeGuard 를 실행하세요.",
            proceedTitle: "닫기") else { return }
        NSApp.terminate(nil)
    }

    // MARK: 설정 쓰기

    private func apply(_ change: (inout Config) -> Void) {
        do {
            try ConfigAccess.update(change)
            // 데몬이 3초 안에 반영하므로 곧 아이콘이 따라 바뀐다.
            refresh()
        } catch {
            Dialogs.error(title: "설정을 바꾸지 못했습니다", message: error.localizedDescription)
        }
    }

    // MARK: 아이콘 확인

    /// 아이콘이 실제로 어떤 색으로 그려지는지 알려 준다.
    /// 메뉴 바에서 눈으로 확인하기 어려울 때 --icon-check 로 부른다.
    static func iconCheckReport() -> String {
        var lines = ["아이콘 상태별로 실제 그려지는 색:"]
        let cases: [(IconState, String)] = [
            (.blocking, "차단 중"),
            (.idle, "켜짐, 허용 시간"),
            (.disabled, "꺼짐"),
            (.unresponsive, "데몬 응답 없음"),
        ]
        for (state, label) in cases {
            let image = state.makeImage(pointSize: 64)
            let c = averageColor(of: image)
            let template = image.isTemplate ? "템플릿 켜짐 (색이 무시됩니다)" : "템플릿 꺼짐"
            lines.append("  \(label) · rgb(\(c.r),\(c.g),\(c.b)) · \(template)")
        }
        return lines.joined(separator: "\n")
    }

    /// 그림에서 실제로 칠해진 픽셀의 평균 색.
    private static func averageColor(of image: NSImage) -> (r: Int, g: Int, b: Int) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return (0, 0, 0) }
        var red = 0.0, green = 0.0, blue = 0.0, count = 0.0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y), c.alphaComponent >= 0.5 else { continue }
                red += c.redComponent * 255
                green += c.greenComponent * 255
                blue += c.blueComponent * 255
                count += 1
            }
        }
        guard count > 0 else { return (0, 0, 0) }
        return (Int(red / count), Int(green / count), Int(blue / count))
    }
}
