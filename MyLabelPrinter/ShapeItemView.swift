import Cocoa

enum LabelShapeStyle: String, Codable, CaseIterable {
    case rectangle = "Rectangle"
    case rounded = "Rounded Rectangle"
    case oval = "Oval"
}

struct LabelShape: Codable, Equatable {
    static let weights: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.5, 2.25, 3, 4.5, 6]
    var style: LabelShapeStyle = .rectangle
    var weight: CGFloat = 1
    var cornerRadiusMM: CGFloat = 2
    var minimumSizeMM: CGFloat { max(2, 2 * weight * 25.4 / 72) }

    func validate(sizeMM: CGSize) throws {
        guard Self.weights.contains(weight), cornerRadiusMM.isFinite,
              cornerRadiusMM > 0, cornerRadiusMM <= 1000,
              [sizeMM.width, sizeMM.height].allSatisfy({ $0.isFinite && $0 >= minimumSizeMM && $0 <= 1000 }) else {
            throw FrameError("Enter valid dimensions large enough for the selected shape weight.")
        }
    }

    func path(in rect: CGRect, pixelsPerMM: CGFloat) -> CGPath {
        let stroke = weight * pixelsPerMM * 25.4 / 72
        let area = rect.insetBy(dx: stroke / 2, dy: stroke / 2)
        let path = CGMutablePath()
        guard area.width > 0, area.height > 0 else { return path }
        switch style {
        case .rectangle: path.addRect(area)
        case .oval: path.addEllipse(in: area)
        case .rounded:
            let radius = min(cornerRadiusMM * pixelsPerMM, min(area.width, area.height) / 2)
            path.addRoundedRect(in: area, cornerWidth: radius, cornerHeight: radius)
        }
        return path
    }

    func draw(in rect: CGRect, context: CGContext, pixelsPerMM: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(weight * pixelsPerMM * 25.4 / 72)
        context.setLineDash(phase: 0, lengths: [])
        context.addPath(path(in: rect, pixelsPerMM: pixelsPerMM))
        context.strokePath()
    }
}

final class ShapeItemView: FrameItemView {
    var shape = LabelShape() { didSet { needsDisplay = true } }
    override var minimumResizeSizeMM: CGFloat { shape.minimumSizeMM }

    override func containsFramePoint(_ point: CGPoint) -> Bool {
        bounds.contains(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        shape.draw(in: bounds, context: context, pixelsPerMM: pixelsPerMM)
        drawSelectionHandles()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onSelect?()
        let menu = NSMenu()
        let item = NSMenuItem(title: "Delete Shape", action: #selector(deleteShape), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func deleteShape() { onDelete?() }

    override func printDrawing() -> (NSView) -> Void {
        let shape = shape, rect = frame, scale = pixelsPerMM
        return { _ in
            if let context = NSGraphicsContext.current?.cgContext {
                shape.draw(in: rect, context: context, pixelsPerMM: scale)
            }
        }
    }
}
