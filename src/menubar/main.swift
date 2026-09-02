import Cocoa

// 메뉴 바에만 나타나는 앱이라 Dock 아이콘과 메뉴 막대는 두지 않는다.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

// 아이콘이 어떤 색으로 그려지는지만 확인하고 끝내는 길.
if CommandLine.arguments.contains("--icon-check") {
    print(AppDelegate.iconCheckReport())
    exit(0)
}

let delegate = AppDelegate()
application.delegate = delegate
application.run()
