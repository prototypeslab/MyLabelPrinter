
import Cocoa
import CoreText
import ImageIO


private struct SavedLabel: Codable {
    var format = "MyLabelPrinter"
    var version = 1
    var sizeMM: CGSize
    var items: [SavedLabelItem]
    var outlineShape: LabelOutlineShape?
    var labelTypeName: String?

    func validate() throws {
        guard format == "MyLabelPrinter", version == 1 else {
            throw LabelFileError.unsupportedFormat
        }
        func dimension(_ value: CGFloat) -> Bool {
            value.isFinite && value > 0 && value <= 1000
        }
        guard dimension(sizeMM.width), dimension(sizeMM.height), items.count <= 1000 else {
            throw LabelFileError.invalidContent
        }
        for item in items {
            if item.kind == .line {
                guard let line = item.line else { throw LabelFileError.invalidContent }
                try line.validate()
            }
            if item.kind == .frame {
                guard let configuration = item.frameConfiguration else { throw LabelFileError.invalidContent }
                try configuration.validate(sizeMM: item.rectMM.size)
            }
            if item.kind == .shape {
                guard let shape = item.shapeConfiguration else { throw LabelFileError.invalidContent }
                try shape.validate(sizeMM: item.rectMM.size)
            }
            let rect = item.rectMM
            guard dimension(rect.width), dimension(rect.height),
                  rect.minX.isFinite, rect.minY.isFinite,
                  abs(rect.minX) <= 10000, abs(rect.minY) <= 10000 else {
                throw LabelFileError.invalidContent
            }
            if let size = item.fontSize, !dimension(size) { throw LabelFileError.invalidContent }
            if let textAppearance = item.textAppearance, !textAppearance.isValid { throw LabelFileError.invalidContent }
            if let quietZone = item.quietZone,
               !quietZone.isFinite || quietZone < 0 || quietZone > 1000 {
                throw LabelFileError.invalidContent
            }
        }
    }
}

private struct SavedLabelItem: Codable {
    enum Kind: String, Codable { case text, qr, barcode, line, frame, image, shape }
    var kind: Kind
    var value: String
    var rectMM: CGRect
    var fontName: String?
    var fontSize: CGFloat?
    var automaticallyFitsFont: Bool?
    var databaseField: String?
    var horizontalAlignment: LabelHorizontalAlignment?
    var verticalAlignment: LabelVerticalAlignment?
    var textAppearance: TextAppearance?
    var quietZone: CGFloat?
    var barcodeFormat: BarcodeFormat?
    var showsBarcodeData: Bool?
    var amazonDetails: AmazonLabelDetails?
    var line: LabelLine?
    var frameConfiguration: LabelFrame?
    var imageData: Data?
    var imageContentKind: ImageContentKind?
    var shapeConfiguration: LabelShape?
}

private enum LabelFileError: LocalizedError {
    case unsupportedFormat, invalidContent

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "This file is not a supported MyLabelPrinter label."
        case .invalidContent:
            return "The label file contains invalid dimensions or objects."
        }
    }
}

public enum RulerUnit {
    case inches
    case millimeters
}
public enum LabelOutlineShape: String, Codable {
    case rectangle
    case round
}


enum LabelHorizontalAlignment: String, Codable, CaseIterable {
    case left, center, right, justified
    var appKit: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .justified: return .justified
        }
    }
}
enum LabelVerticalAlignment: String, Codable, CaseIterable { case top, center, bottom }

private final class CenteredLabelTextCell: NSTextFieldCell {
    var textAppearance = TextAppearance()
    var textScale: CGFloat = 1
    var horizontal: LabelHorizontalAlignment = .center
    var vertical: LabelVerticalAlignment = .center
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        StyledTextDrawing.draw(attributedStringValue, in: cellFrame, flipped: controlView.isFlipped,
                               horizontal: horizontal, vertical: vertical, textAppearance: textAppearance, scale: textScale)
    }
}

