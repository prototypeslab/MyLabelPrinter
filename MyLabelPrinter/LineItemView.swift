import Cocoa

enum LabelLineStyle: String, Codable, CaseIterable {
    case line = "Line", dashed = "Dashed", dotted = "Dotted"
}

enum LabelLineEndpoint: String, Codable, CaseIterable {
    case rectangle = "Rectangle", round = "Round"
    case arrowThin = "Arrow Thin", arrowMedium = "Arrow Medium", arrowThick = "Arrow Thick"
}

struct LabelLine: Codable, Equatable {
    static let weights: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.5, 2.25, 3, 4.5, 6]
    var weight: CGFloat = 1
    var style: LabelLineStyle = .line
    var startEndpoint: LabelLineEndpoint = .rectangle
    var endEndpoint: LabelLineEndpoint = .rectangle
    var startMM = CGPoint(x: 5, y: 10)
    var endMM = CGPoint(x: 30, y: 10)

    func validate() throws {
        guard Self.weights.contains(weight),
              [startMM.x, startMM.y, endMM.x, endMM.y].allSatisfy({ $0.isFinite && abs($0) <= 10000 }),
              hypot(endMM.x - startMM.x, endMM.y - startMM.y) > 0.01 else {
            throw NSError(domain: "LabelLine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The line has invalid weight or endpoints."])
        }
    }

    func draw(context: CGContext, pixelsPerMM: CGFloat) {
        let a = CGPoint(x: startMM.x * pixelsPerMM, y: startMM.y * pixelsPerMM)
        let b = CGPoint(x: endMM.x * pixelsPerMM, y: endMM.y * pixelsPerMM)
        let scale = pixelsPerMM * 25.4 / 72
        let thickness = weight * scale
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(NSColor.black.cgColor)
        context.setFillColor(NSColor.black.cgColor)
        context.setLineWidth(thickness)
        context.setLineCap(style == .dotted ? .round : .butt)
        switch style {
        case .line: break
        case .dashed: context.setLineDash(phase: 0, lengths: [6 * thickness, 3 * thickness])
        case .dotted: context.setLineDash(phase: 0, lengths: [0, 3 * thickness])
        }
        context.move(to: a)
        context.addLine(to: b)
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
        func endpoint(_ kind: LabelLineEndpoint, at tip: CGPoint, toward other: CGPoint) {
            switch kind {
            case .rectangle: return
            case .round:
                context.fillEllipse(in: CGRect(x: tip.x - thickness / 2, y: tip.y - thickness / 2,
                                               width: thickness, height: thickness))
            case .arrowThin, .arrowMedium, .arrowThick:
                let factor: CGFloat = kind == .arrowThin ? 1 : (kind == .arrowMedium ? 1.7 : 2.5)
                let size = min(length / 3, max(6 * scale, thickness * 3) * factor)
                let ux = (other.x - tip.x) / length
                let uy = (other.y - tip.y) / length
                let left = CGPoint(x: tip.x + ux * size - uy * size * 0.45,
                                   y: tip.y + uy * size + ux * size * 0.45)
                let right = CGPoint(x: tip.x + ux * size + uy * size * 0.45,
                                    y: tip.y + uy * size - ux * size * 0.45)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.setLineWidth(max(scale * 0.6, thickness) * factor)
                context.move(to: left)
                context.addLine(to: tip)
                context.addLine(to: right)
                context.strokePath()
            }
        }
        endpoint(startEndpoint, at: a, toward: b)
        endpoint(endEndpoint, at: b, toward: a)
    }
}

final class LineItemView: NSView {
    var line = LabelLine() { didSet { needsDisplay = true } }
    var pixelsPerMM: CGFloat = 72 / 25.4 { didSet { needsDisplay = true } }
    var showsHandles = true { didSet { needsDisplay = true } }
    var isPreview = false
    var onSelect: (() -> Void)?
    var onDelete: (() -> Void)?
    private var dragPart = 0
    private var dragOrigin = CGPoint.zero
    private var original = LabelLine()
    override var acceptsFirstResponder: Bool { true }

    private func point(_ mm: CGPoint) -> CGPoint {
        CGPoint(x: mm.x * pixelsPerMM, y: mm.y * pixelsPerMM)
    }

