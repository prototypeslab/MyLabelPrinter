import Cocoa

struct JoinedField {
    var template: String
    var removesEmptyLines = true

    private static let tokenExpression = try? NSRegularExpression(pattern: #"\[([^\[\]\r\n]+)\]"#)

    static func referencedFields(in template: String) -> [String] {
        let text = template as NSString
        return tokenExpression?.matches(in: template, range: NSRange(location: 0, length: text.length))
            .map { text.substring(with: $0.range(at: 1)) } ?? []
    }

    func value(for values: [String: String]) -> String {
        template.components(separatedBy: "\n").compactMap { line -> String? in
            let names = Self.referencedFields(in: line)
            if removesEmptyLines, !names.isEmpty,
               names.allSatisfy({ (values[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return nil
            }
            let text = line as NSString
            let matches = Self.tokenExpression?.matches(in: line, range: NSRange(location: 0, length: text.length)) ?? []
            let result = NSMutableString(string: line)
            for match in matches.reversed() {
                result.replaceCharacters(in: match.range, with: values[text.substring(with: match.range(at: 1))] ?? "")
            }
            return result as String
        }.joined(separator: "\n")
    }
}

private func joinedFieldList(_ table: NSTableView) -> NSScrollView {
    table.headerView = nil
    table.usesAlternatingRowBackgroundColors = true
    table.allowsMultipleSelection = true
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
    column.width = 280
    table.addTableColumn(column)
    let scroll = NSScrollView()
    scroll.borderType = .bezelBorder
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.documentView = table
    return scroll
}

final class JoinedFieldsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var joinedFields: [JoinedField] = []
    var sourceFields: [String] = []
    var sourceName = "Fields"
    var onChange: (([JoinedField]) -> Void)?
    private let table = NSTableView()
    private lazy var deleteButton = NSButton(title: "Delete", target: self, action: #selector(deleteFields))
    private lazy var insertButton = NSButton(title: "Insert All", target: self, action: #selector(insertAll))

    override func loadView() {
        title = "Joined Field"
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 454, height: 330))
        let heading = NSTextField(labelWithString: "Insert all the items in the list")
        heading.font = .boldSystemFont(ofSize: 13)
        let scroll = joinedFieldList(table)
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(editField)
        let add = NSButton(title: "Add…", target: self, action: #selector(addField))
        add.isEnabled = !sourceFields.isEmpty
        let close = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        close.keyEquivalent = "\u{1b}"
        for child in [heading, scroll, add, deleteButton, close, insertButton] {
            child.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(child)
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            scroll.trailingAnchor.constraint(equalTo: add.leadingAnchor, constant: -12),
            add.topAnchor.constraint(equalTo: scroll.topAnchor),
            add.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            add.widthAnchor.constraint(equalToConstant: 96),
            deleteButton.topAnchor.constraint(equalTo: add.bottomAnchor, constant: 8),
            deleteButton.leadingAnchor.constraint(equalTo: add.leadingAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: add.trailingAnchor),
            insertButton.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            insertButton.leadingAnchor.constraint(equalTo: add.leadingAnchor),
            insertButton.trailingAnchor.constraint(equalTo: add.trailingAnchor),
            close.bottomAnchor.constraint(equalTo: insertButton.topAnchor, constant: -8),
            close.leadingAnchor.constraint(equalTo: add.leadingAnchor),
            close.trailingAnchor.constraint(equalTo: add.trailingAnchor)
        ])
        view = root
        updateButtons()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { joinedFields.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: joinedFields[row].template)
        label.toolTip = joinedFields[row].template
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

    private func updateButtons() {
        deleteButton.isEnabled = !table.selectedRowIndexes.isEmpty
        insertButton.isEnabled = !joinedFields.isEmpty
    }

    @objc private func addField() { openEditor(at: nil) }

    @objc private func editField() {
        guard joinedFields.indices.contains(table.clickedRow) else { return }
        openEditor(at: table.clickedRow)
    }

    private func openEditor(at index: Int?) {
        let editor = JoinedFieldEditorViewController()
        editor.sourceFields = sourceFields
        editor.sourceName = sourceName
        editor.existingTitles = sourceFields + joinedFields.enumerated().filter { $0.offset != index }.map { $0.element.template }
        if let index { editor.field = joinedFields[index] }
        editor.onSave = { [weak self] field in
            guard let self else { return }
            if let index { self.joinedFields[index] = field }
            else { self.joinedFields.append(field) }
            self.table.reloadData()
            self.updateButtons()
            self.onChange?(self.joinedFields)
        }
        presentAsSheet(editor)
    }

    @objc private func deleteFields() {
        for index in table.selectedRowIndexes.reversed() { joinedFields.remove(at: index) }
        table.deselectAll(nil)
        table.reloadData()
        updateButtons()
        onChange?(joinedFields)
    }

    @objc private func insertAll() {
        onChange?(joinedFields)
        closeWindow()
    }

    @objc private func closeWindow() { presentingViewController?.dismiss(self) }
}

final class JoinedFieldEditorViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var sourceFields: [String] = []
    var sourceName = "Fields"
    var existingTitles: [String] = []
    var field = JoinedField(template: "")
    var onSave: ((JoinedField) -> Void)?
    private let table = NSTableView()
    private let textView = NSTextView()
    private let removeEmpty = NSButton(checkboxWithTitle: "Fill up lines that contain no data", target: nil, action: nil)
    private lazy var addButton = NSButton(title: "Add", target: self, action: #selector(addSelectedFields))

    override func loadView() {
        title = "Join Fields Editor"
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 446))
        let instructions = NSTextField(wrappingLabelWithString:
            "To connect fields, select the field, and then click [Add].\nOther characters and line feeds can be entered either before or after a field.")
        let dataLabel = NSTextField(labelWithString: "Data")
        let sourceLabel = NSTextField(labelWithString: sourceName)
        let fieldScroll = joinedFieldList(table)
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(addSelectedFields)
        let textScroll = NSScrollView()
        textScroll.borderType = .bezelBorder
        textScroll.hasVerticalScroller = true
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 420, height: CGFloat.greatestFiniteMagnitude)
        textView.string = field.template
        textView.setAccessibilityLabel("Joined field template")
        textScroll.documentView = textView
        addButton.isEnabled = false
        removeEmpty.state = field.removesEmptyLines ? .on : .off
        removeEmpty.toolTip = "Remove a line when all fields on that line are empty."
        let clear = NSButton(title: "Clear All", target: self, action: #selector(clearText))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelEditing))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "OK", target: self, action: #selector(saveField))
        save.keyEquivalent = "\r"
        for child in [instructions, dataLabel, sourceLabel, fieldScroll, textScroll, addButton, removeEmpty, clear, cancel, save] {
            child.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(child)
        }
        NSLayoutConstraint.activate([
            instructions.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            instructions.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            instructions.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            dataLabel.topAnchor.constraint(equalTo: instructions.bottomAnchor, constant: 24),
            dataLabel.leadingAnchor.constraint(equalTo: instructions.leadingAnchor),
            sourceLabel.firstBaselineAnchor.constraint(equalTo: dataLabel.firstBaselineAnchor),
            sourceLabel.leadingAnchor.constraint(equalTo: fieldScroll.leadingAnchor),
            textScroll.topAnchor.constraint(equalTo: dataLabel.bottomAnchor, constant: 12),
            textScroll.leadingAnchor.constraint(equalTo: dataLabel.leadingAnchor),
            textScroll.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -12),
            textScroll.bottomAnchor.constraint(equalTo: removeEmpty.topAnchor, constant: -12),
            addButton.widthAnchor.constraint(equalToConstant: 96),
            addButton.centerYAnchor.constraint(equalTo: textScroll.centerYAnchor),
            fieldScroll.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 12),
            fieldScroll.trailingAnchor.constraint(equalTo: instructions.trailingAnchor),
            fieldScroll.widthAnchor.constraint(equalToConstant: 214),
            fieldScroll.topAnchor.constraint(equalTo: textScroll.topAnchor),
            fieldScroll.bottomAnchor.constraint(equalTo: removeEmpty.bottomAnchor),
            removeEmpty.leadingAnchor.constraint(equalTo: textScroll.leadingAnchor),
            removeEmpty.bottomAnchor.constraint(equalTo: save.topAnchor, constant: -24),
            clear.centerYAnchor.constraint(equalTo: removeEmpty.centerYAnchor),
            clear.trailingAnchor.constraint(equalTo: textScroll.trailingAnchor),
            save.trailingAnchor.constraint(equalTo: instructions.trailingAnchor),
            save.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            save.widthAnchor.constraint(equalToConstant: 64),
            cancel.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -8),
            cancel.centerYAnchor.constraint(equalTo: save.centerYAnchor)
        ])
        view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { sourceFields.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        NSTextField(labelWithString: sourceFields[row])
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        addButton.isEnabled = !table.selectedRowIndexes.isEmpty
    }

