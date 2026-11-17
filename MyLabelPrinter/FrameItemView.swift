import Cocoa

enum LabelFrameStyle: String, Codable, CaseIterable {
    case rectangle = "Rectangle"
    case doubleRectangle = "Rectangle Double"
    case rounded = "Rectangle Round Corners"
    case dotted = "Rectangle Dots"
    case circle = "Circle"
    case circleDouble = "Circle Double"
    case circleDotted = "Circle Dotted"
}

enum LabelFrameWeight: String, Codable, CaseIterable {
    case simple = "Simple", thin = "Thin", thick = "Thick"

    var points: CGFloat {
        switch self {
        case .simple: return 1
        case .thin: return 0.5
        case .thick: return 3
        }
    }
}

struct LabelFrame: Codable, Equatable {
    var style: LabelFrameStyle = .rectangle
    var weight: LabelFrameWeight = .simple
    var cornerRadiusMM: CGFloat = 2
    var doubleGapMM: CGFloat = 1
    var dotSpacingMM: CGFloat = 1.5

    var minimumSizeMM: CGFloat {
        let stroke = weight.points * 25.4 / 72
        let isDouble = style == .doubleRectangle || style == .circleDouble
        return max(2, isDouble ? 4 * stroke + 2 * doubleGapMM : 2 * stroke)
    }

    func validate(sizeMM: CGSize) throws {
        guard [cornerRadiusMM, doubleGapMM, dotSpacingMM].allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 1000 }),
              sizeMM.width.isFinite, sizeMM.height.isFinite,
              sizeMM.width >= minimumSizeMM, sizeMM.height >= minimumSizeMM,
              sizeMM.width <= 1000, sizeMM.height <= 1000 else {
            throw FrameError("Enter valid dimensions large enough for the selected border.")
        }
        if (style == .dotted || style == .circleDotted),
           dotSpacingMM <= weight.points * 25.4 / 72 {
            throw FrameError("Dot spacing must be greater than the border thickness.")
        }
    }

    func path(in rect: CGRect, pixelsPerMM: CGFloat) -> CGPath {
        let stroke = weight.points * pixelsPerMM * 25.4 / 72
        let outer = rect.insetBy(dx: stroke / 2, dy: stroke / 2)
        let path = CGMutablePath()
        guard outer.width > 0, outer.height > 0 else { return path }
        if style == .rounded {
            let radius = min(cornerRadiusMM * pixelsPerMM, min(outer.width, outer.height) / 2)
            path.addRoundedRect(in: outer, cornerWidth: radius, cornerHeight: radius)
        } else if style == .circle || style == .circleDouble || style == .circleDotted {
            path.addEllipse(in: outer)
            if style == .circleDouble {
                let inset = doubleGapMM * pixelsPerMM + stroke
                let inner = outer.insetBy(dx: inset, dy: inset)
                if inner.width > 0, inner.height > 0 { path.addEllipse(in: inner) }
            }
        } else {
            path.addRect(outer)
            if style == .doubleRectangle {
                let inset = doubleGapMM * pixelsPerMM + stroke
                let inner = outer.insetBy(dx: inset, dy: inset)
                if inner.width > 0, inner.height > 0 { path.addRect(inner) }
            }
        }
        return path
    }

    func draw(in rect: CGRect, context: CGContext, pixelsPerMM: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(weight.points * pixelsPerMM * 25.4 / 72)
        if style == .dotted || style == .circleDotted {
            context.setLineCap(.round)
            context.setLineDash(phase: 0, lengths: [0, dotSpacingMM * pixelsPerMM])
        }
        context.addPath(path(in: rect, pixelsPerMM: pixelsPerMM))
        context.strokePath()
    }
}

struct FrameError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

class FrameItemView: NSView {
    var configuration = LabelFrame() { didSet { needsDisplay = true } }
    var rectMM: CGRect = .zero
    var pixelsPerMM: CGFloat = 72 / 25.4 { didSet { needsDisplay = true } }
    var showsHandles = true { didSet { needsDisplay = true } }
    var onSelect: (() -> Void)?
    var onDelete: (() -> Void)?
    var onFrameChanged: ((CGRect) -> Void)?
    private var dragOrigin = CGPoint.zero
    private var originalFrame = CGRect.zero
    private var corner: Int?
    override var acceptsFirstResponder: Bool { true }

    var minimumResizeSizeMM: CGFloat { configuration.minimumSizeMM }

