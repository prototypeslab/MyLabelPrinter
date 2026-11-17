import Cocoa
import CoreText

struct TextAppearance: Codable, Equatable {
    var isVertical = false
    var characterSpacing: CGFloat = 0
    var lineSpacing: CGFloat = 0
    var underline = false
    var strikethrough = false
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0

    var color: NSColor { NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1) }
    static var remembered: TextAppearance {
        guard let data = UserDefaults.standard.data(forKey: "textAppearance"),
              var value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return Self() }
        value.red = 0
        value.green = 0
        value.blue = 0
        return value
    }
    var isValid: Bool {
        [characterSpacing, lineSpacing].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1000 } &&
        [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
    func remember() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "textAppearance") }
    }
}

enum StyledTextDrawing {
    static func draw(_ source: NSAttributedString, in rect: CGRect, flipped: Bool,
                     horizontal: LabelHorizontalAlignment, vertical: LabelVerticalAlignment,
                     textAppearance: TextAppearance, scale: CGFloat) {
        guard source.length > 0, rect.width > 0, rect.height > 0,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let text = NSMutableAttributedString(attributedString: source)
        text.addAttributes([.kern: textAppearance.characterSpacing * scale,
                            .foregroundColor: textAppearance.color,
                            .underlineStyle: textAppearance.underline ? NSUnderlineStyle.single.rawValue : 0,
                            .strikethroughStyle: textAppearance.strikethrough ? NSUnderlineStyle.single.rawValue : 0],
                           range: NSRange(location: 0, length: text.length))
        let width = textAppearance.isVertical ? rect.height : rect.width
        let height = textAppearance.isVertical ? rect.width : rect.height
        let typesetter = CTTypesetterCreateWithAttributedString(text)
        var lines: [(CTLine, CGRect, CGFloat)] = []
        var index = 0
        var baseline: CGFloat = 0
        var union = CGRect.null
        while index < text.length {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, index, Double(width)))
            var line = CTTypesetterCreateLine(typesetter, CFRange(location: index, length: count))
            let endsParagraph = (text.string as NSString).substring(with: NSRange(location: index, length: count)).hasSuffix("\n")
            if horizontal == .justified, index + count < text.length, !endsParagraph {
                line = CTLineCreateJustifiedLine(line, 1, Double(width)) ?? line
            }
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            var ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            if ink.isNull || ink.isEmpty { ink = CGRect(x: 0, y: -descent, width: 0, height: ascent + descent) }
            lines.append((line, ink, baseline))
            union = union.union(ink.offsetBy(dx: 0, dy: baseline))
            baseline -= ascent + descent + max(0, leading) + textAppearance.lineSpacing * scale
            index += count
        }
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: rect)
        context.translateBy(x: rect.midX, y: rect.midY)
        if flipped { context.scaleBy(x: 1, y: -1) }
        if textAppearance.isVertical { context.rotate(by: -.pi / 2) }
        context.textMatrix = .identity
        let offsetY: CGFloat
        switch vertical {
        case .top: offsetY = height / 2 - union.maxY
        case .center: offsetY = -union.midY
        case .bottom: offsetY = -height / 2 - union.minY
        }
        for (line, ink, baseline) in lines {
            let x: CGFloat
            switch horizontal {
            case .left, .justified: x = -width / 2 - ink.minX
            case .center: x = -ink.midX
            case .right: x = width / 2 - ink.maxX
            }
            context.textPosition = CGPoint(x: x, y: baseline + offsetY)
            CTLineDraw(line, context)
            if textAppearance.underline {
                context.setStrokeColor(textAppearance.color.cgColor)
                context.setLineWidth(max(0.5, scale * 0.6))
                let y = baseline + offsetY - scale
                context.move(to: CGPoint(x: x + ink.minX, y: y))
                context.addLine(to: CGPoint(x: x + ink.maxX, y: y))
                context.strokePath()
            }
            if textAppearance.strikethrough {
                context.setStrokeColor(textAppearance.color.cgColor)
                context.setLineWidth(max(0.5, scale * 0.6))
                let y = baseline + offsetY + ink.midY
                context.move(to: CGPoint(x: x + ink.minX, y: y))
                context.addLine(to: CGPoint(x: x + ink.maxX, y: y))
                context.strokePath()
            }
        }
    }
}
