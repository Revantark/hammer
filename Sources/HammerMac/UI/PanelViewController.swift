import AppKit
import HammerCore

public enum PanelKeyCommand: Equatable, Sendable {
    case up, down, enter, escape, openSettings
    /// Clipboard: next entry. Launcher: fills in the selected "/command ".
    case tab
    /// Space in a checklist: ticks or unticks the selected item.
    case toggle

    /// Maps key equivalents that reach the panel (⌘,).
    public static func from(_ event: NSEvent) -> PanelKeyCommand? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "," { return .openSettings }
        return nil
    }
}

/// Supplies clipboard images: cheap list thumbnails and an async-decoded preview.
@MainActor public protocol ThumbnailSource: AnyObject {
    func listThumbnail(for id: UUID) -> CGImage?
    /// The big preview if it can be had in a few ms (saved preview file); nil means use `preview(for:)`.
    func quickPreview(for id: UUID) -> CGImage?
    func preview(for id: UUID) async -> CGImage?
    func clear()
}

enum PanelRow {
    case header(String)
    case app(LauncherResult)
    case clip(ClipEntry)
    /// A command's screens: a line of context or detail, checklist items (index into `Checklist.items`), a result's title.
    case note(String)
    case check(Int)
    case report(CommandReport)
}

/// What the panel shows once a command has locked onto its target.
enum CommandScreen {
    /// Review before acting (uninstall). Esc goes back to the list.
    case checklist(Checklist)
    case working(String)
    /// What happened. Enter opens the plain launcher, Esc closes.
    case report(CommandReport)
}

