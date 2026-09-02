import Cocoa

/// 아이콘 그림.
///
/// 24 × 24 격자에 그려 두고 필요한 크기로 늘린다. 시스템 심볼을 쓰지 않고
/// 직접 그리는 까닭은 네 상태를 방패 하나의 변주로 묶기 위해서다.
/// 채운 방패는 지금 무언가를 하고 있다는 뜻이고, 선으로만 그린 방패는
/// 지켜보고만 있다는 뜻이다. 색을 구별하기 어려워도 이 차이로 알아볼 수 있다.
enum IconArt {

    /// 도형을 그린 격자의 한 변.
    static let grid: CGFloat = 24

    enum State {
        case blocking       // 채운 방패 + 가로 막대를 뚫음
        case allowed        // 선 방패 + 재생 삼각형
        case off            // 선 방패 + 사선
        case unresponsive   // 채운 방패 + 느낌표를 뚫음
    }

    /// 상태 색. 시안에 적힌 값을 그대로 쓴다.
    enum Palette {
        static let blocking = NSColor(srgbRed: 1.000, green: 0.220, blue: 0.235, alpha: 1)      // #FF383C
        static let allowed = NSColor(srgbRed: 0.204, green: 0.776, blue: 0.345, alpha: 1)       // #34C658
        static let off = NSColor(srgbRed: 0.557, green: 0.557, blue: 0.573, alpha: 1)           // #8E8E92
        static let unresponsive = NSColor(srgbRed: 1.000, green: 0.553, blue: 0.157, alpha: 1)  // #FF8D28

        static let plateTop = NSColor(srgbRed: 0.180, green: 0.196, blue: 0.227, alpha: 1)      // #2E323A
        static let plateBottom = NSColor(srgbRed: 0.102, green: 0.114, blue: 0.133, alpha: 1)   // #1A1D22
    }

    // MARK: 도형

