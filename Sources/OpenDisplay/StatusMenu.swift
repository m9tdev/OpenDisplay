import AppKit
import Observation

/// The menu bar item. Uses a plain NSMenu so it looks like the system Wi-Fi and Sound menus.
///
/// NSMenu does not handle changes to its items well while it is open. Tests showed:
/// - Changing the items during a click in the menu can leave empty space at the bottom.
/// - An item that was hidden at any time while the menu is open cannot expand again correctly.
/// - A separate item always takes at least 1 pt, also at 0 height.
///
/// So these rules apply:
/// 1. Before the menu opens, it contains only the rows that are needed now (no collapsed rows).
/// 2. While it is open, items are never added, removed, or hidden. Rows can only collapse
///    (for example the sliders of a display that turns off), or expand inside a `RowStackView`.
/// 3. If the menu needs new rows while it is open (a display turns on, an error appears),
///    it closes and opens again with new items.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let manager: DisplayManager
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let keyboard: KeyboardControl

    init(manager: DisplayManager, keyboard: KeyboardControl) {
        self.manager = manager
        self.keyboard = keyboard
        super.init()
        statusItem.button?.image = MenuBarIcon.image()
        menu.delegate = self
        menu.minimumWidth = Layout.width
        statusItem.menu = menu
        watchNeededRows()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // The menu bar icon can move a moment after the notification, so check again later.
                for delay in [0.0, 0.5, 1.0] {
                    self?.after(delay) { $0.reopenIfWanted() }
                }
            }
        }

        // Debug helper: `OpenDisplay --open-menu [seconds]` opens the menu at launch (after 1 s by default), for screenshots.
        if let index = CommandLine.arguments.firstIndex(of: "--open-menu") {
            let delay = CommandLine.arguments.dropFirst(index + 1).first.flatMap(Double.init) ?? 1
            // A timer, not a main queue block: the menu blocks its caller while it is open,
            // and a blocked main queue block stops all other main queue work.
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.statusItem.button?.performClick(nil) }
            }
        }
    }

    // MARK: Open and close

    /// Called just before the menu opens: the right moment to read the displays and build the items.
    func menuNeedsUpdate(_ menu: NSMenu) {
        manager.lastError = nil
        manager.refresh()
        update()
        for display in manager.displays where display.isEnabled {
            manager.readDDCSettings(display)
        }
    }

    private var openCount = 0
    /// The screen with the menu bar icon, and the displays that were on, when the menu opened.
    private var menuScreen: NSNumber?
    private var menuEnabledDisplays: Set<CGDirectDisplayID> = []
    /// True if the last close came from a click or key press, not from macOS.
    private var closedByUser = false

    func menuWillOpen(_ menu: NSMenu) {
        MenuState.isOpen = true
        openCount += 1
        menuScreen = iconScreen()
        menuEnabledDisplays = enabledDisplays()
    }

    func menuDidClose(_ menu: NSMenu) {
        MenuState.isOpen = false
        let userEvents: [NSEvent.EventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .keyDown]
        closedByUser = NSApp.currentEvent.map { userEvents.contains($0.type) } ?? false
        update()
    }

    private func iconScreen() -> NSNumber? {
        statusItem.button?.window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }

    private func enabledDisplays() -> Set<CGDirectDisplayID> {
        Set(manager.displays.filter(\.isEnabled).map(\.id))
    }

    // MARK: Reopen

    // When a display turns on or off while the menu is open, the menu can need new rows, or the menu bar icon can
    // move to another screen (and the open menu stays in its old place). macOS can also close the menu itself
    // during the display change. In all these cases, the menu opens again, with new items, at the icon.

    /// Set when a display turned on or off while the menu was open. Expires after a few seconds.
    private var reopenWanted: Date?

    private func after(_ delay: TimeInterval, _ action: @escaping @MainActor (StatusMenu) -> Void) {
        // A timer, not a main queue block: see the `--open-menu` note.
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func rowsMissing() -> Bool {
        guard let builtRows else { return true }
        return !neededRows().isSubset(of: builtRows)
    }

    private func reopenIfWanted() {
        guard let wanted = reopenWanted else { return }
        guard Date().timeIntervalSince(wanted) < 6 else {
            reopenWanted = nil
            return
        }
        if MenuState.isOpen {
            guard rowsMissing() || iconScreen() != menuScreen else { return }
            menu.cancelTracking()
        } else if closedByUser {
            reopenWanted = nil
            return
        }
        reopenWanted = nil
        openAgain()
    }

    /// Opens the menu. The icon can still be moving between screens, or a display can still be waking up,
    /// and then a click does not open the menu. So try again for a few seconds.
    private func openAgain() {
        var tries = 0
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                tries += 1
                guard let self, !MenuState.isOpen, tries <= 20 else { return timer.invalidate() }
                let opens = self.openCount
                // This call returns only when the menu closes again.
                self.statusItem.button?.performClick(nil)
                if self.openCount != opens { timer.invalidate() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: Building

    /// The rows in the menu now, by key (see `neededRows`).
    private var builtRows: Set<String>?

    /// The rows the menu needs now. A display that is off needs only its own row.
    private func neededRows() -> Set<String> {
        var rows: Set<String> = []
        for display in manager.displays {
            rows.insert("\(display.id)")
            rows.formUnion(DisplayControls.neededRows(for: display, manager: manager))
        }
        return rows
    }

    private func watchNeededRows() {
        withObservationTracking {
            _ = neededRows()
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.update()
                self.watchNeededRows()
            }
        }
        update()
    }

    /// Applies the rules in the type comment: build while closed, or reopen if the open menu misses rows.
    private func update() {
        let needed = neededRows()
        if !MenuState.isOpen {
            if needed != builtRows { buildItems(needed) }
        } else if rowsMissing() || enabledDisplays() != menuEnabledDisplays {
            reopenWanted = Date()
            menuEnabledDisplays = enabledDisplays()
            // Wait a moment, so the display change can start first.
            after(0.5) { $0.reopenIfWanted() }
        }
    }

    /// One flat menu, like BetterDisplay: a block per display with its controls. No submenus.
    /// Presets and settings are in the Settings window.
    private func buildItems(_ rows: Set<String>) {
        builtRows = rows
        menu.removeAllItems()

        // The general error message is in the same item as the title, so it can expand fully.
        add(RowStackView([
            TitleRowView("Displays"),
            MessageRowView(indented: false) { [manager] in manager.lastError },
        ]))
        for display in manager.displays {
            menu.addItem(.separator())
            // One item per display, so collapsed controls take no space (a separate item takes at least 1 pt).
            var block: [MenuRowView] = [DisplayRowView(manager: manager, display: display)]
            for key in DisplayControls.neededRows(for: display, manager: manager) where rows.contains(key) {
                let name = String(key.split(separator: ".", maxSplits: 1).last ?? "")
                if let row = DisplayControls.row(name, manager: manager, display: display) { block.append(row) }
            }
            add(RowStackView(block))
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let displays = NSMenuItem(title: "Displays Settings…", action: #selector(openDisplaySettings), keyEquivalent: "")
        displays.target = self
        menu.addItem(displays)
        let quit = NSMenuItem(title: "Quit OpenDisplay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        // macOS adds a gear and an X icon to these standard items by itself. No other item has an icon.
        if #available(macOS 27, *) {
            for item in [settings, displays, quit] { item.preferredImageVisibility = .hidden }
        }
    }

    private func add(_ row: MenuRowView) {
        let item = NSMenuItem()
        item.view = row
        menu.addItem(item)
    }

    // MARK: Actions

    @objc private func openSettings() {
        // The menu is still closing now, and macOS does not activate an app during that. So wait a moment.
        after(0.1) { SettingsWindow.show(manager: $0.manager, keyboard: $0.keyboard) }
    }

    @objc private func openDisplaySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
    }
}
