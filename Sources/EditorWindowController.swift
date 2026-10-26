/*
 * Notepad für macOS – Editorfenster mit Statusleiste.
 * Entspricht dem Edit-Control, DIALOG_GoTo, DIALOG_EditTimeDate, DIALOG_EditWrap und
 * DIALOG_StatusBarUpdate* in ReactOS Notepad.
 * LICENSE: LGPL-2.1-or-later
 */

import AppKit

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    let textView: NotepadTextView
    private let scrollView = NSScrollView()
    private let menuStrip = MenuStripView()
    private let statusBar = StatusBarView()
    private var scrollBottomToStatusBar: NSLayoutConstraint!
    private var scrollBottomToWindow: NSLayoutConstraint!
    private var zoomPercent = 100

    private static var cascadePoint: NSPoint?

    private var textDocument: TextDocument? { document as? TextDocument }

    override var document: AnyObject? {
        didSet { updateStatusBar() }
    }

    init(text: String) {
        // TextKit 1 with non-contiguous layout stays fast for large files.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        textView = NotepadTextView(frame: .zero, textContainer: container)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 320, height: 200)
        super.init(window: window)
        window.delegate = self

        configureTextView()
        layOut(in: window)

        textView.string = text
        applyFont()
        applyWordWrap()
        applyStatusBarVisibility()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        window.initialFirstResponder = textView

        if let point = Self.cascadePoint {
            Self.cascadePoint = window.cascadeTopLeft(from: point)
        } else {
            window.center()
            Self.cascadePoint = window.cascadeTopLeft(from: NSPoint(x: window.frame.minX, y: window.frame.maxY))
        }

        NotificationCenter.default.addObserver(self, selector: #selector(preferencesDidChange(_:)),
                                               name: Preferences.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clipViewFrameDidChange(_:)),
                                               name: NSView.frameDidChangeNotification, object: scrollView.contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureTextView() {
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.usesFontPanel = false
        textView.allowsDocumentBackgroundColorChange = false
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        if #available(macOS 14.0, *) {
            textView.inlinePredictionType = .no
        }
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    private func layOut(in window: NSWindow) {
        let contentView = NSView()
        window.contentView = contentView

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.findBarPosition = .aboveContent
        scrollView.contentView.postsFrameChangedNotifications = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        menuStrip.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(menuStrip)
        contentView.addSubview(scrollView)
        contentView.addSubview(statusBar)

        scrollBottomToStatusBar = scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor)
        scrollBottomToWindow = scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        NSLayoutConstraint.activate([
            menuStrip.topAnchor.constraint(equalTo: contentView.topAnchor),
            menuStrip.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            menuStrip.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            menuStrip.heightAnchor.constraint(equalToConstant: 26),
            scrollView.topAnchor.constraint(equalTo: menuStrip.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),
        ])
        contentView.layoutSubtreeIfNeeded()
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
    }

    // MARK: - Appearance

    @objc private func preferencesDidChange(_ notification: Notification) {
        applyFont()
        applyWordWrap()
        applyStatusBarVisibility()
    }

    @objc private func clipViewFrameDidChange(_ notification: Notification) {
        textView.minSize = scrollView.contentSize
        textView.sizeToFit()
    }

    private func applyFont() {
        let base = Preferences.font
        let font = NSFont(descriptor: base.fontDescriptor, size: base.pointSize * CGFloat(zoomPercent) / 100) ?? base

        // Tab stops every 8 characters, like the Windows edit control.
        let style = NSMutableParagraphStyle()
        style.tabStops = []
        style.defaultTabInterval = 8 * (" " as NSString).size(withAttributes: [.font: font]).width

        textView.font = font
        textView.defaultParagraphStyle = style
        textView.typingAttributes = [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.textColor]
        if let storage = textView.textStorage {
            storage.addAttributes([.font: font, .paragraphStyle: style],
                                  range: NSRange(location: 0, length: storage.length))
        }
        updateStatusBar()
    }

    private func applyWordWrap() {
        guard let container = textView.textContainer else { return }
        let contentSize = scrollView.contentSize

        if Preferences.wordWrap {
            scrollView.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            container.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            container.widthTracksTextView = true
            textView.frame.size.width = contentSize.width
        } else {
            scrollView.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        textView.minSize = scrollView.contentSize
        textView.sizeToFit()
    }

    private func applyStatusBarVisibility() {
        let visible = Preferences.showStatusBar
        statusBar.isHidden = !visible
        scrollBottomToWindow.isActive = !visible
        scrollBottomToStatusBar.isActive = visible
        updateStatusBar()
    }

    func updateStatusBar() {
        guard Preferences.showStatusBar else { return }
        let position = LineScanner.position(of: textView.selectedRange().location, in: textView.string as NSString)
        statusBar.positionLabel.stringValue = "Zeile \(position.line), Spalte \(position.column)"
        statusBar.zoomLabel.stringValue = "\(zoomPercent) %"
        if let textDocument {
            statusBar.lineEndingLabel.stringValue = textDocument.lineEnding.displayName
            statusBar.encodingLabel.stringValue = textDocument.encoding.displayName
        }
    }

    // MARK: - Text

    func replaceText(_ text: String) {
        textView.string = text
        applyFont()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textDocument?.undoManager?.removeAllActions()
        updateStatusBar()
    }

    func appendLogTimestamp() {
        let end = (textView.string as NSString).length
        let stamp = "\n" + Self.timeDateString() + "\n"
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.insertText(stamp, replacementRange: NSRange(location: end, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    private static func timeDateString() -> String {
        let now = Date()
        let time = DateFormatter()
        time.timeStyle = .short
        time.dateStyle = .none
        let date = DateFormatter()
        date.timeStyle = .none
        date.dateStyle = .long
        return "\(time.string(from: now)) \(date.string(from: now))"
    }

    // MARK: - Menu actions

    @objc func insertTimeDate(_ sender: Any?) {
        textView.insertText(Self.timeDateString(), replacementRange: textView.selectedRange())
    }

    @objc func goToLine(_ sender: Any?) {
        guard let window else { return }
        let text = textView.string as NSString
        let lineCount = LineScanner.lineCount(in: text)
        let currentLine = LineScanner.position(of: textView.selectedRange().location, in: text).line

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = String(currentLine)

        let alert = NSAlert()
        alert.messageText = "Gehe zu Zeile"
        alert.informativeText = "Zeilennummer (1–\(lineCount)):"
        alert.accessoryView = field
        alert.addButton(withTitle: "Gehe zu")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let input = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard let line = Int(input), (1...lineCount).contains(line) else {
                DispatchQueue.main.async { self.showLineOutOfRange() }
                return
            }
            let offset = LineScanner.offset(ofLine: line, in: self.textView.string as NSString)
            self.textView.setSelectedRange(NSRange(location: offset, length: 0))
            self.textView.scrollRangeToVisible(self.textView.selectedRange())
            window.makeFirstResponder(self.textView)
        }
    }

    private func showLineOutOfRange() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Notepad – Gehe zu Zeile"
        alert.informativeText = "Die angegebene Zeilennummer liegt außerhalb des gültigen Bereichs."
        alert.beginSheetModal(for: window)
    }

    @objc func showFonts(_ sender: Any?) {
        window?.makeFirstResponder(textView)
        NSFontManager.shared.setSelectedFont(Preferences.font, isMultiple: false)
        NSFontManager.shared.orderFrontFontPanel(sender)
    }

    @objc func zoomIn(_ sender: Any?) { setZoom(zoomPercent + 10) }
    @objc func zoomOut(_ sender: Any?) { setZoom(zoomPercent - 10) }
    @objc func resetZoom(_ sender: Any?) { setZoom(100) }

    private func setZoom(_ percent: Int) {
        zoomPercent = min(500, max(10, percent))
        applyFont()
    }

    // MARK: - Delegates

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        document?.undoManager
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateStatusBar()
    }
}

