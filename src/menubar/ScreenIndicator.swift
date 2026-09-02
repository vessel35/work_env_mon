import Cocoa

/// 모든 화면의 오른쪽 위에 떠 있는 작은 표시기.
///
/// 메뉴 바는 자리가 모자라면 왼쪽 아이콘부터 잘라 내며, 어떤 아이콘을 남길지는
/// macOS 가 정한다. 노치가 있는 화면에서는 아이콘 몇 개가 늘 잘려 나가고
/// 프로그램이 이를 되돌릴 방법이 없다. 그래서 메뉴 바와 별개로, 화면마다
/// 창을 하나씩 띄워 상태가 언제나 보이도록 한다.
final class ScreenIndicator {

    /// 표시기의 한 변 길이와 화면 모서리에서 떨어뜨릴 거리.
    private let size: CGFloat = 30
    private let margin: CGFloat = 12

    private var panels: [NSPanel] = []
    private var image: NSImage?
    private var tooltip: String = ""

    /// 표시기를 눌렀을 때 열 메뉴. 메뉴 바 아이콘이 잘려 보이지 않을 때를 위한 것이다.
    weak var menu: NSMenu?

    var isVisible: Bool = false {
        didSet {
            guard isVisible != oldValue else { return }
            isVisible ? build() : tearDown()
        }
    }

    init() {
        // 모니터를 꽂거나 빼거나 해상도가 바뀌면 창을 다시 배치한다.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isVisible else { return }
            self.build()
        }
    }

    // MARK: 내용 갱신

    func update(image: NSImage?, tooltip: String) {
        let imageChanged = image !== self.image
        self.image = image
        self.tooltip = tooltip
        for panel in panels {
            guard let view = panel.contentView as? IndicatorView else { continue }
            if imageChanged { view.imageView.image = image }
            view.toolTip = tooltip
        }
    }

    // MARK: 창 만들고 없애기

    private func tearDown() {
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
    }

    private func build() {
        tearDown()
        for screen in NSScreen.screens {
            panels.append(makePanel(for: screen))
        }
    }

    private func makePanel(for screen: NSScreen) -> NSPanel {
        // visibleFrame 은 메뉴 바와 Dock 을 뺀 영역이라, 메뉴 바 바로 아래에 붙는다.
        let area = screen.visibleFrame
        let frame = NSRect(x: area.maxX - size - margin,
                           y: area.maxY - size - margin,
                           width: size,
                           height: size)

        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        // 모든 공간과 전체 화면 위에도 남아 있게 한다.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]

        let view = IndicatorView(frame: NSRect(origin: .zero, size: frame.size))
        view.imageView.image = image
        view.toolTip = tooltip
        view.onClick = { [weak self, weak view] in
            guard let menu = self?.menu, let view = view else { return }
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: view.bounds.height + 4),
                       in: view)
        }
        panel.contentView = view
        panel.orderFrontRegardless()
        return panel
    }
}

/// 표시기 한 개의 겉모습. 반투명 바탕 위에 방패 그림을 올린다.
private final class IndicatorView: NSView {

    let imageView = NSImageView()
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let background = NSVisualEffectView(frame: bounds)
        background.material = .hudWindow
        background.state = .active
        background.blendingMode = .behindWindow
        background.autoresizingMask = [.width, .height]
        background.wantsLayer = true
        background.layer?.cornerRadius = frameRect.width / 2
        background.layer?.masksToBounds = true
        addSubview(background)

        let inset = frameRect.width * 0.22
        imageView.frame = bounds.insetBy(dx: inset, dy: inset)
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("코드에서만 만듭니다")
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
