import Cocoa

private final class ObjectOrderButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedControlColor.withAlphaComponent(0.25).setFill()
            bounds.fill()
        }
        let gray = NSColor(calibratedWhite: 0.65, alpha: 1)
        let coral = NSColor(calibratedRed: 1, green: 0.40, blue: 0.36, alpha: 1)
        func square(_ rect: NSRect, _ color: NSColor) {
            color.setFill()
            rect.fill()
            NSColor.windowBackgroundColor.setStroke()
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 0.5
            outline.stroke()
        }
        let rear = NSRect(x: 10, y: 11, width: 9, height: 9)
        let middle = NSRect(x: 14, y: 7, width: 9, height: 9)
        let front = NSRect(x: 18, y: 3, width: 9, height: 9)
        switch RulerImageView.ObjectOrder(rawValue: tag) {
        case .back:
            square(middle, coral)
            square(rear, gray)
            square(front, gray)
        case .backward:
            square(front, coral)
            square(rear, gray)
        case .forward:
            square(rear, gray)
            square(front, coral)
        case .front:
            square(rear, gray)
            square(front, gray)
            square(middle, coral)
        case nil: break
        }
    }
}

class WindowController: NSWindowController, NSToolbarItemValidation {

  private static let mainWindowFrameName: NSWindow.FrameAutosaveName = "MyLabelPrinterMainWindow"

  
  private var titlebarAccessoryViewController: CustomTitlebarAccessoryViewController?
  private var titlebarAccessoryViewControllerToggleButton: NSToolbarItem?
  private weak var zoomLevelLabel: NSTextField?
  private var artworkPopover: NSPopover?
  private var titlebarAccessoryViewIsHidden = true
  
  
  
