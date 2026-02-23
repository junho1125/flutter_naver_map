import NMapsMap

internal struct NOverlayImage {
    let path: String
    let mode: NOverlayImageMode

    var overlayImage: NMFOverlayImage {
        switch mode {
        case .file, .temp, .widget: return makeOverlayImageWithPath()
        case .asset: return makeOverlayImageWithAssetPath()
        }
    }

    private func makeOverlayImageWithPath() -> NMFOverlayImage {
        guard let image = loadImageFromPath(path) else {
            return fallbackOverlayImage(reason: "Invalid overlay image path", path: path)
        }

        return NMFOverlayImage(image: image)
    }

    private func makeOverlayImageWithAssetPath() -> NMFOverlayImage {
        let key = SwiftFlutterNaverMapPlugin.getAssets(path: path)

        guard let assetPath = Bundle.main.path(forResource: key, ofType: nil),
              let image = loadImageFromPath(assetPath) else {
            return fallbackOverlayImage(reason: "Invalid overlay asset path", path: path)
        }

        return NMFOverlayImage(image: image, reuseIdentifier: assetPath)
    }

    private func loadImageFromPath(_ fullPath: String) -> UIImage? {
        guard !fullPath.isEmpty,
              let image = UIImage(contentsOfFile: fullPath),
              let cgImage = image.cgImage else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: DisplayUtil.scale, orientation: image.imageOrientation)
    }

    private func fallbackOverlayImage(reason: String, path: String) -> NMFOverlayImage {
        let fileManager = FileManager.default
        let fileExists = fileManager.fileExists(atPath: path)
        let fileSize: Int64 = {
            guard fileExists,
                  let attrs = try? fileManager.attributesOfItem(atPath: path),
                  let raw = attrs[.size] as? NSNumber else {
                return -1
            }
            return raw.int64Value
        }()

        print("[FlutterNaverMapPlugin] \(reason): mode=\(mode.rawValue), path=\(path), exists=\(fileExists), size=\(fileSize)")

        return NMFOverlayImage(image: NOverlayImage.makeTransparentPixel())
    }

    private static func makeTransparentPixel() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    func toMessageable() -> Dictionary<String, Any> {
        [
            "path": path,
            "mode": mode.rawValue
        ]
    }

    static func fromMessageable(_ v: Any) -> NOverlayImage {
        let d = asDict(v)
        return NOverlayImage(
                path: asString(d["path"]!),
                mode: NOverlayImageMode(rawValue: asString(d["mode"]!))!
        )
    }

    static let none = NOverlayImage(path: "", mode: .temp)
}
