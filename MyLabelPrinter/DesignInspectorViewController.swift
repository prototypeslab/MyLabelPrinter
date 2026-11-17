import Cocoa
import UniformTypeIdentifiers

private final class InspectorDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class DesignInspectorViewController: NSViewController, NSTextFieldDelegate, NSComboBoxDelegate {
    weak var ruler: RulerImageView?
    var databaseFieldsProvider: () -> [String] = { [] }
    var databaseValueProvider: (String) -> String? = { _ in nil }
    private weak var item: NSView?
    private let stack = NSStackView()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let preview = NSImageView()
    private var fields: [String: NSTextField] = [:]
    private var menus: [String: NSPopUpButton] = [:]
    private var checks: [String: NSButton] = [:]
    private var rows: [String: NSView] = [:]
    private var combos: [String: NSComboBox] = [:]
    private var radiusStepper: NSStepper?
    private var artworkPicker: ArtworkPickerViewController?
    private var artworkPickerHeightConstraint: NSLayoutConstraint?
    private var horizontalAlignmentControl: NSSegmentedControl?
    private var verticalAlignmentControl: NSSegmentedControl?
    private var fontStyles: [String] = []
    private var formattingControl: NSSegmentedControl?
    private var directionControl: NSSegmentedControl?
    private var textColorControl: NSColorWell?
    private var typographySteppers: [String: NSStepper] = [:]
    private var rebuilding = false
    enum ObjectKind { case text, barcode, shape, frame, image, line }
    private var draftRuler: RulerImageView?
    private var imageChosen = false
    private let creationButtons = NSStackView()
    private var creationButtonsHeight: NSLayoutConstraint?
    private var editingRuler: RulerImageView? { draftRuler ?? ruler }
    private var availableFrameStyles: [LabelFrameStyle] {
        if editingRuler?.labelShape == .round {
            return [.circle, .circleDouble, .circleDotted]
        }
        return [.rectangle, .doubleRectangle, .rounded, .dotted]
    }

    func beginAdding(_ kind: ObjectKind, barcodeFormat: BarcodeFormat = .code128, value: String? = nil) {
        guard let ruler else { return }
        _ = view
        let draft = RulerImageView(frame: ruler.bounds)
        draft.setSize(width: ruler.labelSizeMM.width, height: ruler.labelSizeMM.height)
        draft.labelShape = ruler.labelShape
        draft.setZoomLevel(ruler.zoomLevel)
        do {
            switch kind {
            case .text:
                draft.addDemoLabel(text: "Text")
            case .barcode:
                let showsData = UserDefaults.standard.object(forKey: "barcodeShowsData") as? Bool ?? true
                try draft.addBarcode(value.flatMap { $0.isEmpty ? nil : $0 } ?? barcodeFormat.example,
                                     format: barcodeFormat, showsData: showsData)
            case .shape:
                try draft.addShape(LabelShape(), sizeMM: CGSize(width: min(20, ruler.labelSizeMM.width),
                                                                height: min(15, ruler.labelSizeMM.height)))
            case .frame:
                let style: LabelFrameStyle = ruler.labelShape == .round ? .circle : .rectangle
                try draft.addFrame(LabelFrame(style: style), sizeMM: ruler.maximumFrameSizeMM)
            case .line:
                draft.addLine(LabelLine())
            case .image:
                let placeholder = NSImage(size: CGSize(width: 32, height: 32), flipped: false) { rect in
                    NSColor.white.setFill()
                    rect.fill()
                    return true
                }
                guard let data = placeholder.tiffRepresentation else { throw ImageImportError() }
                try draft.addImage(data: data)
            }
            draftRuler = draft
            imageChosen = kind != .image
            render(draft.inspectorSelection)
        } catch {
            errorLabel.stringValue = error.localizedDescription
        }
    }

    @objc func cancelAdding() {
        draftRuler = nil
        render(ruler?.inspectorSelection)
    }

