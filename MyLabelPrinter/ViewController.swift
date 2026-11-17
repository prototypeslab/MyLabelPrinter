import Cocoa
import UniformTypeIdentifiers


struct DatabaseRecord {
    var isSelected = true
    var values: [String: String]
}

final class DatabaseViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let joinFieldsButton = NSButton(title: "Join Fields", target: nil, action: nil)
    private let clearDatabaseButton = NSButton(title: "Clear Database", target: nil, action: nil)
    private var sourceFields: [String] = []
    private var joinedFields: [JoinedField] = []
    var sourceName = "Fields"
    var onFieldsChanged: (() -> Void)?
    private(set) var fields: [String] = []
    private(set) var records: [DatabaseRecord] = []

    var selectedRecords: [DatabaseRecord] { records.filter(\.isSelected) }

    override func loadView() {
        let root = NSView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)
        joinFieldsButton.target = self
        joinFieldsButton.action = #selector(showJoinedFields)
        joinFieldsButton.isEnabled = !sourceFields.isEmpty
        joinFieldsButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(joinFieldsButton)
        clearDatabaseButton.target = self
        clearDatabaseButton.action = #selector(clearDatabase)
        clearDatabaseButton.isEnabled = !sourceFields.isEmpty
        clearDatabaseButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(clearDatabaseButton)
        NSLayoutConstraint.activate([
            joinFieldsButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            joinFieldsButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            clearDatabaseButton.leadingAnchor.constraint(equalTo: joinFieldsButton.trailingAnchor, constant: 8),
            clearDatabaseButton.centerYAnchor.constraint(equalTo: joinFieldsButton.centerYAnchor),
            scrollView.topAnchor.constraint(equalTo: joinFieldsButton.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)
        ])
        view = root
    }

    func load(url: URL, headerRow: Bool = true) throws {
        let parsed = url.pathExtension.lowercased() == "vcf"
            ? try ContactTable.readVCard(url) : try ContactTable.readCSV(url, headerRow: headerRow)
        load(parsed)
    }

    func load(_ data: ContactTable) {
        sourceFields = data.fields
        joinedFields = []
        fields = data.fields
        joinFieldsButton.isEnabled = !sourceFields.isEmpty
        clearDatabaseButton.isEnabled = !sourceFields.isEmpty
        records = data.rows.map { DatabaseRecord(values: $0) }
        rebuildColumns()
        tableView.reloadData()
    }

    func clear() {
        sourceFields = []
        joinedFields = []
        joinFieldsButton.isEnabled = false
        clearDatabaseButton.isEnabled = false
        fields = []
        records = []
        rebuildColumns()
        tableView.reloadData()
    }

    @objc private func clearDatabase() {
        clear()
        onFieldsChanged?()
    }

    @objc private func showJoinedFields() {
        let manager = JoinedFieldsViewController()
        manager.sourceFields = sourceFields
        manager.sourceName = sourceName
        manager.joinedFields = joinedFields
        manager.onChange = { [weak self] fields in self?.updateJoinedFields(fields) }
        presentAsModalWindow(manager)
    }

    private func updateJoinedFields(_ definitions: [JoinedField]) {
        let oldTitles = joinedFields.map(\.template)
        joinedFields = definitions
        fields = sourceFields + definitions.map(\.template)
        for index in records.indices {
            for title in oldTitles { records[index].values.removeValue(forKey: title) }
            let source = records[index].values
            for definition in definitions {
                records[index].values[definition.template] = definition.value(for: source)
            }
        }
        rebuildColumns()
        tableView.reloadData()
        onFieldsChanged?()
    }

    private func rebuildColumns() {
        tableView.tableColumns.forEach(tableView.removeTableColumn)
        let selected = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("selected"))
        selected.width = 34
        selected.minWidth = 34
        selected.maxWidth = 34
        selected.headerCell.title = records.allSatisfy(\.isSelected) ? "☑" : "☐"
        tableView.addTableColumn(selected)
        for field in fields {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(field))
            column.title = field
            column.width = 140
            tableView.addTableColumn(column)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { records.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }
        if tableColumn.identifier.rawValue == "selected" {
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(rowSelectionChanged(_:)))
            button.tag = row
            button.state = records[row].isSelected ? .on : .off
            return button
        }
        return NSTextField(labelWithString: records[row].values[tableColumn.identifier.rawValue] ?? "")
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard tableColumn.identifier.rawValue == "selected" else { return }
        let selectAll = records.contains { !$0.isSelected }
        for index in records.indices { records[index].isSelected = selectAll }
        tableColumn.headerCell.title = selectAll ? "☑" : "☐"
        tableView.reloadData()
    }

    @objc private func rowSelectionChanged(_ sender: NSButton) {
        guard records.indices.contains(sender.tag) else { return }
        records[sender.tag].isSelected = sender.state == .on
        if let header = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("selected"))?.headerCell {
            header.title = records.allSatisfy(\.isSelected) ? "☑" : records.allSatisfy({ !$0.isSelected }) ? "☐" : "−"
            tableView.headerView?.needsDisplay = true
        }
    }


}
import UniformTypeIdentifiers

class ViewController: NSViewController, NSWindowDelegate {
    private struct LabelSize {
        let name: String
        let widthInches: CGFloat
        let heightInches: CGFloat
        let widthMillimeters: CGFloat
        let heightMillimeters: CGFloat
    }

