import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var floatingBarControllers: [NSNumber: FloatingBarWindowController] = [:]
    private var primaryScreenID: NSNumber?
    private var screenRefreshTimer: Timer?
    private static let promptedAccessibilityBuildKey = "promptedAccessibilityBuild"

    func applicationDidFinishLaunching(_ notification: Notification) {
        primaryScreenID = NSScreen.primaryScreenID
        requestAccessibilityPermissionIfNeeded()
        syncBarsWithExternalScreens()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        screenRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncBarsWithExternalScreens()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func screenParametersDidChange() {
        syncBarsWithExternalScreens()
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else {
            UserDefaults.standard.removeObject(forKey: Self.promptedAccessibilityBuildKey)
            return
        }

        let currentBuild = accessibilityPromptBuildIdentifier()
        guard UserDefaults.standard.string(forKey: Self.promptedAccessibilityBuildKey) != currentBuild else {
            return
        }

        UserDefaults.standard.set(currentBuild, forKey: Self.promptedAccessibilityBuildKey)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func accessibilityPromptBuildIdentifier() -> String {
        guard let executablePath = Bundle.main.executablePath else { return "unknown" }
        let modificationDate = (try? FileManager.default.attributesOfItem(atPath: executablePath)[.modificationDate] as? Date)
        return "\(executablePath)-\(modificationDate?.timeIntervalSince1970 ?? 0)"
    }

    private func syncBarsWithExternalScreens() {
        let excludedScreenID = primaryScreenID ?? NSScreen.primaryScreenID
        let externalScreens = NSScreen.screens.filter { $0.screenID != nil && $0.screenID != excludedScreenID }
        let externalScreenIDs = Set(externalScreens.compactMap(\.screenID))

        for removedScreenID in floatingBarControllers.keys where !externalScreenIDs.contains(removedScreenID) {
            floatingBarControllers[removedScreenID]?.close()
            floatingBarControllers[removedScreenID] = nil
        }

        for screen in externalScreens {
            guard let screenID = screen.screenID else { continue }

            if let controller = floatingBarControllers[screenID] {
                controller.showWindow(nil)
            } else {
                let controller = FloatingBarWindowController(screenID: screenID)
                floatingBarControllers[screenID] = controller
                controller.showWindow(nil)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        screenRefreshTimer?.invalidate()
    }
}
