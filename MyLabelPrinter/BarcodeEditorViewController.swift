import Cocoa

final class BarcodeEditorViewController: NSViewController, NSTextFieldDelegate, NSComboBoxDelegate {
    var onAdd: ((String, BarcodeFormat, AmazonLabelDetails?, Bool) throws -> Void)?
    private let formatPopup = NSPopUpButton()
    private let inputLabel = NSTextField(labelWithString: "")
    private let input = NSTextField()
    private let guidance = NSTextField(wrappingLabelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let preview = NSImageView()
    private let amazonFields = NSStackView()
    private let productName = NSTextField()
    private let condition = NSComboBox()
    private let showData = NSButton(checkboxWithTitle: "Show data below barcode", target: nil, action: nil)
    private let showDataDefaultsKey = "barcodeShowsData"

    private var format: BarcodeFormat {
        BarcodeFormat.allCases[formatPopup.indexOfSelectedItem]
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 600))
        let title = NSTextField(labelWithString: "Add Barcode")
        title.font = .boldSystemFont(ofSize: 20)
        let typeLabel = NSTextField(labelWithString: "Barcode Type")
        formatPopup.addItems(withTitles: BarcodeFormat.allCases.map(\.title))
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        formatPopup.setAccessibilityLabel("Barcode Type")
        input.delegate = self
        input.target = self
        input.action = #selector(updatePreview)
        guidance.textColor = .secondaryLabelColor
        errorLabel.textColor = .systemRed
        errorLabel.setAccessibilityLabel("Barcode validation")
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.setAccessibilityLabel("Barcode preview")

        productName.placeholderString = "Product name from your Amazon listing"
        productName.setAccessibilityLabel("Product name")
        productName.delegate = self
        condition.delegate = self
        productName.target = self
        productName.action = #selector(updatePreview)
        condition.addItems(withObjectValues: AmazonLabelDetails.conditions)
        condition.stringValue = "New"
        condition.isEditable = true
        condition.setAccessibilityLabel("Product condition")
        amazonFields.orientation = .vertical
        amazonFields.alignment = .leading
        amazonFields.spacing = 8
        for field in [NSTextField(labelWithString: "Product name (required)"), productName,
                      NSTextField(labelWithString: "Condition (required; select or type listing condition)"), condition] {
            amazonFields.addArrangedSubview(field)
        }
        productName.widthAnchor.constraint(equalTo: amazonFields.widthAnchor).isActive = true
        condition.widthAnchor.constraint(equalTo: amazonFields.widthAnchor).isActive = true

        showData.state = (UserDefaults.standard.object(forKey: showDataDefaultsKey) as? Bool ?? true) ? .on : .off
        showData.target = self
        showData.action = #selector(showDataChanged)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{001b}"
        let add = NSButton(title: "Add Barcode", target: self, action: #selector(addBarcode))
        add.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancel, add])
        buttons.orientation = .horizontal
        buttons.spacing = 12

        let stack = NSStackView(views: [title, typeLabel, formatPopup, inputLabel, input,
                                       guidance, amazonFields, showData, preview, errorLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            formatPopup.widthAnchor.constraint(equalTo: stack.widthAnchor),
            input.widthAnchor.constraint(equalTo: stack.widthAnchor),
            guidance.widthAnchor.constraint(equalTo: stack.widthAnchor),
            amazonFields.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),
            errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        preferredContentSize = view.frame.size
        formatChanged()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(input)
    }

    @objc private func formatChanged() {
        amazonFields.isHidden = format != .amazonFNSKU
        inputLabel.stringValue = format.fieldTitle + " (required)"
        input.setAccessibilityLabel(inputLabel.stringValue)
        input.placeholderString = format.example
        guidance.stringValue = format.guidance
        updatePreview()
    }

    func controlTextDidChange(_ notification: Notification) {
        updatePreview()
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        if let selected = condition.objectValueOfSelectedItem as? String {
            condition.stringValue = selected
        }
        updatePreview()
    }

    @objc private func showDataChanged() {
        UserDefaults.standard.set(showData.state == .on, forKey: showDataDefaultsKey)
        updatePreview()
    }

    @objc private func updatePreview() {
        guard !input.stringValue.isEmpty else {
            preview.image = nil
            errorLabel.stringValue = ""
            return
        }
        do {
            let artwork = try BarcodeGenerator.shared.generate(input.stringValue, format: format)
            let box = CodeBoxView(frame: CGRect(x: 0, y: 0, width: 460, height: 220))
            box.type = format
            box.code = try format.validatedValue(input.stringValue)
            box.artwork = artwork
            box.amazonDetails = try amazonDetails()
            box.showsData = showData.state == .on
            box.showsBorder = false
            let draw = try box.printDrawing()
            preview.image = NSImage(size: box.frame.size, flipped: false) { _ in
                draw(box)
                return true
            }
            errorLabel.stringValue = ""
        } catch {
            preview.image = nil
            errorLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func addBarcode() {
        do {
            let value = try format.validatedValue(input.stringValue)
            try onAdd?(value, format, amazonDetails(), showData.state == .on)
            dismiss(self)
        } catch {
            preview.image = nil
            errorLabel.stringValue = error.localizedDescription
        }
    }

    private func amazonDetails() throws -> AmazonLabelDetails? {
        guard format == .amazonFNSKU else { return nil }
        return try AmazonLabelDetails(productName: productName.stringValue,
                                      condition: condition.stringValue).validated()
    }

    @objc private func cancel() {
        dismiss(self)
    }
}