  override func windowDidLoad()
  {
      super.windowDidLoad()

      if let window {
          _ = window.setFrameUsingName(Self.mainWindowFrameName)
          _ = window.setFrameAutosaveName(Self.mainWindowFrameName)
      }
      
      
      self.configureToolbar()
      self.configureTitlebarAccessoryView()
  }
  private func configureToolbar()
  {
      if  let unwrappedWindow = self.window {
          
          let newToolbar = NSToolbar(identifier: NSToolbar.Identifier.mainWindowToolbarIdentifier)
          newToolbar.delegate = self
          newToolbar.allowsUserCustomization = false
          newToolbar.autosavesConfiguration = true
          newToolbar.displayMode = .iconAndLabel
          newToolbar.sizeMode = .regular
          newToolbar.centeredItemIdentifier = NSToolbarItem.Identifier.toolbarPickerItem
          
          unwrappedWindow.title = "Swift Commander"
          if #available(macOS 11.0, *) {
              unwrappedWindow.subtitle = "Swift Commander"
              unwrappedWindow.toolbarStyle = .unified
          }
          
          unwrappedWindow.titleVisibility = .hidden
          
          unwrappedWindow.toolbar = newToolbar
          if !newToolbar.items.contains(where: { $0.itemIdentifier == .toolbarItemObjectOrder }),
             let zoomIndex = newToolbar.items.firstIndex(where: { $0.itemIdentifier == .toolbarItemZoom }) {
              newToolbar.insertItem(withItemIdentifier: .toolbarItemObjectOrder, at: zoomIndex)
          }
          unwrappedWindow.toolbar?.validateVisibleItems()
      }
  }
  
  
  func validateToolbarItem(_ item: NSToolbarItem) -> Bool
  {
    let itemIdentifier = item.itemIdentifier
      
      
      if  item.itemIdentifier == NSToolbarItem.Identifier.toolbarMoreActions {
          return true
      }
      
      if  item.itemIdentifier == NSToolbarItem.Identifier.toolbarShareButtonItem {
          return true
      }
      
      if  item.itemIdentifier == NSToolbarItem.Identifier.toolbarItemToggleTitlebarAccessory {
          return self.titlebarAccessoryViewController != nil
      }
      
      if  item.itemIdentifier == NSToolbarItem.Identifier.toolbarItemMoreInfo {
          return false
      }
    if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemNew
    {
        return true
    }
    if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemOpen
    {
        return true
    }
    if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemSave
    {
        return true
    }
      if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemPrint
      {
          return true
      }
      if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemSettings
      {
          return true
      }
      if  item.itemIdentifier == NSToolbarItem.Identifier.toolbarItemExit {
          return true
      }
      
      
      return true
  }
  
  @IBAction func testAction(_ sender: Any)
  {
      if  let toolbarItem = sender as? NSToolbarItem {
          print("Clicked \(toolbarItem.itemIdentifier.rawValue)")
      }
  }

  @objc private func changeObjectOrder(_ sender: NSButton) {
      guard let order = RulerImageView.ObjectOrder(rawValue: sender.tag) else { return }
      (contentViewController as? ViewController)?.rulerView.changeSelectedObjectOrder(order)
  }

  @objc private func zoomOutFromToolbar(_ sender: Any) {
      (contentViewController as? ViewController)?.zoomOutButtonAction(sender)
      refreshToolbarZoomLevel()
  }

  @objc private func zoomInFromToolbar(_ sender: Any) {
      (contentViewController as? ViewController)?.zoomInButtonAction(sender)
      refreshToolbarZoomLevel()
  }

  @objc private func showSymbolPicker(_ sender: NSButton) {
      showArtworkPicker(.symbol, relativeTo: sender)
  }

  @objc private func showClipArtPicker(_ sender: NSButton) {
      showArtworkPicker(.clipArt, relativeTo: sender)
  }

  private func showArtworkPicker(_ kind: ArtworkPickerViewController.Kind, relativeTo sender: NSView) {
      artworkPopover?.close()
      let picker = ArtworkPickerViewController(kind: kind)
      let popover = NSPopover()
      popover.behavior = .transient
      popover.contentSize = NSSize(width: 292, height: 470)
      popover.contentViewController = picker
      picker.onSelect = { [weak self, weak popover] image in
          let contentKind: ImageContentKind = kind == .symbol ? .symbol : .clipArt
          (self?.contentViewController as? ViewController)?.insertArtwork(image, kind: contentKind)
          popover?.close()
      }
      artworkPopover = popover
      popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
  }

  private func refreshToolbarZoomLevel() {
      guard let viewController = contentViewController as? ViewController else { return }
      zoomLevelLabel?.stringValue = "\(Int((viewController.rulerView.zoomLevel * 100).rounded()))%"
  }
  
  @IBAction func exitAction(_ sender: Any)
  {
      if  let toolbarItem = sender as? NSToolbarItem {
          print("Clicked \(toolbarItem.itemIdentifier.rawValue)")
          NSApp.terminate(self)
      }
  }
}
extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let img = self.copy() as! NSImage
        img.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: img.size)
        rect.fill(using: .sourceAtop)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}
extension WindowController: NSToolbarDelegate
{
    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem?
    {
        let isBordered = false
        
        if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemToggleTitlebarAccessory {
            let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
            toolbarItem.target = self
            toolbarItem.action = #selector(toggleTitlebarAccessory(_:))
            toolbarItem.label = "Info"
            toolbarItem.paletteLabel = "Info"
            toolbarItem.toolTip = "Hides additional accessories"
            toolbarItem.isBordered = isBordered
            if  #available(macOS 11.0, *) {
                toolbarItem.image = NSImage(systemSymbolName: "menubar.arrow.up.rectangle", accessibilityDescription: "")
            } else {
                toolbarItem.image = NSImage(named: NSImage.touchBarGoUpTemplateName)
            }
            self.titlebarAccessoryViewControllerToggleButton = toolbarItem
            return toolbarItem
        }
        