final class LabelBoxView: NSView, NSTextFieldDelegate {
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if RulerImageView.canvas(for: self)?.moveSelection(with: event) == true { return }
        super.keyDown(with: event)
    }

    enum Hit: Int { case none, move, tl, tr, bl, br, left, right, top, bottom }

    private let textField = NSTextField()
    var databaseField: String?
    var textAppearance = TextAppearance.remembered { didSet { needsLayout = true; needsDisplay = true } }
    var textScale: CGFloat = 1 { didSet { needsLayout = true } }
    var horizontalAlignment = LabelHorizontalAlignment(rawValue: UserDefaults.standard.string(forKey: "textHorizontalAlignment") ?? "") ?? .center {
        didSet { needsLayout = true; needsDisplay = true }
    }
    var verticalAlignment = LabelVerticalAlignment(rawValue: UserDefaults.standard.string(forKey: "textVerticalAlignment") ?? "") ?? .center {
        didSet { needsLayout = true; needsDisplay = true }
    }
    private var automaticallyFitsFont = true
    private var isEditingText = false
    private var hasActiveTextEditor: Bool {
        isEditingText || textField.currentEditor() != nil
    }

    var inspectorFont: NSFont { textField.font ?? .systemFont(ofSize: 12) }
    var fitsFontAutomatically: Bool { automaticallyFitsFont }
    func setAutomaticFontFit(_ enabled: Bool) {
        automaticallyFitsFont = enabled
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
    func rescaleManualFont(by factor: CGFloat) {
        if !automaticallyFitsFont {
            setFont(name: inspectorFont.fontName, size: inspectorFont.pointSize * factor)
        }
    }
    var rectMM: CGRect = .zero
    var onDelete: (() -> Void)?
    public var minSize: NSSize = NSSize(width: 40, height: 24)
    var showsBorder: Bool = true {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    private var dragStartPoint: NSPoint = .zero
    private var originalFrame: NSRect = .zero
    private var hit: Hit = .none
    private let handle: CGFloat = 12
    var onFrameChanged: ((NSRect) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderColor = NSColor.clear.cgColor

        wantsLayer = true
        clipsToBounds = true
        layer?.masksToBounds = true

        textField.cell = CenteredLabelTextCell(textCell: "")
        textField.isBordered = false
        textField.drawsBackground = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.delegate = self
        textField.alignment = .center
        textField.textColor = .black
        textField.cell?.wraps = false
        textField.cell?.usesSingleLineMode = true
        textField.font = .systemFont(ofSize: 32, weight: .regular)
        textField.stringValue = "LABEL"
        addSubview(textField)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let padding = bounds.height * 0.08
        let available = bounds.insetBy(dx: padding, dy: padding)
        if automaticallyFitsFont {
            fitFont(in: available.size)
        }
        textField.frame = available
        textField.alignment = horizontalAlignment.appKit
        if let cell = textField.cell as? CenteredLabelTextCell {
            cell.horizontal = horizontalAlignment
            cell.vertical = verticalAlignment
            cell.textAppearance = textAppearance
            cell.textScale = textScale
        }
        textField.needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    public var text: String {
        get { textField.stringValue }
        set {
            textField.stringValue = newValue
            needsLayout = true
        }
    }

    private func fitFont(in size: NSSize) {
        guard size.width > 0, size.height > 0 else { return }
        let descriptor = inspectorFont.fontDescriptor
        var lower: CGFloat = 0.1
        var upper = max(1, size.height * 2)
        for _ in 0..<20 {
            let candidate = (lower + upper) / 2
            textField.font = NSFont(descriptor: descriptor, size: candidate)
            let layoutSize = textAppearance.isVertical ? CGSize(width: size.height, height: size.width) : size
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = textAppearance.lineSpacing * textScale
            let sample = NSAttributedString(string: text, attributes: [
                .font: textField.font ?? .systemFont(ofSize: candidate),
                .kern: textAppearance.characterSpacing * textScale,
                .paragraphStyle: paragraph
            ])
            let measured = sample.boundingRect(with: CGSize(width: layoutSize.width, height: 100000),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading]).size
            if measured.height <= layoutSize.height && measured.width <= layoutSize.width {
                lower = candidate
            } else {
                upper = candidate
            }
        }
        textField.font = NSFont(descriptor: descriptor, size: lower)
    }

    func fittedSize(height: CGFloat, maximumWidth: CGFloat) -> NSSize {
        let padding = height * 0.08
        fitFont(in: NSSize(width: max(0.1, maximumWidth - padding * 2),
                          height: height - padding * 2))
        let width = (textField.cell?.cellSize.width ?? 0) + padding * 2
        return NSSize(width: min(maximumWidth, ceil(width)), height: height)
    }

    public func setFont(name: String?, size: CGFloat) {
        automaticallyFitsFont = false
        if let n = name, let f = NSFont(name: n, size: size) {
            textField.font = f
        } else {
            textField.font = .systemFont(ofSize: size)
        }
        needsLayout = true
        needsDisplay = true
        layoutSubtreeIfNeeded()
    }

    fileprivate func savedItem(scale: CGFloat) -> SavedLabelItem {
        layoutSubtreeIfNeeded()
        return SavedLabelItem(kind: .text, value: text, rectMM: rectMM,
                       fontName: inspectorFont.fontName,
                       fontSize: inspectorFont.pointSize / scale,
                       automaticallyFitsFont: automaticallyFitsFont, databaseField: databaseField,
                       horizontalAlignment: horizontalAlignment, verticalAlignment: verticalAlignment,
                       textAppearance: textAppearance)
    }

    func printDrawing() throws -> (NSView) -> Void {
        layoutSubtreeIfNeeded()
        let printedText = textField.stringValue
        let printedFont = textField.font ?? .systemFont(ofSize: 12)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textField.alignment
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: printedFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        let horizontal = horizontalAlignment, vertical = verticalAlignment
        let textAppearance = textAppearance, scale = textScale
        let attributedText = NSAttributedString(string: printedText, attributes: attributes)
        let textRect = textField.frame.offsetBy(dx: frame.minX, dy: frame.minY)
        let clipRect = bounds.offsetBy(dx: frame.minX, dy: frame.minY)
        return { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSBezierPath(rect: clipRect).addClip()
            StyledTextDrawing.draw(attributedText, in: textRect, flipped: false,
                                   horizontal: horizontal, vertical: vertical, textAppearance: textAppearance, scale: scale)
        }
    }

    private var handleRects: [(hit: Hit, rect: NSRect)] {
        let size = min(handle, bounds.width / 3, bounds.height / 3)
        return [
            (.tl, NSRect(x: bounds.minX, y: bounds.maxY - size, width: size, height: size)),
            (.tr, NSRect(x: bounds.maxX - size, y: bounds.maxY - size, width: size, height: size)),
            (.bl, NSRect(x: bounds.minX, y: bounds.minY, width: size, height: size)),
            (.br, NSRect(x: bounds.maxX - size, y: bounds.minY, width: size, height: size)),
            (.left, NSRect(x: bounds.minX, y: bounds.midY - size / 2, width: size, height: size)),
            (.right, NSRect(x: bounds.maxX - size, y: bounds.midY - size / 2, width: size, height: size)),
            (.top, NSRect(x: bounds.midX - size / 2, y: bounds.maxY - size, width: size, height: size)),
            (.bottom, NSRect(x: bounds.midX - size / 2, y: bounds.minY, width: size, height: size))
        ]
    }

    private func hitTestHandle(_ point: NSPoint) -> Hit {
        guard showsBorder, bounds.contains(point) else { return .none }
        return handleRects.first { $0.rect.contains(point) }?.hit ?? .move
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }

        if showsBorder, handleRects.contains(where: { $0.rect.contains(localPoint) }) { return self }
        if hasActiveTextEditor, textField.frame.contains(localPoint) {
            return textField.hitTest(localPoint) ?? textField
        }

        return self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard showsBorder else { return }
        var moveRects = [bounds]
        let excludedRects = (hasActiveTextEditor ? [textField.frame] : []) + handleRects.map({ $0.rect })
        for excluded in excludedRects {
            moveRects = moveRects.flatMap { rect -> [NSRect] in
                let cut = rect.intersection(excluded)
                guard !cut.isEmpty else { return [rect] }
                return [
                    NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: cut.minY - rect.minY),
                    NSRect(x: rect.minX, y: cut.maxY, width: rect.width, height: rect.maxY - cut.maxY),
                    NSRect(x: rect.minX, y: cut.minY, width: cut.minX - rect.minX, height: cut.height),
                    NSRect(x: cut.maxX, y: cut.minY, width: rect.maxX - cut.maxX, height: cut.height)
                ].filter { !$0.isEmpty }
            }
        }
        for rect in moveRects {
            let visible = rect.intersection(visibleRect)
            if !visible.isEmpty { addCursorRect(visible, cursor: .openHand) }
        }
        for (_, rect) in handleRects {
            let visible = rect.intersection(visibleRect)
            if !visible.isEmpty { addCursorRect(visible, cursor: .arrow) }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsBorder else { return }
        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
        for (_, rect) in handleRects {
            let outline = NSBezierPath(rect: rect.insetBy(dx: 0.75, dy: 0.75))
            NSColor.systemBlue.setStroke()
            outline.lineWidth = 1.5
            outline.stroke()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let deleteItem = NSMenuItem(title: "Delete Label", action: #selector(deleteLabel), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        return menu
    }

    @objc private func deleteLabel() {
        onDelete?()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let overHandle = showsBorder && handleRects.contains(where: { $0.rect.contains(point) })
        if !overHandle, event.clickCount == 2, textField.frame.contains(point) {
            isEditingText = true
            window?.invalidateCursorRects(for: self)
            window?.makeFirstResponder(textField)
            textField.selectText(nil)
            return
        }
        if !overHandle, hasActiveTextEditor, textField.frame.contains(point) {
            textField.mouseDown(with: event)
            return
        }
        if hasActiveTextEditor {
            window?.makeFirstResponder(nil)
        } else {
            window?.makeFirstResponder(self)
        }
        dragStartPoint = superview?.convert(event.locationInWindow, from: nil) ?? .zero
        originalFrame = frame
        hit = hitTestHandle(convert(event.locationInWindow, from: nil))
        if hit == .none { hit = .move }
        if hit == .move { NSCursor.closedHand.set() }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        isEditingText = false
        window?.invalidateCursorRects(for: self)
    }

    fileprivate func containsEditingText(atWindowPoint point: NSPoint) -> Bool {
        guard hasActiveTextEditor else { return false }
        return textField.frame.contains(convert(point, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let wasMoving = hit == .move
        hit = .none
        window?.invalidateCursorRects(for: self)
        let point = convert(event.locationInWindow, from: nil)
        if wasMoving, bounds.contains(point),
           !handleRects.contains(where: { $0.rect.contains(point) }) {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if hit == .move { NSCursor.closedHand.set() }
        let p = superview?.convert(event.locationInWindow, from: nil) ?? .zero
        let dx = p.x - dragStartPoint.x
        let dy = p.y - dragStartPoint.y
        var f = originalFrame
        switch hit {
        case .move:
            f.origin.x += dx
            f.origin.y += dy
        case .tl:
            f.origin.x += dx
            f.size.width -= dx
            f.size.height += dy
        case .tr:
            f.size.width += dx
            f.size.height += dy
        case .bl:
            f.origin.x += dx
            f.origin.y += dy
            f.size.width -= dx
            f.size.height -= dy
        case .br:
            f.size.width += dx
            f.size.height -= dy
        case .left:
            f.origin.x = min(originalFrame.maxX - minSize.width, originalFrame.minX + dx)
            f.size.width = originalFrame.maxX - f.minX
        case .right:
            f.size.width += dx
        case .top:
            f.size.height += dy
        case .bottom:
            f.origin.y = min(originalFrame.maxY - minSize.height, originalFrame.minY + dy)
            f.size.height = originalFrame.maxY - f.minY
        case .none:
            break
        }
        f.size.width = max(minSize.width, f.size.width)
        f.size.height = max(minSize.height, f.size.height)
        if let s = superview {
            f.origin.x = max(0, min(f.origin.x, s.bounds.width - f.width))
            f.origin.y = max(0, min(f.origin.y, s.bounds.height - f.height))
        }
        f = RulerImageView.snapDrag(f, original: originalFrame, minimum: minSize, view: self)
        let oldFrame = frame
        frame = f
        needsLayout = true
        window?.invalidateCursorRects(for: self)
        onFrameChanged?(f)
        needsDisplay = true
        superview?.setNeedsDisplay(oldFrame.union(f))
    }
}
final class CodeBoxView: NSView {
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if RulerImageView.canvas(for: self)?.moveSelection(with: event) == true { return }
        super.keyDown(with: event)
    }

    typealias CodeType = BarcodeFormat
    enum Hit { case none, move, tl, tr, bl, br, left, right, top, bottom }

    var code: String = "" { didSet { artwork = nil; needsLayout = true } }
    var type: CodeType = .qr { didSet { artwork = nil; needsLayout = true } }
    var artwork: BarcodeArtwork?
    var showsData = true { didSet { needsLayout = true } }
    var amazonDetails: AmazonLabelDetails? { didSet { needsLayout = true } }
    var rectMM: CGRect = .zero
    var onDelete: (() -> Void)?
    private let borderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    var quietZone: CGFloat = 4 // inner margin
    var onFrameChanged: ((NSRect) -> Void)?
    var showsBorder: Bool = true {
        didSet {
            updateSelectionAppearance()
            window?.invalidateCursorRects(for: self)
        }
    }
    private let imageView = NSImageView()
    private let captionField = NSTextField(labelWithString: "")
    private var dragStart: NSPoint = .zero
    private var originalFrame: NSRect = .zero
    private var hit: Hit = .none
    private let handle: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignCenter
        addSubview(imageView)
        captionField.alignment = .center
        captionField.textColor = .black
        captionField.drawsBackground = false
        captionField.isSelectable = false
        captionField.cell?.wraps = false
        captionField.cell?.usesSingleLineMode = true
        captionField.lineBreakMode = .byClipping
        addSubview(captionField)
        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.systemBlue.cgColor
        borderLayer.lineWidth = 1
        borderLayer.zPosition = 1000
        handlesLayer.fillColor = nil
        handlesLayer.strokeColor = NSColor.systemBlue.cgColor
        handlesLayer.lineWidth = 1.5
        handlesLayer.zPosition = 1001
        layer?.addSublayer(borderLayer)
        layer?.addSublayer(handlesLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        imageView.frame = barcodeImageRect
        captionField.isHidden = !showsData || type == .amazonFNSKU
        captionField.stringValue = code
        if showsData {
            let available = captionRect
            var lower: CGFloat = 0.1
            var upper = max(1, available.height * 2)
            for _ in 0..<20 {
                let size = (lower + upper) / 2
                captionField.font = .monospacedSystemFont(ofSize: size, weight: .regular)
                let measured = captionField.cell?.cellSize ?? .zero
                if measured.width <= available.width && measured.height <= available.height {
                    lower = size
                } else {
                    upper = size
                }
            }
            captionField.font = .monospacedSystemFont(ofSize: lower, weight: .regular)
            let height = min(available.height, captionField.cell?.cellSize.height ?? available.height)
            captionField.frame = NSRect(x: available.minX, y: available.midY - height / 2,
                                       width: available.width, height: height)
        }
        regenerateImage()
        updateSelectionAppearance()
        window?.invalidateCursorRects(for: self)
    }

    private var captionRect: NSRect {
        let area = bounds.insetBy(dx: quietZone, dy: quietZone)
        return NSRect(x: area.minX, y: area.minY,
                      width: max(0, area.width), height: max(0, area.height * 0.22))
    }

    private var barcodeImageRect: NSRect {
        let area = bounds.insetBy(dx: quietZone, dy: quietZone)
        guard showsData, type != .amazonFNSKU else { return area }
        let reservedHeight = captionRect.height + max(0, area.height * 0.04)
        return NSRect(x: area.minX, y: area.minY + reservedHeight,
                      width: area.width, height: max(0, area.height - reservedHeight))
    }

    private func barcodeArtwork() throws -> BarcodeArtwork {
        if let artwork { return artwork }
        let generated = try BarcodeGenerator.shared.generate(code, format: type)
        artwork = generated
        return generated
    }

    private func regenerateImage() {
        let size = imageView.bounds.size
        guard size.width > 4, size.height > 4 else { imageView.image = nil; return }
        if type == .amazonFNSKU, let details = amazonDetails, let artwork = try? barcodeArtwork() {
            imageView.image = details.image(fnsku: code, artwork: artwork, size: size, showsData: showsData)
        } else {
            imageView.image = (try? barcodeArtwork())?.image(size: size)
        }
    }

    func printDrawing() throws -> (NSView) -> Void {
        layoutSubtreeIfNeeded()
        let artwork = try barcodeArtwork()
        let area = barcodeImageRect.offsetBy(dx: frame.minX, dy: frame.minY)
        guard area.width > 0, area.height > 0 else {
            throw BarcodeError("A barcode box is too small to print. Enlarge it and try again.")
        }
        if type == .amazonFNSKU {
            guard let details = amazonDetails else { throw BarcodeError("Missing Amazon label details.") }
            let validated = try details.validated()
            let fnsku = code
            let showData = showsData
            let background = bounds.offsetBy(dx: frame.minX, dy: frame.minY)
            return { _ in
                NSColor.white.setFill()
                background.fill()
                validated.draw(fnsku: fnsku, artwork: artwork, in: area, showsData: showData)
            }
        }
        let caption = showsData ? captionField.cell?.copy() as? NSTextFieldCell : nil
        let captionFrame = captionField.frame.offsetBy(dx: frame.minX, dy: frame.minY)
        let background = bounds.offsetBy(dx: frame.minX, dy: frame.minY)
        return { view in
            NSColor.white.setFill()
            background.fill()
            if let context = NSGraphicsContext.current?.cgContext {
                artwork.draw(in: area, context: context)
            }
            caption?.draw(withFrame: captionFrame, in: view)
        }
    }

    private var handleRects: [(hit: Hit, rect: NSRect)] {
        let size = min(handle, bounds.width / 3, bounds.height / 3)
        return [
            (.tl, NSRect(x: bounds.minX, y: bounds.maxY - size, width: size, height: size)),
            (.tr, NSRect(x: bounds.maxX - size, y: bounds.maxY - size, width: size, height: size)),
            (.bl, NSRect(x: bounds.minX, y: bounds.minY, width: size, height: size)),
            (.br, NSRect(x: bounds.maxX - size, y: bounds.minY, width: size, height: size)),
            (.left, NSRect(x: bounds.minX, y: bounds.midY - size / 2, width: size, height: size)),
            (.right, NSRect(x: bounds.maxX - size, y: bounds.midY - size / 2, width: size, height: size)),
            (.top, NSRect(x: bounds.midX - size / 2, y: bounds.maxY - size, width: size, height: size)),
            (.bottom, NSRect(x: bounds.midX - size / 2, y: bounds.minY, width: size, height: size))
        ]
    }

    private func hitTestHandle(_ point: NSPoint) -> Hit {
        guard showsBorder, bounds.contains(point) else { return .none }
        return handleRects.first { $0.rect.contains(point) }?.hit ?? .move
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    private func updateSelectionAppearance() {
        borderLayer.frame = bounds
        handlesLayer.frame = bounds
        borderLayer.isHidden = !showsBorder
        handlesLayer.isHidden = !showsBorder
        borderLayer.path = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).cgPath
        let path = NSBezierPath()
        for (_, rect) in handleRects { path.appendRect(rect.insetBy(dx: 0.75, dy: 0.75)) }
        handlesLayer.path = path.cgPath
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard showsBorder else { return }
        let size = min(handle, bounds.width / 2, bounds.height / 2)
        let moveRects = [
            bounds.insetBy(dx: size, dy: 0),
            NSRect(x: bounds.minX, y: bounds.minY + size, width: size, height: bounds.height - 2 * size),
            NSRect(x: bounds.maxX - size, y: bounds.minY + size, width: size, height: bounds.height - 2 * size)
        ]
        for rect in moveRects {
            let visible = rect.intersection(visibleRect)
            if !visible.isEmpty { addCursorRect(visible, cursor: .openHand) }
        }
        for (_, rect) in handleRects {
            let visible = rect.intersection(visibleRect)
            if !visible.isEmpty { addCursorRect(visible, cursor: .arrow) }
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let title = type == .qr ? "Delete QR Code" : "Delete Barcode"
        let item = NSMenuItem(title: title, action: #selector(deleteCode), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func deleteCode() { onDelete?() }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragStart = superview?.convert(event.locationInWindow, from: nil) ?? .zero
        originalFrame = frame
        hit = hitTestHandle(convert(event.locationInWindow, from: nil))
        if hit == .none { hit = .move }
        if hit == .move { NSCursor.closedHand.set() }
    }

    override func mouseDragged(with event: NSEvent) {
        if hit == .move { NSCursor.closedHand.set() }
        let point = superview?.convert(event.locationInWindow, from: nil) ?? .zero
        let dx = point.x - dragStart.x
        let dy = point.y - dragStart.y
        var f = originalFrame
        switch hit {
        case .move: f.origin.x += dx; f.origin.y += dy
        case .tl: f.origin.x += dx; f.size.width -= dx; f.size.height += dy
        case .tr: f.size.width += dx; f.size.height += dy
        case .bl: f.origin.x += dx; f.origin.y += dy; f.size.width -= dx; f.size.height -= dy
        case .br: f.size.width += dx; f.size.height -= dy
        case .left:
            f.origin.x = min(originalFrame.maxX - max(24, quietZone * 2 + 5), originalFrame.minX + dx)
            f.size.width = originalFrame.maxX - f.minX
        case .right: f.size.width += dx
        case .top: f.size.height += dy
        case .bottom:
            f.origin.y = min(originalFrame.maxY - max(24, quietZone * 2 + 5), originalFrame.minY + dy)
            f.size.height = originalFrame.maxY - f.minY
        case .none: break
        }
        let minimum = max(24, quietZone * 2 + 5)
        f.size.width = max(minimum, f.width)
        f.size.height = max(minimum, f.height)
        if let parent = superview {
            f.origin.x = max(0, min(f.minX, parent.bounds.width - f.width))
            f.origin.y = max(0, min(f.minY, parent.bounds.height - f.height))
        }
        f = RulerImageView.snapDrag(f, original: originalFrame,
                                    minimum: CGSize(width: minimum, height: minimum), view: self)
        frame = f
        needsLayout = true
        window?.invalidateCursorRects(for: self)
        onFrameChanged?(f)
    }

    override func mouseUp(with event: NSEvent) {
        hit = .none
        window?.invalidateCursorRects(for: self)
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point), !handleRects.contains(where: { $0.rect.contains(point) }) {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}
extension RulerImageView {
    private func pxPerMMCurrent() -> CGFloat {
        let dpi: CGFloat = self.dpi > 0 ? self.dpi : 72
        return (dpi / 25.4) * contentScale
    }
    private func mmRectToPx(_ r: CGRect) -> CGRect {
        let s = pxPerMMCurrent()
        return CGRect(x: r.origin.x * s, y: r.origin.y * s, width: r.size.width * s, height: r.size.height * s)
    }
    private func pxRectToMM(_ r: CGRect) -> CGRect {
        let s = pxPerMMCurrent()
        guard s > 0 else { return .zero }
        return CGRect(x: r.origin.x / s, y: r.origin.y / s, width: r.size.width / s, height: r.size.height / s)
    }

    public func addDemoLabel(text: String = "Text") {
        guard imageView.bounds.width > 0, imageView.bounds.height > 0 else { return }
        let box = LabelBoxView(frame: .zero)
        box.textScale = contentScale
        box.text = text
        let area = imageView.bounds
        let size = box.fittedSize(height: area.height / 2, maximumWidth: area.width)
        box.frame = NSRect(x: area.midX - size.width / 2,
                           y: area.midY - size.height / 2,
                           width: size.width, height: size.height)
        box.rectMM = pxRectToMM(box.frame)
        if let name = UserDefaults.standard.string(forKey: "textFontName") {
            let size = UserDefaults.standard.double(forKey: "textFontSize")
            if size.isFinite, size > 0, size <= 1000 {
                box.setFont(name: name, size: CGFloat(size) * contentScale)
            }
        }
        if let automaticallyFitsFont = UserDefaults.standard.object(forKey: "textFitsFontAutomatically") as? Bool {
            box.setAutomaticFontFit(automaticallyFitsFont)
        }
        textLabels.append(box)
        imageView.addSubview(box)
        box.onFrameChanged = { [weak self, weak box] frame in
            guard let self, let box else { return }
            box.rectMM = self.pxRectToMM(frame)
        }
        box.onDelete = { [weak self, weak box] in
            guard let self, let box else { return }
            self.deleteTextLabel(box)
        }
        selectEditorItem(box)
        box.needsLayout = true
        box.layoutSubtreeIfNeeded()
    }

    enum ObjectOrder: Int, CaseIterable {
        case back, backward, forward, front

        var title: String {
            switch self {
            case .back: return "Move To Back"
            case .backward: return "Move One Step Back"
            case .forward: return "Move One Step To Front"
            case .front: return "Move To Front"
            }
        }
    }

    func changeSelectedObjectOrder(_ order: ObjectOrder) {
        guard let selectedItem,
              let index = imageView.subviews.firstIndex(where: { $0 === selectedItem }) else { return }
        var objects = imageView.subviews
        let destination: Int
        switch order {
        case .back: destination = 0
        case .backward: destination = max(0, index - 1)
        case .forward: destination = min(objects.count - 1, index + 1)
        case .front: destination = objects.count - 1
        }
        guard destination != index else { return }
        window?.makeFirstResponder(self)
        objects.remove(at: index)
        objects.insert(selectedItem, at: destination)
        imageView.subviews = objects
        imageView.needsDisplay = true
    }

    private func selectEditorItem(_ selected: NSView?) {
        let selectionChanged = selectedItem !== selected
        if selectedItem !== selected {
            window?.makeFirstResponder(self)
        }
        for line in lineItems { line.showsHandles = line === selected }
        for frame in frameItems { frame.showsHandles = frame === selected }
        selectedItem = selected
        labelBox = selected as? LabelBoxView
        for box in textLabels {
            box.showsBorder = box === selected
        }
        for box in codeBoxes {
            box.showsBorder = box === selected
        }
        if selectionChanged { onSelectionChanged?(selected) }
    }

    private func deleteTextLabel(_ box: LabelBoxView) {
        if labelBox === box {
            selectEditorItem(nil)
        }
        textLabels.removeAll { $0 === box }
        box.removeFromSuperview()
    }

    private func updateTextLabelFrames() {
        for box in textLabels {
            box.textScale = contentScale
            let newFrame = mmRectToPx(box.rectMM)
            if box.frame.width > 0 { box.rescaleManualFont(by: newFrame.width / box.frame.width) }
            box.frame = newFrame
            box.needsLayout = true
            box.layoutSubtreeIfNeeded()
        }
    }

    func addAddressTemplate() {
        let rows = ["Full Name", "Address", "City, State and Zip", "Country"]
        let margin: CGFloat = 2
        let rowHeight = (labelSizeMM.height - margin * 2) / CGFloat(rows.count)
        let width = labelSizeMM.width - margin * 2
        guard rowHeight > 0, width > 0 else { return }
        let fontScale = min(labelSizeMM.width / 88.9, labelSizeMM.height / 28.6)
        var firstBox: LabelBoxView?
        for (rowIndex, field) in rows.enumerated() {
            addDemoLabel(text: field)
            guard let box = labelBox else { continue }
            let rect = CGRect(x: margin,
                              y: labelSizeMM.height - margin - CGFloat(rowIndex + 1) * rowHeight,
                              width: width, height: rowHeight)
            applyInspectorRect(rect, to: box)
            box.setFont(name: rowIndex == 0 ? "Helvetica-Bold" : "Helvetica",
                        size: (rowIndex == 0 ? 12 : 10) * fontScale * contentScale)
            if firstBox == nil { firstBox = box }
        }
        selectEditorItem(firstBox)
        onSelectionChanged?(firstBox)
    }

    public func configureLabel(text: String, fontName: String? = nil, fontSize: CGFloat = 24) {
        if labelBox == nil { addDemoLabel(text:text) }
        labelBox?.text = text
        labelBox?.setFont(name: fontName, size: fontSize)
    }

    public func setLabelRectMM(_ rectMM: CGRect) {
        if labelBox == nil { addDemoLabel() }
        if let box = labelBox {
            box.rectMM = rectMM
            box.frame = mmRectToPx(rectMM)
            box.needsLayout = true
        }
    }
    
    var qrBox: CodeBoxView? {
        if let box = selectedItem as? CodeBoxView, box.type == .qr { return box }
        return codeBoxes.last { $0.type == .qr }
    }

    var barcodeBox: CodeBoxView? {
        if let box = selectedItem as? CodeBoxView, box.type != .qr { return box }
        return codeBoxes.last { $0.type != .qr }
    }

    public func addDemoQR(_ text: String = "https://example.com") {
        addCodeBox(text: text, type: .qr)
    }

    public func addDemoBarcode(_ text: String = "X001ABCDEF") {
        addCodeBox(text: text, type: .code128)
    }

    func addBarcode(_ text: String, format: BarcodeFormat, amazonDetails: AmazonLabelDetails? = nil, showsData: Bool = true) throws {
        let details: AmazonLabelDetails?
        if format == .amazonFNSKU {
            guard let amazonDetails else { throw BarcodeError("Enter product name and condition.") }
            details = try amazonDetails.validated()
        } else {
            details = nil
        }
        let value = try format.validatedValue(text)
        let artwork = try BarcodeGenerator.shared.generate(value, format: format)
        guard imageView.bounds.width > 0, imageView.bounds.height > 0 else {
            throw BarcodeError("Set a label size before adding a barcode.")
        }
        addCodeBox(text: value, type: format, artwork: artwork, amazonDetails: details, showsData: showsData)
    }

    private func addCodeBox(text: String, type: CodeBoxView.CodeType, artwork: BarcodeArtwork? = nil, amazonDetails: AmazonLabelDetails? = nil, showsData: Bool? = nil) {
        guard imageView.bounds.width > 0, imageView.bounds.height > 0 else { return }
        let box = CodeBoxView(frame: .zero)
        box.type = type
        box.showsData = showsData ?? type.isLinear
        box.code = text
        box.artwork = artwork
        box.amazonDetails = amazonDetails
        let scale = pxPerMMCurrent()
        let width = min(type == .amazonFNSKU ? 60 : (type.isSquare ? 20 : 40), imageView.bounds.width / scale)
        let height = min(type == .amazonFNSKU ? 30 : 20, imageView.bounds.height / scale)
        let center = imageView.bounds.width / scale * (type == .qr ? 0.33 : 0.66)
        box.rectMM = CGRect(x: max(0, min(center - width / 2, imageView.bounds.width / scale - width)),
                            y: max(0, (imageView.bounds.height / scale - height) / 2),
                            width: width, height: height)
        box.frame = mmRectToPx(box.rectMM)
        codeBoxes.append(box)
        imageView.addSubview(box)
        box.onFrameChanged = { [weak self, weak box] frame in
            guard let self, let box else { return }
            box.rectMM = self.pxRectToMM(frame)
        }
        box.onDelete = { [weak self, weak box] in
            guard let self, let box else { return }
            if self.selectedItem === box { self.selectEditorItem(nil) }
            self.codeBoxes.removeAll { $0 === box }
            box.removeFromSuperview()
        }
        selectEditorItem(box)
        box.needsLayout = true
        box.layoutSubtreeIfNeeded()
    }

    private func updateCodeBoxFrames() {
        for box in codeBoxes {
            box.frame = mmRectToPx(box.rectMM)
            box.needsLayout = true
            box.layoutSubtreeIfNeeded()
        }
    }

    public func setQRRectMM(_ rectMM: CGRect, text: String) {
        if qrBox == nil { addDemoQR(text) }
        if let box = qrBox {
            box.code = text
            box.rectMM = rectMM
            box.frame = mmRectToPx(rectMM)
        }
    }

    public func setBarcodeRectMM(_ rectMM: CGRect, text: String) {
        if barcodeBox == nil { addDemoBarcode(text) }
        if let box = barcodeBox {
            box.code = text
            box.rectMM = rectMM
            box.frame = mmRectToPx(rectMM)
        }
    }
}


private final class CursorImageView: NSImageView {
    var gridSpacing: CGFloat = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard gridSpacing > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        NSColor(calibratedWhite: 0.65, alpha: 1).setFill()
        let diameter = min(2, max(1.2, gridSpacing * 0.3))
        let area = dirtyRect.intersection(bounds)
        guard !area.isEmpty else { return }
        let startX = max(gridSpacing, floor(area.minX / gridSpacing) * gridSpacing)
        let startY = max(gridSpacing, floor(area.minY / gridSpacing) * gridSpacing)
        for x in stride(from: startX, to: min(bounds.maxX, area.maxX + diameter), by: gridSpacing) {
            for y in stride(from: startY, to: min(bounds.maxY, area.maxY + diameter), by: gridSpacing) {
                NSBezierPath(ovalIn: CGRect(x: x - diameter / 2, y: y - diameter / 2,
                                           width: diameter, height: diameter)).fill()
            }
        }
    }

    var onMouseMoved: ((NSPoint) -> Void)?
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    private var tracking: NSTrackingArea?
    
    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let opts: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate]
        tracking = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }
    
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onMouseMoved?(p)
    }
    override func mouseEntered(with event: NSEvent) { onMouseEntered?() }
    override func mouseExited(with event: NSEvent)  { onMouseExited?() }
}
private final class LabelPrintView: NSView {
    private let editorScale: CGFloat
    private let drawings: [(NSView) -> Void]
    private let outputScale: CGFloat
    private let offset: NSPoint
    private let rotates180: Bool
    private let mirrorsHorizontally: Bool

    init(size: NSSize, editorScale: CGFloat, drawings: [(NSView) -> Void],
         outputScale: CGFloat, offset: NSPoint, rotates180: Bool, mirrorsHorizontally: Bool) {
        self.editorScale = editorScale
        self.drawings = drawings
        self.outputScale = outputScale
        self.offset = offset
        self.rotates180 = rotates180
        self.mirrorsHorizontally = mirrorsHorizontally
        super.init(frame: NSRect(origin: .zero, size: size))
    }

    required init?(coder: NSCoder) { nil }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: 1)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        page == 1 ? bounds : .zero
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        let transform = NSAffineTransform()
        transform.translateX(by: offset.x, yBy: offset.y)
        transform.translateX(by: bounds.midX, yBy: bounds.midY)
        if rotates180 { transform.rotate(byDegrees: 180) }
        transform.scaleX(by: mirrorsHorizontally ? -outputScale : outputScale, yBy: outputScale)
        transform.translateX(by: -bounds.midX, yBy: -bounds.midY)
        transform.scale(by: 1 / editorScale)
        transform.concat()
        for draw in drawings { draw(self) }
    }
}

public final class RulerImageView: NSView {
    var showsGrid = UserDefaults.standard.bool(forKey: "labelShowsGrid") {
        didSet {
            UserDefaults.standard.set(showsGrid, forKey: "labelShowsGrid")
            updateGrid()
        }
    }
    var snapsToGrid = UserDefaults.standard.bool(forKey: "labelSnapsToGrid") {
        didSet { UserDefaults.standard.set(snapsToGrid, forKey: "labelSnapsToGrid") }
    }
    private func updateGrid() {
        imageView.gridSpacing = showsGrid ? pxPerMMCurrent() : 0
    }

    static func canvas(for view: NSView) -> RulerImageView? {
        var ancestor: NSView? = view
        while let current = ancestor {
            if let ruler = current as? RulerImageView { return ruler }
            ancestor = current.superview
        }
        return nil
    }

    static func snapDrag(_ proposed: CGRect, original: CGRect, minimum: CGSize, view: NSView) -> CGRect {
        guard let ruler = canvas(for: view), ruler.snapsToGrid, let parent = view.superview else { return proposed }
        let step = ruler.pxPerMMCurrent()
        let isMoving = proposed.size == original.size
        func snap(_ value: CGFloat) -> CGFloat { (value / step).rounded() * step }
        func axis(_ low: CGFloat, _ high: CGFloat, _ oldLow: CGFloat, _ oldHigh: CGFloat,
                  _ minimum: CGFloat, _ maximum: CGFloat) -> (CGFloat, CGFloat) {
            if !isMoving, abs(low - oldLow) < 0.0001, abs(high - oldHigh) < 0.0001 { return (low, high) }
            if abs((high - low) - (oldHigh - oldLow)) < 0.0001 {
                let origin = max(0, min(maximum - (high - low), snap(low)))
                return (origin, origin + high - low)
            }
            if abs(low - oldLow) < 0.0001 {
                return (low, max(low + minimum, min(maximum, snap(high))))
            }
            return (max(0, min(high - minimum, snap(low))), high)
        }
        let x = axis(proposed.minX, proposed.maxX, original.minX, original.maxX, minimum.width, parent.bounds.width)
        let y = axis(proposed.minY, proposed.maxY, original.minY, original.maxY, minimum.height, parent.bounds.height)
        return CGRect(x: x.0, y: y.0, width: x.1 - x.0, height: y.1 - y.0)
    }

    public override var acceptsFirstResponder: Bool { true }

    @discardableResult
    func moveSelection(with event: NSEvent) -> Bool {
        guard (123...126).contains(event.keyCode), let selectedItem,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        if window?.firstResponder is NSTextView || window?.firstResponder is NSControl { return false }
        let direction: CGFloat = (event.keyCode == 123 || event.keyCode == 125) ? -1 : 1
        let horizontal = event.keyCode == 123 || event.keyCode == 124
        let step: CGFloat = (snapsToGrid ? 1 : 0.1) * (event.modifierFlags.contains(.shift) ? 10 : 1)
        func delta(_ coordinate: CGFloat) -> CGFloat {
            if snapsToGrid {
                return direction > 0
                    ? floor(coordinate + 0.000001) + step - coordinate
                    : ceil(coordinate - 0.000001) - step - coordinate
            }
            return direction * step
        }
        if let line = selectedItem as? LineItemView {
            var value = line.line
            let minX = min(value.startMM.x, value.endMM.x), maxX = max(value.startMM.x, value.endMM.x)
            let minY = min(value.startMM.y, value.endMM.y), maxY = max(value.startMM.y, value.endMM.y)
            let dx = horizontal ? max(-minX, min(labelSizeMM.width - maxX, delta(value.startMM.x))) : 0
            let dy = horizontal ? 0 : max(-minY, min(labelSizeMM.height - maxY, delta(value.startMM.y)))
            value.startMM.x += dx; value.endMM.x += dx
            value.startMM.y += dy; value.endMM.y += dy
            line.line = value
        } else {
            var rect = inspectorRect(for: selectedItem)
            if horizontal {
                rect.origin.x = max(0, min(max(0, labelSizeMM.width - rect.width), rect.minX + delta(rect.minX)))
            } else {
                rect.origin.y = max(0, min(max(0, labelSizeMM.height - rect.height), rect.minY + delta(rect.minY)))
            }
            applyInspectorRect(rect, to: selectedItem)
        }
        onSelectionChanged?(selectedItem)
        return true
    }

    public override func keyDown(with event: NSEvent) {
        if moveSelection(with: event) { return }
        guard event.keyCode == 51 || event.keyCode == 117 else {
            super.keyDown(with: event)
            return
        }

        if let textBox = selectedItem as? LabelBoxView {
            textBox.onDelete?()
        } else if let codeBox = selectedItem as? CodeBoxView {
            codeBox.onDelete?()
        } else if let frame = selectedItem as? FrameItemView {
            frame.onDelete?()
        } else if let line = selectedItem as? LineItemView {
            line.onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }


    public var showsCrosshair: Bool = true { didSet { updateCrosshairVisibility() } }
    private var mouseInsideImage: Bool = false
    private static let unitDefaultsKey = "labelEditorRulerUnit"
    public var unit: RulerUnit = {
        UserDefaults.standard.string(forKey: RulerImageView.unitDefaultsKey) == "in"
            ? .inches : .millimeters
    }() {
        didSet {
            UserDefaults.standard.set(unit == .millimeters ? "mm" : "in",
                                      forKey: Self.unitDefaultsKey)
            applyUnit()
            onUnitChanged?(unit)
        }
    }
    public var onUnitChanged: ((RulerUnit) -> Void)?
    public var labelShape: LabelOutlineShape = .rectangle {
        didSet { updateDocumentLayout() }
    }
    public var dpi: CGFloat = 72 { didSet { updateRulers() } }
    public var allowsMagnification: Bool {
        get { scrollView.allowsMagnification }
        set { scrollView.allowsMagnification = newValue }
    }
    public var magnification: CGFloat {
        get { scrollView.magnification }
        set { scrollView.magnification = max(0.05, min(newValue, 64)) }
    }
    public func showCrosshair() { showsCrosshair = true }
    public func hideCrosshair() { showsCrosshair = false }
    var showsBorder: Bool = true {
        didSet {
            layer?.borderWidth = showsBorder ? 1 : 0
            needsDisplay = true
        }
    }
    private let scrollView = NSScrollView()
    private let unitButton = NSButton(frame: .zero)
    private var textLabels: [LabelBoxView] = []
    private var codeBoxes: [CodeBoxView] = []
    private var lineItems: [LineItemView] = []
    private var frameItems: [FrameItemView] = []
    var labelSizeMM: CGSize { contentSizeMM }

    var maximumFrameSizeMM: CGSize {
        let radius = min(4, min(contentSizeMM.width, contentSizeMM.height) / 2)
        let inset = radius * (1 - 1 / sqrt(2.0)) + 0.1
        return CGSize(width: max(0, contentSizeMM.width - 2 * inset),
                      height: max(0, contentSizeMM.height - 2 * inset))
    }
    private weak var selectedItem: NSView?
    var onSelectionChanged: ((NSView?) -> Void)?
    var inspectorSelection: NSView? { selectedItem }

    func addInspectorDraft(_ draft: NSView, fontScale: CGFloat) throws {
        if let text = draft as? LabelBoxView {
            addDemoLabel(text: text.text)
            if let added = selectedItem as? LabelBoxView {
                added.databaseField = text.databaseField
                added.textAppearance = text.textAppearance
                added.horizontalAlignment = text.horizontalAlignment
                added.verticalAlignment = text.verticalAlignment
                applyInspectorRect(text.rectMM, to: added)
                if !text.fitsFontAutomatically {
                    added.setFont(name: text.inspectorFont.fontName,
                                  size: text.inspectorFont.pointSize / fontScale * contentScale)
                }
                added.setAutomaticFontFit(text.fitsFontAutomatically)
            }
        } else if let code = draft as? CodeBoxView {
            try addBarcode(code.code, format: code.type, amazonDetails: code.amazonDetails, showsData: code.showsData)
            if let added = selectedItem { applyInspectorRect(code.rectMM, to: added) }
        } else if let image = draft as? ImageItemView {
            let decoded = try ImageItemView.decode(image.imageData)
            insertImage(data: image.imageData, image: decoded, rectMM: image.rectMM,
                        contentKind: image.contentKind)
        } else if let shape = draft as? ShapeItemView {
            try shape.shape.validate(sizeMM: shape.rectMM.size)
            insertShape(shape.shape, rectMM: shape.rectMM)
        } else if let frame = draft as? FrameItemView {
            try frame.configuration.validate(sizeMM: frame.rectMM.size)
            insertFrame(frame.configuration, rectMM: frame.rectMM)
        } else if let line = draft as? LineItemView {
            try line.line.validate()
            insertLine(line.line)
        }
        onSelectionChanged?(selectedItem)
    }
    weak var inspectorInteractionView: NSView?
    var inspectorFontScale: CGFloat { contentScale }

    func applyDatabaseRecord(_ values: [String: String]) {
        for label in textLabels {
            guard let field = label.databaseField else { continue }
            label.text = values[field] ?? ""
        }
        imageView.needsDisplay = true
    }

    func hasDatabaseTextBinding(for fields: [String]) -> Bool {
        let available = Set(fields)
        return textLabels.contains { label in
            guard let field = label.databaseField else { return false }
            return available.contains(field)
        }
    }

    func clearDatabaseBindings(except fields: [String] = []) {
        let available = Set(fields)
        for label in textLabels {
            if let field = label.databaseField, available.contains(field) { continue }
            label.databaseField = nil
        }
        onSelectionChanged?(selectedItem)
    }

    func inspectorRect(for item: NSView) -> CGRect {
        if let text = item as? LabelBoxView { return text.rectMM }
        if let code = item as? CodeBoxView { return code.rectMM }
        if let frame = item as? FrameItemView { return frame.rectMM }
        return .zero
    }

    func applyInspectorRect(_ rect: CGRect, to item: NSView) {
        if let text = item as? LabelBoxView { text.rectMM = rect }
        if let code = item as? CodeBoxView { code.rectMM = rect }
        if let frame = item as? FrameItemView { frame.rectMM = rect }
        let previous = item.frame
        item.frame = mmRectToPx(rect)
        item.needsLayout = true
        item.needsDisplay = true
        item.layoutSubtreeIfNeeded()
        item.superview?.setNeedsDisplay(previous.union(item.frame))
    }
    private(set) weak var labelBox: LabelBoxView?
    private var selectionMonitor: Any?
    private let docView = NSView()
    private let labelBackground = NSView()
    private let labelShapeLayer = CAShapeLayer()
    private let imageView = CursorImageView()
    private let hRuler: MeasurementRulerView
    private let vRuler: MeasurementRulerView
    public var resizeToImageOnSet: Bool = false
    private let crosshairH = CAShapeLayer()
    private let crosshairV = CAShapeLayer()
    private var contentSizeMM = CGSize(width: 88.9, height: 28.6)
    private var contentScale: CGFloat = 1.0
    public var zoomLevel: CGFloat { contentScale }
    private func regenerateGridImage() {
        guard contentSizeMM.width > 0, contentSizeMM.height > 0 else { return }
        dpi = 72
        let pointsPerMM = dpi / 25.4 * contentScale
        let size = NSSize(width: contentSizeMM.width * pointsPerMM,
                          height: contentSizeMM.height * pointsPerMM)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        setImage(image)
        imageView.setFrameSize(size)
        updateGrid()
        updateDocumentLayout()
        updateCrosshairLayerFrames()
        updateRulers()
        updateTextLabelFrames()
        updateCodeBoxFrames()
        for frame in frameItems {
            frame.frame = mmRectToPx(frame.rectMM)
            frame.pixelsPerMM = pxPerMMCurrent()
        }
        for line in lineItems {
            line.frame = imageView.bounds
            line.pixelsPerMM = pxPerMMCurrent()
        }
    }
    public override init(frame frameRect: NSRect) {
        hRuler = MeasurementRulerView(scrollView: scrollView, orientation: .horizontalRuler)
        vRuler = MeasurementRulerView(scrollView: scrollView, orientation: .verticalRuler)
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        hRuler = MeasurementRulerView(scrollView: scrollView, orientation: .horizontalRuler)
        vRuler = MeasurementRulerView(scrollView: scrollView, orientation: .verticalRuler)
        super.init(coder: coder)
        commonInit()
    }
    public override var intrinsicContentSize: NSSize {
        return resizeToImageOnSet ? imageView.bounds.size : NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        imageView.imageScaling = .scaleNone // we manage zoom via scrollView magnification
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.white.cgColor
        imageView.layer?.masksToBounds = true
        labelBackground.wantsLayer = true
        labelBackground.layer?.backgroundColor = NSColor.clear.cgColor
        labelBackground.layer?.masksToBounds = false
        labelShapeLayer.fillColor = NSColor.white.cgColor
        labelShapeLayer.shadowColor = NSColor.black.cgColor
        labelShapeLayer.shadowOpacity = 0.35
        labelShapeLayer.shadowRadius = 8
        labelShapeLayer.shadowOffset = CGSize(width: 0, height: -4)
        labelShapeLayer.masksToBounds = false
        labelBackground.layer?.addSublayer(labelShapeLayer)

        updateGrid()

        crosshairH.isHidden = true
        crosshairV.isHidden = true
        crosshairH.fillColor = nil
        crosshairV.fillColor = nil
        crosshairH.lineWidth = 1 / (window?.backingScaleFactor ?? 1)
        crosshairV.lineWidth = 1 / (window?.backingScaleFactor ?? 1)
        crosshairH.strokeColor = NSColor.systemRed.withAlphaComponent(0.9).cgColor
        crosshairV.strokeColor = NSColor.systemRed.withAlphaComponent(0.9).cgColor
        crosshairH.zPosition = 999
        crosshairV.zPosition = 999
        imageView.layer?.addSublayer(crosshairH)
        imageView.layer?.addSublayer(crosshairV)
        updateCrosshairLayerFrames()
        
        imageView.onMouseMoved = { [weak self] p in
            guard let self = self else { return }
            self.mouseInsideImage = true
            self.updateCrosshairVisibility()
            self.updateCrosshair(at: p)
        }
        imageView.onMouseEntered = { [weak self] in
            guard let self = self else { return }
            self.mouseInsideImage = true
            self.updateCrosshairVisibility()
        }
        imageView.onMouseExited  = { [weak self] in
            guard let self = self else { return }
            self.mouseInsideImage = false
            self.updateCrosshairVisibility()
        }

        self.updateCrosshairVisibility()

        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = NSColor(calibratedWhite: 0.8, alpha: 1)
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = docView
        docView.addSubview(labelBackground)
        docView.addSubview(imageView)
        scrollView.allowsMagnification = true
        scrollView.maxMagnification = 64
        scrollView.minMagnification = 0.05
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalRulerView = hRuler
        scrollView.verticalRulerView = vRuler
        scrollView.hasHorizontalRuler = true
        scrollView.hasVerticalRuler = true
        hRuler.clientView = imageView
        vRuler.clientView = imageView
        scrollView.rulersVisible = true
        
        addSubview(scrollView)
        unitButton.isBordered = false
        unitButton.wantsLayer = true
        unitButton.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
        unitButton.layer?.borderColor = NSColor(calibratedWhite: 0.6, alpha: 1).cgColor
        unitButton.layer?.borderWidth = 1
        unitButton.contentTintColor = .black
        unitButton.controlSize = .mini
        unitButton.font = .systemFont(ofSize: 10)
        unitButton.imagePosition = .noImage
        unitButton.alignment = .center
        unitButton.target = self
        unitButton.action = #selector(toggleRulerUnit)
        unitButton.setAccessibilityLabel("Ruler units")
        addSubview(unitButton)
        applyUnit()
        regenerateGridImage()
    }
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        if let selectionMonitor {
            NSEvent.removeMonitor(selectionMonitor)
            self.selectionMonitor = nil
        }
        guard window != nil else { return }
        selectionMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            if let orderControl = window.toolbar?.items.first(where: {
                $0.itemIdentifier == .toolbarItemObjectOrder
            })?.view,
               orderControl.bounds.contains(orderControl.convert(event.locationInWindow, from: nil)) {
                return event
            }
            if let inspector = self.inspectorInteractionView,
               inspector.bounds.contains(inspector.convert(event.locationInWindow, from: nil)) {
                return event
            }
            if self.textLabels.contains(where: {
                $0.containsEditingText(atWindowPoint: event.locationInWindow)
            }) {
                return event
            }
            if event.type == .leftMouseUp {
                self.onSelectionChanged?(self.selectedItem)
                return event
            }
            let point = self.imageView.convert(event.locationInWindow, from: nil)
            let visible = self.imageView.visibleRect.contains(point)
            let selected = visible ? self.imageView.subviews.reversed().first {
                if let frame = $0 as? FrameItemView {
                    return !frame.isHidden && frame.containsFramePoint(frame.convert(point, from: self.imageView))
                }
                if let line = $0 as? LineItemView {
                    return !line.isHidden && line.containsLinePoint(line.convert(point, from: self.imageView))
                }
                return !$0.isHidden && ($0 is LabelBoxView || $0 is CodeBoxView) && $0.frame.contains(point)
            } : nil
            self.selectEditorItem(selected)
            if let selected,
               event.type == .rightMouseDown || event.modifierFlags.contains(.control),
               let menu = selected.menu(for: event) {
                NSMenu.popUpContextMenu(menu, with: event, for: selected)
                return nil
            }
            return event
        }
    }
    public override func layout() {
        super.layout()
        scrollView.frame = bounds
        scrollView.tile()
        unitButton.frame = NSRect(x: bounds.minX,
                                  y: bounds.maxY - hRuler.ruleThickness,
                                  width: vRuler.ruleThickness,
                                  height: hRuler.ruleThickness)
        updateDocumentLayout()
        let scale = window?.backingScaleFactor ?? 1
        crosshairH.lineWidth = 1 / scale
        crosshairV.lineWidth = 1 / scale
        updateCrosshairLayerFrames()
        updateRulers()
    }

    public func setImage(_ image: NSImage?) {
        imageView.image = image
        if let rep = image?.bestRepresentation(for: .zero, context: nil, hints: nil) as? NSBitmapImageRep {
            if let img = image, let data = img.tiffRepresentation,
               let src = CGImageSourceCreateWithData(data as CFData, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {

                if let dpiWidth = props[kCGImagePropertyDPIWidth] as? NSNumber {
                    let val = CGFloat(truncating: dpiWidth)
                    if val > 18 && val < 1200 { dpi = val }
                } else if
                    let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
                    let resXNum = tiff[kCGImagePropertyTIFFXResolution] as? NSNumber,
                    let unitNum = tiff[kCGImagePropertyTIFFResolutionUnit] as? NSNumber {
                    var val = CGFloat(truncating: resXNum)
                    if unitNum.intValue == 3 { val *= 2.54 } // cm -> inches
                    if val > 18 && val < 1200 { dpi = val }
                } else if
                    let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any],
                    let ppmX = png[kCGImagePropertyPNGXPixelsPerMeter] as? NSNumber {
                    let val = CGFloat(truncating: ppmX) / 39.37007874
                    if val > 18 && val < 1200 { dpi = val }
                }
            }
            let size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            imageView.frame = NSRect(origin: .zero, size: size)
            updateDocumentLayout()
            updateCrosshairLayerFrames()
            if resizeToImageOnSet
            {
                updateOwnSize(to: size)
            }
        } else if let image = image {
            imageView.frame = NSRect(origin: .zero, size: image.size)
            updateDocumentLayout()
            updateCrosshairLayerFrames()
            if resizeToImageOnSet
            {
                updateOwnSize(to: image.size)
            }
        } else {
            imageView.frame = .zero
            updateDocumentLayout()
            updateCrosshairLayerFrames()
            if resizeToImageOnSet
            {
                updateOwnSize(to: .zero)
            }
        }
        updateRulers()
        hRuler.clientView = imageView
        vRuler.clientView = imageView
        if imageView.bounds.width > 0, imageView.bounds.height > 0 {
            updateCrosshairVisibility()
            updateCrosshair(at: NSPoint(x: imageView.bounds.midX, y: imageView.bounds.midY))
        }
    }

    public func setUnit(_ unit: RulerUnit) { self.unit = unit }

    public func setSize(width: CGFloat, height: CGFloat) {
        contentSizeMM = CGSize(width: max(1, width), height: max(1, height))
        contentScale = 1.0
        regenerateGridImage()
    }
    public func zoomToFit()
    {
        guard let doc = scrollView.documentView, doc.bounds.width > 0, doc.bounds.height > 0 else { return }
        let inset = scrollView.contentInsets
        let avail = scrollView.contentView.bounds.insetBy(dx: inset.left + inset.right, dy: inset.top + inset.bottom).size
        let scaleX = avail.width / doc.bounds.width
        let scaleY = avail.height / doc.bounds.height
        magnification = max(0.05, min(scaleX, scaleY))
    }


    private func centerInSuperviewIfPossible() {
        guard let s = self.superview else { return }
        if self.translatesAutoresizingMaskIntoConstraints {
            let x = max(0, floor((s.bounds.width  - self.frame.width)  / 2))
            let y = max(0, floor((s.bounds.height - self.frame.height) / 2))
            self.setFrameOrigin(NSPoint(x: x, y: y))
            return
        }
        func zeroCenterConstraint(_ attr: NSLayoutConstraint.Attribute) {
            for c in s.constraints {
                let firstIsSelf  = (c.firstItem as AnyObject?) === self
                let secondIsSelf = (c.secondItem as AnyObject?) === self
                let firstIsSup   = (c.firstItem as AnyObject?) === s
                let secondIsSup  = (c.secondItem as AnyObject?) === s
                if firstIsSelf && secondIsSup && c.firstAttribute == attr && c.secondAttribute == attr {
                    c.constant = 0
                    return
                }
                if secondIsSelf && firstIsSup && c.secondAttribute == attr && c.firstAttribute == attr {
                    c.constant = 0
                    return
                }
            }
        }
        zeroCenterConstraint(.centerX)
        zeroCenterConstraint(.centerY)
        s.layoutSubtreeIfNeeded()
    }

    private func updateOwnSize(to size: NSSize) {
        self.setFrameSize(size)
        self.invalidateIntrinsicContentSize()

        for c in self.constraints {
            guard c.relation == .equal,
                  c.secondItem == nil,
                  (c.firstItem as AnyObject?) === self else { continue }
            switch c.firstAttribute {
            case .width:  c.constant = size.width
            case .height: c.constant = size.height
            default: break
            }
        }

        self.layoutSubtreeIfNeeded()
        centerInSuperviewIfPossible()
    }

    func addLine(_ configuration: LabelLine) {
        var line = configuration
        line.startMM = CGPoint(x: contentSizeMM.width * 0.2, y: contentSizeMM.height * 0.5)
        line.endMM = CGPoint(x: contentSizeMM.width * 0.8, y: contentSizeMM.height * 0.5)
        insertLine(line)
    }

    private func insertLine(_ configuration: LabelLine) {
        let line = LineItemView(frame: imageView.bounds)
        line.line = configuration
        line.pixelsPerMM = pxPerMMCurrent()
        lineItems.append(line)
        imageView.addSubview(line)
        line.onSelect = { [weak self, weak line] in self?.selectEditorItem(line) }
        line.onDelete = { [weak self, weak line] in
            guard let self, let line else { return }
            if self.selectedItem === line { self.selectEditorItem(nil) }
            self.lineItems.removeAll { $0 === line }
            line.removeFromSuperview()
        }
        selectEditorItem(line)
    }

    func addFrame(_ configuration: LabelFrame, sizeMM: CGSize) throws {
        try configuration.validate(sizeMM: sizeMM)
        guard sizeMM.width <= contentSizeMM.width, sizeMM.height <= contentSizeMM.height else {
            throw FrameError("The frame must fit within the label.")
        }
        let rect = CGRect(x: (contentSizeMM.width - sizeMM.width) / 2,
                          y: (contentSizeMM.height - sizeMM.height) / 2,
                          width: sizeMM.width, height: sizeMM.height)
        insertFrame(configuration, rectMM: rect)
    }

    private func insertFrame(_ configuration: LabelFrame, rectMM: CGRect) {
        let frame = FrameItemView(frame: mmRectToPx(rectMM))
        frame.rectMM = rectMM
        frame.configuration = configuration
        frame.pixelsPerMM = pxPerMMCurrent()
        frameItems.append(frame)
        imageView.addSubview(frame)
        frame.onSelect = { [weak self, weak frame] in self?.selectEditorItem(frame) }
        frame.onFrameChanged = { [weak self, weak frame] rect in
            guard let self, let frame else { return }
            frame.rectMM = self.pxRectToMM(rect)
        }
        frame.onDelete = { [weak self, weak frame] in
            guard let self, let frame else { return }
            if self.selectedItem === frame { self.selectEditorItem(nil) }
            self.frameItems.removeAll { $0 === frame }
            frame.removeFromSuperview()
        }
        selectEditorItem(frame)
    }

    func addImage(data: Data, contentKind: ImageContentKind = .image) throws {
        let image = try ImageItemView.decode(data)
        guard contentSizeMM.width > 0, contentSizeMM.height > 0 else { throw ImageImportError() }
        let area = CGRect(x: contentSizeMM.width * 0.1, y: contentSizeMM.height * 0.1,
                          width: contentSizeMM.width * 0.8, height: contentSizeMM.height * 0.8)
        let rect = ImageItemView.fittedRect(imageSize: image.size, in: area)
        insertImage(data: data, image: image, rectMM: rect, contentKind: contentKind)
    }

    private func insertImage(data: Data, image: NSImage, rectMM: CGRect,
                             contentKind: ImageContentKind = .image) {
        let item = ImageItemView(data: data, image: image, frame: mmRectToPx(rectMM),
                                 contentKind: contentKind)
        item.rectMM = rectMM
        item.pixelsPerMM = pxPerMMCurrent()
        frameItems.append(item)
        imageView.addSubview(item)
        item.onSelect = { [weak self, weak item] in self?.selectEditorItem(item) }
        item.onFrameChanged = { [weak self, weak item] rect in
            guard let self, let item else { return }
            item.rectMM = self.pxRectToMM(rect)
        }
        item.onDelete = { [weak self, weak item] in
            guard let self, let item else { return }
            if self.selectedItem === item { self.selectEditorItem(nil) }
            self.frameItems.removeAll { $0 === item }
            item.removeFromSuperview()
        }
        selectEditorItem(item)
    }

    func addShape(_ shape: LabelShape, sizeMM: CGSize) throws {
        try shape.validate(sizeMM: sizeMM)
        guard sizeMM.width <= contentSizeMM.width, sizeMM.height <= contentSizeMM.height else {
            throw FrameError("The shape must fit within the label.")
        }
        let rect = CGRect(x: (contentSizeMM.width - sizeMM.width) / 2,
                          y: (contentSizeMM.height - sizeMM.height) / 2,
                          width: sizeMM.width, height: sizeMM.height)
        insertShape(shape, rectMM: rect)
    }

    private func insertShape(_ shape: LabelShape, rectMM: CGRect) {
        let item = ShapeItemView(frame: mmRectToPx(rectMM))
        item.shape = shape
        item.rectMM = rectMM
        item.pixelsPerMM = pxPerMMCurrent()
        frameItems.append(item)
        imageView.addSubview(item)
        item.onSelect = { [weak self, weak item] in self?.selectEditorItem(item) }
        item.onFrameChanged = { [weak self, weak item] rect in
            guard let self, let item else { return }
            item.rectMM = self.pxRectToMM(rect)
        }
        item.onDelete = { [weak self, weak item] in
            guard let self, let item else { return }
            if self.selectedItem === item { self.selectEditorItem(nil) }
            self.frameItems.removeAll { $0 === item }
            item.removeFromSuperview()
        }
        selectEditorItem(item)
    }

    public func clearLabelObjects() {
        window?.makeFirstResponder(nil)
        selectEditorItem(nil)
        for box in textLabels { box.removeFromSuperview() }
        for box in codeBoxes { box.removeFromSuperview() }
        textLabels.removeAll()
        codeBoxes.removeAll()
        for line in lineItems { line.removeFromSuperview() }
        lineItems.removeAll()
        for frame in frameItems { frame.removeFromSuperview() }
        frameItems.removeAll()
    }

    public func labelFileData(labelTypeName: String? = nil) throws -> Data {
        window?.makeFirstResponder(nil)
        let items: [SavedLabelItem] = imageView.subviews.compactMap { view in
            if let shape = view as? ShapeItemView {
                return SavedLabelItem(kind: .shape, value: "", rectMM: shape.rectMM,
                                      shapeConfiguration: shape.shape)
            }
            if let image = view as? ImageItemView {
                return SavedLabelItem(kind: .image, value: "", rectMM: image.rectMM,
                                      imageData: image.imageData, imageContentKind: image.contentKind)
            }
            if let frame = view as? FrameItemView {
                return SavedLabelItem(kind: .frame, value: "", rectMM: frame.rectMM,
                                      frameConfiguration: frame.configuration)
            }
            if let line = view as? LineItemView {
                return SavedLabelItem(kind: .line, value: "", rectMM: CGRect(x: 0, y: 0, width: 1, height: 1),
                                      line: line.line)
            }
            if let text = view as? LabelBoxView {
                return text.savedItem(scale: contentScale)
            }
            if let code = view as? CodeBoxView {
                return SavedLabelItem(kind: code.type == .qr ? .qr : .barcode,
                                      value: code.code, rectMM: code.rectMM,
                                      quietZone: code.quietZone, barcodeFormat: code.type, showsBarcodeData: code.showsData,
                                      amazonDetails: code.amazonDetails)
            }
            return nil
        }
        let document = SavedLabel(sizeMM: contentSizeMM, items: items, outlineShape: labelShape,
                                  labelTypeName: labelTypeName)
        try document.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    @discardableResult
    public func loadLabelFileData(_ data: Data) throws -> String? {
        let document = try JSONDecoder().decode(SavedLabel.self, from: data)
        try document.validate()
        for item in document.items where item.kind == .qr || item.kind == .barcode {
            if item.barcodeFormat == .amazonFNSKU {
                guard let details = item.amazonDetails else { throw BarcodeError("Missing Amazon label details.") }
                _ = try details.validated()
            }
            _ = try BarcodeGenerator.shared.generate(item.value,
                format: item.barcodeFormat ?? (item.kind == .qr ? .qr : .code128))
        }
        var decodedImages: [Int: NSImage] = [:]
        for (index, item) in document.items.enumerated() where item.kind == .image {
            guard let data = item.imageData else { throw ImageImportError() }
            decodedImages[index] = try ImageItemView.decode(data)
        }
        clearLabelObjects()
        contentSizeMM = document.sizeMM
        labelShape = document.outlineShape ?? .rectangle
        regenerateGridImage()
        for (index, item) in document.items.enumerated() {
            switch item.kind {
            case .shape:
                if let shape = item.shapeConfiguration { insertShape(shape, rectMM: item.rectMM) }
            case .image:
                if let data = item.imageData, let image = decodedImages[index] {
                    insertImage(data: data, image: image, rectMM: item.rectMM,
                                contentKind: item.imageContentKind ?? .image)
                }
            case .frame:
                if let configuration = item.frameConfiguration {
                    insertFrame(configuration, rectMM: item.rectMM)
                }
            case .line:
                if let line = item.line { insertLine(line) }
            case .text:
                addDemoLabel(text: item.value)
                if let box = labelBox {
                    box.textAppearance = item.textAppearance ?? TextAppearance()
                    box.horizontalAlignment = item.horizontalAlignment ?? .center
                    box.verticalAlignment = item.verticalAlignment ?? .center
                    box.rectMM = item.rectMM
                    box.frame = mmRectToPx(item.rectMM)
                    box.databaseField = item.databaseField
                    box.setFont(name: item.fontName, size: (item.fontSize ?? 12) * contentScale)
                    box.setAutomaticFontFit(item.automaticallyFitsFont ?? (item.fontSize == nil))
                    box.needsLayout = true
                    box.layoutSubtreeIfNeeded()
                }
            case .qr, .barcode:
                addCodeBox(text: item.value, type: item.barcodeFormat ?? (item.kind == .qr ? .qr : .code128),
                           amazonDetails: item.amazonDetails, showsData: item.showsBarcodeData)
                if let box = selectedItem as? CodeBoxView {
                    box.rectMM = item.rectMM
                    box.quietZone = item.quietZone ?? 4
                    box.frame = mmRectToPx(item.rectMM)
                    box.needsLayout = true
                    box.layoutSubtreeIfNeeded()
                }
            }
        }
        selectEditorItem(nil)
        return document.labelTypeName
    }

    private static let preferredPrinterDefaultsKey = "preferredLabelPrinterName"

    public var preferredPrinterName: String {
        preferredPrinter?.name ?? NSPrintInfo.shared.printer.name
    }

    public func selectPrinter(named name: String) {
        guard NSPrinter(name: name) != nil else { return }
        UserDefaults.standard.set(name, forKey: Self.preferredPrinterDefaultsKey)
    }

    private var preferredPrinter: NSPrinter? {
        if let savedName = UserDefaults.standard.string(forKey: Self.preferredPrinterDefaultsKey),
           let printer = NSPrinter(name: savedName) {
            return printer
        }
        if let rolloName = NSPrinter.printerNames.first(where: {
            $0.localizedCaseInsensitiveContains("Rollo")
        }) {
            return NSPrinter(name: rolloName)
        }
        return NSPrintInfo.shared.printer
    }

    public func previewAndPrintLabel(copies: Int = 1,
                                     showsPrintPanel: Bool = true,
                                     previewsOnly: Bool = false,
                                     orientation: Int = 0,
                                     scalePercent: CGFloat = 100,
                                     offsetMM: NSPoint = .zero,
                                     rotates180: Bool = false,
                                     mirrorsHorizontally: Bool = false) throws {
        guard NSPrintOperation.current == nil else { return }
        window?.makeFirstResponder(nil)
        imageView.layoutSubtreeIfNeeded()
        let size = NSSize(width: contentSizeMM.width * 72 / 25.4,
                          height: contentSizeMM.height * 72 / 25.4)
        guard size.width > 0, size.height > 0, contentScale > 0 else { return }
        var drawings: [(NSView) -> Void] = []
        for subview in imageView.subviews where !subview.isHidden {
            if let text = subview as? LabelBoxView {
                drawings.append(try text.printDrawing())
            } else if let code = subview as? CodeBoxView {
                drawings.append(try code.printDrawing())
            } else if let line = subview as? LineItemView {
                drawings.append(line.printDrawing())
            } else if let frame = subview as? FrameItemView {
                drawings.append(frame.printDrawing())
            }
        }
        let printable = LabelPrintView(size: size, editorScale: contentScale, drawings: drawings,
                                       outputScale: min(4, max(0.25, scalePercent / 100)),
                                       offset: NSPoint(x: offsetMM.x * 72 / 25.4,
                                                       y: offsetMM.y * 72 / 25.4),
                                       rotates180: rotates180,
                                       mirrorsHorizontally: mirrorsHorizontally)
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        if let printer = preferredPrinter {
            info.printer = printer
        }
        switch orientation {
        case 1: info.orientation = .portrait
        case 2: info.orientation = .landscape
        default: info.orientation = size.width > size.height ? .landscape : .portrait
        }
        info.paperSize = size
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.scalingFactor = 1
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        info.horizontalPagination = .clip
        info.verticalPagination = .clip
        info.dictionary()[NSPrintInfo.AttributeKey.copies] = NSNumber(value: max(1, copies))
        if previewsOnly {
            info.jobDisposition = .preview
        }
        let operation = NSPrintOperation(view: printable, printInfo: info)
        operation.jobTitle = "Label"
        operation.showsPrintPanel = showsPrintPanel
        operation.showsProgressPanel = !previewsOnly
        if showsPrintPanel {
            operation.printPanel.options = [.showsCopies, .showsPreview]
        }
        let completed = operation.run()
        if showsPrintPanel, completed {
            UserDefaults.standard.set(operation.printInfo.printer.name,
                                      forKey: Self.preferredPrinterDefaultsKey)
        }
    }


    public func makePrintableView() -> NSView { imageView }

    @discardableResult
    public func exportCompositionToDesktop(baseName: String = "Label",
                                           dpi: CGFloat? = nil,
                                           bleedMM: CGFloat = 0) throws -> (pngURL: URL, pdfURL: URL) {
        let printable = makePrintableView()
        let bounds = printable.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            throw NSError(domain: "RulerImageView", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Nothing to export (empty bounds)"])
        }

        let oldGridSpacing = imageView.gridSpacing
        imageView.gridSpacing = 0
        defer { imageView.gridSpacing = oldGridSpacing }
        let oldHHidden = crosshairH.isHidden
        let oldVHidden = crosshairV.isHidden
        crosshairH.isHidden = true
        crosshairV.isHidden = true
        var overlayBorderStates: [(NSView, Bool)] = []
        for v in imageView.subviews {
            if let frame = v as? FrameItemView { overlayBorderStates.append((frame, frame.showsHandles)); frame.showsHandles = false }
            if let line = v as? LineItemView { overlayBorderStates.append((line, line.showsHandles)); line.showsHandles = false }
            if let lb = v as? LabelBoxView { overlayBorderStates.append((lb, lb.showsBorder)); lb.showsBorder = false }
            if let cb = v as? CodeBoxView  { overlayBorderStates.append((cb, cb.showsBorder)); cb.showsBorder  = false }
        }
        defer {
            crosshairH.isHidden = oldHHidden
            crosshairV.isHidden = oldVHidden
            for (v, s) in overlayBorderStates {
                (v as? FrameItemView)?.showsHandles = s
                (v as? LineItemView)?.showsHandles = s
                (v as? LabelBoxView)?.showsBorder = s
                (v as? CodeBoxView )?.showsBorder = s
            }
        }

        let outDPI: CGFloat = dpi ?? max(self.dpi, 72)
        let pxPerMM: CGFloat = outDPI / 25.4
        let bleedPx: CGFloat = max(0, bleedMM) * pxPerMM

        let fm = FileManager.default
        guard let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "RulerImageView", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot locate Desktop directory"])
        }
        let stamp: String = { let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date()) }()
        let pngURL = desktop.appendingPathComponent("\(baseName)_\(stamp).png")
        let pdfURL = desktop.appendingPathComponent("\(baseName)_\(stamp).pdf")

        guard let contentRep = printable.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw NSError(domain: "RulerImageView", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to allocate bitmap rep"])
        }
        contentRep.size = bounds.size
        printable.cacheDisplay(in: bounds, to: contentRep)

        let scale = outDPI / 72.0
        let outW = Int(ceil(bounds.width  * scale + bleedPx * 2))
        let outH = Int(ceil(bounds.height * scale + bleedPx * 2))
        guard let destRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: outW,
            pixelsHigh: outH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "RulerImageView", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to allocate destination rep"])
        }
        destRep.size = NSSize(width: outW, height: outH) // 1pt == 1px for output image size

        NSGraphicsContext.saveGraphicsState()
        if let gc = NSGraphicsContext(bitmapImageRep: destRep) {
            NSGraphicsContext.current = gc
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: outW, height: outH)).fill()

            let contentImg = NSImage(size: bounds.size)
            contentImg.addRepresentation(contentRep)
            let drawRect = NSRect(x: bleedPx, y: bleedPx,
                                  width: bounds.width * scale,
                                  height: bounds.height * scale)
            contentImg.draw(in: drawRect)
            gc.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()

        if let pngData = destRep.representation(using: .png, properties: [:]) {
            try pngData.write(to: pngURL, options: .atomic)
        } else {
            throw NSError(domain: "RulerImageView", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG representation"])
        }

        let pdfView = NSImageView(frame: NSRect(x: 0, y: 0, width: outW, height: outH))
        let pdfImage = NSImage(size: NSSize(width: outW, height: outH))
        pdfImage.addRepresentation(destRep)
        pdfView.image = pdfImage
        let pdfData = pdfView.dataWithPDF(inside: pdfView.bounds)
        try pdfData.write(to: pdfURL, options: .atomic)

        return (pngURL, pdfURL)
    }
    public func exportToDesktop(dpi: CGFloat? = nil, bleedMM: CGFloat = 0) {
        do {
            let urls = try exportCompositionToDesktop(baseName: "Label", dpi: dpi, bleedMM: bleedMM)
            Swift.print("Exported to:\nPNG: \(urls.pngURL.path)\nPDF: \(urls.pdfURL.path)")
        } catch {
            Swift.print("Export failed: \(error)")
        }
    }
    public func zoom(by factor: CGFloat) {
        guard factor.isFinite, factor > 0 else { return }
        setZoomLevel(contentScale * factor)
    }

    public func setZoomLevel(_ level: CGFloat) {
        guard level.isFinite, level > 0 else { return }
        contentScale = max(0.25, min(level, 4.0))
        regenerateGridImage()
        scrollView.setMagnification(1.0, centeredAt: NSPoint(x: scrollView.contentView.bounds.midX,
                                                             y: scrollView.contentView.bounds.midY))
        updateDocumentLayout()
        updateRulers()
    }
    private func updateDocumentLayout() {
        let clip = scrollView.contentView
        let size = imageView.bounds.size
        let margin: CGFloat = 24
        let documentSize = NSSize(width: max(clip.bounds.width, size.width + margin * 2),
                                  height: max(clip.bounds.height, size.height + margin * 2))
        docView.frame = NSRect(origin: .zero, size: documentSize)
        imageView.setFrameOrigin(NSPoint(x: (documentSize.width - size.width) / 2,
                                         y: (documentSize.height - size.height) / 2))
        let shadowMargin: CGFloat = 12
        labelBackground.frame = imageView.frame.insetBy(dx: -shadowMargin, dy: -shadowMargin)
        let radius: CGFloat
        switch labelShape {
        case .rectangle:
            radius = min(size.height / 2, 4 * dpi / 25.4 * contentScale)
        case .round:
            radius = size.width / 2
        }
        imageView.layer?.cornerRadius = radius
        labelShapeLayer.frame = labelBackground.bounds
        let labelRect = labelBackground.bounds.insetBy(dx: shadowMargin, dy: shadowMargin)
        let shapePath = CGPath(
            roundedRect: labelRect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
        labelShapeLayer.path = shapePath
        labelShapeLayer.shadowPath = shapePath
        scrollView.reflectScrolledClipView(clip)
    }
    private func updateCrosshairLayerFrames() {
        crosshairH.frame = imageView.bounds
        crosshairV.frame = imageView.bounds
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        crosshairH.contentsScale = scale
        crosshairV.contentsScale = scale

    }
    @objc private func toggleRulerUnit() {
        unit = unit == .millimeters ? .inches : .millimeters
    }

    private func applyUnit() {
        let title = unit == .millimeters ? "mm" : "in"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        unitButton.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ])
        unitButton.toolTip = unit == .millimeters ? "Switch to inches" : "Switch to millimeters"
        unitButton.setAccessibilityValue(unit == .millimeters ? "Millimeters" : "Inches")
        hRuler.unit = unit
        vRuler.unit = unit
        let native: NSRulerView.UnitName = (unit == .millimeters) ? .centimeters : .inches
        hRuler.measurementUnits = native
        vRuler.measurementUnits = native
        updateRulers()
    }

    private func updateRulers() {
        hRuler.dpiProvider = { [weak self] in self?.dpi ?? 72 }
        vRuler.dpiProvider = { [weak self] in self?.dpi ?? 72 }
        hRuler.pointsPerPixelProvider = { [weak self] in self?.contentScale ?? 1 }
        vRuler.pointsPerPixelProvider = hRuler.pointsPerPixelProvider
        updateDocumentLayout()

        if !crosshairH.isHidden { updateCrosshair(at: NSPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)) }
        hRuler.needsDisplay = true
        vRuler.needsDisplay = true
    }

    private func setCrosshairVisible(_ visible: Bool) {
        crosshairH.isHidden = !visible
        crosshairV.isHidden = !visible
    }
    private func updateCrosshairVisibility() {
        let visible = showsCrosshair && mouseInsideImage
        setCrosshairVisible(visible)
        if !visible {
            hRuler.cursorPosition = nil
            vRuler.cursorPosition = nil
            hRuler.needsDisplay = true
            vRuler.needsDisplay = true
        }
    }
    private func updateCrosshair(at imagePoint: NSPoint) {
        guard imageView.bounds.width > 0, imageView.bounds.height > 0 else { return }
        updateCrosshairVisibility()
        let x = max(0, min(imagePoint.x, imageView.bounds.width))
        let y = max(0, min(imagePoint.y, imageView.bounds.height))

        let hPath = NSBezierPath()
        hPath.move(to: NSPoint(x: 0, y: y))
        hPath.line(to: NSPoint(x: imageView.bounds.width, y: y))
        crosshairH.path = hPath.cgPath

        let vPath = NSBezierPath()
        vPath.move(to: NSPoint(x: x, y: 0))
        vPath.line(to: NSPoint(x: x, y: imageView.bounds.height))
        crosshairV.path = vPath.cgPath
    
        hRuler.cursorPosition = x
        vRuler.cursorPosition = imageView.bounds.height - y
        hRuler.needsDisplay = true
        vRuler.needsDisplay = true

        hRuler.needsDisplay = true
        vRuler.needsDisplay = true
    }
}