/// The Frost panel's content: search field, result list, footer. Driven by `PanelModel`.
@MainActor public final class PanelViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let model: PanelModel
    private let launcher: LauncherController
    let clipboard: ClipboardController
    let pasteSender: PasteSending
    private let icons: IconProvider
    let thumbnails: ThumbnailSource
    let clock: HammerClock
    private let settings: () -> Settings

    public var onOpenSettings: (() -> Void)?
    public var onVisibilityChanged: ((Bool) -> Void)?
    public var onSizeChanged: ((NSSize) -> Void)?

    public let searchField = NSTextField()
    private let searchIcon = NSImageView()
    private let effect = NSVisualEffectView()
    private let border = PassThroughView()
    private let topDivider = NSView()
    private let footer = NSView()
    private let footerLeft = makeLabel(Theme.font(12), Theme.secondaryText)
    private let footerRight = KeyHintsView()
    let scrollView = NSScrollView()
    let tableView = NSTableView()

    private var rows: [PanelRow] = []
    private var itemRows: [Int] = []          // item index → row index
    private var results: [LauncherResult] = []
    private var clips: [ClipEntry] = []
    let preview = ClipboardPreviewView()
    private let previewDivider = NSView()
    public internal(set) var previewTask: Task<Void, Never>?
    /// Loads icons for every launcher result in display order, so scrolling never waits on IconServices.
    private(set) var iconPrefetch: Task<Void, Never>?
    private var lastVisible = false
    private var lastMode: PanelMode?
    private var lastQuery: String?

    /// Set once a command row is chosen: the search field is locked to `lockTitle` and keys drive the screen.
    private(set) var screen: CommandScreen?
    private var lockTitle = ""
    /// Bumped whenever the screen is left, so late results from abandoned work are dropped.
    private var screenGeneration = 0
    private(set) var checklistSizes: Task<Void, Never>?
    /// The command's work; keeps running if the panel closes meanwhile.
    private(set) var commandTask: Task<Void, Never>?
    /// True while work that may raise a password prompt runs: losing focus mustn't close the panel.
    public private(set) var holdsPanelOpen = false
    /// Asks for keyboard focus back after work that let another window (a password prompt) take it.
    public var onNeedsFocus: (() -> Void)?

    var checklist: Checklist? {
        if case .checklist(let list) = screen { return list }
        return nil
    }


    public init(model: PanelModel, launcher: LauncherController, clipboard: ClipboardController, pasteSender: PasteSending,
                icons: IconProvider, thumbnails: ThumbnailSource, clock: HammerClock, settings: @escaping () -> Settings) {
        self.model = model
        self.launcher = launcher
        self.clipboard = clipboard
        self.pasteSender = pasteSender
        self.icons = icons
        self.thumbnails = thumbnails
        self.clock = clock
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        model.onChange = { [weak self] in self?.render() }
        clipboard.onChange = { [weak self] in self?.clipboardChanged() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Test/inspection surface

    var displayedRowCount: Int { itemRows.count }
    var displayedHeaders: [String] { rows.compactMap { if case .header(let t) = $0 { return t } else { return nil } } }
    var footerLeftText: String { footerLeft.stringValue }
    var footerRightText: String { footerRight.text }
    var selectedClipID: UUID? { clips.indices.contains(model.selectedIndex) ? clips[model.selectedIndex].id : nil }

    public var preferredPanelSize: NSSize {
        if model.mode == .clipboard {
            return NSSize(width: Theme.clipboardWidth,
                          height: Theme.searchHeight + 1 + Theme.clipboardBodyHeight + Theme.footerHeight)
        }
        let listHeight: CGFloat
        if rows.isEmpty {
            listHeight = Theme.rowHeight
        } else {
            var h: CGFloat = 0
            var items = 0
            for row in rows {
                if case .header = row { h += Theme.headerHeight; continue }
                if items == Theme.maxVisibleRows { break }
                h += Theme.rowHeight
                items += 1
            }
            listHeight = h + Theme.listInset
        }
        return NSSize(width: Theme.launcherWidth, height: Theme.searchHeight + 1 + listHeight + Theme.footerHeight)
    }

    // MARK: View

    public override func loadView() {
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.maskImage = Self.roundedMask(radius: Theme.cornerRadius)
        effect.frame = NSRect(origin: .zero, size: preferredPanelSize)

        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        searchIcon.contentTintColor = Theme.secondaryText

        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = Theme.font(Theme.searchFontSize)
        searchField.textColor = Theme.primaryText
        searchField.cell?.usesSingleLineMode = true
        searchField.cell?.lineBreakMode = .byClipping
        searchField.delegate = self

        topDivider.wantsLayer = true
        topDivider.layer?.backgroundColor = Theme.divider.cgColor

        let column = NSTableColumn(identifier: .init("main"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.focusRingType = .none
        tableView.style = .plain
        tableView.refusesFirstResponder = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.doubleAction = #selector(rowDoubleClicked)
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        footer.wantsLayer = true
        footer.layer?.backgroundColor = Theme.footerFill.cgColor
        let footerLine = NSView(frame: NSRect(x: 0, y: Theme.footerHeight - 1, width: 4000, height: 1))
        footerLine.wantsLayer = true
        footerLine.layer?.backgroundColor = Theme.divider.cgColor
        footer.addSubview(footerLine)
        footer.addSubview(footerLeft)
        footer.addSubview(footerRight)

        border.wantsLayer = true
        border.layer?.borderWidth = 1
        border.layer?.borderColor = Theme.border.cgColor
        border.layer?.cornerRadius = Theme.cornerRadius

        [searchIcon, searchField, topDivider, scrollView, footer].forEach(effect.addSubview)
        addBodySubviews(to: effect)
        effect.addSubview(border)
        view = effect
    }

    public override func viewDidLayout() {
        super.viewDidLayout()
        let b = view.bounds
        let searchY = b.height - Theme.searchHeight
        searchIcon.frame = NSRect(x: 18, y: searchY + (Theme.searchHeight - 20) / 2, width: 20, height: 20)
        let fieldHeight = searchField.intrinsicContentSize.height
        searchField.frame = NSRect(x: 46, y: searchY + (Theme.searchHeight - fieldHeight) / 2, width: b.width - 64, height: fieldHeight)
        topDivider.frame = NSRect(x: 0, y: searchY - 1, width: b.width, height: 1)
        footer.frame = NSRect(x: 0, y: 0, width: b.width, height: Theme.footerHeight)
        let lh = footerLeft.intrinsicContentSize.height
        footerLeft.frame = NSRect(x: 14, y: (Theme.footerHeight - lh) / 2, width: 260, height: lh)
        let rs = footerRight.fittingSize
        footerRight.frame = NSRect(x: b.width - 14 - rs.width, y: (Theme.footerHeight - rs.height) / 2, width: rs.width, height: rs.height)
        let body = NSRect(x: 0, y: Theme.footerHeight, width: b.width, height: max(0, searchY - 1 - Theme.footerHeight))
        layoutBody(body)
        border.frame = b
    }

    func layoutBody(_ body: NSRect) {
        let clipMode = model.mode == .clipboard
        preview.isHidden = !clipMode
        previewDivider.isHidden = !clipMode
        var listFrame = body
        if clipMode {
            listFrame.size.width = floor(body.width * 0.44)
            previewDivider.frame = NSRect(x: listFrame.maxX, y: body.minY, width: 1, height: body.height)
            preview.frame = NSRect(x: listFrame.maxX + 1, y: body.minY, width: body.width - listFrame.width - 1, height: body.height)
        }
        scrollView.frame = listFrame.insetBy(dx: 0, dy: Theme.listInset / 2)
        tableView.tableColumns.first?.width = scrollView.contentSize.width
    }

    func addBodySubviews(to container: NSView) {
        previewDivider.wantsLayer = true
        previewDivider.layer?.backgroundColor = Theme.divider.cgColor
        container.addSubview(previewDivider)
        container.addSubview(preview)
    }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: Rendering

    func render() {
        if model.isVisible != lastVisible {
            lastVisible = model.isVisible
            if model.isVisible { reloadItems() } else { releaseResources() }
            onVisibilityChanged?(model.isVisible)
            return
        }
        guard model.isVisible else { return }
        if model.mode != lastMode || model.query != lastQuery {
            reloadItems()
        } else {
            updateSelection()
        }
    }

    func reloadItems() {
        _ = view
        lastMode = model.mode
        lastQuery = model.query
        if screen == nil, searchField.stringValue != model.query {
            searchField.stringValue = model.query
            // Filled in by Tab/Enter on a command: keep typing after it.
            searchField.currentEditor()?.selectedRange = NSRange(location: (model.query as NSString).length, length: 0)
        }
        searchField.placeholderAttributedString = NSAttributedString(
            string: model.mode == .launcher ? "Search apps, or / for commands…" : "Search clipboard…",
            attributes: [.foregroundColor: Theme.secondaryText, .font: Theme.font(Theme.searchFontSize)])
        buildRows()
        tableView.reloadData()
        prefetchIcons()
        updateSelection()
        updateFooter()
        onSizeChanged?(preferredPanelSize)
        view.needsLayout = true
    }

    func buildRows() {
        rows = []
        itemRows = []
        results = []
        clips = []
        if model.mode == .launcher, let screen {
            switch screen {
            case .checklist(let list):
                rows.append(.header(list.title))
                if let note = list.note { rows.append(.note(note)) }
                for index in list.items.indices {
                    itemRows.append(rows.count)
                    rows.append(.check(index))
                }
            case .working(let title):
                rows.append(.note(title))
            case .report(let report):
                rows.append(.report(report))
                rows += report.lines.map { .note($0) }
            }
            return
        }
        if model.mode == .clipboard {
            let matches = clipboard.search(model.query)
            for section in ClipHistory.sections(matches, now: clock.now(), calendar: .current, locale: .current) {
                rows.append(.header(section.title))
                for entry in section.entries {
                    itemRows.append(rows.count)
                    rows.append(.clip(entry))
                    clips.append(entry)
                }
            }
            return
        }
        results = launcher.results(for: model.query)
        var sections: [String] = []
        var bySection: [String: [LauncherResult]] = [:]
        for r in results {
            if bySection[r.section] == nil { sections.append(r.section) }
            bySection[r.section, default: []].append(r)
        }
        results = []
        for section in sections {
            rows.append(.header(section))
            for r in bySection[section] ?? [] {
                itemRows.append(rows.count)
                rows.append(.app(r))
                results.append(r)
            }
        }
    }

    /// Icons loaded ahead on open (about three screens); rows further down load as they scroll in.
    static let iconPrefetchLimit = 24

    func prefetchIcons() {
        iconPrefetch?.cancel()
        iconPrefetch = nil
        let paths = results.prefix(Self.iconPrefetchLimit).compactMap { result -> String? in
            guard let path = Self.iconPath(for: result), icons.cachedIcon(forPath: path) == nil else { return nil }
            return path
        }
        guard !paths.isEmpty else { return }
        iconPrefetch = Task { [icons] in
            for path in paths {
                if Task.isCancelled { return }
                _ = await icons.icon(forPath: path)
            }
        }
    }

    /// Drops rows, preview and decoded images while hidden so idle memory falls back.
    func releaseResources() {
        rows = []
        itemRows = []
        results = []
        clips = []
        leaveScreen()
        lastMode = nil
        lastQuery = nil
        tableView.reloadData()
        previewTask?.cancel()
        previewTask = nil
        iconPrefetch?.cancel()
        iconPrefetch = nil
        preview.clear()
        clipboard.releaseSearch()
        thumbnails.clear()
    }

    func updateSelection() {
        let selectedRow = itemRows.indices.contains(model.selectedIndex) ? itemRows[model.selectedIndex] : -1
        tableView.enumerateAvailableRowViews { rowView, row in
            (rowView as? SelectionRowView)?.isItemSelected = row == selectedRow
        }
        if selectedRow >= 0 { tableView.scrollRowToVisible(selectedRow) }
        selectionChanged()
        if model.mode == .launcher { updateFooter() }   // "Open" vs "Copy" follows the selected row
    }

    func selectionChanged() {
        previewTask?.cancel()
        previewTask = nil
        guard model.mode == .clipboard, let id = selectedClipID, let entry = clips.first(where: { $0.id == id }) else {
            preview.clear()
            return
        }
        switch entry.kind {
        case .text:
            preview.show(entry: entry, payload: clipboard.payload(id: id), image: nil, now: clock.now())
        case .image:
            if let image = thumbnails.quickPreview(for: id) {
                preview.show(entry: entry, payload: nil, image: image, now: clock.now())
                return
            }
            preview.show(entry: entry, payload: nil, image: nil, now: clock.now())
            previewTask = Task { [weak self, thumbnails] in
                let image = await thumbnails.preview(for: id)
                guard let self, !Task.isCancelled, self.model.isVisible, self.selectedClipID == id else { return }
                self.preview.setImage(image)
            }
        }
    }

    func updateFooter() {
        let s = settings()
        if model.mode == .clipboard {
            let n = clipboard.history.entries.count
            footerLeft.stringValue = "Clipboard · \(n) \(n == 1 ? "item" : "items")"
            footerRight.setHints([("Paste", "↵"), ("Launcher", s.launcherHotkey.displayString)])
        } else if let screen {
            footerLeft.stringValue = ""
            switch screen {
            case .checklist(let list):
                if !list.items.isEmpty {
                    let bytes = list.checkedBytes
                    footerLeft.stringValue = "\(list.checkedItems.count) selected" + (bytes > 0 ? " · " + Self.size(bytes) : "")
                }
                footerRight.setHints(list.items.isEmpty ? [(list.confirmLabel, "↵"), ("Back", "esc")]
                                                        : [(list.confirmLabel, "↵"), ("Toggle", "Space"), ("Back", "esc")])
            case .working:
                footerRight.setHints([("Close", "esc")])
            case .report:
                footerRight.setHints([("Open Launcher", "↵"), ("Close", "esc")])
            }
        } else {
            footerLeft.stringValue = "Hammer"
            let enterLabel = results.indices.contains(model.selectedIndex) ? Self.enterLabel(for: results[model.selectedIndex]) : "Open"
            footerRight.setHints([(enterLabel, "↵"), ("Clipboard", s.clipboardHotkey.displayString)])
        }
    }

    static func enterLabel(for result: LauncherResult) -> String {
        switch result.action {
        case .openApp: "Open"
        case .copyText: "Copy"
        case .completeCommand: "Select"
        case .runCommand(_, .none): "Run"
        case .runCommand: result.typeLabel
        }
    }

    /// The file whose icon a launcher row shows; nil for glyph rows (calculator, commands).
    static func iconPath(for result: LauncherResult) -> String? {
        switch result.action {
        case .openApp(let path): path
        case .runCommand(_, .option(let option)): option.iconPath
        case .copyText, .completeCommand, .runCommand: nil
        }
    }

    /// A copy arrived while the panel is open: refresh the list, keep the selection on the same entry.
    func clipboardChanged() {
        guard model.isVisible, model.mode == .clipboard else { return }
        let oldIDs = clips.map(\.id.uuidString)
        buildRows()
        tableView.reloadData()
        updateFooter()
        model.itemsChanged(newIDs: clips.map(\.id.uuidString), oldIDs: oldIDs)
    }

    // MARK: Input

    /// Keys the panel sees before the search field. While a command screen is up, every key drives the screen and
    /// nothing reaches the (locked) field; ⌘ shortcuts still pass through (⌘, opens Settings).
    public func handleKeyDown(_ event: NSEvent) -> Bool {
        guard screen != nil, model.isVisible, !event.modifierFlags.contains(.command) else { return false }
        switch event.keyCode {
        case 36, 76: handleKey(.enter)      // Return, keypad Enter
        case 53: handleKey(.escape)
        case 125: handleKey(.down)
        case 126: handleKey(.up)
        case 49: handleKey(.toggle)         // Space
        default: break                      // typing does nothing while locked
        }
        return true
    }

    public func handleKey(_ command: PanelKeyCommand) {
        if let screen, model.mode == .launcher {
            switch (screen, command) {
            case (_, .openSettings): onOpenSettings?()
            case (.checklist, .up), (.checklist, .down): model.moveSelection(by: command == .up ? -1 : 1, count: itemRows.count)
            case (.checklist, .escape): leaveScreen(); reloadItems()
            case (.checklist(let list), .enter): confirm(list)
            case (.checklist(let list), .toggle): list.toggle(at: model.selectedIndex)
            case (.report, .enter): openLauncher()
            case (.working, .escape), (.report, .escape): model.hide()
            default: break
            }
            return
        }
        switch command {
        case .up: model.moveSelection(by: -1, count: itemRows.count)
        case .down: model.moveSelection(by: 1, count: itemRows.count)
        case .escape: model.hide()
        case .openSettings: onOpenSettings?()
        case .enter: activateSelection()
        case .toggle: break
        case .tab:
            if model.mode == .clipboard {
                handleKey(.down)
            } else if results.indices.contains(model.selectedIndex), case .completeCommand(let name) = results[model.selectedIndex].action {
                model.setQuery("/\(name) ")
            }
        }
    }

    func activateSelection() {
        if model.mode == .clipboard {
            guard let id = selectedClipID else { return }
            _ = clipboard.paste(id: id, sender: pasteSender, beforePaste: { model.hide() })
            return
        }
        guard results.indices.contains(model.selectedIndex) else { return }
        let result = results[model.selectedIndex]
        switch result.action {
        case .completeCommand(let name):
            model.setQuery("/\(name) ")
        case .runCommand(let name, let argument):
            let title = argument == .none ? result.title : "\(result.typeLabel) \(result.title)"   // "Uninstall Zed"
            switch launcher.runCommand(name: name, argument: argument) {
            case .done, nil: model.hide()
            case .confirm(let list): showChecklist(list, lockTitle: title)
            case .working(let workingTitle, let keepsOpen, let work):
                lock(title)
                run(work, title: workingTitle, keepsPanelOpen: keepsOpen)
            }
        case .openApp, .copyText:
            model.hide()
            launcher.perform(result)
        }
    }

    public func controlTextDidChange(_ obj: Notification) {
        guard screen == nil else { return }
        model.setQuery(searchField.stringValue)
    }

    // MARK: Command screens

    private func lock(_ title: String) {
        lockTitle = title
        searchField.abortEditing()
        searchField.isEditable = false
        searchField.isSelectable = false
        searchField.textColor = Theme.secondaryText
        searchField.stringValue = title
    }

    private func setScreen(_ new: CommandScreen) {
        screen = new
        reloadItems()
        model.moveSelection(by: -model.selectedIndex, count: itemRows.count)
    }

    private func showChecklist(_ list: Checklist, lockTitle title: String) {
        lock(title)
        list.onChange = { [weak self, weak list] in
            guard let self, let list, self.checklist === list else { return }
            self.tableView.reloadData()
            self.updateSelection()
        }
        setScreen(.checklist(list))
        checklistSizes = Task { await list.loadSizes() }
    }

    private func confirm(_ list: Checklist) {
        guard list.items.isEmpty || !list.checkedItems.isEmpty else { return }
        run({ await list.confirm() ?? CommandReport(succeeded: false, title: "Nothing to do", lines: []) },
            title: list.workingTitle, keepsPanelOpen: true)
    }

    private func run(_ work: @escaping @MainActor () async -> CommandReport, title: String, keepsPanelOpen: Bool) {
        guard commandTask == nil else { return }
        checklistSizes?.cancel()
        checklistSizes = nil
        holdsPanelOpen = keepsPanelOpen
        setScreen(.working(title))
        let generation = screenGeneration
        commandTask = Task { [weak self] in
            let report = await work()
            guard let self else { return }
            self.commandTask = nil
            guard self.screenGeneration == generation, self.model.isVisible else { return }
            self.holdsPanelOpen = false
            self.setScreen(.report(report))
            if keepsPanelOpen { self.onNeedsFocus?() }
        }
    }

    /// Back to normal searching; the field shows the query again.
    private func leaveScreen() {
        guard screen != nil else { return }
        checklist?.onChange = nil
        screen = nil
        screenGeneration += 1
        holdsPanelOpen = false
        checklistSizes?.cancel()
        checklistSizes = nil
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.textColor = Theme.primaryText
        searchField.stringValue = model.query
        if let window = view.window, model.isVisible {
            window.makeFirstResponder(searchField)
            searchField.currentEditor()?.selectedRange = NSRange(location: (model.query as NSString).length, length: 0)
        }
    }

    /// The result screen's Enter: the plain launcher with every app.
    private func openLauncher() {
        model.setQuery("")
        leaveScreen()
        reloadItems()
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): handleKey(.up)
        case #selector(NSResponder.moveDown(_:)): handleKey(.down)
        case #selector(NSResponder.insertNewline(_:)): handleKey(.enter)
        case #selector(NSResponder.cancelOperation(_:)): handleKey(.escape)
        // Clipboard: Tab / ⇧Tab step through entries. Launcher: Tab completes a command; never moves focus off the search field.
        case #selector(NSResponder.insertTab(_:)): handleKey(.tab)
        case #selector(NSResponder.insertBacktab(_:)): if model.mode == .clipboard { handleKey(.up) }
        default: return false
        }
        return true
    }

    @objc private func rowClicked() {
        guard let item = itemRows.firstIndex(of: tableView.clickedRow) else { return }
        model.moveSelection(by: item - model.selectedIndex, count: itemRows.count)
        if case .checklist = screen { handleKey(.toggle) }   // a click ticks; only Enter confirms
    }

    @objc private func rowDoubleClicked() {
        guard screen == nil else { return }
        rowClicked()
        handleKey(.enter)
    }

    // MARK: Table

    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .header = rows[row] { return Theme.headerHeight }
        return rowHeight
    }

    var rowHeight: CGFloat { model.mode == .clipboard ? Theme.clipRowHeight : Theme.rowHeight }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = SelectionRowView()
        view.isItemSelected = itemRows.indices.contains(model.selectedIndex) && itemRows[model.selectedIndex] == row
        return view
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .note(let text):
            let cell = tableView.makeView(withIdentifier: .init("note"), owner: nil) as? ItemCellView ?? {
                let c = ItemCellView(); c.identifier = .init("note"); c.title.font = Theme.font(12); c.title.textColor = Theme.secondaryText; return c
            }()
            cell.iconSize = 18
            cell.iconPath = nil
            cell.iconView.image = Self.noteGlyph
            cell.title.stringValue = text
            cell.trailing.stringValue = ""
            cell.needsLayout = true
            return cell
        case .report(let report):
            let cell = tableView.makeView(withIdentifier: .init("report"), owner: nil) as? ItemCellView ?? {
                let c = ItemCellView(); c.identifier = .init("report"); c.title.font = Theme.font(15, .semibold); return c
            }()
            cell.iconSize = 22
            cell.iconPath = nil
            cell.iconView.image = report.succeeded ? Self.successGlyph : Self.failureGlyph
            cell.title.stringValue = report.title
            cell.trailing.stringValue = ""
            cell.needsLayout = true
            return cell
        case .check(let index):
            let cell = tableView.makeView(withIdentifier: .init("check"), owner: nil) as? ItemCellView ?? {
                let c = ItemCellView(); c.identifier = .init("check"); c.title.lineBreakMode = .byTruncatingMiddle; return c
            }()
            let item = checklist?.items[safe: index]
            cell.iconSize = 18
            cell.iconPath = nil
            cell.iconView.image = item?.isChecked == false ? Self.uncheckedGlyph : Self.checkedGlyph
            cell.title.stringValue = item?.title ?? ""
            cell.trailing.stringValue = item?.bytes.map(Self.size) ?? "…"
            cell.needsLayout = true
            return cell
        case .header(let title):
            let cell = tableView.makeView(withIdentifier: .init("header"), owner: nil) as? HeaderCellView ?? {
                let c = HeaderCellView(); c.identifier = .init("header"); return c
            }()
            cell.label.stringValue = title
            return cell
        case .app(let result):
            let cell = tableView.makeView(withIdentifier: .init("item"), owner: nil) as? ItemCellView ?? {
                let c = ItemCellView(); c.identifier = .init("item"); return c
            }()
            cell.title.stringValue = result.title
            cell.trailing.stringValue = result.typeLabel
            cell.iconSize = Theme.iconSize
            if let path = Self.iconPath(for: result) {
                cell.iconPath = path
                cell.iconView.image = icons.cachedIcon(forPath: path)
                if cell.iconView.image == nil {
                    Task { [weak cell, icons] in
                        let icon = await icons.icon(forPath: path)
                        if let cell, cell.iconPath == path { cell.iconView.image = icon }
                    }
                }
            } else {
                cell.iconPath = nil
                if case .copyText = result.action { cell.iconView.image = Self.calculatorGlyph } else { cell.iconView.image = Self.commandGlyph }
            }
            cell.needsLayout = true
            return cell
        case .clip(let entry):
            let cell = tableView.makeView(withIdentifier: .init("item"), owner: nil) as? ItemCellView ?? {
                let c = ItemCellView(); c.identifier = .init("item"); return c
            }()
            cell.iconSize = 18
            cell.iconPath = nil
            cell.trailing.stringValue = ""
            if entry.kind == .image {
                cell.title.stringValue = "Image (\(entry.pixelWidth ?? 0)×\(entry.pixelHeight ?? 0))"
                cell.iconView.image = thumbnails.listThumbnail(for: entry.id)
                    .map { NSImage(cgImage: $0, size: NSSize(width: 18, height: 18)) } ?? Self.textGlyph
            } else {
                cell.title.stringValue = (entry.snippet ?? "").split(whereSeparator: \.isNewline).first.map(String.init)?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                cell.iconView.image = Self.textGlyph
            }
            cell.needsLayout = true
            return cell
        }
    }

    public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    /// Small "T" tile for text entries.
    static let textGlyph = glyph("T", side: 18, fontSize: 10, radius: 4)
    /// "=" tile for calculator results, app-icon sized.
    static let calculatorGlyph = glyph("=", side: Theme.iconSize, fontSize: 17, radius: 7)
    static let checkedGlyph = symbol("checkmark.square.fill", tint: .white, .controlAccentColor)
    static let uncheckedGlyph = symbol("square", tint: Theme.secondaryText)
    static let noteGlyph = symbol("info.circle", tint: Theme.secondaryText)
    static let successGlyph = symbol("checkmark.circle.fill", size: 20, tint: .white, .systemGreen)
    static let failureGlyph = symbol("xmark.circle.fill", size: 20, tint: .white, .systemRed)

    /// `tint`: one color per symbol layer (checkmark, then box).
    private static func symbol(_ name: String, size: CGFloat = 14, tint: NSColor...) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular).applying(.init(paletteColors: tint))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
    }

    /// "/" tile for commands.
    static let commandGlyph = glyph("/", side: Theme.iconSize, fontSize: 17, radius: 7)

    private static func glyph(_ text: String, side: CGFloat, fontSize: CGFloat, radius: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor(white: 1, alpha: 0.08).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                                                        .foregroundColor: NSColor(white: 1, alpha: 0.6)]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2), withAttributes: attrs)
            return true
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
