import Cocoa

final class ShapeEditorViewController: NSViewController, NSTextFieldDelegate {
    var onAdd: ((LabelShape, CGSize) throws -> Void)?
    var maximumSizeMM = CGSize(width: 1000, height: 1000)
    private let style = NSPopUpButton()
    private let weight = NSPopUpButton()
    private let width = NSTextField(string: "30")
    private let height = NSTextField(string: "20")
    private let radius = NSTextField(string: "2")
    private let radiusStepper = NSStepper()
    private let preview = NSImageView()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private var radiusRow = NSView()
        
    override func loadView() {
        view = NSView(frame: CGRect(x: 0, y: 0, width: 480, height: 540))
        let title = NSTextField(labelWithString: "Add Shape")
        title.font = .boldSystemFont(ofSize: 20)
        style.addItems(withTitles: LabelShapeStyle.allCases.map(\.rawValue))
        weight.addItems(withTitles: ["0.25 pt", "0.5 pt", "0.75 pt", "1.0 pt", "1.5 pt", "2.25 pt", "3.0 pt", "4.5 pt", "6.0 pt"])
        weight.selectItem(at: 3)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .floor
        width.stringValue = formatter.string(from: NSNumber(value: Double(min(30, maximumSizeMM.width * 0.8)))) ?? ""
        height.stringValue = formatter.string(from: NSNumber(value: Double(min(20, maximumSizeMM.height * 0.8)))) ?? ""
        for popup in [style, weight] {
            popup.target = self
            popup.action = #selector(optionsChanged)
        }
        for field in [width, height, radius] { field.delegate = self }
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
        _ = row("Shape Type", style)
        _ = row("Weight", weight)
        _ = row("Width (mm)", width)
        _ = row("Height (mm)", height)
        radiusStepper.minValue = 0.1
        radiusStepper.maxValue = 1000
        radiusStepper.increment = 0.5
        radiusStepper.valueWraps = false
        radiusStepper.doubleValue = 2
        radiusStepper.target = self
        radiusStepper.action = #selector(radiusStepped)
        radiusStepper.setAccessibilityLabel("Adjust corner radius in millimeters")
        radius.setAccessibilityLabel("Corner radius in millimeters")
        let radiusControls = NSStackView(views: [radius, radiusStepper])
        radiusControls.spacing = 8
        radiusRow = row("Corner radius (mm)", radiusControls)
        stack.addArrangedSubview(NSTextField(labelWithString: "Preview"))
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.setAccessibilityLabel("Selected shape preview")
        stack.addArrangedSubview(preview)
        preview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 150).isActive = true
        errorLabel.textColor = .systemRed
        stack.addArrangedSubview(errorLabel)
        errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{001b}"
        let add = NSButton(title: "Add Shape", target: self, action: #selector(addShape))
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

    private func configuration() throws -> (LabelShape, CGSize) {
        var frame = LabelShape(style: LabelShapeStyle.allCases[style.indexOfSelectedItem],
                               weight: LabelShape.weights[weight.indexOfSelectedItem])
        if frame.style == .rounded { frame.cornerRadiusMM = try number(radius) }
        let size = try CGSize(width: number(width), height: number(height))
        try frame.validate(sizeMM: size)
        guard size.width <= maximumSizeMM.width, size.height <= maximumSizeMM.height else {
            throw FrameError("The shape must fit within the label.")
        }
        return (frame, size)
    }

    func controlTextDidChange(_ notification: Notification) {
        if let value = try? number(radius) {
            radiusStepper.doubleValue = Double(value)
        }
        optionsChanged()
    }

    @objc private func radiusStepped() {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 3
        radius.stringValue = formatter.string(from: NSNumber(value: radiusStepper.doubleValue)) ?? ""
        optionsChanged()
    }

    @objc private func optionsChanged() {
        let selected = LabelShapeStyle.allCases[style.indexOfSelectedItem]
        radiusRow.isHidden = selected != .rounded
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

    @objc private func addShape() {
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

