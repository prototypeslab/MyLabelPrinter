import Cocoa

enum ImageContentKind: String, Codable {
    case image = "Image"
    case symbol = "Symbol"
    case clipArt = "Clip Art"
}

final class ImageItemView: FrameItemView {
    private(set) var imageData: Data
    private(set) var image: NSImage
    let contentKind: ImageContentKind

    func replaceImage(data: Data) throws {
        let replacement = try Self.decode(data)
        imageData = data
        image = replacement
        needsDisplay = true
    }

    static func thermalArtworkData(_ artwork: NSImage) throws -> Data {
        let rendered = NSImage(size: NSSize(width: 256, height: 256))
        rendered.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 256, height: 256).fill()
        NSColor.black.set()
        artwork.draw(in: NSRect(x: 24, y: 24, width: 208, height: 208),
                     from: .zero, operation: .sourceOver, fraction: 1)
        rendered.unlockFocus()
        guard let data = rendered.tiffRepresentation else { throw ImageImportError() }
        return data
    }

    static func decode(_ data: Data) throws -> NSImage {
        guard let image = NSImage(data: data), image.isValid,
              image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0 else {
            throw ImageImportError()
        }
        return image
    }

    init(data: Data, image: NSImage, frame: CGRect, contentKind: ImageContentKind = .image) {
        self.imageData = data
        self.image = image
        self.contentKind = contentKind
        super.init(frame: frame)
        setAccessibilityLabel(contentKind.rawValue)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func containsFramePoint(_ point: CGPoint) -> Bool {
        bounds.contains(point)
    }

    static func fittedRect(imageSize: CGSize, in box: CGRect) -> CGRect {
        let scale = min(box.width / imageSize.width, box.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    private static func draw(_ image: NSImage, in box: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: fittedRect(imageSize: image.size, in: box),
                   from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true, hints: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        Self.draw(image, in: bounds)
        if showsHandles {
            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
        drawSelectionHandles()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onSelect?()
        let menu = NSMenu()
        let item = NSMenuItem(title: "Delete Image", action: #selector(deleteImage), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func deleteImage() { onDelete?() }

    override func printDrawing() -> (NSView) -> Void {
        let image = image, rect = frame
        return { _ in Self.draw(image, in: rect) }
    }
}

struct ImageImportError: LocalizedError {
    var errorDescription: String? { "This file could not be opened as an image. Choose a valid image file." }
}
