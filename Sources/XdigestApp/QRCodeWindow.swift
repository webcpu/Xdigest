import AppKit
import CoreImage
import SystemConfiguration

private let port = 8408

/// Detects the Mac's local hostname and Tailscale hostname (if running),
/// generates QR codes for the reader URL, and shows them in a window.
@MainActor
func showQRCodeWindow() -> NSWindow {
    let localHost = localHostname()
    let tailscaleHost = tailscaleHostname()
    let localURL = "http://\(localHost):\(port)"

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 0),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = "Open Reader on iPhone / iPad"
    window.isReleasedWhenClosed = false

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 16
    stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)

    let qrRow = NSStackView()
    qrRow.orientation = .horizontal
    qrRow.alignment = .top
    qrRow.spacing = 24

    qrRow.addArrangedSubview(qrColumn(title: "Same WiFi", url: localURL))
    if let tsHost = tailscaleHost {
        let tsURL = "http://\(tsHost):\(port)"
        qrRow.addArrangedSubview(qrColumn(title: "Anywhere", url: tsURL))
    }
    stack.addArrangedSubview(qrRow)

    let hint = NSTextField(wrappingLabelWithString: "Scan with your phone's camera, then tap \"Add to Home Screen\" for one-tap access.")
    hint.font = .systemFont(ofSize: 12)
    hint.textColor = .secondaryLabelColor
    hint.alignment = .center
    stack.addArrangedSubview(hint)

    window.contentView = stack
    window.center()
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    return window
}

// MARK: - QR Column

private func qrColumn(title: String, url: String) -> NSView {
    let column = NSStackView()
    column.orientation = .vertical
    column.alignment = .centerX
    column.spacing = 8

    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 13, weight: .semibold)
    column.addArrangedSubview(label)

    if let qrImage = generateQRCode(for: url) {
        let imageView = NSImageView(image: qrImage)
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentHuggingPriority(.required, for: .vertical)
        imageView.widthAnchor.constraint(equalToConstant: 160).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 160).isActive = true
        column.addArrangedSubview(imageView)
    }

    let urlLabel = NSTextField(labelWithString: url)
    urlLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    urlLabel.textColor = .secondaryLabelColor
    urlLabel.isSelectable = true
    column.addArrangedSubview(urlLabel)

    return column
}

// MARK: - QR Code Generation

private func generateQRCode(for string: String) -> NSImage? {
    guard let data = string.data(using: .utf8),
          let filter = CIFilter(name: "CIQRCodeGenerator")
    else { return nil }

    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")

    guard let ciImage = filter.outputImage else { return nil }

    // Scale up from the tiny CIFilter output to a crisp bitmap.
    let scale = 160.0 / ciImage.extent.width
    let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

    let rep = NSCIImageRep(ciImage: scaled)
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
}

// MARK: - Hostname Detection

/// Returns the Bonjour/mDNS local hostname, e.g. "m4.local".
private func localHostname() -> String {
    if let name = SCDynamicStoreCopyLocalHostName(nil) {
        return "\(name as String).local"
    }
    return "localhost"
}

/// Returns the Tailscale MagicDNS hostname if Tailscale is running,
/// e.g. "m4.tailnet-name.ts.net". Returns nil if Tailscale isn't active.
///
/// Detection: enumerate network interfaces for a 100.64.0.0/10 (CGNAT)
/// address, then reverse-DNS it to the MagicDNS name. Works with both
/// the Mac App Store and standalone Tailscale builds (no CLI needed).
private func tailscaleHostname() -> String? {
    guard let ip = tailscaleIPv4() else { return nil }

    // Reverse DNS: 100.x.x.x → m4.tailnet.ts.net
    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    inet_pton(AF_INET, ip, &addr.sin_addr)

    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    let result = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            getnameinfo(sa, socklen_t(MemoryLayout<sockaddr_in>.size),
                        &host, socklen_t(host.count), nil, 0, 0)
        }
    }
    guard result == 0 else { return nil }
    let hostname = String(cString: host)
    // Sanity: must end in .ts.net (Tailscale's domain)
    guard hostname.hasSuffix(".ts.net") else { return nil }
    // Use just the first component (e.g. "m4" from "m4.tailnet.ts.net").
    // Tailscale's MagicDNS resolves short names on all devices in the
    // tailnet, so the full FQDN is unnecessary noise in the QR code.
    return hostname.split(separator: ".").first.map(String.init) ?? hostname
}

/// Finds a Tailscale IPv4 address by scanning network interfaces for
/// the 100.64.0.0/10 CGNAT range that Tailscale allocates.
private func tailscaleIPv4() -> String? {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }

    var cursor: UnsafeMutablePointer<ifaddrs>? = first
    while let ifa = cursor {
        defer { cursor = ifa.pointee.ifa_next }
        guard let ifaAddr = ifa.pointee.ifa_addr else { continue }
        guard ifaAddr.pointee.sa_family == AF_INET else { continue }
        let addr = ifaAddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            $0.pointee.sin_addr
        }
        let byte0 = UInt8((addr.s_addr >> 0) & 0xFF)
        let byte1 = UInt8((addr.s_addr >> 8) & 0xFF)
        // 100.64.0.0/10: first byte == 100, bits 7-6 of second byte == 01
        guard byte0 == 100, (byte1 & 0xC0) == 0x40 else { continue }
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var mutable = addr
        inet_ntop(AF_INET, &mutable, &buf, socklen_t(buf.count))
        return String(cString: buf)
    }
    return nil
}
