import Cocoa

final class FrameEditorViewController: NSViewController, NSTextFieldDelegate {
    var onAdd: ((LabelFrame, CGSize) throws -> Void)?
    var maximumSizeMM = CGSize(width: 1000, height: 1000)
    private let style = NSPopUpButton()
    private let weight = NSPopUpButton()
    private let width = NSTextField(string: "30")
    private let height = NSTextField(string: "20")
    private let radius = NSTextField(string: "2")
    private let gap = NSTextField(string: "1")
    private let spacing = NSTextField(string: "1.5")
    private let preview = NSImageView()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private var radiusRow = NSView()
    private var gapRow = NSView()
    private var spacingRow = NSView()

    override func loadView() {
        view = NSView(frame: CGRect(x: 0, y: 0, width: 480, height: 540))
        let title = NSTextField(labelWithString: "Add Frame")
        title.font = .boldSystemFont(ofSize: 20)
        style.addItems(withTitles: LabelFrameStyle.allCases.map(\.rawValue))
        weight.addItems(withTitles: ["Simple (1 pt)", "Thin (0.5 pt)", "Thick (3 pt)"])
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .floor
        width.stringValue = formatter.string(from: NSNumber(value: Double(maximumSizeMM.width))) ?? ""
        height.stringValue = formatter.string(from: NSNumber(value: Double(maximumSizeMM.height))) ?? ""
        for popup in [style, weight] {
            popup.target = self
            popup.action = #selector(optionsChanged)
        }
        for field in [width, height, radius, gap, spacing] { field.delegate = self }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.addArrangedSubview(title)
        func row(_ title: String, _ control: NSView) -> NSView {
            let label = NSTextField(labelWithString: title)
            label.widthAnchor.constraint(equalToConstant: 170).isActive = true
            control.setAccessibilityLabel(title)
            let row = NSStackView(views: [label, control])
            row.spacing = 12
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            control.widthAnchor.constraint(equalToConstant: 240).isActive = true
            return row
        }
        _ = row("Frame Type", style)
        _ = row("Border", weight)
        _ = row("Width (mm)", width)
        _ = row("Height (mm)", height)
        radiusRow = row("Corner radius (mm)", radius)
        gapRow = row("Border gap (mm)", gap)
        spacingRow = row("Dot spacing (mm)", spacing)
        stack.addArrangedSubview(NSTextField(labelWithString: "Preview"))
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.setAccessibilityLabel("Selected frame preview")
        stack.addArrangedSubview(preview)
        preview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 150).isActive = true
        errorLabel.textColor = .systemRed
        stack.addArrangedSubview(errorLabel)
        errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{001b}"
        let add = NSButton(title: "Add Frame", target: self, action: #selector(addFrame))
        add.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancel, add])
        buttons.spacing = 12
        stack.addArrangedSubview(buttons)
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24)
        ])
        preferredContentSize = view.frame.size
        optionsChanged()
    }

    private func number(_ field: NSTextField) throws -> CGFloat {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let value = formatter.number(from: text)?.doubleValue,
              value.isFinite, value > 0, value <= 1000 else {
            throw FrameError("Enter positive numbers up to 1000 in the visible size fields.")
        }
        return CGFloat(value)
    }

    private func configuration() throws -> (LabelFrame, CGSize) {
        var frame = LabelFrame(style: LabelFrameStyle.allCases[style.indexOfSelectedItem],
                               weight: LabelFrameWeight.allCases[weight.indexOfSelectedItem])
        if frame.style == .rounded { frame.cornerRadiusMM = try number(radius) }
        if frame.style == .doubleRectangle { frame.doubleGapMM = try number(gap) }
        if frame.style == .dotted { frame.dotSpacingMM = try number(spacing) }
        let size = try CGSize(width: number(width), height: number(height))
        try frame.validate(sizeMM: size)
        guard size.width <= maximumSizeMM.width, size.height <= maximumSizeMM.height else {
            throw FrameError("The frame must fit inside the label’s rounded corners.")
        }
        return (frame, size)
    }

    func controlTextDidChange(_ notification: Notification) { optionsChanged() }

    @objc private func optionsChanged() {
        let selected = LabelFrameStyle.allCases[style.indexOfSelectedItem]
        radiusRow.isHidden = selected != .rounded
        gapRow.isHidden = selected != .doubleRectangle
        spacingRow.isHidden = selected != .dotted
        do {
            let (frame, size) = try configuration()
            let scale = min(400 / size.width, 140 / size.height)
            let imageSize = CGSize(width: size.width * scale + 8, height: size.height * scale + 8)
            preview.image = NSImage(size: imageSize, flipped: false) { rect in
                NSColor.white.setFill()
                rect.fill()
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                frame.draw(in: rect.insetBy(dx: 4, dy: 4), context: context, pixelsPerMM: scale)
                return true
            }
            errorLabel.stringValue = ""
        } catch {
            preview.image = nil
            errorLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func addFrame() {
        do {
            let (frame, size) = try configuration()
            try onAdd?(frame, size)
            dismiss(self)
        } catch {
            errorLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func cancel() { dismiss(self) }
}
