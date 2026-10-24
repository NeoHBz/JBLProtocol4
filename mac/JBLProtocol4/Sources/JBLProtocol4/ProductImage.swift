import AppKit
import JBLKit

/// Product photos from ProductImages/, copied into the app by scripts/bundle.sh, named `<pid>_<Colour>.<ext>`
/// with `<pid>.<ext>` as the model's default. A model with no photo gets nil and shows a symbol.
@MainActor
enum ProductImage {
    private static let folder = Bundle.main.resourceURL?.appendingPathComponent("ProductImages")
    private static var cache: [String: NSImage?] = [:]

    static func image(pid: UInt16?, colorID: Int?) -> NSImage? {
        guard let pid else { return nil }
        let p = String(format: "%04x", pid)
        let names = (colorID.flatMap(Product.colourKey).map { ["\(p)_\($0)"] } ?? []) + [p]
        for n in names { if let i = load(n) { return i } }
        return nil
    }

    private static func load(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        let i = ["webp", "png"].lazy.compactMap { ext in
            folder.flatMap { NSImage(contentsOf: $0.appendingPathComponent("\(name).\(ext)")) }
        }.first
        cache[name] = i
        return i
    }
}
