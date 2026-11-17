import Cocoa

private final class ArtworkGridView: NSView {
    override var isFlipped: Bool { true }
    var buttons: [NSButton] = [] {
        didSet {
            oldValue.forEach { $0.removeFromSuperview() }
            buttons.forEach { addSubview($0) }
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        let spacing: CGFloat = 4
        let columns = 4
        let itemHeight: CGFloat = 62
        let itemWidth = max(1, (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        for (index, button) in buttons.enumerated() {
            let column = index % columns
            let row = index / columns
            button.frame = NSRect(x: CGFloat(column) * (itemWidth + spacing),
                                  y: CGFloat(row) * (itemHeight + spacing),
                                  width: itemWidth, height: itemHeight)
        }
    }
}

final class ArtworkPickerViewController: NSViewController {
    enum Kind { case symbol, clipArt }

    var onSelect: ((NSImage) -> Void)?
    private let kind: Kind
    private let category = NSPopUpButton()
    private let grid = ArtworkGridView()
    private let scroll = NSScrollView()

    private let symbolCategories: [(String, [String])] = [
        ("PT Dingbats 1", ["hand.point.right.fill", "scissors", "pencil", "envelope.fill", "phone.fill", "printer.fill", "key.fill", "lock.fill", "bell.fill", "flag.fill", "star.fill", "heart.fill"]),
        ("PT Dingbats 2", ["arrow.left", "arrow.right", "arrow.up", "arrow.down", "checkmark", "xmark", "plus", "minus", "questionmark", "exclamationmark", "circle", "square"]),
        ("PT Dingbats 3", ["house.fill", "building.2.fill", "car.fill", "airplane", "tram.fill", "bicycle", "figure.walk", "tree.fill", "leaf.fill", "flame.fill", "drop.fill", "sun.max.fill"]),
        ("PT Dingbats 4", ["camera.fill", "music.note", "film.fill", "mic.fill", "speaker.wave.2.fill", "headphones", "tv.fill", "gamecontroller.fill", "book.fill", "newspaper.fill", "calendar", "clock.fill"]),
        ("PT Symbol 1", ["circle.fill", "square.fill", "triangle.fill", "diamond.fill", "hexagon.fill", "octagon.fill", "seal.fill", "burst.fill", "asterisk", "infinity", "equal", "number"]),
        ("PT Symbol 2", ["person.fill", "person.2.fill", "figure.child", "pawprint.fill", "bird.fill", "fish.fill", "tortoise.fill", "ant.fill", "hare.fill", "ladybug.fill", "cat.fill", "dog.fill"]),
        ("Symbol", ["info.circle", "questionmark.circle", "exclamationmark.triangle", "checkmark.circle", "xmark.circle", "plus.circle", "minus.circle", "play.fill", "pause.fill", "stop.fill", "record.circle", "power"]),
        ("Webdings", ["globe", "network", "wifi", "antenna.radiowaves.left.and.right", "link", "paperclip", "at", "magnifyingglass", "cart.fill", "creditcard.fill", "shippingbox.fill", "barcode"]),
        ("Wingdings", ["hand.thumbsup.fill", "hand.thumbsdown.fill", "hand.raised.fill", "hand.wave.fill", "eyes", "mouth.fill", "face.smiling", "bolt.fill", "umbrella.fill", "gift.fill", "graduationcap.fill", "crown.fill"]),
        ("Wingdings 2", ["arrowshape.left.fill", "arrowshape.right.fill", "arrowshape.up.fill", "arrowshape.down.fill", "return", "delete.left.fill", "eject.fill", "forward.fill", "backward.fill", "repeat", "shuffle", "scope"]),
        ("Wingdings 3", ["doc.fill", "folder.fill", "tray.fill", "externaldrive.fill", "archivebox.fill", "clipboard.fill", "list.bullet", "tablecells.fill", "chart.bar.fill", "chart.pie.fill", "map.fill", "mappin"])
    ]

    private let clipCategories: [(String, [String])] = [
        ("DP_Emoji", ["face.smiling", "face.dashed", "heart.fill", "hand.thumbsup.fill", "hand.wave.fill", "eyes", "mouth.fill", "star.fill", "sparkles", "balloon.fill", "gift.fill", "party.popper.fill"]),
        ("DP_Music / Electronics", ["music.note", "guitars.fill", "pianokeys", "hifispeaker.fill", "headphones", "mic.fill", "radio.fill", "tv.fill", "desktopcomputer", "laptopcomputer", "iphone", "camera.fill"]),
        ("DP_Closets / Storage", ["cabinet.fill", "archivebox.fill", "shippingbox.fill", "tray.full.fill", "folder.fill", "books.vertical.fill", "hanger", "basket.fill", "bag.fill", "suitcase.fill", "lock.fill", "key.fill"]),
        ("DP_Vehicle / Travel", ["car.fill", "bus.fill", "tram.fill", "airplane", "ferry.fill", "bicycle", "scooter", "fuelpump.fill", "map.fill", "mappin", "suitcase.rolling.fill", "tent.fill"]),
        ("DP_Home", ["house.fill", "bed.double.fill", "sofa.fill", "chair.lounge.fill", "lamp.table.fill", "door.left.hand.closed", "shower.fill", "bathtub.fill", "washer.fill", "refrigerator.fill", "oven.fill", "lightbulb.fill"]),
        ("DP_Sports / Games", ["american.football.fill", "basketball.fill", "baseball.fill", "soccerball", "tennis.racket", "hockey.puck.fill", "figure.run", "figure.skiing.downhill", "gamecontroller.fill", "dice.fill", "trophy.fill", "medal.fill"]),
        ("DP_Animals", ["pawprint.fill", "dog.fill", "cat.fill", "bird.fill", "fish.fill", "tortoise.fill", "hare.fill", "ant.fill", "ladybug.fill", "lizard.fill", "allergens.fill", "fossil.shell.fill"]),
        ("DP_Baby / Kids", ["figure.child", "teddybear.fill", "balloon.fill", "birthday.cake.fill", "puzzlepiece.fill", "book.fill", "paintpalette.fill", "backpack.fill", "graduationcap.fill", "gamecontroller.fill", "bicycle", "star.fill"]),
        ("DP_Seasons", ["sun.max.fill", "cloud.rain.fill", "snowflake", "leaf.fill", "tree.fill", "flame.fill", "drop.fill", "wind", "thermometer.sun.fill", "thermometer.snowflake", "umbrella.fill", "moon.stars.fill"]),
        ("DP_Events / Special Occasions", ["gift.fill", "birthday.cake.fill", "party.popper.fill", "balloon.2.fill", "heart.fill", "crown.fill", "graduationcap.fill", "fireworks", "sparkles", "bell.fill", "camera.fill", "calendar"]),
        ("DP_Decorative / Craft", ["scissors", "paintbrush.fill", "paintpalette.fill", "pencil", "scribble", "seal.fill", "rosette", "ribbon", "wand.and.stars", "camera.macro", "leaf.fill", "flower"]),
        ("DP_Garden", ["tree.fill", "leaf.fill", "camera.macro", "flower", "wateringcan.fill", "shovel.fill", "sun.max.fill", "drop.fill", "ladybug.fill", "bird.fill", "house.fill", "basket.fill"]),
        ("DP_Family", ["person.fill", "person.2.fill", "person.3.fill", "figure.child", "figure.2.and.child.holdinghands", "house.fill", "heart.fill", "pawprint.fill", "car.fill", "fork.knife", "birthday.cake.fill", "camera.fill"]),
        ("DP_School", ["graduationcap.fill", "book.fill", "books.vertical.fill", "pencil", "backpack.fill", "ruler.fill", "scissors", "paintpalette.fill", "globe", "function", "calendar", "bell.fill"]),
        ("DP_Office", ["briefcase.fill", "printer.fill", "desktopcomputer", "keyboard.fill", "phone.fill", "envelope.fill", "paperclip", "folder.fill", "doc.fill", "calendar", "clock.fill", "chart.bar.fill"]),
        ("DP_Astrology", ["sun.max.fill", "moon.fill", "star.fill", "sparkles", "globe.americas.fill", "circle.hexagongrid.fill", "scope", "wand.and.stars", "cloud.fill", "bolt.fill", "flame.fill", "infinity"]),
        ("DP_Foods / Beverages", ["fork.knife", "cup.and.saucer.fill", "mug.fill", "takeoutbag.and.cup.and.straw.fill", "wineglass.fill", "birthday.cake.fill", "carrot.fill", "fish.fill", "basket.fill", "refrigerator.fill", "oven.fill", "flame.fill"]),
        ("DP_Kitchen", ["fork.knife", "refrigerator.fill", "oven.fill", "microwave.fill", "dishwasher.fill", "frying.pan.fill", "cup.and.saucer.fill", "mug.fill", "takeoutbag.and.cup.and.straw.fill", "basket.fill", "flame.fill", "drop.fill"]),
        ("DP_Shapes / Arrows", ["circle.fill", "square.fill", "triangle.fill", "diamond.fill", "hexagon.fill", "arrow.left", "arrow.right", "arrow.up", "arrow.down", "arrow.turn.up.right", "arrow.uturn.left", "arrow.up.and.down"]),
        ("DP_Signs", ["exclamationmark.triangle.fill", "info.circle.fill", "questionmark.circle.fill", "checkmark.circle.fill", "xmark.circle.fill", "nosign", "stop.circle.fill", "parkingsign.circle.fill", "figure.walk", "wheelchair", "arrow.left.circle.fill", "arrow.right.circle.fill"])
    ]

    init(kind: Kind) { self.kind = kind; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 292, height: 470))
        let label = NSTextField(labelWithString: "Category")
        label.font = .boldSystemFont(ofSize: 13)
        let header = NSStackView(views: [label, category])
        header.orientation = .horizontal; header.alignment = .centerY; header.spacing = 8
        category.target = self; category.action = #selector(categoryChanged(_:))
        category.addItems(withTitles: categories.map(\.0))
        category.selectItem(at: 0)
        scroll.documentView = grid
        grid.autoresizingMask = [.width]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.scrollerStyle = .legacy
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        grid.wantsLayer = true
        grid.layer?.backgroundColor = NSColor.white.cgColor
        [header, scroll].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 10), header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            category.widthAnchor.constraint(greaterThanOrEqualToConstant: 185),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        view.layoutSubtreeIfNeeded()
        rebuildGrid()
    }

