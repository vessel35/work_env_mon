import Foundation

/// 설정에 따라 실제로 막을 주소 목록을 만든다.
enum Blocklist {

    /// 브라우저가 자체 암호화 DNS 로 hosts 파일을 건너뛰는 것을 막기 위한 목록.
    /// 차단 시간 동안에만 넣으며, 이름 조회 경로만 시스템 쪽으로 되돌릴 뿐
    /// 다른 사이트 접속을 막지는 않는다.
    static let dohEndpoints = [
        "dns.google", "dns64.dns.google",
        "cloudflare-dns.com", "one.one.one.one",
        "chrome.cloudflare-dns.com", "mozilla.cloudflare-dns.com",
        "security.cloudflare-dns.com", "family.cloudflare-dns.com",
        "dns.quad9.net", "dns10.quad9.net", "dns11.quad9.net",
        "doh.opendns.com", "familyshield.opendns.com",
        "dns.nextdns.io",
        "doh.cleanbrowsing.org",
        "dns.adguard.com", "dns-unfiltered.adguard.com",
    ]

    /// hosts 파일에 넣을 주소 전체.
    /// 순서를 고정해 두어야 내용이 같을 때 파일을 괜히 다시 쓰지 않는다.
    static func hostnames(config: Config) -> [String] {
        var names: [String] = []

        for id in config.services {
            guard let service = Services.service(id: id) else { continue }
            names += service.hosts
            if config.blockMediaHosts {
                names += service.mediaHosts
            }
        }

        for host in config.customHosts {
            names += HostName.expand(host)
        }

        if config.hardenDoH {
            names += dohEndpoints
        }

        return Array(Set(names)).sorted()
    }

    /// 방화벽으로 IP 를 막을 때 주소를 조회할 대상.
    /// 직접 적어 넣은 주소도 함께 본다.
    static func packetFilterTargets(config: Config) -> [String] {
        var names: [String] = []
        for id in config.services {
            guard let service = Services.service(id: id) else { continue }
            names += service.packetFilterTargets
        }
        names += config.customHosts
        return Array(Set(names)).sorted()
    }
}