final class MeasurementRulerView: NSRulerView {
    var unit: RulerUnit = .millimeters
    var dpiProvider: (() -> CGFloat)?
    var pointsPerPixelProvider: (() -> CGFloat)?

    private let rulerBackgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1)
    private let majorLabelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.2, alpha: 1)
    ]

    private let minorTickColor = NSColor(calibratedWhite: 0.4, alpha: 1)
    private let tickColor = NSColor(calibratedWhite: 0.6, alpha: 1)

    override var requiredThickness: CGFloat { 24 } // Enough space for labels

    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        clientView = self.scrollView?.documentView
        measurementUnits = .centimeters // arbitrary; we draw custom ticks anyway
        ruleThickness = requiredThickness
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func snapped(_ value: CGFloat, step: CGFloat) -> CGFloat {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }
    var cursorPosition: CGFloat? = nil
    override var isFlipped: Bool { true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        rulerBackgroundColor.setFill()
        bounds.fill()

        let horizontal = orientation == .horizontalRuler
        let border = NSBezierPath()
        if horizontal {
            border.move(to: NSPoint(x: bounds.minX, y: bounds.maxY - 0.5))
            border.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - 0.5))
        } else {
            border.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
            border.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        }
        tickColor.setStroke()
        border.lineWidth = 1
        border.stroke()

        guard clientView != nil, let scrollView else { return }
        let pointsPerInch = (dpiProvider?() ?? 72) * (pointsPerPixelProvider?() ?? 1)
        let major = unit == .inches ? pointsPerInch : pointsPerInch / 25.4 * 10
        let subdivisions = unit == .inches ? 8 : 10
        let step = major / CGFloat(subdivisions)
        guard step > 0 else { return }

        let origin = convertFromClient(0)
        let screenStep = step * scrollView.magnification
        let limit = horizontal ? bounds.maxX : bounds.maxY
        let first = max(0, Int(ceil(-origin / screenStep)))
        let last = Int(floor((limit - origin) / screenStep))
        let ticks = NSBezierPath()
        if first <= last {
            for index in first...last {
                let position = convertFromClient(CGFloat(index) * step)
                let isMajor = index % subdivisions == 0
                let isMedium = index % (subdivisions / 2) == 0
                let length: CGFloat = isMajor ? 11 : (isMedium ? 7 : 4)
                if horizontal {
                    ticks.move(to: NSPoint(x: position, y: bounds.maxY))
                    ticks.line(to: NSPoint(x: position, y: bounds.maxY - length))
                } else {
                    ticks.move(to: NSPoint(x: bounds.maxX, y: position))
                    ticks.line(to: NSPoint(x: bounds.maxX - length, y: position))
                }
                if isMajor {
                    let value = (index / subdivisions) * (unit == .millimeters ? 10 : 1)
                    let label = NSAttributedString(string: String(value),
                                                   attributes: majorLabelAttributes)
                    label.draw(at: horizontal
                               ? NSPoint(x: position + 3, y: bounds.minY)
                               : NSPoint(x: bounds.minX + 2, y: position + 2))
                }
            }
        }
        minorTickColor.setStroke()
        ticks.lineWidth = 1 / (window?.backingScaleFactor ?? 1)
        ticks.stroke()

        if let cursorPosition {
            let position = convertFromClient(cursorPosition)
            let marker = NSBezierPath()
            marker.move(to: horizontal ? NSPoint(x: position, y: bounds.minY)
                                      : NSPoint(x: bounds.minX, y: position))
            marker.line(to: horizontal ? NSPoint(x: position, y: bounds.maxY)
                                       : NSPoint(x: bounds.maxX, y: position))
            NSColor.systemGreen.setStroke()
            marker.lineWidth = 1
            marker.stroke()
        }
    }

    private func convertFromClient(_ distance: CGFloat) -> CGFloat {
        guard let client = clientView else { return distance }
        let point = orientation == .horizontalRuler
            ? NSPoint(x: client.bounds.minX + distance, y: client.bounds.maxY)
            : NSPoint(x: client.bounds.minX, y: client.bounds.maxY - distance)
        let converted = convert(point, from: client)
        return orientation == .horizontalRuler ? converted.x : converted.y
    }
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        guard places >= 0 else { return self }
        let p = pow(10.0, CGFloat(places))
        return (self * p).rounded() / p
    }
}

