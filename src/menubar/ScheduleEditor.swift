import Cocoa

/// 차단 시간과 차단 대상을 고치는 창.
/// 저장을 누르면 반드시 확인 대화상자를 한 번 거친 뒤에만 실제로 반영한다.
final class ScheduleEditor: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var tabView: NSTabView!
    private var rulesTextView: NSTextView!
    private var customHostsTextView: NSTextView!
    private var errorLabel: NSTextField!

    private var serviceCheckboxes: [String: NSButton] = [:]
    private var mediaCheckbox: NSButton!
    private var dohCheckbox: NSButton!
    private var pfCheckbox: NSButton!

    private var originalConfig = Config.default
    private var onSaved: (() -> Void)?

    private let windowSize = NSSize(width: 640, height: 600)
    private let tabContentSize = NSSize(width: 588, height: 478)

    // MARK: 창 열기

    /// tab 은 "time" 또는 "target". 메뉴에서 고른 탭이 곧바로 열리게 한다.
    func show(tab: String = "time", onSaved: @escaping () -> Void) {
        self.onSaved = onSaved

        if let window = window {
            tabView.selectTabViewItem(withIdentifier: tab)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        guard let config = ConfigAccess.loadConfig() else {
            Dialogs.error(title: "설정을 읽지 못했습니다",
                          message: ConfigAccess.AccessError.notInstalled.localizedDescription)
            return
        }
        originalConfig = config

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "YouTubeGuard · 차단 설정"
        window.delegate = self
        window.center()
        window.isReleasedWhenClosed = false

        buildContent(in: window, config: config)
        tabView.selectTabViewItem(withIdentifier: tab)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(tab == "target" ? customHostsTextView : rulesTextView)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        serviceCheckboxes.removeAll()
    }

    // MARK: 창 뼈대

    private func buildContent(in window: NSWindow, config: Config) {
        let content = NSView(frame: NSRect(origin: .zero, size: windowSize))

        tabView = NSTabView(frame: NSRect(x: 16, y: 60, width: 608, height: 524))
        tabView.autoresizingMask = [.width, .height]

        let timeTab = NSTabViewItem(identifier: "time")
        timeTab.label = "차단 시간"
        timeTab.view = buildTimeTab(config: config)
        tabView.addTabViewItem(timeTab)

        let targetTab = NSTabViewItem(identifier: "target")
        targetTab.label = "차단 대상"
        targetTab.view = buildTargetTab(config: config)
        tabView.addTabViewItem(targetTab)

        content.addSubview(tabView)

        errorLabel = makeLabel("", frame: NSRect(x: 18, y: 20, width: 380, height: 36), lines: 2)
        errorLabel.textColor = .systemRed
        content.addSubview(errorLabel)

        let save = NSButton(frame: NSRect(x: 524, y: 16, width: 100, height: 32))
        save.title = "저장"
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.target = self
        save.action = #selector(saveTapped)
        content.addSubview(save)

        let cancel = NSButton(frame: NSRect(x: 416, y: 16, width: 100, height: 32))
        cancel.title = "취소"
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.target = self
        cancel.action = #selector(cancelTapped)
        content.addSubview(cancel)

        window.contentView = content
    }

    // MARK: 차단 시간 탭

    private func buildTimeTab(config: Config) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: tabContentSize))
        let width = tabContentSize.width - 32

        let intro = makeLabel(
            """
            한 줄에 차단 구간 하나를 적습니다. 요일은 월 화 수 목 금 토 일 과 매일, 평일, 주말 을 쓸 수 있습니다.
            끝 시각이 시작 시각보다 앞서면 자정을 넘어 이어지고, 시작과 끝을 같게 적으면 하루 종일이 됩니다.
            """,
            frame: NSRect(x: 16, y: 416, width: width, height: 46), lines: 3)
        intro.textColor = .secondaryLabelColor
        view.addSubview(intro)

        let (scroll, text) = makeTextArea(frame: NSRect(x: 16, y: 26, width: width, height: 380))
        text.string = RuleText.format(config.rules)
        rulesTextView = text
        view.addSubview(scroll)

        return view
    }

    // MARK: 차단 대상 탭

    private func buildTargetTab(config: Config) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: tabContentSize))
        let width = tabContentSize.width - 32
        let selected = Set(config.services)

        view.addSubview(makeLabel("막을 서비스를 고르세요.",
                                  frame: NSRect(x: 16, y: 444, width: width, height: 18)))

        // 두 줄로 나누어 배치한다. 목록이 늘어나도 행 수만 달라진다.
        let columnWidth = (width - 16) / 2
        let rowHeight: CGFloat = 24
        let rows = (Services.all.count + 1) / 2
        for (index, service) in Services.all.enumerated() {
            let column = index / rows
            let row = index % rows
            let box = makeCheckbox(
                service.name,
                frame: NSRect(x: 18 + CGFloat(column) * (columnWidth + 16),
                              y: 418 - CGFloat(row) * rowHeight,
                              width: columnWidth,
                              height: 20))
            box.state = selected.contains(service.id) ? .on : .off
            box.toolTip = "막는 주소 " + service.hosts.prefix(3).joined(separator: ", ") + " 등"
            serviceCheckboxes[service.id] = box
            view.addSubview(box)
        }

        let firstSeparatorY = 418 - CGFloat(rows) * rowHeight
        view.addSubview(makeSeparator(y: firstSeparatorY, width: width))

        view.addSubview(makeLabel("함께 적용할 설정",
                                  frame: NSRect(x: 16, y: firstSeparatorY - 26, width: width, height: 18)))

        mediaCheckbox = makeCheckbox("영상 전송 호스트도 함께 막기",
                                     frame: NSRect(x: 18, y: firstSeparatorY - 52, width: width, height: 20))
        mediaCheckbox.state = config.blockMediaHosts ? .on : .off
        mediaCheckbox.toolTip = "다른 사이트에 끼워 넣은 재생 창까지 함께 막습니다."
        view.addSubview(mediaCheckbox)

        dohCheckbox = makeCheckbox("브라우저의 암호화 DNS 우회 막기",
                                   frame: NSRect(x: 18, y: firstSeparatorY - 76, width: width, height: 20))
        dohCheckbox.state = config.hardenDoH ? .on : .off
        dohCheckbox.toolTip = "차단 시간에만 적용되며, 이름 조회 경로만 되돌릴 뿐 다른 사이트 접속은 그대로입니다."
        view.addSubview(dohCheckbox)

        pfCheckbox = makeCheckbox("방화벽으로 IP 까지 막기 (고급)",
                                  frame: NSRect(x: 18, y: firstSeparatorY - 100, width: width, height: 20))
        pfCheckbox.state = config.usePacketFilter ? .on : .off
        view.addSubview(pfCheckbox)

        let pfNote = makeLabel("더 확실하게 막지만, 주소가 같은 회사의 다른 서비스와 겹치면 그쪽도 함께 막힐 수 있습니다.",
                               frame: NSRect(x: 38, y: firstSeparatorY - 120, width: width - 22, height: 16))
        pfNote.textColor = .secondaryLabelColor
        view.addSubview(pfNote)

        let secondSeparatorY = firstSeparatorY - 134
        view.addSubview(makeSeparator(y: secondSeparatorY, width: width))

        view.addSubview(makeLabel("직접 추가할 주소",
                                  frame: NSRect(x: 16, y: secondSeparatorY - 26, width: width, height: 18)))
        let hostNote = makeLabel("한 줄에 하나씩 적습니다. www. 를 붙인 형태도 함께 막습니다.",
                                 frame: NSRect(x: 16, y: secondSeparatorY - 44, width: width, height: 16))
        hostNote.textColor = .secondaryLabelColor
        view.addSubview(hostNote)

        let textHeight = secondSeparatorY - 52 - 26
        let (scroll, text) = makeTextArea(
            frame: NSRect(x: 16, y: 26, width: width, height: max(60, textHeight)))
        text.string = HostName.format(config.customHosts)
        customHostsTextView = text
        view.addSubview(scroll)

        return view
    }

    // MARK: 부품 만들기

    private func makeTextArea(frame: NSRect) -> (NSScrollView, NSTextView) {
        let scroll = NSScrollView(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autohidesScrollers = true
        scroll.autoresizingMask = [.width, .height]

        let text = NSTextView(frame: NSRect(origin: .zero, size: frame.size))
        text.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        text.isRichText = false
        text.isVerticallyResizable = true
        text.textContainerInset = NSSize(width: 6, height: 8)
        // 자동 고침이 09:00-18:00 의 붙임표를 긴 줄표로 바꾸는 것을 막는다.
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        scroll.documentView = text
        return (scroll, text)
    }

    private func makeLabel(_ text: String, frame: NSRect, lines: Int = 1) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.stringValue = text
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.font = NSFont.systemFont(ofSize: 11)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = lines
        label.cell?.wraps = true
        label.autoresizingMask = [.width, .minYMargin]
        return label
    }

    private func makeCheckbox(_ title: String, frame: NSRect) -> NSButton {
        let box = NSButton(frame: frame)
        box.setButtonType(.switch)
        box.title = title
        box.font = NSFont.systemFont(ofSize: 13)
        box.autoresizingMask = [.minYMargin]
        return box
    }

    private func makeSeparator(y: CGFloat, width: CGFloat) -> NSBox {
        let line = NSBox(frame: NSRect(x: 16, y: y, width: width, height: 1))
        line.boxType = .separator
        line.autoresizingMask = [.width, .minYMargin]
        return line
    }

    // MARK: 저장

    @objc private func cancelTapped() {
        window?.close()
    }

    /// 잘못된 곳이 있으면 그 탭으로 옮겨 주고 이유를 보여 준다.
    private func showError(_ message: String, tab: String) {
        errorLabel.stringValue = message
        tabView.selectTabViewItem(withIdentifier: tab)
        NSSound.beep()
    }

    @objc private func saveTapped() {
        errorLabel.stringValue = ""

        let rules: [BlockRule]
        do {
            rules = try RuleText.parse(rulesTextView.string)
        } catch let e as RuleText.ParseError {
            showError("차단 시간 \(e.line)번째 줄을 읽지 못했습니다. \(e.message)", tab: "time")
            return
        } catch {
            showError(error.localizedDescription, tab: "time")
            return
        }

        let customHosts: [String]
        do {
            customHosts = try HostName.parseList(customHostsTextView.string)
        } catch let e as HostName.ParseError {
            showError("직접 추가할 주소 \(e.line)번째 줄을 읽지 못했습니다. \(e.message)", tab: "target")
            return
        } catch {
            showError(error.localizedDescription, tab: "target")
            return
        }

        // 목록에 적힌 차례를 유지해서, 저장할 때마다 순서가 뒤바뀌지 않게 한다.
        let services = Services.all
            .filter { serviceCheckboxes[$0.id]?.state == .on }
            .map { $0.id }

        let media = mediaCheckbox.state == .on
        let doh = dohCheckbox.state == .on
        let pf = pfCheckbox.state == .on

        if services.isEmpty && customHosts.isEmpty {
            showError("막을 대상이 하나도 없습니다. 서비스를 고르거나 주소를 적어 주세요.", tab: "target")
            return
        }

        let unchanged = rules == originalConfig.rules
            && services == originalConfig.services
            && customHosts == originalConfig.customHosts
            && media == originalConfig.blockMediaHosts
            && doh == originalConfig.hardenDoH
            && pf == originalConfig.usePacketFilter
        if unchanged {
            Dialogs.info(title: "바뀐 내용이 없습니다", message: "고친 곳이 없어 그대로 닫습니다.")
            window?.close()
            return
        }

        guard Dialogs.confirm(
            title: "차단 설정을 바꿀까요?",
            message: summary(rules: rules, services: services, customHosts: customHosts,
                             media: media, doh: doh, pf: pf),
            proceedTitle: "바꾸기") else { return }

        do {
            try ConfigAccess.update { config in
                config.rules = rules
                config.services = services
                config.customHosts = customHosts
                config.blockMediaHosts = media
                config.hardenDoH = doh
                config.usePacketFilter = pf
            }
        } catch {
            Dialogs.error(title: "저장하지 못했습니다", message: error.localizedDescription)
            return
        }

        onSaved?()
        window?.close()
    }

    /// 확인 대화상자에 무엇이 어떻게 바뀌는지 그대로 보여 준다.
    private func summary(rules: [BlockRule], services: [String], customHosts: [String],
                         media: Bool, doh: Bool, pf: Bool) -> String {
        var lines: [String] = []

        if rules.isEmpty {
            lines.append("차단 구간을 모두 지웁니다. 정해진 시간에 따른 차단이 사라지고, 메뉴에서 직접 차단할 때만 막힙니다.")
        } else {
            lines.append("차단 시간")
            lines.append(contentsOf: rules.map { "    " + RuleText.format($0) })
        }

        lines.append("")
        lines.append("막을 대상")
        if services.isEmpty {
            lines.append("    (고른 서비스 없음)")
        } else {
            lines.append("    " + Services.names(ids: services).joined(separator: ", "))
        }
        for host in customHosts {
            lines.append("    " + host)
        }

        var options: [String] = []
        if media != originalConfig.blockMediaHosts {
            options.append("영상 전송 호스트 차단: \(onOff(originalConfig.blockMediaHosts)) → \(onOff(media))")
        }
        if doh != originalConfig.hardenDoH {
            options.append("암호화 DNS 우회 막기: \(onOff(originalConfig.hardenDoH)) → \(onOff(doh))")
        }
        if pf != originalConfig.usePacketFilter {
            options.append("방화벽 IP 차단: \(onOff(originalConfig.usePacketFilter)) → \(onOff(pf))")
        }
        if !options.isEmpty {
            lines.append("")
            lines.append(contentsOf: options.map { "    " + $0 })
        }

        lines.append("")
        lines.append("저장하면 곧바로 반영됩니다.")
        return lines.joined(separator: "\n")
    }

    private func onOff(_ value: Bool) -> String { value ? "켬" : "끔" }
}
