import Foundation

/// 막을 수 있는 서비스 하나.
///
/// hosts 파일은 하위 도메인 전체를 한 번에 막지 못하므로,
/// 들어가는 입구가 되는 주소를 빠짐없이 적어 두는 것이 중요하다.
/// 입구가 막히면 영상이 내려오는 주소를 받아 올 일 자체가 없어진다.
struct BlockedService: Equatable {
    /// 설정 파일에 적히는 이름. 한 번 정하면 바꾸지 않는다.
    let id: String
    /// 사람에게 보여 줄 이름.
    let name: String
    /// 서비스로 들어가는 입구.
    let hosts: [String]
    /// 영상이 실제로 내려오는 쪽. "영상 전송 호스트도 함께 막기" 를 켰을 때만 쓴다.
    let mediaHosts: [String]
    /// 방화벽으로 IP 까지 막을 때 주소를 조회할 대상.
    let packetFilterTargets: [String]
}

enum Services {

    static let all: [BlockedService] = [
        BlockedService(
            id: "youtube",
            name: "YouTube",
            hosts: [
                "youtube.com", "www.youtube.com", "m.youtube.com",
                "music.youtube.com", "tv.youtube.com", "studio.youtube.com",
                "kids.youtube.com", "gaming.youtube.com",
                "youtu.be", "www.youtu.be",
                "youtube-nocookie.com", "www.youtube-nocookie.com",
                "youtubei.googleapis.com", "youtubeembeddedplayer.googleapis.com",
                "yt3.ggpht.com", "yt4.ggpht.com",
                "i.ytimg.com", "s.ytimg.com", "i9.ytimg.com", "img.youtube.com",
            ],
            mediaHosts: [
                "googlevideo.com", "www.googlevideo.com",
                "manifest.googlevideo.com", "redirector.googlevideo.com",
            ],
            packetFilterTargets: ["www.youtube.com", "m.youtube.com", "youtubei.googleapis.com"]
        ),

        BlockedService(
            id: "netflix",
            name: "넷플릭스",
            hosts: [
                "netflix.com", "www.netflix.com", "m.netflix.com",
                "api-global.netflix.com", "ichnaea.netflix.com",
                "help.netflix.com", "netflix.net",
            ],
            mediaHosts: [
                "nflxvideo.net", "nflxso.net", "www.nflxso.net",
                "nflxext.com", "assets.nflxext.com",
                "nflximg.net", "nflximg.com",
            ],
            packetFilterTargets: ["www.netflix.com", "api-global.netflix.com"]
        ),

        BlockedService(
            id: "disneyplus",
            name: "디즈니+",
            hosts: [
                "disneyplus.com", "www.disneyplus.com",
                "disney-plus.net", "www.disney-plus.net",
                "bamgrid.com", "global.edge.bamgrid.com",
                "disneystreaming.com", "media.disneystreaming.com",
            ],
            mediaHosts: [
                "dssott.com", "prod-ripcut-delivery.disney-plus.net",
            ],
            packetFilterTargets: ["www.disneyplus.com", "global.edge.bamgrid.com"]
        ),

        BlockedService(
            id: "tving",
            name: "티빙",
            hosts: [
                "tving.com", "www.tving.com", "m.tving.com", "api.tving.com",
            ],
            mediaHosts: ["image.tving.com", "stream.tving.com"],
            packetFilterTargets: ["www.tving.com", "api.tving.com"]
        ),

        BlockedService(
            id: "wavve",
            name: "웨이브",
            hosts: [
                "wavve.com", "www.wavve.com", "m.wavve.com", "apis.wavve.com",
            ],
            mediaHosts: ["image.wavve.com", "vod.wavve.com"],
            packetFilterTargets: ["www.wavve.com", "apis.wavve.com"]
        ),

        BlockedService(
            id: "coupangplay",
            name: "쿠팡플레이",
            // 쇼핑 쪽(coupang.com)은 건드리지 않는다.
            hosts: [
                "coupangplay.com", "www.coupangplay.com", "api.coupangplay.com",
            ],
            mediaHosts: ["image.coupangplay.com"],
            packetFilterTargets: ["www.coupangplay.com"]
        ),

        BlockedService(
            id: "watcha",
            name: "왓챠",
            hosts: [
                "watcha.com", "www.watcha.com", "pedia.watcha.com",
                "watcha.net", "www.watcha.net",
            ],
            mediaHosts: ["an.watcha.com"],
            packetFilterTargets: ["www.watcha.com"]
        ),

        BlockedService(
            id: "primevideo",
            name: "프라임 비디오",
            // 아마존 쇼핑(amazon.com)은 건드리지 않는다.
            hosts: [
                "primevideo.com", "www.primevideo.com", "atv-ps.amazon.com",
            ],
            mediaHosts: ["aiv-cdn.net", "aiv-delivery.net"],
            packetFilterTargets: ["www.primevideo.com"]
        ),

        BlockedService(
            id: "appletv",
            name: "Apple TV+",
            hosts: ["tv.apple.com"],
            mediaHosts: ["uts-api.itunes.apple.com", "play-edge.itunes.apple.com"],
            packetFilterTargets: ["tv.apple.com"]
        ),

        BlockedService(
            id: "twitch",
            name: "트위치",
            hosts: [
                "twitch.tv", "www.twitch.tv", "m.twitch.tv",
                "api.twitch.tv", "gql.twitch.tv", "passport.twitch.tv",
            ],
            mediaHosts: ["usher.ttvnw.net", "ttvnw.net", "jtvnw.net", "static-cdn.jtvnw.net"],
            packetFilterTargets: ["www.twitch.tv", "gql.twitch.tv"]
        ),
    ]

    static func service(id: String) -> BlockedService? {
        all.first { $0.id == id }
    }

    static func names(ids: [String]) -> [String] {
        ids.compactMap { service(id: $0)?.name }
    }
}