    @objc private func addDraft() {
        guard let draftRuler, let item, let ruler else { return }
        applyChanges(sender: nil)
        guard errorLabel.stringValue.isEmpty else { return }
        guard !(item is ImageItemView) || imageChosen else {
            errorLabel.stringValue = "Choose an image before adding it."
            return
        }
        do {
            try ruler.addInspectorDraft(item, fontScale: draftRuler.inspectorFontScale)
            self.draftRuler = nil
            render(ruler.inspectorSelection)
        } catch {
            errorLabel.stringValue = error.localizedDescription
        }
    }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let document = InspectorDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        let root = NSView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        creationButtons.translatesAutoresizingMaskIntoConstraints = false
        creationButtons.spacing = 12
        creationButtons.addArrangedSubview(NSButton(title: "Cancel", target: self, action: #selector(cancelAdding)))
        creationButtons.addArrangedSubview(NSButton(title: "Add", target: self, action: #selector(addDraft)))
        root.addSubview(scroll)
        root.addSubview(creationButtons)
        creationButtonsHeight = creationButtons.heightAnchor.constraint(equalToConstant: 0)
        creationButtonsHeight?.isActive = true
        view = root
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: creationButtons.topAnchor),
            creationButtons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            creationButtons.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12)
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        artworkPickerHeightConstraint?.constant = max(200, view.bounds.height - 66)
    }

    func inspect(_ selected: NSView?) {
        guard draftRuler == nil else { return }
        render(selected)
    }

    private func render(_ selected: NSView?) {
        _ = view
        creationButtons.isHidden = draftRuler == nil
        creationButtonsHeight?.constant = draftRuler == nil ? 0 : 44
        item = selected
        rebuilding = true
        defer { rebuilding = false }
        for child in stack.arrangedSubviews { stack.removeArrangedSubview(child); child.removeFromSuperview() }
        artworkPickerHeightConstraint?.isActive = false
        artworkPickerHeightConstraint = nil
        artworkPicker?.removeFromParent()
        artworkPicker = nil
        fields = [:]; menus = [:]; checks = [:]; rows = [:]; combos = [:]
        radiusStepper = nil
        errorLabel.stringValue = ""
        guard let selected, let ruler = editingRuler else {
            append(NSTextField(wrappingLabelWithString: "Select an object on the label to edit its settings."))
            return
        }
        selected.layoutSubtreeIfNeeded()
        let title: String
        if selected is LabelBoxView { title = "Text" }
        else if selected is CodeBoxView { title = "Barcode" }
        else if let image = selected as? ImageItemView { title = image.contentKind.rawValue }
        else if selected is ShapeItemView { title = "Shape" }
        else if selected is LineItemView { title = "Line" }
        else { title = "Frame" }
        let heading = NSTextField(labelWithString: draftRuler == nil ? title : "Add \(title)")
        heading.font = .boldSystemFont(ofSize: 18)
        append(heading)

        if let text = selected as? LabelBoxView {
            field("text", "Text", text.text)
            var databaseFields = [""] + databaseFieldsProvider()
            if let savedField = text.databaseField, !databaseFields.contains(savedField) {
                databaseFields.append(savedField)
            }
            menu("databaseField", "Database Field", databaseFields,
                 databaseFields.firstIndex(of: text.databaseField ?? "") ?? 0)
            fontControls(for: text, scale: ruler.inspectorFontScale)
            check("autoFont", "Fit font automatically", text.fitsFontAutomatically)
            append(NSTextField(labelWithString: "Alignment"))
            horizontalAlignmentControl = alignmentSegments(
                titles: ["Left", "Center", "Right", "Justify"],
                symbols: ["text.alignleft", "text.aligncenter", "text.alignright", "text.justify"],
                selected: LabelHorizontalAlignment.allCases.firstIndex(of: text.horizontalAlignment) ?? 1,
                label: "Horizontal alignment")
            verticalAlignmentControl = alignmentSegments(
                titles: ["Top", "Middle", "Bottom"],
                symbols: ["arrow.up.to.line", "arrow.up.and.down", "arrow.down.to.line"],
                selected: LabelVerticalAlignment.allCases.firstIndex(of: text.verticalAlignment) ?? 1,
                label: "Vertical alignment")
            append(NSTextField(labelWithString: "Text Direction"))
            directionControl = NSSegmentedControl(labels: ["Horizontal", "Vertical"], trackingMode: .selectOne,
                                                 target: self, action: #selector(changed))
            if let directionControl {
                directionControl.selectedSegment = text.textAppearance.isVertical ? 1 : 0
                directionControl.segmentDistribution = .fillEqually
                directionControl.setAccessibilityLabel("Text direction")
                append(directionControl)
            }
            append(NSTextField(labelWithString: "Spacing"))
            typographyNumber("characterSpacing", "Character Spacing (pt)", text.textAppearance.characterSpacing, minimum: 0, step: 0.5)
            typographyNumber("lineSpacing", "Space Between Lines (pt)", text.textAppearance.lineSpacing, minimum: 0, step: 0.5)
        } else if let code = selected as? CodeBoxView {
            menu("barcode", "Barcode Type", BarcodeFormat.allCases.map(\.title),
                 BarcodeFormat.allCases.firstIndex(of: code.type) ?? 0)
            field("data", code.type.fieldTitle, code.code)
            let guidance = NSTextField(wrappingLabelWithString: code.type.guidance)
            guidance.textColor = .secondaryLabelColor
            append(guidance)
            rows["guidance"] = guidance
            field("product", "Product name", code.amazonDetails?.productName ?? "")
            combo("condition", "Condition", AmazonLabelDetails.conditions, code.amazonDetails?.condition ?? "New")
            check("showData", "Show data below barcode", code.showsData)
        } else if let image = selected as? ImageItemView {
            if image.contentKind == .symbol || image.contentKind == .clipArt {
                let kind: ArtworkPickerViewController.Kind = image.contentKind == .symbol ? .symbol : .clipArt
                let picker = ArtworkPickerViewController(kind: kind)
                addChild(picker)
                artworkPicker = picker
                picker.onSelect = { [weak self, weak image] artwork in
                    guard let self, let image else { return }
                    do {
                        try image.replaceImage(data: ImageItemView.thermalArtworkData(artwork))
                        self.errorLabel.stringValue = ""
                        self.updatePreview()
                    } catch {
                        self.errorLabel.stringValue = error.localizedDescription
                    }
                }
                append(picker.view)
                let height = picker.view.heightAnchor.constraint(equalToConstant: max(200, view.bounds.height - 66))
                height.isActive = true
                artworkPickerHeightConstraint = height
            } else {
                let replace = NSButton(title: "Choose Image…", target: self, action: #selector(replaceImage))
                append(replace)
                append(NSTextField(wrappingLabelWithString: "The image scales proportionally to fit its box."))
            }
        } else if let shape = selected as? ShapeItemView {
            menu("shape", "Shape Type", LabelShapeStyle.allCases.map(\.rawValue),
                 LabelShapeStyle.allCases.firstIndex(of: shape.shape.style) ?? 0)
            weightMenu(shape.shape.weight)
            radiusField(shape.shape.cornerRadiusMM)
        } else if let frame = selected as? FrameItemView {
            let frameStyles = availableFrameStyles
            menu("frame", "Frame Type", frameStyles.map(\.rawValue),
                 frameStyles.firstIndex(of: frame.configuration.style) ?? 0)
            menu("border", "Border", ["Simple (1 pt)", "Thin (0.5 pt)", "Thick (3 pt)"],
                 LabelFrameWeight.allCases.firstIndex(of: frame.configuration.weight) ?? 0)
            radiusField(frame.configuration.cornerRadiusMM)
            field("gap", "Border gap (mm)", formatted(frame.configuration.doubleGapMM))
            field("spacing", "Dot spacing (mm)", formatted(frame.configuration.dotSpacingMM))
        } else if let line = selected as? LineItemView {
            weightMenu(line.line.weight)
            menu("line", "Style", LabelLineStyle.allCases.map(\.rawValue),
                 LabelLineStyle.allCases.firstIndex(of: line.line.style) ?? 0)
            menu("start", "Start Endpoint", LabelLineEndpoint.allCases.map(\.rawValue),
                 LabelLineEndpoint.allCases.firstIndex(of: line.line.startEndpoint) ?? 0)
            menu("end", "End Endpoint", LabelLineEndpoint.allCases.map(\.rawValue),
                 LabelLineEndpoint.allCases.firstIndex(of: line.line.endEndpoint) ?? 0)
        }
        let isArtwork = (selected as? ImageItemView).map {
            $0.contentKind == .symbol || $0.contentKind == .clipArt
        } ?? false
        errorLabel.textColor = .systemRed
        if !isArtwork {
            append(errorLabel)
        }
        if !isArtwork {
            preview.imageScaling = .scaleProportionallyUpOrDown
            preview.setAccessibilityLabel("Selected object preview")
            append(preview)
            if preview.constraints.first(where: { $0.firstAttribute == .height }) == nil {
                preview.heightAnchor.constraint(equalToConstant: 120).isActive = true
            }
        }
        updateVisibility()
        if isArtwork {
            preview.image = nil
        } else {
            updatePreview()
        }
    }

    private func fontControls(for text: LabelBoxView, scale: CGFloat) {
        append(NSTextField(labelWithString: "Font"))
        var families = NSFontManager.shared.availableFontFamilies.sorted()
        if let currentFamily = text.inspectorFont.familyName, !families.contains(currentFamily) {
            families.insert(currentFamily, at: 0)
        }
        menu("fontFamily", "Family", families, families.firstIndex(of: text.inspectorFont.familyName ?? "") ?? 0)
        menus["fontFamily"]?.action = #selector(fontFamilyChanged)
        let selected = NSComboBox()
        selected.stringValue = text.inspectorFont.fontName
        combos["font"] = selected
        menu("fontStyle", "Typeface", [], 0)
        menus["fontStyle"]?.action = #selector(fontStyleChanged)
        rebuildFontStyles(preferred: text.inspectorFont.fontName)
        typographyNumber("fontSize", "Size (pt)", text.inspectorFont.pointSize / scale, minimum: 1, step: 1)
        let formatting = NSSegmentedControl(labels: ["B", "I", "U", "S̶"], trackingMode: .selectAny,
                                            target: self, action: #selector(fontFormattingChanged))
        formatting.segmentDistribution = .fillEqually
        formatting.setAccessibilityLabel("Font formatting")
        let traits = NSFontManager.shared.traits(of: text.inspectorFont)
        formatting.setSelected(traits.contains(.boldFontMask), forSegment: 0)
        formatting.setSelected(traits.contains(.italicFontMask), forSegment: 1)
        formatting.setSelected(text.textAppearance.underline, forSegment: 2)
        formatting.setSelected(text.textAppearance.strikethrough, forSegment: 3)
        for (index, title) in ["Bold", "Italic", "Underline", "Strikethrough"].enumerated() {
            formatting.setToolTip(title, forSegment: index)
        }
        formattingControl = formatting
        append(formatting)
        let color = NSColorWell()
        color.color = text.textAppearance.color
        color.target = self
        color.action = #selector(changed)
        textColorControl = color
        row("textColor", "Text Color", color)
        rows["textColor"]?.isHidden = true
    }

    private func typographyNumber(_ key: String, _ title: String, _ value: CGFloat, minimum: Double, step: Double) {
        let input: NSTextField
        if key == "fontSize" {
            let sizes = NSComboBox()
            sizes.addItems(withObjectValues: ["6", "8", "9", "10", "11", "12", "14", "16", "18", "24", "28", "32", "36", "40", "48", "60", "72"])
            sizes.delegate = self
            input = sizes
        } else {
            input = NSTextField()
        }
        input.stringValue = formatted(value, fractionDigits: 1)
        input.delegate = self
        input.target = self
        input.action = #selector(changed)
        input.setAccessibilityLabel(title)
        fields[key] = input
        let stepper = NSStepper()
        stepper.minValue = minimum
        stepper.maxValue = 1000
        stepper.increment = step
        stepper.doubleValue = Double(value)
        stepper.valueWraps = false
        stepper.identifier = NSUserInterfaceItemIdentifier(key)
        stepper.setAccessibilityLabel(title)
        stepper.target = self
        stepper.action = #selector(typographyStep(_:))
        typographySteppers[key] = stepper
        row(key, title, NSStackView(views: [input, stepper]))
    }

    @objc private func typographyStep(_ sender: NSStepper) {
        guard let key = sender.identifier?.rawValue else { return }
        fields[key]?.stringValue = formatted(CGFloat(sender.doubleValue), fractionDigits: 1)
        applyChanges(sender: fields[key])
    }

    private func rebuildFontStyles(preferred: String?) {
        guard let family = menus["fontFamily"]?.titleOfSelectedItem, let menu = menus["fontStyle"] else { return }
        let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
        if members.isEmpty, let preferred {
            fontStyles = [preferred]
            menu.removeAllItems()
            menu.addItem(withTitle: "Regular")
            combos["font"]?.stringValue = preferred
            return
        }
        fontStyles = members.compactMap { $0.first as? String }
        menu.removeAllItems()
        menu.addItems(withTitles: members.compactMap { $0.count > 1 ? $0[1] as? String : nil })
        if let preferred, let index = fontStyles.firstIndex(of: preferred) {
            menu.selectItem(at: index)
        } else if let index = menu.itemTitles.firstIndex(of: "Regular") {
            menu.selectItem(at: index)
        }
        if fontStyles.indices.contains(menu.indexOfSelectedItem) {
            combos["font"]?.stringValue = fontStyles[menu.indexOfSelectedItem]
        }
    }

    private func syncFontTraits() {
        guard let name = combos["font"]?.stringValue, let font = NSFont(name: name, size: 12) else { return }
        let traits = NSFontManager.shared.traits(of: font)
        formattingControl?.setSelected(traits.contains(.boldFontMask), forSegment: 0)
        formattingControl?.setSelected(traits.contains(.italicFontMask), forSegment: 1)
    }

    @objc private func fontFamilyChanged() {
        rebuildFontStyles(preferred: nil)
        syncFontTraits()
        applyChanges(sender: combos["font"])
    }

    @objc private func fontStyleChanged() {
        let index = menus["fontStyle"]?.indexOfSelectedItem ?? -1
        guard fontStyles.indices.contains(index) else { return }
        combos["font"]?.stringValue = fontStyles[index]
        syncFontTraits()
        applyChanges(sender: combos["font"])
    }

    @objc private func fontFormattingChanged() {
        guard let control = formattingControl,
              let name = combos["font"]?.stringValue, var font = NSFont(name: name, size: 12) else { return }
        let manager = NSFontManager.shared
        font = control.isSelected(forSegment: 0) ? manager.convert(font, toHaveTrait: .boldFontMask)
            : manager.convert(font, toNotHaveTrait: .boldFontMask)
        font = control.isSelected(forSegment: 1) ? manager.convert(font, toHaveTrait: .italicFontMask)
            : manager.convert(font, toNotHaveTrait: .italicFontMask)
        combos["font"]?.stringValue = font.fontName
        rebuildFontStyles(preferred: font.fontName)
        syncFontTraits()
        applyChanges(sender: combos["font"])
    }

    private func alignmentSegments(titles: [String], symbols: [String], selected: Int,
                                   label: String) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: titles, trackingMode: .selectOne,
                                         target: self, action: #selector(changed))
        control.segmentStyle = .rounded
        control.segmentDistribution = .fillEqually
        control.setAccessibilityLabel(label)
        for index in titles.indices {
            if let icon = NSImage(systemSymbolName: symbols[index], accessibilityDescription: titles[index]) {
                control.setImage(icon, forSegment: index)
                control.setLabel("", forSegment: index)
            }
            control.setToolTip(titles[index], forSegment: index)
        }
        control.selectedSegment = selected
        append(control)
        return control
    }

    private func append(_ control: NSView) {
        stack.addArrangedSubview(control)
        control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func row(_ key: String, _ title: String, _ control: NSView) {
        control.setAccessibilityLabel(title)
        let label = NSTextField(labelWithString: title)
        label.alignment = .left
        let isSpacingRow = key == "characterSpacing" || key == "lineSpacing"
        if isSpacingRow {
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            label.lineBreakMode = .byTruncatingTail
            label.toolTip = title
        } else {
            label.widthAnchor.constraint(equalToConstant: 130).isActive = true
        }

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rows[key] = row
        append(row)
        if isSpacingRow, let input = fields[key], let stepper = typographySteppers[key],
           let controls = control as? NSStackView {
            let fixedWidth = 130 + row.spacing + controls.spacing + stepper.intrinsicContentSize.width
            input.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.5,
                                         constant: -fixedWidth / 2).isActive = true
        }
    }

    private func field(_ key: String, _ title: String, _ value: String) {
        let field = NSTextField(string: value)
        field.delegate = self
        field.target = self
        field.action = #selector(changed)
        fields[key] = field
        row(key, title, field)
    }

    private func menu(_ key: String, _ title: String, _ values: [String], _ index: Int) {
        let menu = NSPopUpButton()
        menu.addItems(withTitles: values)
        menu.selectItem(at: index)
        menu.target = self
        menu.action = #selector(changed)
        menus[key] = menu
        row(key, title, menu)
    }

    private func combo(_ key: String, _ title: String, _ values: [String], _ value: String) {
        let combo = NSComboBox()
        combo.addItems(withObjectValues: values)
        combo.stringValue = value
        combo.delegate = self
        combos[key] = combo
        row(key, title, combo)
    }

    private func check(_ key: String, _ title: String, _ value: Bool) {
        let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(changed))
        button.state = value ? .on : .off
        checks[key] = button
        row(key, title, button)
    }

    private func weightMenu(_ weight: CGFloat) {
        menu("weight", "Weight", ["0.25 pt", "0.5 pt", "0.75 pt", "1.0 pt", "1.5 pt", "2.25 pt", "3.0 pt", "4.5 pt", "6.0 pt"],
             LabelShape.weights.firstIndex(of: weight) ?? 3)
    }

    private func radiusField(_ value: CGFloat) {
        let field = NSTextField(string: formatted(value))
        field.delegate = self
        fields["radius"] = field
        let stepper = NSStepper()
        stepper.minValue = 0.1
        stepper.maxValue = 1000
        stepper.increment = 0.5
        stepper.valueWraps = false
        stepper.doubleValue = Double(value)
        stepper.target = self
        stepper.action = #selector(radiusChanged)
        radiusStepper = stepper
        row("radius", "Corner radius (mm)", NSStackView(views: [field, stepper]))
    }

    private func formatted(_ value: CGFloat, fractionDigits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: Double(value))) ?? ""
    }