    /// 방패. 네 상태가 모두 이 실루엣을 공유한다.
    static func shield() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 12, y: 2.2))
        path.addLine(to: CGPoint(x: 20.4, y: 5.15))
        path.addLine(to: CGPoint(x: 20.4, y: 11.9))
        path.addCurve(to: CGPoint(x: 12, y: 21.8),
                      control1: CGPoint(x: 20.4, y: 16.65),
                      control2: CGPoint(x: 17, y: 20.3))
        path.addCurve(to: CGPoint(x: 3.6, y: 11.9),
                      control1: CGPoint(x: 7, y: 20.3),
                      control2: CGPoint(x: 3.6, y: 16.65))
        path.addLine(to: CGPoint(x: 3.6, y: 5.15))
        path.closeSubpath()
        return path
    }

    /// 차단 중일 때 뚫는 가로 막대.
    static func bar() -> CGPath {
        CGPath(roundedRect: CGRect(x: 7.6, y: 10.75, width: 8.8, height: 2.5),
               cornerWidth: 1.25, cornerHeight: 1.25, transform: nil)
    }

    /// 재생 삼각형. 오른쪽을 향하는 도형이라 무게 중심이 격자 가운데에 오도록 잡았다.
    static func play() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 10.1, y: 8.9))
        path.addLine(to: CGPoint(x: 15.9, y: 12))
        path.addLine(to: CGPoint(x: 10.1, y: 15.1))
        path.closeSubpath()
        return path
    }

    /// 데몬이 응답하지 않을 때 뚫는 느낌표.
    static func exclamation() -> CGPath {
        let path = CGMutablePath()
        path.addPath(CGPath(roundedRect: CGRect(x: 10.85, y: 6.9, width: 2.3, height: 6.7),
                            cornerWidth: 1.15, cornerHeight: 1.15, transform: nil))
        path.addPath(CGPath(ellipseIn: CGRect(x: 10.65, y: 14.6, width: 2.7, height: 2.7),
                            transform: nil))
        return path
    }

    /// 꺼짐을 나타내는 사선.
    static func slash() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 4.7, y: 4.7))
        path.addLine(to: CGPoint(x: 19.3, y: 19.3))
        return path
    }

    /// 앱을 나타내는 표지. 방패에 재생 삼각형을 뚫은 모양이다.
    static func mark() -> CGPath {
        let path = CGMutablePath()
        path.addPath(shield())
        path.addPath(play())
        return path
    }

    // MARK: 상태 아이콘

    /// 메뉴 바와 화면 표시기에 쓰는 그림.
    /// 그릴 때마다 다시 그리므로 어떤 크기에서도 또렷하다.
    static func statusImage(_ state: State, pointSize: CGFloat) -> NSImage {
        let color = self.color(for: state)
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.scaleBy(x: rect.width / grid, y: rect.height / grid)
            draw(state, color: color, in: context)
            context.restoreGState()
            return true
        }
        // 색을 직접 칠한 그림이므로 메뉴 바가 덧칠하지 않도록 표시를 꺼 둔다.
        image.isTemplate = false
        return image
    }

    static func color(for state: State) -> NSColor {
        switch state {
        case .blocking: return Palette.blocking
        case .allowed: return Palette.allowed
        case .off: return Palette.off
        case .unresponsive: return Palette.unresponsive
        }
    }

    private static func draw(_ state: State, color: NSColor, in context: CGContext) {
        context.setFillColor(color.cgColor)
        context.setStrokeColor(color.cgColor)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        switch state {
        case .blocking:
            let path = CGMutablePath()
            path.addPath(shield())
            path.addPath(bar())
            context.addPath(path)
            context.fillPath(using: .evenOdd)

        case .allowed:
            context.addPath(shield())
            context.setLineWidth(1.9)
            context.strokePath()
            context.addPath(play())
            context.fillPath()

        case .off:
            // 사선이 지나갈 자리를 방패 선에서 미리 파낸다.
            // 그러지 않으면 두 선이 겹치는 곳이 뭉쳐 보인다.
            let band = slash().copy(strokingWithWidth: 4.2, lineCap: .round,
                                    lineJoin: .round, miterLimit: 10)
            let cut = CGMutablePath()
            cut.addRect(CGRect(x: -1, y: -1, width: grid + 2, height: grid + 2))
            cut.addPath(band)

            context.saveGState()
            context.addPath(cut)
            context.clip(using: .evenOdd)
            context.addPath(shield())
            context.setLineWidth(1.7)
            context.strokePath()
            context.restoreGState()

            context.addPath(slash())
            context.setLineWidth(2)
            context.strokePath()

        case .unresponsive:
            let path = CGMutablePath()
            path.addPath(shield())
            path.addPath(exclamation())
            context.addPath(path)
            context.fillPath(using: .evenOdd)
        }
    }

    // MARK: 앱 번들 아이콘

    /// macOS 아이콘 격자를 따른다.
    /// 1024 짜리 화폭 가운데에 824 정사각형을 두고 모서리를 둥글린다.
    static func drawAppIcon(in context: CGContext, size: CGFloat) {
        context.saveGState()
        context.scaleBy(x: size / 1024, y: size / 1024)

        let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
        let squircle = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)

        context.saveGState()
        context.addPath(squircle)
        context.clip()
        let colors = [Palette.plateTop.cgColor, Palette.plateBottom.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: 512, y: plate.minY),
                                       end: CGPoint(x: 512, y: plate.maxY),
                                       options: [])
        }
        context.restoreGState()

        // 위쪽 가장자리에 아주 옅은 빛을 넣어 판이 떠 보이게 한다.
        context.saveGState()
        context.addPath(CGPath(roundedRect: plate.insetBy(dx: 1.5, dy: 1.5),
                               cornerWidth: 183.5, cornerHeight: 183.5, transform: nil))
        context.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor)
        context.setLineWidth(3)
        context.strokePath()
        context.restoreGState()

        // 표지는 방패 높이가 판의 절반을 조금 넘도록 잡았다.
        let box: CGFloat = 588
        context.saveGState()
        context.translateBy(x: 512 - box / 2, y: 512 - box / 2)
        context.scaleBy(x: box / grid, y: box / grid)
        context.addPath(mark())
        context.setFillColor(Palette.blocking.cgColor)
        context.fillPath(using: .evenOdd)
        context.restoreGState()

        context.restoreGState()
    }
}
