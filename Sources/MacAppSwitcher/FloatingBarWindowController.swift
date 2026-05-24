import AppKit
import SwiftUI

@MainActor
final class FloatingBarWindowController: NSWindowController {
    private let provider: RunningAppProvider
    private let screenID: NSNumber
    private let windowSize = NSSize(width: 700, height: 48)
    private let topInset: CGFloat = -8

    init(screenID: NSNumber) {
        self.screenID = screenID

        let provider = RunningAppProvider {
            NSScreen.screen(withID: screenID)
        }
        self.provider = provider

        let contentView = FloatingBarView(provider: provider)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(origin: .zero, size: windowSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false

        super.init(window: panel)

        provider.start()
        positionWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        positionWindow()
        super.showWindow(sender)
        window?.orderFrontRegardless()
    }

    private func positionWindow() {
        guard let window,
              let screenFrame = NSScreen.screen(withID: screenID)?.frame
        else { return }

        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.maxY - windowSize.height - topInset
        window.setFrame(NSRect(x: x, y: y, width: windowSize.width, height: windowSize.height), display: true)
    }
}

extension NSScreen {
    static func screen(withID screenID: NSNumber) -> NSScreen? {
        screens.first { $0.screenID == screenID }
    }

    static var primaryScreenID: NSNumber? {
        screens.first { $0.frame.origin == .zero }?.screenID ?? screens.first?.screenID
    }

    var screenID: NSNumber? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }
}