    private func number(_ key: String, positive: Bool = false) throws -> CGFloat {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        guard let field = fields[key], let number = formatter.number(from: field.stringValue),
              number.doubleValue.isFinite, abs(number.doubleValue) <= 10000,
              !positive || number.doubleValue > 0 else {
            throw FrameError("Enter a valid number for \(key).")
        }
        return CGFloat(number.doubleValue)
    }

    private func index(_ key: String) -> Int { max(0, menus[key]?.indexOfSelectedItem ?? 0) }
    private func text(_ key: String) -> String { fields[key]?.stringValue ?? "" }
    private func checked(_ key: String) -> Bool { checks[key]?.state == .on }

    private func updateVisibility() {
        if menus["barcode"] != nil {
            let format = BarcodeFormat.allCases[index("barcode")]
            rows["product"]?.isHidden = format != .amazonFNSKU
            rows["condition"]?.isHidden = format != .amazonFNSKU
            (rows["guidance"] as? NSTextField)?.stringValue = format.guidance
            if let row = rows["data"] as? NSStackView,
               let label = row.arrangedSubviews.first as? NSTextField {
                label.stringValue = format.fieldTitle
                fields["data"]?.setAccessibilityLabel(format.fieldTitle)
            }
        }
        if menus["shape"] != nil { rows["radius"]?.isHidden = LabelShapeStyle.allCases[index("shape")] != .rounded }
        if menus["frame"] != nil {
            let style = availableFrameStyles[index("frame")]
            rows["radius"]?.isHidden = style != .rounded
            rows["gap"]?.isHidden = style != .doubleRectangle && style != .circleDouble
            rows["spacing"]?.isHidden = style != .dotted && style != .circleDotted
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        if let radius = try? number("radius", positive: true) { radiusStepper?.doubleValue = Double(radius) }
        changed(notification.object)
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        if let combo = notification.object as? NSComboBox, let value = combo.objectValueOfSelectedItem as? String {
            combo.stringValue = value
        }
        changed(notification.object)
    }

    @objc private func radiusChanged() {
        if let stepper = radiusStepper { fields["radius"]?.stringValue = formatted(CGFloat(stepper.doubleValue)) }
        applyChanges(sender: nil)
    }

    @objc private func changed(_ sender: Any?) { applyChanges(sender: sender) }

    private func applyChanges(sender: Any?) {
        guard !rebuilding, let item, item.superview != nil, let ruler = editingRuler else { return }
        updateVisibility()
        do {
            if let line = item as? LineItemView {
                var value = line.line
                value.weight = LabelShape.weights[index("weight")]
                value.style = LabelLineStyle.allCases[index("line")]
                value.startEndpoint = LabelLineEndpoint.allCases[index("start")]
                value.endEndpoint = LabelLineEndpoint.allCases[index("end")]
                try value.validate()
                line.line = value
            } else {
                let rect = ruler.inspectorRect(for: item)
                guard rect.width <= 1000, rect.height <= 1000 else { throw FrameError("Dimensions must not exceed 1000 mm.") }
                if let textBox = item as? LabelBoxView {
                    let fontName = combos["font"]?.stringValue ?? ""
                    let fontSize = try number("fontSize", positive: true)
                    guard fontSize <= 1000, NSFont(name: fontName, size: fontSize) != nil else {
                        throw FrameError("Choose an available font and a size up to 1000 pt.")
                    }
                    var textAppearance = textBox.textAppearance
                    textAppearance.characterSpacing = try number("characterSpacing")
                    textAppearance.lineSpacing = try number("lineSpacing")
                    textAppearance.isVertical = directionControl?.selectedSegment == 1
                    textAppearance.underline = formattingControl?.isSelected(forSegment: 2) == true
                    textAppearance.strikethrough = formattingControl?.isSelected(forSegment: 3) == true
                    if let color = textColorControl?.color.usingColorSpace(.deviceRGB) {
                        textAppearance.red = color.redComponent
                        textAppearance.green = color.greenComponent
                        textAppearance.blue = color.blueComponent
                    }
                    guard textAppearance.isValid else { throw FrameError("Spacing must be between 0 and 1000 pt.") }
                    textBox.textAppearance = textAppearance
                    textAppearance.remember()
                    for key in ["fontSize", "characterSpacing", "lineSpacing"] {
                        if let value = try? number(key) { typographySteppers[key]?.doubleValue = Double(value) }
                    }
                    let fontEdited = (sender as? NSControl) === combos["font"] || (sender as? NSControl) === fields["fontSize"]
                    if fontEdited {
                        checks["autoFont"]?.state = .off
                        UserDefaults.standard.set(fontName, forKey: "textFontName")
                        UserDefaults.standard.set(Double(fontSize), forKey: "textFontSize")
                    }
                    textBox.text = text("text")
                    let selectedDatabaseField = menus["databaseField"]?.titleOfSelectedItem ?? ""
                    textBox.databaseField = selectedDatabaseField.isEmpty ? nil : selectedDatabaseField
                    if (sender as? NSControl) === menus["databaseField"],
                       !selectedDatabaseField.isEmpty,
                       let value = databaseValueProvider(selectedDatabaseField) {
                        textBox.text = value
                        fields["text"]?.stringValue = value
                    }
                    if !checked("autoFont") { textBox.setFont(name: fontName, size: fontSize * ruler.inspectorFontScale) }
                    textBox.setAutomaticFontFit(checked("autoFont"))
                    if fontEdited || (sender as? NSControl) === checks["autoFont"] {
                        UserDefaults.standard.set(checked("autoFont"), forKey: "textFitsFontAutomatically")
                    }
                    if let horizontalAlignmentControl, let verticalAlignmentControl {
                        textBox.horizontalAlignment = LabelHorizontalAlignment.allCases[max(0, horizontalAlignmentControl.selectedSegment)]
                        textBox.verticalAlignment = LabelVerticalAlignment.allCases[max(0, verticalAlignmentControl.selectedSegment)]
                        if (sender as? NSSegmentedControl) === horizontalAlignmentControl ||
                            (sender as? NSSegmentedControl) === verticalAlignmentControl {
                            UserDefaults.standard.set(textBox.horizontalAlignment.rawValue, forKey: "textHorizontalAlignment")
                            UserDefaults.standard.set(textBox.verticalAlignment.rawValue, forKey: "textVerticalAlignment")
                        }
                    }
                } else if let code = item as? CodeBoxView {
                    let format = BarcodeFormat.allCases[index("barcode")]
                    let value = try format.validatedValue(text("data"))
                    let artwork = try BarcodeGenerator.shared.generate(value, format: format)
                    let details = format == .amazonFNSKU
                        ? try AmazonLabelDetails(productName: text("product"), condition: combos["condition"]?.stringValue ?? "").validated() : nil
                    code.type = format
                    code.code = value
                    code.artwork = artwork
                    code.amazonDetails = details
                    code.showsData = checked("showData")
                    if (sender as? NSButton) === checks["showData"] {
                        UserDefaults.standard.set(code.showsData, forKey: "barcodeShowsData")
                    }
                } else if let shape = item as? ShapeItemView {
                    var value = shape.shape
                    value.style = LabelShapeStyle.allCases[index("shape")]
                    value.weight = LabelShape.weights[index("weight")]
                    if value.style == .rounded { value.cornerRadiusMM = try number("radius", positive: true) }
                    try value.validate(sizeMM: rect.size)
                    shape.shape = value
                } else if let frame = item as? FrameItemView, !(frame is ImageItemView) {
                    var value = frame.configuration
                    value.style = availableFrameStyles[index("frame")]
                    value.weight = LabelFrameWeight.allCases[index("border")]
                    if value.style == .rounded { value.cornerRadiusMM = try number("radius", positive: true) }
                    if value.style == .doubleRectangle || value.style == .circleDouble {
                        value.doubleGapMM = try number("gap", positive: true)
                    }
                    if value.style == .dotted || value.style == .circleDotted {
                        value.dotSpacingMM = try number("spacing", positive: true)
                    }
                    try value.validate(sizeMM: rect.size)
                    frame.configuration = value
                }
                ruler.applyInspectorRect(rect, to: item)
            }
            item.needsDisplay = true
            errorLabel.stringValue = ""
            updatePreview()
        } catch {
            errorLabel.stringValue = error.localizedDescription
        }
    }

    private func updatePreview() {
        guard let item, let ruler = editingRuler else { preview.image = nil; return }
        do {
            let draw: (NSView) -> Void
            var area = item.frame
            if let text = item as? LabelBoxView { draw = try text.printDrawing() }
            else if let code = item as? CodeBoxView { draw = try code.printDrawing() }
            else if let frame = item as? FrameItemView {
                draw = frame.printDrawing()
                let padding = max(4, frame.configuration.weight.points * ruler.inspectorFontScale * 2)
                area = area.insetBy(dx: -padding, dy: -padding)
            }
            else if let line = item as? LineItemView {
                draw = line.printDrawing()
                let a = line.line.startMM, b = line.line.endMM, scale = line.pixelsPerMM
                area = CGRect(x: min(a.x, b.x) * scale, y: min(a.y, b.y) * scale,
                              width: max(1, abs(a.x - b.x) * scale), height: max(1, abs(a.y - b.y) * scale))
                    .insetBy(dx: -30 * ruler.inspectorFontScale, dy: -30 * ruler.inspectorFontScale)
            } else { return }
            guard area.width > 0, area.height > 0 else { return }
            let scale = min(280 / area.width, 110 / area.height)
            let destination = area
            preview.image = NSImage(size: CGSize(width: area.width * scale, height: area.height * scale), flipped: false) { rect in
                NSColor.white.setFill()
                rect.fill()
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.saveGState()
                defer { context.restoreGState() }
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: -destination.minX, y: -destination.minY)
                draw(item)
                return true
            }
        } catch { preview.image = nil }
    }

    @objc private func replaceImage() {
        guard let image = item as? ImageItemView else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            try image.replaceImage(data: Data(contentsOf: url))
            imageChosen = true
            errorLabel.stringValue = ""
            updatePreview()
        } catch { errorLabel.stringValue = error.localizedDescription }
    }
}
