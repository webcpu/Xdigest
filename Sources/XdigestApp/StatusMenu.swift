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
    fontSize: String,
    fontSizeMobile: String,
    generateAction: Selector,
    openReaderAction: Selector,
    fontSizeAction: Selector,
    fontSizeMobileAction: Selector,
    qrCodeAction: Selector,
    quitAction: Selector,
    updaterController: SPUStandardUpdaterController
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

    // Text Size submenu — one 5-level slider per ergonomic class. Mac and
    // touch devices (iPhone + iPad) are tuned independently. Sliders are
    // continuous so the reader updates live on every tick over SSE.
    let fontSizeItem = NSMenuItem(title: "Text Size", action: nil, keyEquivalent: "")
    let fontSizeSubmenu = NSMenu()
    fontSizeSubmenu.addItem(sizeSliderItem(
        label: "For Mac",
        current: fontSize,
        action: fontSizeAction
    ))
    fontSizeSubmenu.addItem(.separator())
    fontSizeSubmenu.addItem(sizeSliderItem(
        label: "For iPhone & iPad",
        current: fontSizeMobile,
        action: fontSizeMobileAction
    ))
    fontSizeItem.submenu = fontSizeSubmenu
    menu.addItem(fontSizeItem)

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

/// Menu item hosting a 5-position NSSlider for a device class. The slider is
/// flanked by a small "A" and a large "A" (Apple's text-size affordance from
/// Display & Brightness). The slider's integer value (0...4) maps to
/// "xs"|"s"|"m"|"l"|"xl" and is read by the AppDelegate's action handler.
/// Continuous so the reader updates live as the user drags.
private func sizeSliderItem(label: String, current: String, action: Selector) -> NSMenuItem {
    let width: CGFloat = 260
    let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 56))

    let titleLabel = NSTextField(labelWithString: label)
    titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    titleLabel.textColor = .secondaryLabelColor
    titleLabel.frame = NSRect(x: 18, y: 34, width: width - 36, height: 16)
    container.addSubview(titleLabel)

    // Small "A" on the left -- smaller of the two glyphs anchored at slider min.
    let smallA = NSTextField(labelWithString: "A")
    smallA.font = NSFont.systemFont(ofSize: 11, weight: .regular)
    smallA.textColor = .secondaryLabelColor
    smallA.alignment = .center
    smallA.frame = NSRect(x: 14, y: 8, width: 14, height: 16)
    container.addSubview(smallA)

    // Large "A" on the right -- larger of the two glyphs anchored at slider max.
    let largeA = NSTextField(labelWithString: "A")
    largeA.font = NSFont.systemFont(ofSize: 17, weight: .regular)
    largeA.textColor = .secondaryLabelColor
    largeA.alignment = .center
    largeA.frame = NSRect(x: width - 14 - 18, y: 4, width: 18, height: 22)
    container.addSubview(largeA)

    let sliderLeft: CGFloat = 14 + 14 + 6 // padding + smallA + gap
    let sliderRight: CGFloat = 14 + 18 + 6 // padding + largeA + gap
    let slider = NSSlider()
    slider.minValue = 0
    slider.maxValue = 4
    slider.doubleValue = Double(sizeKeyToSliderIndex(current))
    slider.numberOfTickMarks = 5
    slider.allowsTickMarkValuesOnly = true
    slider.tickMarkPosition = .below
    slider.isContinuous = true
    slider.target = nil // walks responder chain → AppDelegate
    slider.action = action
    slider.frame = NSRect(x: sliderLeft, y: 4, width: width - sliderLeft - sliderRight, height: 24)
    container.addSubview(slider)

    let item = NSMenuItem()
    item.view = container
    return item
}

/// Maps the persisted size key to the slider's integer position. Unknown
/// values fall back to the middle ("m") so a corrupt UserDefaults value
/// can't strand the slider at an end.
func sizeKeyToSliderIndex(_ key: String) -> Int {
    switch key {
    case "xs": return 0
    case "s":  return 1
    case "m":  return 2
    case "l":  return 3
    case "xl": return 4
    default:   return 2
    }
}

/// Inverse of sizeKeyToSliderIndex. Called by AppDelegate's slider action.
func sliderIndexToSizeKey(_ index: Int) -> String {
    switch index {
    case 0: return "xs"
    case 1: return "s"
    case 2: return "m"
    case 3: return "l"
    case 4: return "xl"
    default: return "m"
    }
}
