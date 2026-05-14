import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let usageStore = UsageStore()
    private var statusItem: NSStatusItem?
    private var statusView: StatusUsageControl?
    private var refreshTimer: Timer?
    private var usageCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        usageStore.refresh()
        InstallationCleanupPrompter.promptIfNeeded()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.usageStore.refresh()
        }
    }

    private func setupStatusItem() {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(refreshMenuItem())
        menu.addItem(.separator())
        menu.addItem(rateLimitMenuItem())
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Open Codex Usage Page", action: #selector(openCodexUsagePage), keyEquivalent: "u"))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        let item = NSStatusBar.system.statusItem(withLength: 78)
        let view = StatusUsageControl(frame: NSRect(x: 0, y: 0, width: 78, height: NSStatusBar.system.thickness))
        view.toolTip = "Codex Dashboard"
        view.openMenu = { [weak item] in
            guard let item else { return }
            item.popUpMenu(menu)
        }
        item.view = view
        statusView = view
        statusItem = item

        updateStatusItem(snapshot: usageStore.snapshot)
        usageCancellable = usageStore.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.updateStatusItem(snapshot: snapshot)
            }
    }

    private func updateStatusItem(snapshot: UsageSnapshot) {
        statusView?.primaryPercent = snapshot.rateLimits?.primary.remainingPercent
        statusView?.secondaryPercent = snapshot.rateLimits?.secondary.remainingPercent
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func refreshMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 44))

        let button = HoverMenuButton(frame: NSRect(x: 10, y: 5, width: 280, height: 34))
        button.title = "Refresh Usage"
        button.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh Usage")
        button.target = self
        button.action = #selector(refreshUsage)

        view.addSubview(button)
        item.view = view
        return item
    }

    private func rateLimitMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let view = NSHostingView(rootView: RateLimitMenuView(store: usageStore))
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 146)
        item.view = view
        return item
    }

    @objc private func refreshUsage() {
        usageStore.refresh()
    }

    @objc private func openCodexUsagePage() {
        NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex/settings/usage")!)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        usageStore.refresh()
    }
}

final class HoverMenuButton: NSControl {
    var title = "" {
        didSet { needsDisplay = true }
    }

    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    private var isHovering = false {
        didSet { needsDisplay = true }
    }

    private var isPressing = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addTrackingArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        addTrackingArea()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressing = false
    }

    override func mouseDown(with event: NSEvent) {
        isPressing = true
    }

    override func mouseUp(with event: NSEvent) {
        let clickedInside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressing = false
        if clickedInside {
            sendAction(action, to: target)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let backgroundColor: NSColor
        if isPressing {
            backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22)
        } else if isHovering {
            backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12)
        } else {
            backgroundColor = .clear
        }

        backgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()

        let contentTint = NSColor.labelColor
        let imageRect = NSRect(x: 13, y: (bounds.height - 15) / 2, width: 15, height: 15)
        if let image {
            image.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))?
                .tinted(contentTint)
                .draw(in: imageRect)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: contentTint,
            .paragraphStyle: paragraphStyle
        ]
        let textRect = NSRect(x: 38, y: (bounds.height - 17) / 2, width: bounds.width - 50, height: 17)
        title.draw(in: textRect, withAttributes: attributes)
    }

    private func addTrackingArea() {
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self))
    }
}

final class StatusUsageControl: NSControl {
    private static let valueFont = NSFont.systemFont(ofSize: 8.5, weight: .medium)

    var primaryPercent: Double? {
        didSet { needsDisplay = true }
    }

    var secondaryPercent: Double? {
        didSet { needsDisplay = true }
    }

    var openMenu: (() -> Void)?

    private var isPressing = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        isPressing = true
    }

    override func mouseUp(with event: NSEvent) {
        let clickedInside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressing = false
        if clickedInside {
            openMenu?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isPressing {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.28).setFill()
            NSBezierPath(rect: bounds).fill()
        }

        let iconSize: CGFloat = 15
        let iconRect = NSRect(
            x: 6,
            y: (bounds.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "Codex Dashboard")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))?
            .tinted(.labelColor)
            .draw(in: iconRect)

        drawLine(percent: primaryPercent, y: bounds.midY + 1)
        drawLine(percent: secondaryPercent, y: bounds.midY - 8)
    }

    private func drawLine(percent: Double?, y: CGFloat) {
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: Self.valueFont,
            .foregroundColor: NSColor.labelColor.resolvedColor
        ]

        NSAttributedString(string: percentText(percent), attributes: valueAttributes)
            .draw(in: NSRect(x: 27, y: y, width: bounds.width - 31, height: 10))
    }

    private func percentText(_ percent: Double?) -> String {
        guard let percent else { return "--" }
        return "\(Int(percent.rounded()))%"
    }
}

private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let image = copy() as! NSImage
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

private extension NSColor {
    var resolvedColor: NSColor {
        usingColorSpace(.sRGB) ?? self
    }
}