private extension Double {
    func cleanString(maxDecimals: Int) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = maxDecimals
        f.minimumIntegerDigits = 1
        return f.string(from: NSNumber(value: self)) ?? String(self)
    }
}

private extension CGFloat {
    func cleanString(maxDecimals: Int) -> String {
        Double(self).cleanString(maxDecimals: maxDecimals)
    }
}

#if DEBUG
public final class RulerImageDemoViewController: NSViewController {
    private let control = RulerImageView()
    private let unitSwitch = NSSegmentedControl(labels: ["mm","in"], trackingMode: .selectOne, target: nil, action: nil)

    public override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        control.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(control)

        unitSwitch.translatesAutoresizingMaskIntoConstraints = false
        unitSwitch.selectedSegment = 0
        unitSwitch.target = self
        unitSwitch.action = #selector(changeUnit)
        view.addSubview(unitSwitch)

        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            control.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            control.topAnchor.constraint(equalTo: view.topAnchor, constant: 44),
            control.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            unitSwitch.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            unitSwitch.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12)
        ])

        let exportBtn = NSButton(title: "Export", target: self, action: #selector(doExport))
        exportBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(exportBtn)
        NSLayoutConstraint.activate([
            exportBtn.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            exportBtn.leadingAnchor.constraint(equalTo: unitSwitch.trailingAnchor, constant: 12)
        ])

    }

    @objc private func changeUnit(_ sender: NSSegmentedControl) {
        control.setUnit(sender.selectedSegment == 0 ? .millimeters : .inches)
    }

    @objc private func doExport() {
        control.exportToDesktop()
    }
}
#endif
