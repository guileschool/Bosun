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
        print("Packaged English/Korean strings and app icon verified")
    }
}