    private var categories: [(String, [String])] {
        let source = kind == .symbol ? symbolCategories : clipCategories
        var seen = Set<String>()
        let all = source.flatMap(\.1).filter { seen.insert($0).inserted }
        return [("All", all)] + source
    }
    @objc private func categoryChanged(_ sender: Any) {
        let selected = max(0, category.indexOfSelectedItem)
        category.menu?.items.enumerated().forEach { index, item in
            item.state = index == selected ? .on : .off
        }
        rebuildGrid()
    }

    private func rebuildGrid() {
        let names = categories[max(0, category.indexOfSelectedItem)].1
        grid.buttons = names.indices.map { index in
            let button = NSButton(image: artwork(named: names[index]), target: self, action: #selector(choseArtwork(_:)))
            button.bezelStyle = .regularSquare
            button.isBordered = false
            button.tag = index
            button.contentTintColor = .black
            button.toolTip = names[index]
            button.imageScaling = .scaleProportionallyDown
            return button
        }
        let viewport = scroll.contentSize
        let rowCount = (names.count + 3) / 4
        let contentHeight = CGFloat(rowCount) * 62 + CGFloat(max(0, rowCount - 1)) * 4
        grid.frame = NSRect(x: 0, y: 0,
                            width: viewport.width,
                            height: max(viewport.height, contentHeight))
        grid.layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func artwork(named name: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 42, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: name)?.withSymbolConfiguration(configuration) ?? NSImage(size: NSSize(width: 42, height: 42))
    }

    @objc private func choseArtwork(_ sender: NSButton) {
        let names = categories[max(0, category.indexOfSelectedItem)].1
        guard names.indices.contains(sender.tag) else { return }
        onSelect?(artwork(named: names[sender.tag]))
    }
}