        if  itemIdentifier == NSToolbarItem.Identifier.toolbarMoreActions {
            let toolbarItem = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            toolbarItem.showsIndicator = true // Make `false` if you don't want the down arrow to be drawn
            toolbarItem.label = "More Actions"
            toolbarItem.paletteLabel = "More Actions"
            toolbarItem.toolTip = "Displays available actions"
            toolbarItem.isBordered = isBordered
            if  #available(macOS 11.0, *) {
                toolbarItem.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "")
            } else {
                toolbarItem.image = NSImage(named: NSImage.advancedName)
            }
            return toolbarItem
        }
        
        if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemUserAccounts {
            let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
            toolbarItem.target = self
            toolbarItem.action = #selector(testAction(_:))
            toolbarItem.label = "Accounts"
            toolbarItem.paletteLabel = "Accounts"
            toolbarItem.toolTip = "Open Accounts panel"
            toolbarItem.visibilityPriority = .low
            toolbarItem.isBordered = isBordered
            if  #available(macOS 11.0, *) {
                toolbarItem.image = NSImage(systemSymbolName: "at", accessibilityDescription: "")
            } else {
                toolbarItem.image = NSImage(named: NSImage.userAccountsName)
            }
            return toolbarItem
        }
      if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemSettings {
          let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
          toolbarItem.target = self
          toolbarItem.action = #selector(toolbarAction(_:))
          toolbarItem.label = "Settings"
          toolbarItem.paletteLabel = "Settings"
          toolbarItem.toolTip = "Settings"
          toolbarItem.visibilityPriority = .standard
          toolbarItem.isBordered = isBordered

          let image = NSImage(systemSymbolName: "wrench.and.screwdriver.fill",accessibilityDescription: "wrench.and.screwdriver.fill")
          toolbarItem.image = image
          return toolbarItem
      }
      if itemIdentifier == .toolbarItemObjectOrder {
          let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
          toolbarItem.label = "Order"
          toolbarItem.paletteLabel = "Object Order"
          toolbarItem.isBordered = false
          let container = NSView(frame: NSRect(x: 0, y: 0, width: 136, height: 24))
          container.wantsLayer = true
          container.layer?.borderWidth = 1
          container.layer?.borderColor = NSColor.separatorColor.cgColor
          container.layer?.cornerRadius = 0
          for order in RulerImageView.ObjectOrder.allCases {
              let button = ObjectOrderButton(frame: NSRect(x: order.rawValue * 34, y: 0, width: 34, height: 24))
              button.tag = order.rawValue
              button.title = ""
              button.isBordered = false
              button.bezelStyle = .smallSquare
              button.target = self
              button.action = #selector(changeObjectOrder(_:))
              button.toolTip = order.title
              button.setAccessibilityLabel(order.title)
              container.addSubview(button)
          }
          toolbarItem.view = container
          return toolbarItem
      }
      if itemIdentifier == .toolbarItemZoom {
          let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
          toolbarItem.label = "Zoom"
          toolbarItem.paletteLabel = "Zoom"
          toolbarItem.toolTip = "Change label zoom"
          toolbarItem.isBordered = false
        
          let zoomOutButton = NSButton(title: "−", target: self, action: #selector(zoomOutFromToolbar(_:)))
          zoomOutButton.bezelStyle = .smallSquare
          zoomOutButton.isBordered = false
          zoomOutButton.setAccessibilityLabel("Zoom Out")
        
          let levelLabel = NSTextField(labelWithString: "100%")
          levelLabel.alignment = .center
          levelLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
          levelLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

          let zoomInButton = NSButton(title: "+", target: self, action: #selector(zoomInFromToolbar(_:)))
          zoomInButton.bezelStyle = .smallSquare
          zoomInButton.isBordered = false
          zoomInButton.setAccessibilityLabel("Zoom In")

          let control = NSStackView(views: [zoomOutButton, levelLabel, zoomInButton])
          control.orientation = .horizontal
          control.alignment = .centerY
          control.spacing = 0
          control.distribution = .fill

          NSLayoutConstraint.activate([
              zoomOutButton.widthAnchor.constraint(equalToConstant: 34),
              levelLabel.widthAnchor.constraint(equalToConstant: 62),
              zoomInButton.widthAnchor.constraint(equalToConstant: 34),
              control.heightAnchor.constraint(equalToConstant: 24)
          ])

          let container = NSView(frame: NSRect(x: 0, y: 0, width: 130, height: 24))
          container.wantsLayer = true
          container.layer?.borderWidth = 1
          container.layer?.borderColor = NSColor.separatorColor.cgColor
          container.layer?.cornerRadius = 0
          control.frame = container.bounds
          control.autoresizingMask = [.width, .height]
          container.addSubview(control)

          toolbarItem.view = container
          toolbarItem.isBordered = false
          zoomLevelLabel = levelLabel
          refreshToolbarZoomLevel()
          return toolbarItem
      }
      if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemNew {
          let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
          toolbarItem.target = self
          toolbarItem.action = #selector(toolbarAction(_:))
          toolbarItem.label = "New"
          toolbarItem.paletteLabel = "New"
          toolbarItem.toolTip = "New"
          toolbarItem.visibilityPriority = .standard
          toolbarItem.isBordered = isBordered

          let image = NSImage(systemSymbolName: "document",accessibilityDescription: "document")
          toolbarItem.image = image
          return toolbarItem
      }
      if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemOpen {
          let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
          toolbarItem.target = self
          toolbarItem.action = #selector(toolbarAction(_:))
          toolbarItem.label = "Open"
          toolbarItem.paletteLabel = "Open"
          toolbarItem.toolTip = "Open"
          toolbarItem.visibilityPriority = .standard
          toolbarItem.isBordered = isBordered

          let image = NSImage(systemSymbolName: "document.badge.arrow.up.fill",accessibilityDescription: "document.badge.arrow.up.fill")
          toolbarItem.image = image
          return toolbarItem
      }
      if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemSave {
          let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
          toolbarItem.target = self
          toolbarItem.action = #selector(toolbarAction(_:))
          toolbarItem.label = "Save"
          toolbarItem.paletteLabel = "Save"
          toolbarItem.toolTip = "Save"
          toolbarItem.visibilityPriority = .standard
          toolbarItem.isBordered = isBordered

          let image = NSImage(systemSymbolName: "arrow.down.document.fill",accessibilityDescription: "arrow.down.document.fill")
          toolbarItem.image = image
          return toolbarItem
      }
      if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemPrint {
          let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
          toolbarItem.target = self
          toolbarItem.action = #selector(toolbarAction(_:))
          toolbarItem.label = "Print"
          toolbarItem.paletteLabel = "Print"
          toolbarItem.toolTip = "Print"
          toolbarItem.visibilityPriority = .standard
          toolbarItem.isBordered = isBordered

          let image = NSImage(systemSymbolName: "printer.inverse",accessibilityDescription: "printer.inverse")
          toolbarItem.image = image
          return toolbarItem
      }
      if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemTextBox {
          let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
          toolbarItem.target = self
          toolbarItem.action = #selector(toolbarAction(_:))
          toolbarItem.label = "Text Box"
          toolbarItem.paletteLabel = "Text Box"
          toolbarItem.toolTip = "Text Box"
          toolbarItem.visibilityPriority = .standard
          toolbarItem.isBordered = isBordered

          let image = NSImage(systemSymbolName: "character.square",accessibilityDescription: "character.square")
          toolbarItem.image = image
          return toolbarItem
      }

      if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemFrame {
          let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
          toolbarItem.target = self
          toolbarItem.action = #selector(toolbarAction(_:))
          toolbarItem.label = "Frame"
          toolbarItem.paletteLabel = "Frame"
          toolbarItem.toolTip = "Frame"
          toolbarItem.visibilityPriority = .standard
          toolbarItem.isBordered = isBordered

          let image = NSImage(systemSymbolName: "rectangle",accessibilityDescription: "rectangle")
          toolbarItem.image = image
          return toolbarItem
      }
      if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemImage {
          let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
          toolbarItem.target = self
          toolbarItem.action = #selector(toolbarAction(_:))
          toolbarItem.label = "Image"
          toolbarItem.paletteLabel = "Image"
          toolbarItem.toolTip = "Image"
          toolbarItem.visibilityPriority = .standard
          toolbarItem.isBordered = isBordered

          let image = NSImage(systemSymbolName: "photo",accessibilityDescription: "photo")
          toolbarItem.image = image
          return toolbarItem
      }

      if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemSymbol {
          let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
          toolbarItem.label = "Symbol"
          toolbarItem.paletteLabel = "Symbol"
          toolbarItem.toolTip = "Symbol"
          toolbarItem.visibilityPriority = .standard
          toolbarItem.isBordered = isBordered

          let configuration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
          let image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "face.smiling")?
              .withSymbolConfiguration(configuration)
          let button = NSButton(image: image ?? NSImage(), target: self, action: #selector(showSymbolPicker(_:)))
          button.bezelStyle = .texturedRounded
          button.isBordered = false
          button.imagePosition = .imageOnly
          button.imageScaling = .scaleNone
          button.frame.size = NSSize(width: 32, height: 32)
          button.setAccessibilityLabel("Symbol")
          toolbarItem.view = button
          return toolbarItem
      }

      if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemClipArt {
          let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
          toolbarItem.label = "Clip Art"
          toolbarItem.paletteLabel = "Clip Art"
          toolbarItem.toolTip = "Clip Art"
          toolbarItem.visibilityPriority = .standard
          toolbarItem.isBordered = isBordered

          let configuration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
          let image = NSImage(systemSymbolName: "american.football", accessibilityDescription: "american.football")?
              .withSymbolConfiguration(configuration)
          let button = NSButton(image: image ?? NSImage(), target: self, action: #selector(showClipArtPicker(_:)))
          button.bezelStyle = .texturedRounded
          button.isBordered = false
          button.imagePosition = .imageOnly
          button.imageScaling = .scaleNone
          button.frame.size = NSSize(width: 32, height: 32)
          button.setAccessibilityLabel("Clip Art")
          toolbarItem.view = button
          return toolbarItem
      }

      if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemShape {
          let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
          toolbarItem.target = self
          toolbarItem.action = #selector(toolbarAction(_:))
          toolbarItem.label = "Shape"
          toolbarItem.paletteLabel = "Shape"
          toolbarItem.toolTip = "Shape"
          toolbarItem.visibilityPriority = .standard
          toolbarItem.isBordered = isBordered

          let image = NSImage(systemSymbolName: "square.on.circle",accessibilityDescription: "square.on.circle")
          toolbarItem.image = image
          return toolbarItem
      }
      if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemLine {
          let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
          toolbarItem.target = self
          toolbarItem.action = #selector(toolbarAction(_:))
          toolbarItem.label = "Line"
          toolbarItem.paletteLabel = "Line"
          toolbarItem.toolTip = "Line"
          toolbarItem.visibilityPriority = .standard
          toolbarItem.isBordered = isBordered

          let image = NSImage(systemSymbolName: "stroke.line.diagonal",accessibilityDescription: "stroke.line.diagonal")
          toolbarItem.image = image
          return toolbarItem
      }
      if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemBarcode {
          let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
          toolbarItem.target = self
          toolbarItem.action = #selector(toolbarAction(_:))
          toolbarItem.label = "Barcode"
          toolbarItem.paletteLabel = "Barcode"
          toolbarItem.toolTip = "Barcode"
          toolbarItem.visibilityPriority = .standard
          toolbarItem.isBordered = isBordered

          let image = NSImage(systemSymbolName: "barcode",accessibilityDescription: "barcode")
          toolbarItem.image = image
          return toolbarItem
      }
      if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemDatabase {
          let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
          toolbarItem.target = self
          toolbarItem.action = #selector(toolbarAction(_:))
          toolbarItem.label = "Database"
          toolbarItem.paletteLabel = "Database"
          toolbarItem.toolTip = "Database"
          toolbarItem.visibilityPriority = .standard
          toolbarItem.isBordered = isBordered

          let image = NSImage(systemSymbolName: "tablecells",accessibilityDescription: "tablecells")
          toolbarItem.image = image
          return toolbarItem
      }
        if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemExit {
            let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
            toolbarItem.target = self
            toolbarItem.action = #selector(exitAction(_:))
            toolbarItem.label = "Exit"
            toolbarItem.paletteLabel = "Exit"
            toolbarItem.toolTip = "Exit App"
            toolbarItem.visibilityPriority = .standard
            toolbarItem.isBordered = isBordered

          let base = NSImage(systemSymbolName: "figure.walk.motion",
                             accessibilityDescription: "figure.walk.motion")

          if #available(macOS 11.0, *) {
              let config = NSImage.SymbolConfiguration(paletteColors: [NSColor.systemRed])
              let image = base?.withSymbolConfiguration(config)
              image?.isTemplate = false
              toolbarItem.image = image
          } else {
              toolbarItem.image = base
          }

            return toolbarItem
        }
        if  itemIdentifier == NSToolbarItem.Identifier.toolbarItemMoreInfo {
            let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
            toolbarItem.target = self
            toolbarItem.action = #selector(testAction(_:))
            toolbarItem.label = "More Info"
            toolbarItem.paletteLabel = "More Info"
            toolbarItem.toolTip = "See more info"
            toolbarItem.isBordered = isBordered
            toolbarItem.visibilityPriority = .low
            if  #available(macOS 11.0, *) {
                toolbarItem.image = NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: "")
            } else {
                toolbarItem.image = NSImage(named: NSImage.infoName)
            }
            return toolbarItem
        }
        
        if  itemIdentifier == NSToolbarItem.Identifier.toolbarPickerItem {
            let titles = ["General", "Advanced", "Sync"]
            
            let toolbarItem = NSToolbarItemGroup(itemIdentifier: itemIdentifier, titles: titles, selectionMode: .selectOne, labels: titles, target: nil, action: Selector(("toolbarPickerDidSelectItem:")) )
            
            toolbarItem.label = "View"
            toolbarItem.paletteLabel = "View"
            toolbarItem.toolTip = "Change the selected view"
            toolbarItem.selectedIndex = 0
            return toolbarItem
        }

        return nil
    }
  @IBAction func toolbarAction(_ sender: Any)
  {
      if  let toolbarItem = sender as? NSToolbarItem {
          

          if(toolbarItem.itemIdentifier.rawValue == "toolbarSearchItem")
          {
              print("Search \(toolbarItem.itemIdentifier.rawValue)")
          }
          if(toolbarItem.itemIdentifier.rawValue == "toolbarItemHidden")
          {
              print("Hidden \(toolbarItem.itemIdentifier.rawValue)")
          }
          if(toolbarItem.itemIdentifier.rawValue == "toolbarItemSelect")
          {
              print("Select \(toolbarItem.itemIdentifier.rawValue)")
          }
          if(toolbarItem.itemIdentifier.rawValue == "toolbarItemInvert")
          {
              print("Invert \(toolbarItem.itemIdentifier.rawValue)")
          }
  
          if toolbarItem.itemIdentifier == .toolbarItemPrint {
              (contentViewController as? ViewController)?.printButtonAction(toolbarItem)
          }
          if toolbarItem.itemIdentifier == .toolbarItemNew {
              (contentViewController as? ViewController)?.newButtonAction(toolbarItem)
          }
          if toolbarItem.itemIdentifier == .toolbarItemOpen {
              (contentViewController as? ViewController)?.openButtonAction(toolbarItem)
          }
          if toolbarItem.itemIdentifier == .toolbarItemSave {
              (contentViewController as? ViewController)?.saveButtonAction(toolbarItem)
          }
          if(toolbarItem.itemIdentifier.rawValue == "toolbarItemTextBox")
          {
            (contentViewController as? ViewController)?.addTextButtonAction(toolbarItem)
          }
          if(toolbarItem.itemIdentifier.rawValue == "toolbarItemFrame")
          {
            (contentViewController as? ViewController)?.frameButtonAction(toolbarItem)
          }
          if(toolbarItem.itemIdentifier.rawValue == "toolbarItemImage")
          {
            (contentViewController as? ViewController)?.imageButtonAction(toolbarItem)
          }
          if(toolbarItem.itemIdentifier.rawValue == "toolbarItemShape")
          {
            (contentViewController as? ViewController)?.shapeButtonAction(toolbarItem)
          }
        if(toolbarItem.itemIdentifier.rawValue == "toolbarItemLine")
        {
          (contentViewController as? ViewController)?.lineButtonAction(toolbarItem)
        }
          if(toolbarItem.itemIdentifier.rawValue == "toolbarItemBarcode")
          {
            (contentViewController as? ViewController)?.barcodeButtonAction(toolbarItem)
          }
        if(toolbarItem.itemIdentifier.rawValue == "toolbarItemDatabase")
        {
          (contentViewController as? ViewController)?.databaseButtonAction(toolbarItem)
        }
        
          if(toolbarItem.itemIdentifier.rawValue == "toolbarItemSettings")
          {
              print("Settings \(toolbarItem.itemIdentifier.rawValue)")
          }
          if(toolbarItem.itemIdentifier.rawValue == "toolbarItemExit")
          {
              print("Exit \(toolbarItem.itemIdentifier.rawValue)")
              NSApp.terminate(self)
          }

      }
  }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
    {
        if  #available(macOS 11.0, *) {
            return [
                NSToolbarItem.Identifier.toolbarItemNew,
                NSToolbarItem.Identifier.toolbarItemOpen,
                NSToolbarItem.Identifier.toolbarItemSave,
                NSToolbarItem.Identifier.flexibleSpace,
                NSToolbarItem.Identifier.toolbarItemTextBox,
                NSToolbarItem.Identifier.toolbarItemFrame,
                NSToolbarItem.Identifier.toolbarItemImage,
                NSToolbarItem.Identifier.toolbarItemSymbol,
                NSToolbarItem.Identifier.toolbarItemClipArt,
                NSToolbarItem.Identifier.toolbarItemShape,
                NSToolbarItem.Identifier.toolbarItemLine,
                NSToolbarItem.Identifier.toolbarItemBarcode,
                NSToolbarItem.Identifier.toolbarItemDatabase,
                NSToolbarItem.Identifier.flexibleSpace,
                NSToolbarItem.Identifier.toolbarItemObjectOrder,
                NSToolbarItem.Identifier.toolbarItemZoom,
                NSToolbarItem.Identifier.flexibleSpace,
                NSToolbarItem.Identifier.toolbarItemPrint,
                NSToolbarItem.Identifier.flexibleSpace,
                NSToolbarItem.Identifier.toolbarItemExit

            ]
        } else {
            return [
                NSToolbarItem.Identifier.toolbarItemNew,
                NSToolbarItem.Identifier.toolbarItemOpen,
                NSToolbarItem.Identifier.toolbarItemSave,
                NSToolbarItem.Identifier.flexibleSpace,
                NSToolbarItem.Identifier.toolbarItemTextBox,
                NSToolbarItem.Identifier.toolbarItemFrame,
                NSToolbarItem.Identifier.toolbarItemImage,
                NSToolbarItem.Identifier.toolbarItemSymbol,
                NSToolbarItem.Identifier.toolbarItemClipArt,
                NSToolbarItem.Identifier.toolbarItemShape,
                NSToolbarItem.Identifier.toolbarItemLine,
                NSToolbarItem.Identifier.toolbarItemBarcode,
                NSToolbarItem.Identifier.toolbarItemDatabase,
                NSToolbarItem.Identifier.flexibleSpace,
                NSToolbarItem.Identifier.toolbarItemObjectOrder,
                NSToolbarItem.Identifier.toolbarItemZoom,
                NSToolbarItem.Identifier.flexibleSpace,
                NSToolbarItem.Identifier.toolbarItemPrint,
                NSToolbarItem.Identifier.flexibleSpace,
                NSToolbarItem.Identifier.toolbarItemExit

            ]
        }
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
    {
        return [
            NSToolbarItem.Identifier.toolbarItemToggleTitlebarAccessory,
            NSToolbarItem.Identifier.toolbarItemNew,
            NSToolbarItem.Identifier.toolbarItemOpen,
            NSToolbarItem.Identifier.toolbarItemSymbol,
            NSToolbarItem.Identifier.toolbarItemClipArt,
            NSToolbarItem.Identifier.toolbarItemSave,
            NSToolbarItem.Identifier.toolbarPickerItem,
            NSToolbarItem.Identifier.toolbarShareButtonItem,
            NSToolbarItem.Identifier.toolbarSearchItem,
            NSToolbarItem.Identifier.toolbarItemTextBox,
            NSToolbarItem.Identifier.toolbarItemFrame,
            NSToolbarItem.Identifier.toolbarItemImage,
            NSToolbarItem.Identifier.toolbarItemShape,
            NSToolbarItem.Identifier.toolbarItemLine,
            NSToolbarItem.Identifier.toolbarItemBarcode,
            NSToolbarItem.Identifier.toolbarItemDatabase,
            NSToolbarItem.Identifier.toolbarItemObjectOrder,
            NSToolbarItem.Identifier.toolbarItemZoom,
            NSToolbarItem.Identifier.toolbarItemPrint,
            NSToolbarItem.Identifier.toolbarItemExit,
            NSToolbarItem.Identifier.space,
            NSToolbarItem.Identifier.flexibleSpace]
    }
    
    func toolbarWillAddItem(_ notification: Notification)
    {
    }
    
    func toolbarDidRemoveItem(_ notification: Notification)
    {
    }
    
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
    {
        return []
    }
}

