import Foundation

/// 외부 명령을 실행하는 얇은 도우미.
enum Shell {
    struct Result {
        var status: Int32
        var stdout: String
        var stderr: String
        var succeeded: Bool { status == 0 }
    }

    @discardableResult
    static func run(_ path: String, _ arguments: [String], input: String? = nil, timeout: TimeInterval = 20) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        var inPipe: Pipe?
        if input != nil {
            let p = Pipe()
            process.standardInput = p
            inPipe = p
        }

        do {
            try process.run()
        } catch {
            return Result(status: -1, stdout: "", stderr: "실행하지 못했습니다: \(error.localizedDescription)")
        }

        if let inPipe = inPipe, let input = input {
            inPipe.fileHandleForWriting.write(Data(input.utf8))
            inPipe.fileHandleForWriting.closeFile()
        }

        // 파이프가 가득 차서 멈추지 않도록 먼저 읽고 나서 기다린다.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            return Result(status: -2, stdout: "", stderr: "시간이 초과되어 중단했습니다.")
        }

        return Result(status: process.terminationStatus,
                      stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: errData, as: UTF8.self))
    }

    /// 이름 조회 결과가 캐시에 남아 차단이 늦게 반영되는 것을 막는다.
    static func flushDNSCache() {
        run("/usr/bin/dscacheutil", ["-flushcache"])
        run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
    }
}