    private let labelSizes: [LabelSize] = [
        LabelSize(name: "Large White Address Label  LW 1 2/5\" x 3 1/2\"", widthInches: 3.50, heightInches: 1.40, widthMillimeters: 88.9, heightMillimeters: 28.6),
        LabelSize(name: "Return Address Label LW 3/4\" x 2\"", widthInches: 2.00, heightInches: 0.75, widthMillimeters: 50.8, heightMillimeters: 19.1),
        LabelSize(name: "Large White Label  LW 1 2/5\" x 3 1/2\"", widthInches: 3.50, heightInches: 1.40, widthMillimeters: 88.9, heightMillimeters: 28.6),
        LabelSize(name: "Small White Label LW 3/4\" x 2\"", widthInches: 2.00, heightInches: 0.75, widthMillimeters: 50.8, heightMillimeters: 19.1),
        LabelSize(name: "Small barcode / SKU / return address", widthInches: 2.00, heightInches: 1.00, widthMillimeters: 50.8, heightMillimeters: 25.4),
        LabelSize(name: "Barcode / product identification", widthInches: 2.25, heightInches: 1.25, widthMillimeters: 57.2, heightMillimeters: 31.8),
        LabelSize(name: "Address / file-folder label", widthInches: 3.00, heightInches: 1.00, widthMillimeters: 76.2, heightMillimeters: 25.4),
        LabelSize(name: "Address / small product label", widthInches: 3.00, heightInches: 1.50, widthMillimeters: 76.2, heightMillimeters: 38.1),
        LabelSize(name: "Large address / multipurpose label", widthInches: 3.00, heightInches: 2.00, widthMillimeters: 76.2, heightMillimeters: 50.8),
        LabelSize(name: "Shelf / storage bin / wide barcode", widthInches: 4.00, heightInches: 1.00, widthMillimeters: 101.6, heightMillimeters: 25.4),
        LabelSize(name: "Large mailing / inventory label", widthInches: 4.00, heightInches: 2.00, widthMillimeters: 101.6, heightMillimeters: 50.8),
        LabelSize(name: "Carton / product information label", widthInches: 4.00, heightInches: 3.00, widthMillimeters: 101.6, heightMillimeters: 76.2),
        LabelSize(name: "Large carton / information label", widthInches: 4.00, heightInches: 5.00, widthMillimeters: 101.6, heightMillimeters: 127.0),
        LabelSize(name: "Standard parcel shipping label", widthInches: 4.00, heightInches: 6.00, widthMillimeters: 101.6, heightMillimeters: 152.4),
        LabelSize(name: "Extended shipping / logistics label", widthInches: 4.00, heightInches: 8.00, widthMillimeters: 101.6, heightMillimeters: 203.2),
        LabelSize(name: "Small square product / QR-code label", widthInches: 2.00, heightInches: 2.00, widthMillimeters: 50.8, heightMillimeters: 50.8),
        LabelSize(name: "Medium square product label", widthInches: 3.00, heightInches: 3.00, widthMillimeters: 76.2, heightMillimeters: 76.2),
        LabelSize(name: "Large square / carton label", widthInches: 4.00, heightInches: 4.00, widthMillimeters: 101.6, heightMillimeters: 101.6),
        LabelSize(name: "Small round sticker / product seal", widthInches: 1.50, heightInches: 1.50, widthMillimeters: 38.1, heightMillimeters: 38.1),
        LabelSize(name: "Medium round sticker / product seal", widthInches: 2.00, heightInches: 2.00, widthMillimeters: 50.8, heightMillimeters: 50.8),
        LabelSize(name: "Large round sticker / product label", widthInches: 3.00, heightInches: 3.00, widthMillimeters: 76.2, heightMillimeters: 76.2)
    ]
    private let customLabelName = "Custom Size"
    private let selectedLabelDefaultsKey = "selectedLabelSizeName"
    private let selectedWidthDefaultsKey = "selectedLabelWidthMM"
    private let selectedHeightDefaultsKey = "selectedLabelHeightMM"
    private var selectedLabelIndex = 0
    private var selectedSizeMM = CGSize(width: 50.8, height: 19.1)
    private var customSizeMM = CGSize(width: 50.8, height: 19.1)
    private var customSizeInches = CGSize(width: 2.00, height: 0.75)
    private var selectedShape: LabelOutlineShape = .rectangle

    @IBOutlet weak var rulerView: RulerImageView!
    private let zoomDefaultsKey = "labelEditorZoomLevel"
    private var labelFileURL: URL?
    private let designInspector = DesignInspectorViewController()
    private let databaseController = DatabaseViewController()
    private var compactDatabaseMode = 1
    private weak var compactRangeStartField: NSTextField?
    private weak var compactRangeEndField: NSTextField?
    private var compactPrintPanel: NSPanel?
    private weak var printCopiesField: NSTextField?
    private let printerPopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let printTabCopiesField = NSTextField()
    private let printOrientationButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let printScaleField = NSTextField()
    private let printOffsetXField = NSTextField()
    private let printOffsetYField = NSTextField()
    private let printRotateButton = NSButton(checkboxWithTitle: "Rotate 180°", target: nil, action: nil)
    private let printMirrorButton = NSButton(checkboxWithTitle: "Mirror horizontally", target: nil, action: nil)
    private let printDefaultsPrefix = "labelPrint."
    var didSetupConstraints = false
  var testButton = NSButton()
  var testLabel = NSTextField()
    private let zoomSteps: [CGFloat] = [0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 1.75, 2.00, 3.00, 4.00]

    @IBAction func zoomInButtonAction(_ sender: Any) {
        let current = rulerView.zoomLevel
        let next = zoomSteps.first(where: { $0 > current + 0.001 }) ?? 4.0
        applyZoomLevel(next)
    }

    @IBAction func zoomOutButtonAction(_ sender: Any) {
        let current = rulerView.zoomLevel
        let previous = zoomSteps.last(where: { $0 < current - 0.001 }) ?? 0.25
        applyZoomLevel(previous)
    }

    private func applyZoomLevel(_ level: CGFloat) {
        rulerView.setZoomLevel(level)
        UserDefaults.standard.set(Double(rulerView.zoomLevel), forKey: zoomDefaultsKey)
    }

    
    @IBAction func frameButtonAction(_ sender: Any) {
        beginAdding(.frame)
    }
    
    @IBOutlet weak var designTabViewItem: NSTabViewItem!
    @IBOutlet weak var tabView: NSTabView!
    
    @IBOutlet var labelTabViewItem: NSTabViewItem!
    
    @IBOutlet var dataTabViewItem: NSTabViewItem!
    
    @IBOutlet var printTabViewItem: NSTabViewItem!
    
    
    @IBAction func imageButtonAction(_ sender: Any) {
        beginAdding(.image)
    }

