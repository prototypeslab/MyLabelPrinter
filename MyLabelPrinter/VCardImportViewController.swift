import Cocoa
import UniformTypeIdentifiers

struct ContactTable {
    let fields: [String]
    let rows: [[String: String]]

    func selecting(_ columns: [String]) -> ContactTable {
        ContactTable(fields: columns, rows: rows.map { row in
            Dictionary(uniqueKeysWithValues: columns.map { ($0, row[$0] ?? "") })
        })
    }

    func csvData() -> Data {
        func quoted(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let lines = [fields] + rows.map { row in fields.map { row[$0] ?? "" } }
        return Data((lines.map { $0.map(quoted).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n").utf8)
    }

    static func readVCard(_ url: URL) throws -> ContactTable {
        let text = try String(contentsOf: url, encoding: .utf8)
        var lines: [String] = []
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n") {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += line.dropFirst()
            } else {
                lines.append(line)
            }
        }
        func unescape(_ value: String) -> String {
            var result = "", escaped = false
            for character in value {
                if escaped {
                    result.append(character == "n" || character == "N" ? "\n" : character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else {
                    result.append(character)
                }
            }
            if escaped { result.append("\\") }
            return result
        }
        var rows: [[String: String]] = []
        var current: [String: String]?
        var fields: [String] = []
        for line in lines {
            if line.uppercased() == "BEGIN:VCARD" {
                current = [:]
            } else if line.uppercased() == "END:VCARD" {
                if let contact = current, !contact.isEmpty { rows.append(contact) }
                current = nil
            } else if current != nil, let colon = line.firstIndex(of: ":") {
                let property = String(line[..<colon]).components(separatedBy: ";")[0]
                let name = (property.components(separatedBy: ".").last ?? property).uppercased()
                guard !name.isEmpty, name != "VERSION" else { continue }
                var key = name
                var occurrence = 2
                while current?[key] != nil {
                    key = "\(name) \(occurrence)"
                    occurrence += 1
                }
                current?[key] = unescape(String(line[line.index(after: colon)...]))
                if !fields.contains(key) { fields.append(key) }
            }
        }
        guard !rows.isEmpty else {
            throw NSError(domain: "VCardImport", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The file contains no readable vCard contacts."])
        }
        let used = Set(rows.flatMap(\.keys))
        return ContactTable(fields: fields.filter { used.contains($0) }, rows: rows)
    }

    static func readCSV(_ url: URL, headerRow: Bool) throws -> ContactTable {
        var text = try String(contentsOf: url, encoding: .utf8)
        if text.hasPrefix("\u{feff}") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var quoted = false, commas = 0, semicolons = 0
        for character in text {
            if character == "\"" { quoted.toggle() }
            else if !quoted {
                if character == "\n" { break }
                if character == "," { commas += 1 }
                if character == ";" { semicolons += 1 }
            }
        }
        let delimiter: Character = semicolons > commas ? ";" : ","
        let characters = Array(text)
        var records: [[String]] = [], row: [String] = [], value = ""
        var index = 0
        quoted = false
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    value.append("\"")
                    index += 1
                } else {
                    quoted.toggle()
                }
            } else if character == delimiter && !quoted {
                row.append(value); value = ""
            } else if character == "\n" && !quoted {
                row.append(value)
                if row != [""] { records.append(row) }
                row = []; value = ""
            } else {
                value.append(character)
            }
            index += 1
        }
        guard !quoted else {
            throw NSError(domain: "CSVImport", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The CSV file has an unclosed quoted field."])
        }
        if !value.isEmpty || !row.isEmpty { row.append(value); records.append(row) }
        guard let first = records.first else { return ContactTable(fields: [], rows: []) }
        var used: Set<String> = []
        let fields = first.enumerated().map { index, value -> String in
            let base = headerRow && !value.isEmpty ? value : "Field \(index + 1)"
            var name = base, suffix = 2
            while used.contains(name) { name = "\(base) \(suffix)"; suffix += 1 }
            used.insert(name)
            return name
        }
        let values = headerRow ? Array(records.dropFirst()) : records
        return ContactTable(fields: fields, rows: values.map { cells in
            Dictionary(uniqueKeysWithValues: fields.enumerated().map {
                ($0.element, $0.offset < cells.count ? cells[$0.offset] : "")
            })
        })
    }
}

final class VCardImportViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    let contacts: ContactTable
    let sourceURL: URL
    var onSave: ((ContactTable) -> Void)?
    private var included: Set<String>
    private let table = NSTableView()
    private let saveButton = NSButton(title: "Save CSV…", target: nil, action: nil)

    init(contacts: ContactTable, sourceURL: URL) {
        self.contacts = contacts
        self.sourceURL = sourceURL
        included = Set(contacts.fields)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 480))
        let title = NSTextField(labelWithString: "Choose CSV Columns")
        title.font = .boldSystemFont(ofSize: 18)
        let description = NSTextField(wrappingLabelWithString:
            "\(contacts.rows.count) contacts in \(sourceURL.lastPathComponent). Select the columns to save and import.")
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 26
        table.usesAlternatingRowBackgroundColors = true
        for (identifier, title, width) in [("include", "Include", 65.0), ("field", "Column", 170.0), ("sample", "Example value", 365.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        scroll.documentView = table
        let all = NSButton(title: "Select All", target: self, action: #selector(selectAllColumns))
        let none = NSButton(title: "Deselect All", target: self, action: #selector(deselectAll))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [all, none, NSView(), cancel, saveButton])
        buttons.spacing = 10
        for child in [title, description, scroll, buttons] {
            child.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(child)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            description.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            description.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            description.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: description.bottomAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: description.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -16),
            buttons.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            buttons.trailingAnchor.constraint(equalTo: description.trailingAnchor),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])
        view = root
    }

    var selectedTable: ContactTable { contacts.selecting(contacts.fields.filter { included.contains($0) }) }
    func numberOfRows(in tableView: NSTableView) -> Int { contacts.fields.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let field = contacts.fields[row]
        if tableColumn?.identifier.rawValue == "include" {
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleColumn(_:)))
            button.tag = row
            button.state = included.contains(field) ? .on : .off
            button.setAccessibilityLabel("Include \(field)")
            return button
        }
        let value = tableColumn?.identifier.rawValue == "field" ? field
            : contacts.rows.lazy.compactMap { $0[field] }.first(where: { !$0.isEmpty }) ?? ""
        let label = NSTextField(labelWithString: value.replacingOccurrences(of: "\n", with: " ↵ "))
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = value
        return label
    }

    @objc private func toggleColumn(_ sender: NSButton) {
        let field = contacts.fields[sender.tag]
        if sender.state == .on { included.insert(field) } else { included.remove(field) }
        saveButton.isEnabled = !included.isEmpty
    }

    @objc private func selectAllColumns() {
        included = Set(contacts.fields)
        table.reloadData()
        saveButton.isEnabled = !included.isEmpty
    }

    @objc private func deselectAll() {
        included = []
        table.reloadData()
        saveButton.isEnabled = false
    }

    @objc private func cancel() { dismiss(self) }

    @objc private func save() {
        guard !included.isEmpty, let window = view.window else { return }
        let selected = selectedTable
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent + ".csv"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                try selected.csvData().write(to: url, options: .atomic)
                self.onSave?(selected)
                self.dismiss(self)
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }
}
