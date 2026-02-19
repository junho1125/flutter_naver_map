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
        guard !path.isEmpty,
              let image = UIImage(contentsOfFile: path),
              let data = image.pngData(),
              let scaledImage = UIImage(data: data, scale: DisplayUtil.scale) else {
            assertionFailure("[FlutterNaverMapPlugin] Invalid overlay image path: \(path)")
            return NMFOverlayImage(image: UIImage())
        }

        return NMFOverlayImage(image: scaledImage)
    }

    private func makeOverlayImageWithAssetPath() -> NMFOverlayImage {
        let key = SwiftFlutterNaverMapPlugin.getAssets(path: path)

        guard let assetPath = Bundle.main.path(forResource: key, ofType: nil),
              let image = UIImage(contentsOfFile: assetPath),
              let data = image.pngData(),
              let scaledImage = UIImage(data: data, scale: DisplayUtil.scale) else {
            assertionFailure("[FlutterNaverMapPlugin] Invalid overlay asset path: \(path)")
            return NMFOverlayImage(image: UIImage())
        }

        return NMFOverlayImage(image: scaledImage, reuseIdentifier: assetPath)
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