    @IBAction func databaseButtonAction(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.title = "Select Database File"
        panel.message = "Select a read-only CSV or vCard contact database."
        panel.allowedContentTypes = [
            UTType.commaSeparatedText,
            UTType(filenameExtension: "vcf") ?? .data
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let readOnly = NSTextField(labelWithString: "Read-Only")
        let headerRow = NSButton(checkboxWithTitle: "Header Row Contains Fields Names", target: nil, action: nil)
        headerRow.state = .on
        let encoding = NSButton(checkboxWithTitle: "Replace Delimiter and File Encoding", target: nil, action: nil)
        encoding.isEnabled = false
        let note = NSTextField(wrappingLabelWithString: "If the text appears incorrectly, change the file encoding.")
        note.textColor = .secondaryLabelColor
        let options = NSStackView(views: [readOnly, headerRow, encoding, note])
        options.orientation = .vertical
        options.alignment = .leading
        options.spacing = 8
        options.frame = NSRect(x: 0, y: 0, width: 520, height: 92)
        panel.accessoryView = options
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if url.pathExtension.lowercased() == "vcf" {
                    let contacts = try ContactTable.readVCard(url)
                    let editor = VCardImportViewController(contacts: contacts, sourceURL: url)
                    editor.onSave = { [weak self] selected in
                        self?.importDatabase(selected, sourceName: url.lastPathComponent)
                    }
                    self.presentAsSheet(editor)
                } else {
                    let data = try ContactTable.readCSV(url, headerRow: headerRow.state == .on)
                    self.importDatabase(data, sourceName: url.lastPathComponent)
                }
            } catch {
                self.showLabelFileError(error)
            }
        }
        if let window = view.window { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { completion(panel.runModal()) }
    }

    private func importDatabase(_ data: ContactTable, sourceName: String) {
        databaseController.sourceName = sourceName
        rulerView.clearDatabaseBindings(except: data.fields)
        databaseController.load(data)
        designInspector.inspect(rulerView.inspectorSelection)
        tabView.selectTabViewItem(dataTabViewItem)
    }

    func insertArtwork(_ image: NSImage, kind: ImageContentKind) {
        do {
            let data = try ImageItemView.thermalArtworkData(image)
            try rulerView.addImage(data: data, contentKind: kind)
        } catch {
            showLabelFileError(error)
        }
    }
    
    private let showGridMenu = NSPopUpButton()
    private let snapGridMenu = NSPopUpButton()
    private let showCrosshairMenu = NSPopUpButton()
    private let crosshairDefaultsKey = "labelEditorShowsCrosshair"

    @objc private func crosshairSettingsChanged(_ sender: NSPopUpButton) {
        let enabled = sender.indexOfSelectedItem == 1
        rulerView.showsCrosshair = enabled
        UserDefaults.standard.set(enabled, forKey: crosshairDefaultsKey)
    }

    @objc private func gridSettingsChanged(_ sender: NSPopUpButton) {
        rulerView.showsGrid = showGridMenu.indexOfSelectedItem == 1
        rulerView.snapsToGrid = snapGridMenu.indexOfSelectedItem == 1
    }

    private let shapeComboButton = NSPopUpButton()
    private let templateTitleLabel = NSTextField(labelWithString: "Template")
    private let templatePopUpButton = NSPopUpButton()
    private let addTemplateButton = NSButton(title: "Add Template", target: nil, action: nil)

    private var availableAddressTemplate: String? {
        guard selectedLabelIndex > 0, selectedLabelIndex <= labelSizes.count else { return nil }
        switch labelSizes[selectedLabelIndex - 1].name {
        case "Large White Address Label  LW 1 2/5\" x 3 1/2\"": return "Address"
        case "Return Address Label LW 3/4\" x 2\"": return "Return Address"
        default: return nil
        }
    }

    private func updateTemplateControl() {
        let template = availableAddressTemplate
        templateTitleLabel.isHidden = template == nil
        templatePopUpButton.isHidden = template == nil
        addTemplateButton.isHidden = template == nil
        templatePopUpButton.removeAllItems()
        if let template { templatePopUpButton.addItem(withTitle: template) }
    }

    @objc private func addTemplateAction(_ sender: Any) {
        guard availableAddressTemplate != nil else { return }
        designInspector.cancelAdding()
        rulerView.addAddressTemplate()
    }
    
    @IBAction func shapeComboButtonAction(_ sender: Any) {
        selectedShape = shapeComboButton.indexOfSelectedItem == 1 ? .round : .rectangle
        applySelectedShape()
    }
    private let selectLabelComboButton = NSPopUpButton()
    
    @IBAction func selectLabelComboButtonAction(_ sender: Any) {
        selectedLabelIndex = max(0, selectLabelComboButton.indexOfSelectedItem)
        if selectedLabelIndex == 0 {
            selectedSizeMM = customSizeMM
            selectedShape = .rectangle
        } else {
            let size = labelSizes[selectedLabelIndex - 1]
            selectedSizeMM = CGSize(width: size.widthMillimeters, height: size.heightMillimeters)
            selectedShape = size.name.localizedCaseInsensitiveContains("round") ? .round : .rectangle
        }
        rulerView.labelShape = selectedShape
        applySelectedLabelSize()
        applyRecommendedPrintOffsetForSelectedLabel()
    }
    @IBOutlet var labelWidthTextField: NSTextField!
    
    @IBOutlet var labelWidthLabel: NSTextField!
    @IBOutlet var labelHeightTextField: NSTextField!
    
    @IBOutlet var labelHeightLabel: NSTextField!
    
    
    @IBAction func shapeButtonAction(_ sender: Any) {
        beginAdding(.shape)
    }
    private func applySelectedLabelSize() {
        rulerView.setSize(width: selectedSizeMM.width, height: selectedSizeMM.height)
        let savedZoom = UserDefaults.standard.double(forKey: zoomDefaultsKey)
        if savedZoom.isFinite, savedZoom > 0 {
            rulerView.setZoomLevel(CGFloat(savedZoom))
        }
        persistSelectedLabelSize()
        refreshLabelSizeControls()
    }
    
    @IBAction func lineButtonAction(_ sender: Any) {
        beginAdding(.line)
    }
    
    @IBAction func addTextButtonAction(_ sender: Any) {
        beginAdding(.text)
    }
    

