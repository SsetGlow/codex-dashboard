import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let usageStore = UsageStore()
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        usageStore.refresh()
        InstallationCleanupPrompter.promptIfNeeded()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.usageStore.refresh()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "Codex Dashboard")

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(menuItem(title: "Refresh Usage", action: #selector(refreshUsage), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(rateLimitMenuItem())
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Open Codex Usage Page", action: #selector(openCodexUsagePage), keyEquivalent: "u"))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
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
