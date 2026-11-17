import Cocoa

final class LineEditorViewController: NSViewController {
    var onAdd: ((LabelLine) -> Void)?
    private let weight = NSPopUpButton()
    private let style = NSPopUpButton()
    private let start = NSPopUpButton()
    private let end = NSPopUpButton()
    private let preview = LineItemView()

    override func loadView() {
        view = NSView(frame: CGRect(x: 0, y: 0, width: 440, height: 420))
        let title = NSTextField(labelWithString: "Add Line")
        title.font = .boldSystemFont(ofSize: 20)
        weight.addItems(withTitles: ["0.25 pt", "0.5 pt", "0.75 pt", "1.0 pt", "1.5 pt",
                                    "2.25 pt", "3.0 pt", "4.5 pt", "6.0 pt"])
        weight.selectItem(at: 3)
        style.addItems(withTitles: LabelLineStyle.allCases.map(\.rawValue))
        start.addItems(withTitles: LabelLineEndpoint.allCases.map(\.rawValue))
        end.addItems(withTitles: LabelLineEndpoint.allCases.map(\.rawValue))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.addArrangedSubview(title)
        for (label, popup) in [("Weight", weight), ("Line Type / Style", style),
                                ("Start Endpoint", start), ("End Endpoint", end)] {
            popup.target = self
            popup.action = #selector(updatePreview)
            popup.setAccessibilityLabel(label)
            let text = NSTextField(labelWithString: label)
            text.widthAnchor.constraint(equalToConstant: 130).isActive = true
            let row = NSStackView(views: [text, popup])
            row.spacing = 12
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        let previewTitle = NSTextField(labelWithString: "Preview")
        previewTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        stack.addArrangedSubview(previewTitle)
        preview.setAccessibilityLabel("Preview of selected line weight, style, and endpoints")
        preview.showsHandles = false
        preview.isPreview = true
        stack.addArrangedSubview(preview)
        preview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 90).isActive = true
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{001b}"
        let add = NSButton(title: "Add Line", target: self, action: #selector(addLine))
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
        updatePreview()
    }

    private var configuration: LabelLine {
        LabelLine(weight: LabelLine.weights[weight.indexOfSelectedItem],
                  style: LabelLineStyle.allCases[style.indexOfSelectedItem],
                  startEndpoint: LabelLineEndpoint.allCases[start.indexOfSelectedItem],
                  endEndpoint: LabelLineEndpoint.allCases[end.indexOfSelectedItem])
    }

    @objc private func updatePreview() {
        preview.line = configuration
        preview.setAccessibilityValue("\(weight.titleOfSelectedItem ?? ""), \(style.titleOfSelectedItem ?? ""), start \(start.titleOfSelectedItem ?? ""), end \(end.titleOfSelectedItem ?? "")")
    }

    @objc private func addLine() {
        onAdd?(configuration)
        dismiss(self)
    }

    @objc private func cancel() { dismiss(self) }
}
