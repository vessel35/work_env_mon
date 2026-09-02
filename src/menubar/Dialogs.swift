import Cocoa

/// 확인 대화상자. 켜고 끄거나 설정을 고치는 모든 조작은 이 창을 한 번 거친다.
enum Dialogs {

    /// 진행할지 묻는다. 실수로 Return 을 눌러 그냥 진행되는 일이 없도록
    /// 기본 단추를 "취소" 쪽에 둔다.
    static func confirm(title: String,
                        message: String,
                        proceedTitle: String,
                        destructive: Bool = false) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message

        // 먼저 넣은 단추가 기본값이 된다.
        let cancel = alert.addButton(withTitle: "취소")
        cancel.keyEquivalent = "\r"

        let proceed = alert.addButton(withTitle: proceedTitle)
        proceed.keyEquivalent = ""
        proceed.hasDestructiveAction = destructive

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }

    static func info(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    static func error(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
