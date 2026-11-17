import Cocoa

struct AmazonLabelDetails: Codable, Equatable {
    var productName: String
    var condition: String

    static let conditions = [
        "New", "Used", "Used - Like New", "Used - Very Good", "Used - Good", "Used - Acceptable",
        "Collectible - Like New", "Collectible - Very Good", "Collectible - Good",
        "Collectible - Acceptable", "Renewed", "Rental"
    ]

    func validated() throws -> Self {
        let name = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw BarcodeError("Enter the product name.") }
        guard !state.isEmpty else { throw BarcodeError("Enter the product condition.") }
        guard name.count <= 500, state.count <= 80 else {
            throw BarcodeError("Use up to 500 characters for the product name and 80 for condition.")
        }
        return Self(productName: name, condition: state)
    }

    func draw(fnsku: String, artwork: BarcodeArtwork, in rect: CGRect, showsData: Bool = true) {
        guard rect.width > 0, rect.height > 0 else { return }
        NSColor.white.setFill()
        rect.fill()
        let area = rect.insetBy(dx: rect.width * 0.025, dy: rect.height * 0.025)
        func band(_ bottom: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: area.minX, y: area.minY + area.height * bottom,
                   width: area.width, height: area.height * height)
        }
        if let context = NSGraphicsContext.current?.cgContext {
            artwork.draw(in: band(0.48, 0.52), context: context)
        }
        if showsData { drawText(fnsku, in: band(0.34, 0.13), monospaced: true) }
        drawText(productName, in: band(0.12, 0.21), wraps: true)
        drawText(condition, in: band(0, 0.11))
    }

    private func drawText(_ text: String, in rect: CGRect, monospaced: Bool = false, wraps: Bool = false) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = wraps ? .byWordWrapping : .byClipping
        var lower: CGFloat = 0.1
        var upper = max(1, rect.height)
        func attributes(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
            [.font: monospaced ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                              : NSFont.systemFont(ofSize: size),
             .foregroundColor: NSColor.black, .paragraphStyle: paragraph]
        }
        for _ in 0..<20 {
            let size = (lower + upper) / 2
            let string = NSAttributedString(string: text, attributes: attributes(size))
            let measured = string.boundingRect(
                with: CGSize(width: wraps ? rect.width : .greatestFiniteMagnitude,
                             height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            if measured.width <= rect.width && measured.height <= rect.height {
                lower = size
            } else {
                upper = size
            }
        }
        NSAttributedString(string: text, attributes: attributes(lower))
            .draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    func image(fnsku: String, artwork: BarcodeArtwork, size: CGSize, showsData: Bool = true) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            self.draw(fnsku: fnsku, artwork: artwork, in: rect, showsData: showsData)
            return true
        }
    }
}
