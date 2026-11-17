import Cocoa
import JavaScriptCore

enum BarcodeFormat: String, CaseIterable, Codable {
    case code128, code39, ean13, ean8, upca, upce, itf, itf14
    case qr, dataMatrix, pdf417, aztec, gs1128, amazonFNSKU

    var title: String {
        switch self {
        case .amazonFNSKU: return "Amazon FNSKU"
        case .code128: return "Code 128"
        case .code39: return "Code 39"
        case .ean13: return "EAN-13"
        case .ean8: return "EAN-8"
        case .upca: return "UPC-A"
        case .upce: return "UPC-E"
        case .itf: return "ITF"
        case .itf14: return "ITF-14"
        case .qr: return "QR Code"
        case .dataMatrix: return "Data Matrix"
        case .pdf417: return "PDF417"
        case .aztec: return "Aztec"
        case .gs1128: return "GS1-128"
        }
    }

    var encoderName: String {
        switch self {
        case .amazonFNSKU: return "code128"
        case .qr: return "qrcode"
        case .dataMatrix: return "datamatrix"
        case .aztec: return "azteccode"
        case .itf: return "interleaved2of5"
        case .gs1128: return "gs1-128"
        default: return rawValue
        }
    }

    var isLinear: Bool { ![.qr, .dataMatrix, .pdf417, .aztec].contains(self) }
    var isSquare: Bool { [.qr, .dataMatrix, .aztec].contains(self) }

    var fieldTitle: String {
        switch self {
        case .ean13, .ean8, .upca, .upce, .itf14: return "Product digits"
        case .amazonFNSKU: return "FNSKU"
        case .itf: return "Numeric data"
        case .gs1128: return "GS1 elements"
        default: return "Text or data"
        }
    }

    var guidance: String {
        switch self {
        case .amazonFNSKU: return "Enter the 10-character FNSKU assigned in Seller Central, product name, and listing condition."
        case .code128: return "Required: ASCII text (letters, numbers, and punctuation)."
        case .code39: return "Required: uppercase A–Z, digits, spaces, or - . $ / + %. No asterisks."
        case .ean13: return "Required: 12 digits, or 13 including the check digit."
        case .ean8: return "Required: 7 digits, or 8 including the check digit."
        case .upca: return "Required: 11 digits, or 12 including the check digit."
        case .upce: return "Required: number system 0 or 1 plus 6 digits; optionally append the check digit."
        case .itf: return "Required: an even number of digits. No check digit is added."
        case .itf14: return "Required: 13 digits, or 14 including the check digit."
        case .gs1128: return "Required: application identifiers in parentheses, followed by their values. Example: (01)09501101530003(10)LOT123(17)271231."
        default: return "Required: text, a URL, or other data. Capacity depends on the selected format."
        }
    }

    var example: String {
        switch self {
        case .amazonFNSKU: return "X001ABCDEF"
        case .code128, .code39: return "ABC123"
        case .ean13: return "5901234123457"
        case .ean8: return "96385074"
        case .upca: return "036000291452"
        case .upce: return "04252614"
        case .itf: return "123456"
        case .itf14: return "10012345000017"
        case .gs1128: return "(01)09501101530003(10)LOT123"
        default: return "https://example.com"
        }
    }

    func validatedValue(_ input: String) throws -> String {
        guard !input.isEmpty else { throw BarcodeError("Enter the required barcode data.") }
        guard input.utf8.count <= 3000 else { throw BarcodeError("Enter no more than 3,000 UTF-8 bytes.") }
        if self == .amazonFNSKU {
            guard input.count == 10, input.allSatisfy({ ("A"..."Z").contains($0) || ("0"..."9").contains($0) }) else {
                throw BarcodeError("FNSKU must contain exactly 10 uppercase letters or digits.")
            }
        }
        let lengths: [Int]?
        switch self {
        case .ean13: lengths = [12, 13]
        case .ean8: lengths = [7, 8]
        case .upca: lengths = [11, 12]
        case .upce: lengths = [7, 8]
        case .itf14: lengths = [13, 14]
        default: lengths = nil
        }
        if let lengths {
            guard input.allSatisfy({ $0 >= "0" && $0 <= "9" }), lengths.contains(input.count) else {
                throw BarcodeError(guidance)
            }
            if self == .upce {
                guard input.first == "0" || input.first == "1" else { throw BarcodeError(guidance) }
                return input
            }
            if input.count == lengths[0] {
                let sum = input.reversed().enumerated().reduce(0) {
                    $0 + ($1.element.wholeNumberValue ?? 0) * ($1.offset.isMultiple(of: 2) ? 3 : 1)
                }
                return input + String((10 - sum % 10) % 10)
            }
        }
        if self == .itf {
            guard input.count.isMultiple(of: 2), input.allSatisfy({ $0 >= "0" && $0 <= "9" }) else {
                throw BarcodeError(guidance)
            }
        }
        if self == .code39 {
            let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -.\u{0024}/+%")
            guard input.allSatisfy({ allowed.contains($0) }) else { throw BarcodeError(guidance) }
        }
        if self == .code128, !input.unicodeScalars.allSatisfy({ $0.value < 128 }) {
            throw BarcodeError(guidance)
        }
        return input
    }
}

