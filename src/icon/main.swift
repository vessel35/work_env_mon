import Cocoa

// 앱 번들 아이콘의 낱장 그림을 만든다.
// build.sh 가 이 도구를 부르고, 나온 폴더를 iconutil 이 .icns 로 묶는다.

func renderAppIcon(pixels: Int) -> CGImage? {
    guard let context = CGContext(data: nil,
                                  width: pixels, height: pixels,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    // 그림을 위에서 아래로 재는 좌표계로 뒤집는다. 도형을 그 기준으로 그렸다.
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: 1, y: -1)
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)

    IconArt.drawAppIcon(in: context, size: CGFloat(pixels))
    return context.makeImage()
}

func writePNG(_ image: CGImage, to path: String) -> Bool {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { return false }
    return (try? data.write(to: URL(fileURLWithPath: path))) != nil
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let outputDirectory = arguments.first else {
    FileHandle.standardError.write(Data("쓸 폴더를 알려 주세요. 예: ytguard-makeicon build/AppIcon.iconset\n".utf8))
    exit(2)
}

// .icns 가 요구하는 낱장 크기들.
let plates: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

do {
    try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
} catch {
    FileHandle.standardError.write(Data("폴더를 만들지 못했습니다: \(error.localizedDescription)\n".utf8))
    exit(1)
}

for plate in plates {
    guard let image = renderAppIcon(pixels: plate.pixels) else {
        FileHandle.standardError.write(Data("\(plate.name) 을 그리지 못했습니다.\n".utf8))
        exit(1)
    }
    let path = "\(outputDirectory)/\(plate.name).png"
    guard writePNG(image, to: path) else {
        FileHandle.standardError.write(Data("\(path) 에 쓰지 못했습니다.\n".utf8))
        exit(1)
    }
}

print("앱 아이콘 낱장 \(plates.count) 장을 \(outputDirectory) 에 썼습니다.")
