import Foundation

/// 설정 파일과 상태 파일을 다루는 쪽. 실패했을 때 사람이 읽을 수 있는 이유를 함께 준다.
enum ConfigAccess {

    enum AccessError: LocalizedError {
        case notInstalled
        case notWritable
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "설정 파일이 없습니다. install.sh 로 설치가 끝났는지 확인해 주세요."
            case .notWritable:
                return "설정 파일에 쓸 권한이 없습니다. 관리자 계정으로 install.sh 를 다시 실행해 주세요."
            case .failed(let detail):
                return detail
            }
        }
    }

    static func loadConfig() -> Config? {
        try? JSONStore.load(Config.self, from: Paths.configFile)
    }

    static func loadState() -> BlockState? {
        try? JSONStore.load(BlockState.self, from: Paths.stateFile)
    }

    static var isWritable: Bool {
        FileManager.default.isWritableFile(atPath: Paths.configFile)
            && FileManager.default.isWritableFile(atPath: Paths.userConfigDir)
    }

    /// 파일을 다시 읽어 고친 뒤 저장한다.
    /// 중간에 다른 곳에서 바꾼 내용을 덮어쓰지 않도록 항상 최신 내용을 읽고 시작한다.
    static func update(_ change: (inout Config) -> Void) throws {
        guard FileManager.default.fileExists(atPath: Paths.configFile) else {
            throw AccessError.notInstalled
        }
        guard isWritable else {
            throw AccessError.notWritable
        }
        var config = loadConfig() ?? Config.default
        change(&config)
        config.updatedAt = Date()
        do {
            try JSONStore.save(config, to: Paths.configFile)
        } catch {
            throw AccessError.failed(error.localizedDescription)
        }
    }
}