struct BarcodeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct BarcodeArtwork {
    let size: CGSize
    let bars: [CGRect]

    func draw(in rect: CGRect, context: CGContext) {
        let scale = min(rect.width / size.width, rect.height / size.height)
        guard scale > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        context.translateBy(x: rect.midX - size.width * scale / 2,
                            y: rect.midY - size.height * scale / 2)
        context.scaleBy(x: scale, y: scale)
        context.setShouldAntialias(false)
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bars)
    }

    func image(size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            self.draw(in: rect, context: context)
            return true
        }
    }
}

@MainActor
final class BarcodeGenerator {
    static let shared = BarcodeGenerator()
    private let context: JSContext?

    private init() {
        context = JSContext()
        let decodeBase64: @convention(block) (String) -> String = { encoded in
            guard let data = Data(base64Encoded: encoded) else { return "" }
            return String(data: data, encoding: .isoLatin1) ?? ""
        }
        context?.setObject(decodeBase64, forKeyedSubscript: "atob" as NSString)
        if let url = Bundle.main.url(forResource: "bwip-js-min", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            context?.evaluateScript(source)
        }
    }

    func generate(_ input: String, format: BarcodeFormat) throws -> BarcodeArtwork {
        let value = try format.validatedValue(input)
        guard let context, let encoder = context.objectForKeyedSubscript("bwipjs"),
              !encoder.isUndefined else {
            throw BarcodeError("The bundled barcode encoder could not be loaded.")
        }
        context.exception = nil
        let usesUTF8 = !format.isLinear && value.unicodeScalars.contains { $0.value > 127 }
        let encodedValue = usesUTF8
            ? "^ECI000026" + value.replacingOccurrences(of: "^", with: "^^") : value
        let result = encoder.invokeMethod("raw", withArguments: [
            ["bcid": format.encoderName, "text": encodedValue, "height": 0.5,
             "includetext": false, "parsefnc": usesUTF8]
        ])
        if let exception = context.exception {
            let message = exception.toString() ?? "The data is invalid for this barcode type."
            let readable = message.replacingOccurrences(of: "^Error: bwipp\\.[^:]+: ",
                                                        with: "", options: .regularExpression)
            throw BarcodeError(readable)
        }
        guard let objects = result?.toArray() as? [[String: Any]], objects.count == 1,
              let object = objects.first else {
            throw BarcodeError("Unable to encode this barcode.")
        }
        var bars: [CGRect] = []
        let size: CGSize
        if let pixels = object["pixs"] as? [Int],
           let width = object["pixx"] as? Int, let height = object["pixy"] as? Int,
           width > 0, height > 0, pixels.count == width * height {
            let physicalWidth = (object["width"] as? Double) ?? Double(width)
            let physicalHeight = (object["height"] as? Double) ?? Double(height)
            let rowHeight = CGFloat(physicalHeight / physicalWidth * Double(width) / Double(height))
            let margin: CGFloat = format == .qr ? 4 : 2
            size = CGSize(width: CGFloat(width) + margin * 2,
                          height: CGFloat(height) * rowHeight + margin * 2)
            for y in 0..<height {
                for x in 0..<width where pixels[y * width + x] != 0 {
                    bars.append(CGRect(x: margin + CGFloat(x),
                                       y: margin + CGFloat(height - 1 - y) * rowHeight,
                                       width: 1, height: rowHeight))
                }
            }
        } else if let widths = object["sbs"] as? [Double],
                  let heights = object["bhs"] as? [Double],
                  let baselines = object["bbs"] as? [Double],
                  heights.count == (widths.count + 1) / 2, baselines.count == heights.count {
            var x: CGFloat = 10
            var maxY: CGFloat = 0
            for (index, width) in widths.enumerated() {
                if index.isMultiple(of: 2) {
                    let y = CGFloat(baselines[index / 2] * 72)
                    let height = CGFloat(heights[index / 2] * 72)
                    bars.append(CGRect(x: x, y: y, width: width, height: height))
                    maxY = max(maxY, y + height)
                }
                x += width
            }
            if format == .itf14 {
                bars = bars.map { $0.offsetBy(dx: 5, dy: 5) }
                bars.append(CGRect(x: 0, y: 0, width: x + 20, height: 5))
                bars.append(CGRect(x: 0, y: maxY + 5, width: x + 20, height: 5))
                bars.append(CGRect(x: 0, y: 0, width: 5, height: maxY + 10))
                bars.append(CGRect(x: x + 15, y: 0, width: 5, height: maxY + 10))
                size = CGSize(width: x + 20, height: maxY + 10)
            } else {
                size = CGSize(width: x + 10, height: maxY)
            }
        } else {
            throw BarcodeError("The encoder returned unsupported barcode geometry.")
        }
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0, !bars.isEmpty else {
            throw BarcodeError("The encoder returned an empty barcode.")
        }
        return BarcodeArtwork(size: size, bars: bars)
    }
}