extension WindowController
{
    private func configureTitlebarAccessoryView()
    {
        if  let titlebarController = self.storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier.customTitlebarAccessoryViewController) as? CustomTitlebarAccessoryViewController {
            titlebarController.layoutAttribute = .bottom
            titlebarController.fullScreenMinHeight = titlebarController.view.bounds.height
            self.window?.addTitlebarAccessoryViewController(titlebarController)
            self.titlebarAccessoryViewController = titlebarController
            self.titlebarAccessoryViewController?.isHidden = self.titlebarAccessoryViewIsHidden
        }
    }
    
    @IBAction func toggleTitlebarAccessory(_ sender: Any)
    {
        self.titlebarAccessoryViewIsHidden.toggle()
        self.titlebarAccessoryViewController?.isHidden = self.titlebarAccessoryViewIsHidden
        
        if  self.titlebarAccessoryViewIsHidden {
            self.titlebarAccessoryViewControllerToggleButton?.label = "Show"
            self.titlebarAccessoryViewControllerToggleButton?.toolTip = "Shows additional accessories"
            if  #available(macOS 11.0, *) {
                self.titlebarAccessoryViewControllerToggleButton?.image = NSImage(systemSymbolName: "menubar.arrow.up.rectangle", accessibilityDescription: "")
            } else {
                self.titlebarAccessoryViewControllerToggleButton?.image = NSImage(named: NSImage.touchBarGoUpTemplateName)
            }
        } else {
            self.titlebarAccessoryViewControllerToggleButton?.label = "Hide"
            self.titlebarAccessoryViewControllerToggleButton?.toolTip = "Hides additional accessories"
            if  #available(macOS 11.0, *) {
                self.titlebarAccessoryViewControllerToggleButton?.image = NSImage(systemSymbolName: "menubar.arrow.down.rectangle", accessibilityDescription: "")
            } else {
                self.titlebarAccessoryViewControllerToggleButton?.image = NSImage(named: NSImage.touchBarGoDownTemplateName)
            }
        }
    }
}


extension WindowController: NSSharingServicePickerToolbarItemDelegate
{
    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        let sharableItems = [URL(string: "https://www.ovidiucarstea.com/")!]
        return sharableItems
    }
}


extension WindowController: NSSearchFieldDelegate
{
    func searchFieldDidStartSearching(_ sender: NSSearchField) {
        print("Search field did start receiving input")
    }
    
    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        print("Search field did end receiving input")
        sender.resignFirstResponder()
    }
}
