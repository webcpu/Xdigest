import AppKit
import Sparkle

/// "XD" wordmark rendered as a template image so macOS handles dark
/// mode, light mode, and tinted menu bar automatically.
func makeMenuBarIcon() -> NSImage {
    let size = NSSize(width: 22, height: 22)
    let image = NSImage(size: size, flipped: false) { rect in
        let font = NSFont.systemFont(ofSize: 14, weight: .heavy)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let text = "XD" as NSString
        let textSize = text.size(withAttributes: attrs)
        let origin = NSPoint(
            x: (rect.width - textSize.width) / 2,
            y: (rect.height - textSize.height) / 2 - 1
        )
        text.draw(at: origin, withAttributes: attrs)
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Xdigest"
    return image
}

/// Builds the status menu from state. Pure function: takes state in,
/// returns menu out. AppDelegate calls this from rebuildMenu() whenever
/// the generating state changes.
///
/// Selectors are passed in because the @objc action methods live on
/// AppDelegate, which this function doesn't (and shouldn't) see.
/// Sparkle's updater controller is set as an explicit target on its
/// menu item so AppKit routes the action directly to Sparkle rather
/// than walking the responder chain.
func buildStatusMenu(
    isGenerating: Bool,
    currentInterval: GenerateInterval,
    generateAction: Selector,
    openReaderAction: Selector,
    qrCodeAction: Selector,
    quitAction: Selector,
    updaterController: SPUStandardUpdaterController,
    intervalHandler: @escaping (GenerateInterval) -> Void
) -> NSMenu {
    let menu = NSMenu()

    let generateItem = NSMenuItem(
        title: isGenerating ? "Generating..." : "Generate Digest",
        action: isGenerating ? nil : generateAction,
        keyEquivalent: "g"
    )
    menu.addItem(generateItem)

    menu.addItem(NSMenuItem(
        title: "Open Reader",
        action: openReaderAction,
        keyEquivalent: "o"
    ))

    menu.addItem(.separator())

    let autoGenItem = NSMenuItem(title: "Auto-Generate", action: nil, keyEquivalent: "")
    let autoGenMenu = NSMenu()
    for interval in GenerateInterval.allCases {
        let item = NSMenuItem(title: interval.title, action: nil, keyEquivalent: "")
        item.state = interval == currentInterval ? .on : .off
        let handler = intervalHandler
        let captured = interval
        item.action = #selector(IntervalTarget.select(_:))
        let target = IntervalTarget(interval: captured, handler: handler)
        item.target = target
        item.representedObject = target
        autoGenMenu.addItem(item)
    }
    autoGenItem.submenu = autoGenMenu
    menu.addItem(autoGenItem)

    menu.addItem(.separator())

    menu.addItem(NSMenuItem(
        title: "QR Code for Phone...",
        action: qrCodeAction,
        keyEquivalent: ""
    ))
    let updatesItem = NSMenuItem(
        title: "Check for Updates...",
        action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
        keyEquivalent: ""
    )
    updatesItem.target = updaterController
    menu.addItem(updatesItem)
    menu.addItem(NSMenuItem(title: "Quit", action: quitAction, keyEquivalent: "q"))

    return menu
}

/// Action target for interval menu items. Stored as `representedObject`
/// to keep it alive for the menu's lifetime.
final class IntervalTarget: NSObject {
    private let interval: GenerateInterval
    private let handler: (GenerateInterval) -> Void

    init(interval: GenerateInterval, handler: @escaping (GenerateInterval) -> Void) {
        self.interval = interval
        self.handler = handler
    }

    @objc func select(_ sender: Any?) {
        handler(interval)
    }
}