    func containsLinePoint(_ p: CGPoint) -> Bool {
        let a = point(line.startMM), b = point(line.endMM)
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared)) : 0
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy) <= max(8, line.weight * pixelsPerMM * 25.4 / 72 / 2)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, !isPreview else { return nil }
        return containsLinePoint(convert(point, from: superview)) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if isPreview {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(bounds)
            context.setStrokeColor(NSColor.lightGray.cgColor)
            context.setLineWidth(1)
            context.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
            var sample = line
            let inset = min(32, bounds.width / 4)
            sample.startMM = CGPoint(x: (bounds.minX + inset) / pixelsPerMM,
                                     y: bounds.midY / pixelsPerMM)
            sample.endMM = CGPoint(x: (bounds.maxX - inset) / pixelsPerMM,
                                   y: bounds.midY / pixelsPerMM)
            sample.draw(context: context, pixelsPerMM: pixelsPerMM)
            return
        }
        line.draw(context: context, pixelsPerMM: pixelsPerMM)
        if showsHandles {
            NSColor.systemBlue.setFill()
            for p in [point(line.startMM), point(line.endMM)] {
                CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
        window?.makeFirstResponder(self)
        dragOrigin = convert(event.locationInWindow, from: nil)
        original = line
        let a = point(line.startMM), b = point(line.endMM)
        dragPart = hypot(dragOrigin.x - a.x, dragOrigin.y - a.y) <= 8 ? 1 :
            (hypot(dragOrigin.x - b.x, dragOrigin.y - b.y) <= 8 ? 2 : 0)
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let width = bounds.width / pixelsPerMM, height = bounds.height / pixelsPerMM
        var changed = original
        if dragPart == 0 {
            let dx = max(-min(original.startMM.x, original.endMM.x),
                         min((p.x - dragOrigin.x) / pixelsPerMM, width - max(original.startMM.x, original.endMM.x)))
            let dy = max(-min(original.startMM.y, original.endMM.y),
                         min((p.y - dragOrigin.y) / pixelsPerMM, height - max(original.startMM.y, original.endMM.y)))
            changed.startMM.x += dx
            changed.endMM.x += dx
            changed.startMM.y += dy
            changed.endMM.y += dy
        } else {
            let endpoint = CGPoint(x: max(0, min(width, p.x / pixelsPerMM)),
                                   y: max(0, min(height, p.y / pixelsPerMM)))
            if dragPart == 1 { changed.startMM = endpoint } else { changed.endMM = endpoint }
        }
        if RulerImageView.canvas(for: self)?.snapsToGrid == true {
            if dragPart == 0 {
                let dx = max(-min(original.startMM.x, original.endMM.x),
                             min(changed.startMM.x.rounded() - original.startMM.x,
                                 width - max(original.startMM.x, original.endMM.x)))
                let dy = max(-min(original.startMM.y, original.endMM.y),
                             min(changed.startMM.y.rounded() - original.startMM.y,
                                 height - max(original.startMM.y, original.endMM.y)))
                changed.startMM = CGPoint(x: original.startMM.x + dx, y: original.startMM.y + dy)
                changed.endMM = CGPoint(x: original.endMM.x + dx, y: original.endMM.y + dy)
            } else {
                let point = dragPart == 1 ? changed.startMM : changed.endMM
                let snapped = CGPoint(x: max(0, min(width, point.x.rounded())),
                                      y: max(0, min(height, point.y.rounded())))
                if dragPart == 1 { changed.startMM = snapped } else { changed.endMM = snapped }
            }
        }
        if (try? changed.validate()) != nil { line = changed }
    }

    override func mouseUp(with event: NSEvent) { NSCursor.arrow.set() }

    override func menu(for event: NSEvent) -> NSMenu? {
        onSelect?()
        let menu = NSMenu()
        let item = NSMenuItem(title: "Delete Line", action: #selector(deleteLine), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    override func keyDown(with event: NSEvent) {
        if RulerImageView.canvas(for: self)?.moveSelection(with: event) == true { return }
        if event.keyCode == 51 || event.keyCode == 117 { onDelete?() }
        else { super.keyDown(with: event) }
    }

    @objc private func deleteLine() { onDelete?() }

    func printDrawing() -> (NSView) -> Void {
        let snapshot = line
        let scale = pixelsPerMM
        return { _ in
            if let context = NSGraphicsContext.current?.cgContext {
                snapshot.draw(context: context, pixelsPerMM: scale)
            }
        }
    }
}
