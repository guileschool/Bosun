import AppKit

@main
struct BundleCheck {
    static func main() {
        let path = CommandLine.arguments[1]
        guard let bundle = Bundle(path: path) else { fatalError("Missing app bundle") }
        for (language, expected) in [("en", "Quit Bosun"), ("ko", "종료")] {
            guard let resources = bundle.path(forResource: language, ofType: "lproj"),
                  let localized = Bundle(path: resources) else { fatalError("Missing language bundle") }
            precondition(localized.localizedString(forKey: "종료", value: nil, table: nil) == expected)
        }
        guard let icon = bundle.path(forResource: "AppIcon", ofType: "icns"),
              let image = NSImage(contentsOfFile: icon) else { fatalError("Invalid app icon") }
        precondition(image.size.width > 0)
        precondition(bundle.object(forInfoDictionaryKey: "SUAllowsAutomaticUpdates") as? Bool == false)
        precondition(bundle.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool == true)
        precondition(bundle.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool == true)
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        precondition(Data(base64Encoded: publicKey)?.count == 32)
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        precondition(URL(string: feed)?.scheme == "https")
        for resource in ["Contents/Frameworks/Sparkle.framework/Sparkle",
                         "Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater",
                         "Contents/Resources/THIRD-PARTY-NOTICES.txt"] {
            precondition(FileManager.default.fileExists(atPath: path + "/" + resource), "Missing " + resource)
        }
        print("Packaged languages, icon, updater helpers, secure update settings and notices verified")
    }
}