    @objc private func addSelectedFields() {
        let tokens = table.selectedRowIndexes.map { "[\(sourceFields[$0])]" }.joined()
        guard !tokens.isEmpty else { return }
        textView.insertText(tokens, replacementRange: textView.selectedRange())
        view.window?.makeFirstResponder(textView)
    }

    @objc private func clearText() {
        textView.selectAll(nil)
        textView.insertText("", replacementRange: textView.selectedRange())
        view.window?.makeFirstResponder(textView)
    }

    @objc private func cancelEditing() { presentingViewController?.dismiss(self) }

    @objc private func saveField() {
        let template = textView.string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let names = JoinedField.referencedFields(in: template)
        let unknown = names.filter { !sourceFields.contains($0) }
        let error: String?
        if names.isEmpty { error = "Add at least one field to the template." }
        else if !unknown.isEmpty { error = "Unknown fields: " + unknown.joined(separator: ", ") }
        else if existingTitles.contains(template) { error = "A column with this template already exists." }
        else { error = nil }
        if let error, let window = view.window {
            let alert = NSAlert()
            alert.messageText = "Check the joined field"
            alert.informativeText = error
            alert.beginSheetModal(for: window)
            return
        }
        onSave?(JoinedField(template: template, removesEmptyLines: removeEmpty.state == .on))
        cancelEditing()
    }
}
