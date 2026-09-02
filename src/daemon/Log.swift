import Foundation

/// 파일 한 개에 남기는 간단한 기록. 너무 커지면 앞부분을 버린다.
final class Log {
    static let shared = Log()

    private let queue = DispatchQueue(label: "com.vincent.ytguard.log")
    private let maxBytes = 512 * 1024
    private let formatter: DateFormatter

    private init() {
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        try? FileManager.default.createDirectory(atPath: Paths.logDir,
                                                 withIntermediateDirectories: true)
    }

    func write(_ message: String) {
        queue.async {
            let line = "[\(self.formatter.string(from: Date()))] \(message)\n"
            FileHandle.standardError.write(Data(line.utf8))

            let url = URL(fileURLWithPath: Paths.logFile)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
            self.trimIfNeeded(url)
        }
    }

    private func trimIfNeeded(_ url: URL) {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
              size > maxBytes,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\n")
        let kept = lines.suffix(lines.count / 2).joined(separator: "\n")
        try? kept.write(to: url, atomically: true, encoding: .utf8)
    }
}

func log(_ message: String) { Log.shared.write(message) }