    var handles: [CGRect] {
        let size = min(12, min(bounds.width, bounds.height) / 3)
        return [
            CGRect(x: 0, y: 0, width: size, height: size),
            CGRect(x: bounds.maxX - size, y: 0, width: size, height: size),
            CGRect(x: 0, y: bounds.maxY - size, width: size, height: size),
            CGRect(x: bounds.maxX - size, y: bounds.maxY - size, width: size, height: size),
            CGRect(x: 0, y: bounds.midY - size / 2, width: size, height: size),
            CGRect(x: bounds.maxX - size, y: bounds.midY - size / 2, width: size, height: size),
            CGRect(x: bounds.midX - size / 2, y: 0, width: size, height: size),
            CGRect(x: bounds.midX - size / 2, y: bounds.maxY - size, width: size, height: size)
        ]
    }

    func containsFramePoint(_ point: CGPoint) -> Bool {
        guard bounds.contains(point) else { return false }
        if showsHandles && handles.contains(where: { $0.contains(point) }) { return true }
        let outline = configuration.path(in: bounds, pixelsPerMM: pixelsPerMM)
        return outline.copy(strokingWithWidth: max(12, configuration.weight.points * pixelsPerMM * 25.4 / 72),
                            lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        !isHidden && containsFramePoint(convert(point, from: superview)) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        configuration.draw(in: bounds, context: context, pixelsPerMM: pixelsPerMM)
        drawSelectionHandles()
    }

    func drawSelectionHandles() {
        if showsHandles {
            NSColor.systemBlue.setStroke()
            for handle in handles {
                let outline = NSBezierPath(rect: handle.insetBy(dx: 0.75, dy: 0.75))
                outline.lineWidth = 1.5
                outline.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
        window?.makeFirstResponder(self)
        dragOrigin = superview?.convert(event.locationInWindow, from: nil) ?? .zero
        originalFrame = frame
        let local = convert(event.locationInWindow, from: nil)
        corner = handles.firstIndex { $0.contains(local) }
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let parent = superview else { return }
        let point = parent.convert(event.locationInWindow, from: nil)
        let dx = point.x - dragOrigin.x, dy = point.y - dragOrigin.y
        var rect = originalFrame
        if let corner {
            let minimum = minimumResizeSizeMM * pixelsPerMM
            if corner == 0 || corner == 2 || corner == 4 {
                let x = max(parent.bounds.minX, min(originalFrame.maxX - minimum, originalFrame.minX + dx))
                rect.origin.x = x
                rect.size.width = originalFrame.maxX - x
            } else if corner == 1 || corner == 3 || corner == 5 {
                rect.size.width = max(minimum, min(parent.bounds.maxX - originalFrame.minX, originalFrame.width + dx))
            }
            if corner == 0 || corner == 1 || corner == 6 {
                let y = max(parent.bounds.minY, min(originalFrame.maxY - minimum, originalFrame.minY + dy))
                rect.origin.y = y
                rect.size.height = originalFrame.maxY - y
            } else if corner == 2 || corner == 3 || corner == 7 {
                rect.size.height = max(minimum, min(parent.bounds.maxY - originalFrame.minY, originalFrame.height + dy))
            }
        } else {
            rect.origin.x = max(parent.bounds.minX, min(parent.bounds.maxX - rect.width, rect.minX + dx))
            rect.origin.y = max(parent.bounds.minY, min(parent.bounds.maxY - rect.height, rect.minY + dy))
        }
        let minimum = minimumResizeSizeMM * pixelsPerMM
        rect = RulerImageView.snapDrag(rect, original: originalFrame,
                                      minimum: CGSize(width: minimum, height: minimum), view: self)
        let previous = frame
        frame = rect
        needsDisplay = true
        parent.setNeedsDisplay(previous.union(rect))
        onFrameChanged?(rect)
    }

    override func mouseUp(with event: NSEvent) { NSCursor.arrow.set() }

    override func menu(for event: NSEvent) -> NSMenu? {
        onSelect?()
        let menu = NSMenu()
        let item = NSMenuItem(title: "Delete Frame", action: #selector(deleteFrame), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func deleteFrame() { onDelete?() }

    override func keyDown(with event: NSEvent) {
        if RulerImageView.canvas(for: self)?.moveSelection(with: event) == true { return }
        if event.keyCode == 51 || event.keyCode == 117 { onDelete?() }
        else { super.keyDown(with: event) }
    }

    func printDrawing() -> (NSView) -> Void {
        let configuration = configuration, rect = frame, scale = pixelsPerMM
        return { _ in
            if let context = NSGraphicsContext.current?.cgContext {
                configuration.draw(in: rect, context: context, pixelsPerMM: scale)
            }
        }
    }
}