    @IBAction func printButtonAction(_ sender: Any) {
        guard compactPrintPanel == nil else { return }

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 250),
                            styleMask: [.titled],
                            backing: .buffered,
                            defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let content = NSView()
        panel.contentView = content

        let printerLabel = NSTextField(labelWithString: rulerView.preferredPrinterName)
        printerLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        printerLabel.alignment = .center

        let topSeparator = NSBox()
        topSeparator.boxType = .separator

        let copiesLabel = NSTextField(labelWithString: "Copies")
        copiesLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let copiesField = NSTextField()
        copiesField.integerValue = 1
        copiesField.alignment = .left
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = 999
        copiesField.formatter = formatter

        let stepper = NSStepper()
        stepper.minValue = 1
        stepper.maxValue = 999
        stepper.increment = 1
        stepper.integerValue = 1
        stepper.target = copiesField
        stepper.action = #selector(NSTextField.takeIntValueFrom(_:))

        let databaseLabel = NSTextField(labelWithString: "Database")
        databaseLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let allRecords = NSButton(radioButtonWithTitle: "All Records", target: self, action: #selector(databasePrintModeChanged(_:)))
        let selectedRecords = NSButton(radioButtonWithTitle: "Selected Records", target: self, action: #selector(databasePrintModeChanged(_:)))
        let recordRange = NSButton(radioButtonWithTitle: "Record Range", target: self, action: #selector(databasePrintModeChanged(_:)))
        [allRecords, selectedRecords, recordRange].enumerated().forEach { index, button in
            button.tag = index
            button.state = index == compactDatabaseMode ? .on : .off
            button.isEnabled = !databaseController.records.isEmpty
        }
        let rangeStart = NSTextField(string: "1")
        let rangeEnd = NSTextField(string: String(max(1, databaseController.records.count)))
        rangeStart.alignment = .center; rangeEnd.alignment = .center
        rangeStart.isEnabled = compactDatabaseMode == 2; rangeEnd.isEnabled = compactDatabaseMode == 2
        compactRangeStartField = rangeStart; compactRangeEndField = rangeEnd
        let dash = NSTextField(labelWithString: "–")
        let rangeFields = NSStackView(views: [rangeStart, dash, rangeEnd])
        rangeFields.orientation = .horizontal; rangeFields.spacing = 8
        let rangeRow = NSStackView(views: [recordRange, rangeFields])
        rangeRow.orientation = .horizontal; rangeRow.spacing = 10
        let databaseChoices = NSStackView(views: [allRecords, selectedRecords, rangeRow])
        databaseChoices.orientation = .vertical; databaseChoices.alignment = .leading; databaseChoices.spacing = 5
        let databaseRow = NSStackView(views: [databaseLabel, databaseChoices])
        databaseRow.orientation = .horizontal; databaseRow.alignment = .top; databaseRow.spacing = 12

        let bottomSeparator = NSBox()
        bottomSeparator.boxType = .separator

        let detailedButton = NSButton(title: "Detailed Settings…",
                                      target: self,
                                      action: #selector(showDetailedPrintSettings(_:)))
        let previewButton = NSButton(title: "Print Preview",
                                     target: self,
                                     action: #selector(previewFromCompactPrintPanel(_:)))
        let cancelButton = NSButton(title: "Cancel",
                                    target: self,
                                    action: #selector(cancelCompactPrintPanel(_:)))
        let printButton = NSButton(title: "Print",
                                   target: self,
                                   action: #selector(printFromCompactPrintPanel(_:)))
        printButton.keyEquivalent = "\r"

        let views = [printerLabel, topSeparator, copiesLabel, copiesField, stepper, databaseRow,
                     bottomSeparator, detailedButton, previewButton, cancelButton, printButton]
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview($0)
        }

        NSLayoutConstraint.activate([
            printerLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 13),
            printerLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            topSeparator.topAnchor.constraint(equalTo: printerLabel.bottomAnchor, constant: 11),
            topSeparator.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            topSeparator.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            copiesLabel.topAnchor.constraint(equalTo: topSeparator.bottomAnchor, constant: 13),
            copiesLabel.trailingAnchor.constraint(equalTo: copiesField.leadingAnchor, constant: -12),
            copiesField.centerYAnchor.constraint(equalTo: copiesLabel.centerYAnchor),
            copiesField.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            copiesField.widthAnchor.constraint(equalToConstant: 96),
            stepper.leadingAnchor.constraint(equalTo: copiesField.trailingAnchor, constant: 5),
            stepper.centerYAnchor.constraint(equalTo: copiesField.centerYAnchor),

            databaseRow.topAnchor.constraint(equalTo: copiesField.bottomAnchor, constant: 12),
            databaseRow.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            rangeStart.widthAnchor.constraint(equalToConstant: 46),
            rangeEnd.widthAnchor.constraint(equalToConstant: 46),

            bottomSeparator.topAnchor.constraint(equalTo: databaseRow.bottomAnchor, constant: 13),
            bottomSeparator.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            bottomSeparator.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            detailedButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            detailedButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            previewButton.leadingAnchor.constraint(equalTo: detailedButton.trailingAnchor, constant: 8),
            previewButton.centerYAnchor.constraint(equalTo: detailedButton.centerYAnchor),

            printButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            printButton.centerYAnchor.constraint(equalTo: detailedButton.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: printButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: detailedButton.centerYAnchor)
        ])

        compactPrintPanel = panel
        printCopiesField = copiesField
        if let window = view.window {
            window.beginSheet(panel)
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func closeCompactPrintPanel() -> Int {
        let copies = max(1, printCopiesField?.integerValue ?? 1)
        if let panel = compactPrintPanel {
            if let parent = panel.sheetParent {
                parent.endSheet(panel)
            } else {
                panel.close()
            }
        }
        compactPrintPanel = nil
        printCopiesField = nil
        compactRangeStartField = nil
        compactRangeEndField = nil
        return copies
    }

    @objc private func databasePrintModeChanged(_ sender: NSButton) {
        compactDatabaseMode = sender.tag
        for tag in 0...2 {
            (sender.superview?.superview?.viewWithTag(tag) as? NSButton)?.state = tag == sender.tag ? .on : .off
        }
        compactRangeStartField?.isEnabled = sender.tag == 2
        compactRangeEndField?.isEnabled = sender.tag == 2
    }

    private func databaseRecordsForPrinting() -> [DatabaseRecord] {
        switch compactDatabaseMode {
        case 0:
            return databaseController.records
        case 2:
            let start = max(1, compactRangeStartField?.integerValue ?? 1)
            let end = min(databaseController.records.count, max(start, compactRangeEndField?.integerValue ?? start))
            guard start <= end else { return [] }
            return Array(databaseController.records[(start - 1)..<end])
        default:
            return databaseController.selectedRecords
        }
    }

    @objc private func cancelCompactPrintPanel(_ sender: Any) {
        _ = closeCompactPrintPanel()
    }

    @objc private func printFromCompactPrintPanel(_ sender: Any) {
        let databaseRecords = databaseRecordsForPrinting()
        let usesDatabase = !databaseController.records.isEmpty
            && rulerView.hasDatabaseTextBinding(for: databaseController.fields)
        let copies = closeCompactPrintPanel()
        if !usesDatabase {
            performLabelPrint(copies: copies, showsPrintPanel: false, previewsOnly: false)
        } else {
            for record in databaseRecords {
                rulerView.applyDatabaseRecord(record.values)
                performLabelPrint(copies: copies, showsPrintPanel: false, previewsOnly: false)
            }
        }
    }

    @objc private func previewFromCompactPrintPanel(_ sender: Any) {
        let copies = closeCompactPrintPanel()
        performLabelPrint(copies: copies, showsPrintPanel: false, previewsOnly: true)
    }

    @objc private func showDetailedPrintSettings(_ sender: Any) {
        let copies = closeCompactPrintPanel()
        DispatchQueue.main.async { [weak self] in
            self?.performLabelPrint(copies: copies, showsPrintPanel: true, previewsOnly: false)
        }
    }

    private func performLabelPrint(copies: Int, showsPrintPanel: Bool, previewsOnly: Bool) {
        do {
            try rulerView.previewAndPrintLabel(copies: copies,
                                               showsPrintPanel: showsPrintPanel,
                                               previewsOnly: previewsOnly,
                                               orientation: UserDefaults.standard.integer(forKey: printDefaultsPrefix + "orientation"),
                                               scalePercent: CGFloat(savedPrintDouble("scale", default: 100)),
                                               offsetMM: NSPoint(x: savedPrintDouble("offsetX", default: 0),
                                                                 y: savedPrintDouble("offsetY", default: 0)),
                                               rotates180: UserDefaults.standard.bool(forKey: printDefaultsPrefix + "rotate180"),
                                               mirrorsHorizontally: UserDefaults.standard.bool(forKey: printDefaultsPrefix + "mirror"))
        } catch {
            showPrintError(error)
        }
    }

    private func showPrintError(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    @IBAction func saveButtonAction(_ sender: Any) {
        let panel = NSSavePanel()
        panel.title = "Save Label"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = labelFileURL?.lastPathComponent ?? "Label.json"
        panel.directoryURL = labelFileURL?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let name = selectedLabelIndex == 0 ? customLabelName : labelSizes[selectedLabelIndex - 1].name
            let data = try rulerView.labelFileData(labelTypeName: name)
            try data.write(to: url, options: .atomic)
            labelFileURL = url
        } catch {
            showLabelFileError(error)
        }
    }

    @IBAction func newButtonAction(_ sender: Any) {
        designInspector.cancelAdding()
        rulerView.clearLabelObjects()
        labelFileURL = nil
    }

    @IBAction func openButtonAction(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.title = "Open Label"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let labelTypeName = try rulerView.loadLabelFileData(data)
            designInspector.cancelAdding()
            selectedSizeMM = rulerView.labelSizeMM
            customSizeMM = selectedSizeMM
            customSizeInches = CGSize(width: selectedSizeMM.width / 25.4, height: selectedSizeMM.height / 25.4)
            selectedShape = rulerView.labelShape
            selectedLabelIndex = restoredLabelIndex(name: labelTypeName, size: selectedSizeMM, shape: selectedShape)
            persistSelectedLabelSize()
            refreshLabelSizeControls()
            labelFileURL = url
        } catch {
            showLabelFileError(error)
        }
    }

    func restoredLabelIndex(name: String?, size: CGSize, shape: LabelOutlineShape) -> Int {
        if name == customLabelName { return 0 }
        let match = labelSizes.firstIndex { label in
            guard abs(label.widthMillimeters - size.width) < 0.01,
                  abs(label.heightMillimeters - size.height) < 0.01 else { return false }
            if let name {
                return label.name == name && (shape == .rectangle || abs(size.width - size.height) < 0.01)
            }
            let defaultShape: LabelOutlineShape = label.name.localizedCaseInsensitiveContains("round") ? .round : .rectangle
            return shape == defaultShape
        }
        return match.map { $0 + 1 } ?? 0
    }

    private func showLabelFileError(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
   
    
    
    @IBAction func barcodeButtonAction(_ sender: Any) {
        beginAdding(.barcode)
    }
    private func beginAdding(_ kind: DesignInspectorViewController.ObjectKind,
                             barcodeFormat: BarcodeFormat = .code128, value: String? = nil) {
        tabView.selectTabViewItem(designTabViewItem)
        designInspector.beginAdding(kind, barcodeFormat: barcodeFormat, value: value)
    }

    override func viewDidLoad() {
    super.viewDidLoad()
        designInspector.ruler = rulerView
        databaseController.onFieldsChanged = { [weak self] in
            guard let self else { return }
            self.rulerView.clearDatabaseBindings(except: self.databaseController.fields)
            self.designInspector.inspect(self.rulerView.inspectorSelection)
        }
        designInspector.databaseFieldsProvider = { [weak self] in
            self?.databaseController.fields ?? []
        }
        designInspector.databaseValueProvider = { [weak self] field in
            self?.databaseController.selectedRecords.first?.values[field]
        }
        addChild(designInspector)
        designTabViewItem.view = designInspector.view
        rulerView.inspectorInteractionView = tabView
        rulerView.onSelectionChanged = { [weak self] item in
            guard let self else { return }
            self.designInspector.inspect(item)
            if item != nil { self.tabView.selectTabViewItem(self.designTabViewItem) }
        }
        designInspector.inspect(nil)
        rulerView.showsCrosshair = UserDefaults.standard.object(forKey: crosshairDefaultsKey) as? Bool ?? true
        configureLabelPopupControls()
        configureShapeSelector()
        configureLabelSizeSelector()
        configureDataTab()
        configurePrintTab()
      rulerView.setSize(width: selectedSizeMM.width, height: selectedSizeMM.height)
      let savedZoom = UserDefaults.standard.double(forKey: zoomDefaultsKey)
      if savedZoom.isFinite, savedZoom > 0 {
          rulerView.setZoomLevel(CGFloat(savedZoom))
      }
      rulerView.becomeFirstResponder()
      
      didSetupConstraints = false
  }

    private func configureLabelPopupControls() {
        guard let contentView = labelTabViewItem.view else { return }
        selectLabelComboButton.frame = NSRect(x: 12, y: 570, width: 314, height: 25)
        selectLabelComboButton.autoresizingMask = [.width, .minYMargin]
        selectLabelComboButton.target = self
        selectLabelComboButton.action = #selector(selectLabelComboButtonAction(_:))
        contentView.addSubview(selectLabelComboButton)

        shapeComboButton.frame = NSRect(x: 93, y: 447, width: 154, height: 25)
        shapeComboButton.autoresizingMask = [.minYMargin]
        shapeComboButton.target = self
        shapeComboButton.action = #selector(shapeComboButtonAction(_:))
        contentView.addSubview(shapeComboButton)

        templateTitleLabel.frame = NSRect(x: 12, y: 409, width: 78, height: 20)
        templatePopUpButton.frame = NSRect(x: 93, y: 405, width: 221, height: 25)
        templatePopUpButton.setAccessibilityLabel("Address template")
        addTemplateButton.frame = NSRect(x: 93, y: 367, width: 140, height: 30)
        addTemplateButton.bezelStyle = .rounded
        addTemplateButton.target = self
        addTemplateButton.action = #selector(addTemplateAction(_:))
        for control in [templateTitleLabel, templatePopUpButton, addTemplateButton] {
            control.autoresizingMask = [.minYMargin]
            contentView.addSubview(control)
        }
        for (title, menu, y, enabled) in [
            ("Show Grid", showGridMenu, CGFloat(325), rulerView.showsGrid),
            ("Snap To Grid", snapGridMenu, CGFloat(287), rulerView.snapsToGrid),
            ("Show Crosshair", showCrosshairMenu, CGFloat(249), rulerView.showsCrosshair)
        ] {
            let label = NSTextField(labelWithString: title)
            label.frame = NSRect(x: 12, y: y + 4, width: 125, height: 20)
            menu.frame = NSRect(x: 145, y: y, width: 169, height: 25)
            menu.addItems(withTitles: ["Off", "On"])
            menu.selectItem(at: enabled ? 1 : 0)
            menu.setAccessibilityLabel(title)
            menu.toolTip = menu === showCrosshairMenu ? "Show crosshair guides over the label" : "1 mm grid"
            menu.target = self
            menu.action = menu === showCrosshairMenu
                ? #selector(crosshairSettingsChanged(_:)) : #selector(gridSettingsChanged(_:))
            for control in [label, menu] {
                control.autoresizingMask = [.minYMargin]
                contentView.addSubview(control)
            }
        }
        updateTemplateControl()
    }

    private func configureDataTab() {
        guard let contentView = dataTabViewItem.view else { return }
        addChild(databaseController)
        let databaseView = databaseController.view
        databaseView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(databaseView)
        NSLayoutConstraint.activate([
            databaseView.topAnchor.constraint(equalTo: contentView.topAnchor),
            databaseView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            databaseView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            databaseView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func configurePrintTab() {
        guard let contentView = printTabViewItem.view else { return }

        let printerLabel = NSTextField(labelWithString: "Printer")
        printerLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)

        printerPopUpButton.target = self
        printerPopUpButton.action = #selector(printerSelectionChanged(_:))
        printerPopUpButton.setAccessibilityLabel("Printer")

        let printerNames = NSPrinter.printerNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        printerPopUpButton.removeAllItems()
        if printerNames.isEmpty {
            printerPopUpButton.addItem(withTitle: "No printers available")
            printerPopUpButton.isEnabled = false
        } else {
            printerPopUpButton.addItems(withTitles: printerNames)
            printerPopUpButton.selectItem(withTitle: rulerView.preferredPrinterName)
        }

        let integerFormatter = NumberFormatter()
        integerFormatter.allowsFloats = false
        integerFormatter.minimum = 1
        integerFormatter.maximum = 999
        configurePrintNumberField(printTabCopiesField, formatter: integerFormatter,
                                  value: savedPrintDouble("copies", default: 1))

        printOrientationButton.addItems(withTitles: ["Automatic", "Portrait", "Landscape"])
        printOrientationButton.selectItem(at: UserDefaults.standard.integer(forKey: printDefaultsPrefix + "orientation"))
        printOrientationButton.target = self
        printOrientationButton.action = #selector(printOptionChanged(_:))

        let decimalFormatter = NumberFormatter()
        decimalFormatter.allowsFloats = true
        decimalFormatter.minimumFractionDigits = 0
        decimalFormatter.maximumFractionDigits = 2
        configurePrintNumberField(printScaleField, formatter: decimalFormatter,
                                  value: savedPrintDouble("scale", default: 100))
        configurePrintNumberField(printOffsetXField, formatter: decimalFormatter,
                                  value: savedPrintDouble("offsetX", default: 0))
        configurePrintNumberField(printOffsetYField, formatter: decimalFormatter,
                                  value: savedPrintDouble("offsetY", default: 0))

        printRotateButton.state = UserDefaults.standard.bool(forKey: printDefaultsPrefix + "rotate180") ? .on : .off
        printMirrorButton.state = UserDefaults.standard.bool(forKey: printDefaultsPrefix + "mirror") ? .on : .off
        [printRotateButton, printMirrorButton].forEach {
            $0.target = self
            $0.action = #selector(printOptionChanged(_:))
        }

        let grid = NSGridView(views: [
            [printerLabel, printerPopUpButton],
            [NSTextField(labelWithString: "Copies"), printTabCopiesField],
            [NSTextField(labelWithString: "Orientation"), printOrientationButton],
            [NSTextField(labelWithString: "Scale (%)"), printScaleField],
            [NSTextField(labelWithString: "Offset X (mm)"), printOffsetXField],
            [NSTextField(labelWithString: "Offset Y (mm)"), printOffsetYField]
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill

        let previewButton = NSButton(title: "Print Preview", target: self,
                                     action: #selector(previewFromPrintTab(_:)))
        let detailedButton = NSButton(title: "Detailed Printer Settings…", target: self,
                                      action: #selector(detailedSettingsFromPrintTab(_:)))
        let driverNote = NSTextField(wrappingLabelWithString:
            "Print quality, darkness, speed, cutter, and tear mode are provided by the selected printer driver in Detailed Printer Settings.")
        driverNote.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [grid, printRotateButton, printMirrorButton,
                                        previewButton, detailedButton, driverNote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        grid.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        driverNote.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            printerPopUpButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 190)
        ])
        applyRecommendedPrintOffsetForSelectedLabel()
    }

    private func applyRecommendedPrintOffsetForSelectedLabel() {
        guard printOffsetXField.formatter != nil, printOffsetYField.formatter != nil else { return }
        let isSmallRoundStock = selectedLabelIndex > 0
            && labelSizes[selectedLabelIndex - 1].name == "Small round sticker / product seal"
        printOffsetXField.doubleValue = isSmallRoundStock ? 1 : 0
        printOffsetYField.doubleValue = isSmallRoundStock ? -1 : 0
        printOptionChanged(self)
    }

    private func configurePrintNumberField(_ field: NSTextField, formatter: NumberFormatter, value: Double) {
        field.formatter = formatter
        field.doubleValue = value
        field.alignment = .right
        field.target = self
        field.action = #selector(printOptionChanged(_:))
    }

    private func savedPrintDouble(_ name: String, default defaultValue: Double) -> Double {
        let key = printDefaultsPrefix + name
        return UserDefaults.standard.object(forKey: key) == nil ? defaultValue : UserDefaults.standard.double(forKey: key)
    }

    @objc private func printOptionChanged(_ sender: Any) {
        let defaults = UserDefaults.standard
        defaults.set(max(1, printTabCopiesField.integerValue), forKey: printDefaultsPrefix + "copies")
        defaults.set(printOrientationButton.indexOfSelectedItem, forKey: printDefaultsPrefix + "orientation")
        defaults.set(min(400, max(25, printScaleField.doubleValue)), forKey: printDefaultsPrefix + "scale")
        defaults.set(printOffsetXField.doubleValue, forKey: printDefaultsPrefix + "offsetX")
        defaults.set(printOffsetYField.doubleValue, forKey: printDefaultsPrefix + "offsetY")
        defaults.set(printRotateButton.state == .on, forKey: printDefaultsPrefix + "rotate180")
        defaults.set(printMirrorButton.state == .on, forKey: printDefaultsPrefix + "mirror")
    }

    @objc private func previewFromPrintTab(_ sender: Any) {
        printOptionChanged(sender)
        performLabelPrint(copies: max(1, printTabCopiesField.integerValue),
                          showsPrintPanel: false, previewsOnly: true)
    }

    @objc private func detailedSettingsFromPrintTab(_ sender: Any) {
        printOptionChanged(sender)
        performLabelPrint(copies: max(1, printTabCopiesField.integerValue),
                          showsPrintPanel: true, previewsOnly: false)
    }

    @objc private func printerSelectionChanged(_ sender: NSPopUpButton) {
        guard let printerName = sender.selectedItem?.title else { return }
        rulerView.selectPrinter(named: printerName)
    }

    private func configureLabelSizeSelector() {
        let defaults = UserDefaults.standard
        let savedName = defaults.string(forKey: selectedLabelDefaultsKey) ?? customLabelName
        selectedLabelIndex = labelSizes.firstIndex(where: { $0.name == savedName }).map { $0 + 1 } ?? 0
        selectedShape = selectedLabelIndex > 0 && labelSizes[selectedLabelIndex - 1].name.localizedCaseInsensitiveContains("round")
            ? .round : .rectangle
        let savedWidth = defaults.double(forKey: selectedWidthDefaultsKey)
        let savedHeight = defaults.double(forKey: selectedHeightDefaultsKey)
        if selectedLabelIndex == 0 {
            if savedWidth.isFinite, savedHeight.isFinite,
               savedWidth > 0, savedHeight > 0, savedWidth <= 1000, savedHeight <= 1000 {
                customSizeMM = CGSize(width: savedWidth, height: savedHeight)
                customSizeInches = CGSize(width: savedWidth / 25.4, height: savedHeight / 25.4)
            }
            selectedSizeMM = customSizeMM
        } else if savedWidth > 0, savedHeight > 0 {
            selectedSizeMM = CGSize(width: savedWidth, height: savedHeight)
        } else {
            let size = labelSizes[selectedLabelIndex - 1]
            selectedSizeMM = CGSize(width: size.widthMillimeters, height: size.heightMillimeters)
        }

        if let rawShape = defaults.string(forKey: "selectedLabelOutlineShape"),
           let shape = LabelOutlineShape(rawValue: rawShape),
           abs(selectedSizeMM.width - selectedSizeMM.height) < 0.01 {
            selectedShape = shape
        }
        labelWidthTextField.target = self
        labelWidthTextField.action = #selector(customSizeTextFieldAction(_:))
        labelHeightTextField.target = self
        labelHeightTextField.action = #selector(customSizeTextFieldAction(_:))
        rulerView.onUnitChanged = { [weak self] _ in
            self?.refreshLabelSizeControls()
        }
        refreshLabelSizeControls()
    }

    private func refreshLabelSizeControls() {
        rebuildLabelSizeMenu()
        updateDimensionFields()
        updateShapeControl()
        updateTemplateControl()
    }

    private func configureShapeSelector() {
        shapeComboButton.removeAllItems()
        shapeComboButton.addItems(withTitles: ["Rectangle", "Round"])
        shapeComboButton.selectItem(at: 0)
        shapeComboButton.isEnabled = false
        rulerView.labelShape = .rectangle
    }

    private func updateShapeControl() {
        let isSquare = abs(selectedSizeMM.width - selectedSizeMM.height) < 0.01
        let canChooseShape = selectedLabelIndex == 0 || isSquare
        shapeComboButton.isEnabled = canChooseShape
        if !canChooseShape {
            selectedShape = .rectangle
        }
        rulerView.labelShape = selectedShape
        shapeComboButton.selectItem(at: selectedShape == .round ? 1 : 0)
    }

    @objc private func selectShapeMenuItem(_ sender: NSMenuItem) {
        selectedShape = sender.tag == 1 ? .round : .rectangle
        applySelectedShape()
    }

    private func applySelectedShape() {
        guard shapeComboButton.isEnabled else {
            selectedShape = .rectangle
            rulerView.labelShape = .rectangle
            updateShapeControl()
            return
        }

        if selectedShape == .round {
            selectedSizeMM.height = selectedSizeMM.width
            if selectedLabelIndex == 0 {
                customSizeMM.height = customSizeMM.width
                customSizeInches.height = customSizeInches.width
            }
        }
        rulerView.labelShape = selectedShape
        applySelectedLabelSize()
        applyRecommendedPrintOffsetForSelectedLabel()
    }

    private func rebuildLabelSizeMenu() {
        let sizes = [customMenuTitle()] + labelSizes.map(menuTitle(for:))
        selectLabelComboButton.removeAllItems()
        selectLabelComboButton.addItems(withTitles: sizes)
        selectLabelComboButton.selectItem(at: selectedLabelIndex)
    }

    private func menuTitle(for size: LabelSize) -> String {
        if rulerView.unit == .inches {
            return "\(size.name) — \(String(format: "%.2f", size.widthInches)) × \(String(format: "%.2f", size.heightInches)) inches"
        }
        return "\(size.name) — \(String(format: "%.1f", size.widthMillimeters)) × \(String(format: "%.1f", size.heightMillimeters)) mm"
    }

    private func customMenuTitle() -> String {
        if rulerView.unit == .inches {
            return "\(customLabelName) — \(String(format: "%.2f", customSizeInches.width)) × \(String(format: "%.2f", customSizeInches.height)) inches"
        }
        return "\(customLabelName) — \(String(format: "%.1f", customSizeMM.width)) × \(String(format: "%.1f", customSizeMM.height)) mm"
    }

    private func updateDimensionFields() {
        let usesInches = rulerView.unit == .inches
        let format = usesInches ? "%.3f" : "%.1f"
        let displayedSize: CGSize
        if selectedLabelIndex == 0 {
            displayedSize = usesInches ? customSizeInches : customSizeMM
        } else {
            let size = labelSizes[selectedLabelIndex - 1]
            displayedSize = usesInches
                ? CGSize(width: size.widthInches, height: size.heightInches)
                : CGSize(width: size.widthMillimeters, height: size.heightMillimeters)
        }
        labelWidthTextField.stringValue = String(format: format, displayedSize.width)
        labelHeightTextField.stringValue = String(format: format, displayedSize.height)
        let unitTitle = usesInches ? "inches" : "mm"
        labelWidthLabel.stringValue = unitTitle
        labelHeightLabel.stringValue = unitTitle
    }

    @objc private func selectLabelMenuItem(_ sender: NSMenuItem) {
        selectedLabelIndex = sender.tag
        if selectedLabelIndex == 0 {
            selectedSizeMM = customSizeMM
            selectedShape = .rectangle
        } else {
            let size = labelSizes[selectedLabelIndex - 1]
            selectedSizeMM = CGSize(width: size.widthMillimeters, height: size.heightMillimeters)
            selectedShape = size.name.localizedCaseInsensitiveContains("round") ? .round : .rectangle
        }
        rulerView.labelShape = selectedShape
        applySelectedLabelSize()
        applyRecommendedPrintOffsetForSelectedLabel()
    }

    @objc private func customSizeTextFieldAction(_ sender: NSTextField) {
        applyCustomSizeFromFields()
    }

    private func applyCustomSizeFromFields() {
        let width = CGFloat(labelWidthTextField.doubleValue)
        let height = CGFloat(labelHeightTextField.doubleValue)
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width <= (rulerView.unit == .inches ? 1000 / 25.4 : 1000),
              height <= (rulerView.unit == .inches ? 1000 / 25.4 : 1000) else {
            updateDimensionFields()
            return
        }
        if rulerView.unit == .inches {
            customSizeInches = CGSize(width: width, height: height)
            customSizeMM = CGSize(width: width * 25.4, height: height * 25.4)
        } else {
            customSizeMM = CGSize(width: width, height: height)
            customSizeInches = CGSize(width: width / 25.4, height: height / 25.4)
        }
        if selectedShape == .round {
            customSizeMM.height = customSizeMM.width
            customSizeInches.height = customSizeInches.width
        }
        selectedLabelIndex = 0
        selectedSizeMM = customSizeMM
        applySelectedLabelSize()
    }

    private func persistSelectedLabelSize() {
        let defaults = UserDefaults.standard
        let name = selectedLabelIndex == 0 ? customLabelName : labelSizes[selectedLabelIndex - 1].name
        defaults.set(selectedShape.rawValue, forKey: "selectedLabelOutlineShape")
        defaults.set(name, forKey: selectedLabelDefaultsKey)
        defaults.set(Double(selectedSizeMM.width), forKey: selectedWidthDefaultsKey)
        defaults.set(Double(selectedSizeMM.height), forKey: selectedHeightDefaultsKey)
    }
  override func updateViewConstraints() {
      
      if (!didSetupConstraints) {
          
          
      }
      super.updateViewConstraints()
  }
  @IBAction func testButtonAction(_ sender: NSButton) {
      
      Log.i("testButtonAction")


  }
  override func viewWillAppear() {
  }
  override func viewWillLayout() {
  }
  override func viewDidLayout() {
  }
  override func viewWillDisappear() {
  }
  override var representedObject: Any? {
      didSet {
        if representedObject is URL {
          }
      }
  }
 

}