/// Plain-text view whose font panel changes the shared Notepad font (unzoomed) for all windows.
final class NotepadTextView: NSTextView {
    override func changeFont(_ sender: Any?) {
        let manager = sender as? NSFontManager ?? NSFontManager.shared
        Preferences.font = manager.convert(Preferences.font)
    }

    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask {
        [.face, .size, .collection]
    }
}

/// Windows-style menu bar inside the window: Datei, Bearbeiten, Format, Ansicht, Hilfe.
final class MenuStripView: NSVisualEffectView {
    init() {
        super.init(frame: .zero)
        material = .titlebar
        blendingMode = .withinWindow

        let titles = (NSApp.delegate as? AppDelegate)?.windowMenuTitles ?? []
        let buttons = titles.enumerated().map { index, title in
            let button = NSButton(title: title, target: self, action: #selector(openMenu(_:)))
            button.bezelStyle = .recessed
            button.showsBorderOnlyWhileMouseInside = true
            button.font = .systemFont(ofSize: NSFont.systemFontSize)
            button.tag = index
            return button
        }
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        let bottomLine = NSBox()
        bottomLine.boxType = .separator
        bottomLine.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        addSubview(bottomLine)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            bottomLine.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomLine.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func openMenu(_ sender: NSButton) {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        let menu = delegate.makeWindowMenu(at: sender.tag)
        let below = NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.maxY + 2 : -2)
        menu.popUp(positioning: nil, at: below, in: sender)
    }
}

final class StatusBarView: NSVisualEffectView {
    let positionLabel = StatusBarView.makeLabel()
    let zoomLabel = StatusBarView.makeLabel()
    let lineEndingLabel = StatusBarView.makeLabel()
    let encodingLabel = StatusBarView.makeLabel()

    init() {
        super.init(frame: .zero)
        material = .titlebar
        blendingMode = .withinWindow

        let topLine = NSBox()
        topLine.boxType = .separator
        topLine.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [
            positionLabel, Self.makeDivider(),
            zoomLabel, Self.makeDivider(),
            lineEndingLabel, Self.makeDivider(),
            encodingLabel,
        ])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        positionLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        positionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(topLine)
        addSubview(stack)
        NSLayoutConstraint.activate([
            topLine.topAnchor.constraint(equalTo: topAnchor),
            topLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            zoomLabel.widthAnchor.constraint(equalToConstant: 44),
            lineEndingLabel.widthAnchor.constraint(equalToConstant: 118),
            encodingLabel.widthAnchor.constraint(equalToConstant: 128),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func makeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private static func makeDivider() -> NSView {
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 14).isActive = true
        return divider
    }
}
