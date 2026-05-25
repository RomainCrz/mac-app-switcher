import AppKit
import ApplicationServices
import Combine
import CoreGraphics

struct WindowFocusTarget: Identifiable, Equatable {
    let windowID: CGWindowID
    let title: String?
    let frame: CGRect

    var id: CGWindowID { windowID }
}

struct RunningAppItem: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: NSImage?
    let application: NSRunningApplication
    let targetWindow: WindowFocusTarget?
    let windows: [WindowFocusTarget]

    static func == (lhs: RunningAppItem, rhs: RunningAppItem) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.targetWindow == rhs.targetWindow && lhs.windows == rhs.windows
    }
}

@MainActor
final class RunningAppProvider: ObservableObject {
    @Published private(set) var apps: [RunningAppItem] = []
    @Published private(set) var maxDisplayedApps: Int
    @Published private(set) var windowRenameRevision = 0

    private static let displayedAppCountKey = "displayedAppCount"
    private static let windowCustomNamesKey = "windowCustomNames"
    private static let displayedAppCountDidChange = Notification.Name("RunningAppProviderDisplayedAppCountDidChange")

    private let screenProvider: () -> NSScreen?
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var displayedAppCountObserver: NSObjectProtocol?
    private var pendingActivationWorkItem: DispatchWorkItem?
    private var recentApplicationPIDs: [pid_t] = []
    private var recentWindowIDsByPID: [pid_t: [CGWindowID]] = [:]
    private var excludedRecentApplicationPIDs: Set<pid_t> = []
    private let activationStabilityDelay: TimeInterval = 0.8

    init(screenProvider: @escaping () -> NSScreen?) {
        self.screenProvider = screenProvider
        self.maxDisplayedApps = Self.savedDisplayedAppCount
    }

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                Task { @MainActor in
                    self?.scheduleActivationRecord(for: app)
                }
            }
        }

        if displayedAppCountObserver == nil {
            displayedAppCountObserver = NotificationCenter.default.addObserver(
                forName: Self.displayedAppCountDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.applyDisplayedAppCount(Self.savedDisplayedAppCount)
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }

        if let displayedAppCountObserver {
            NotificationCenter.default.removeObserver(displayedAppCountObserver)
            self.displayedAppCountObserver = nil
        }

        pendingActivationWorkItem?.cancel()
        pendingActivationWorkItem = nil
    }

    func refresh() {
        let targetScreen = screenProvider()
        let visibleWindowsByPID = targetScreen.map { visibleApplicationWindows(on: $0) } ?? [:]

        let regularApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }

        let screenApps = targetScreen == nil
            ? regularApps
            : regularApps.filter { !(visibleWindowsByPID[$0.processIdentifier]?.isEmpty ?? true) }

        let eligibleApps = screenApps.filter { !excludedRecentApplicationPIDs.contains($0.processIdentifier) }

        let visibleApps = eligibleApps
            .sorted { lhs, rhs in
                compareByRecentUsage(lhs, rhs)
            }
            .prefix(maxDisplayedApps)
            .map { app in
                let windows = sortedWindows(visibleWindowsByPID[app.processIdentifier] ?? [], for: app)
                let targetWindow = windows.first
                return RunningAppItem(
                    id: itemID(for: app),
                    name: displayName(for: app),
                    icon: app.icon,
                    application: app,
                    targetWindow: targetWindow,
                    windows: windows
                )
            }

        let updatedApps = Array(visibleApps)

        if updatedApps != apps {
            apps = updatedApps
        }
    }

    private func visibleApplicationWindows(on screen: NSScreen) -> [pid_t: [WindowFocusTarget]] {
        guard let windowInfos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }

        let screenFrame = coreGraphicsFrame(for: screen)
        var windowsByPID: [pid_t: [(target: WindowFocusTarget, area: CGFloat)]] = [:]

        for info in windowInfos {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowNumber = info[kCGWindowNumber as String] as? CGWindowID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let alpha = info[kCGWindowAlpha as String] as? Double,
                  alpha > 0,
                  let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any]
            else { continue }

            var windowFrame = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDictionary as CFDictionary, &windowFrame),
                  windowFrame.width > 100,
                  windowFrame.height > 80
            else { continue }

            let intersection = windowFrame.intersection(screenFrame)
            guard !intersection.isNull else { continue }

            let intersectionArea = intersection.width * intersection.height
            let windowArea = windowFrame.width * windowFrame.height
            let coverage = intersectionArea / windowArea
            guard intersectionArea > 10_000, coverage > 0.20 else { continue }

            let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let target = WindowFocusTarget(windowID: windowNumber, title: title, frame: windowFrame)

            windowsByPID[pid, default: []].append((target, intersectionArea))
        }

        return windowsByPID.mapValues { windows in
            windows
                .sorted { lhs, rhs in lhs.area > rhs.area }
                .map(\.target)
        }
    }

    func setMaxDisplayedApps(_ count: Int) {
        let clampedCount = min(max(count, 1), 12)
        UserDefaults.standard.set(clampedCount, forKey: Self.displayedAppCountKey)
        applyDisplayedAppCount(clampedCount)
        NotificationCenter.default.post(name: Self.displayedAppCountDidChange, object: nil)
    }

    func removeFromRecent(_ app: RunningAppItem) {
        let pid = app.application.processIdentifier
        recentApplicationPIDs.removeAll { $0 == pid }
        excludedRecentApplicationPIDs.insert(pid)
        refresh()
    }

    func activate(_ app: RunningAppItem) {
        activate(app, window: app.targetWindow)
    }

    func activate(_ app: RunningAppItem, window: WindowFocusTarget?) {
        if focusWindow(window, for: app.application) {
            recordActivation(of: app.application, window: window)
            return
        }

        app.application.activate(options: [.activateIgnoringOtherApps])
        recordActivation(of: app.application, window: window)
    }

    private func applyDisplayedAppCount(_ count: Int) {
        let clampedCount = min(max(count, 1), 12)
        guard maxDisplayedApps != clampedCount else { return }

        maxDisplayedApps = clampedCount
        refresh()
    }

    private func scheduleActivationRecord(for app: NSRunningApplication) {
        guard app.activationPolicy == .regular, !app.isTerminated else { return }

        pendingActivationWorkItem?.cancel()

        let pid = app.processIdentifier
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                self?.recordActivation(of: app, window: nil)
            }
        }
        pendingActivationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + activationStabilityDelay, execute: workItem)
    }

    private func recordActivation(of app: NSRunningApplication, window: WindowFocusTarget?) {
        guard app.activationPolicy == .regular, !app.isTerminated else { return }

        let pid = app.processIdentifier
        excludedRecentApplicationPIDs.remove(pid)
        recentApplicationPIDs.removeAll { $0 == pid }
        recentApplicationPIDs.insert(pid, at: 0)
        recentApplicationPIDs = Array(recentApplicationPIDs.prefix(30))

        if let window {
            var recentWindowIDs = recentWindowIDsByPID[pid] ?? []
            recentWindowIDs.removeAll { $0 == window.windowID }
            recentWindowIDs.insert(window.windowID, at: 0)
            recentWindowIDsByPID[pid] = Array(recentWindowIDs.prefix(20))
        }

        refresh()
    }

    func displayName(for window: WindowFocusTarget, in app: RunningAppItem) -> String {
        let customName = customWindowNames[windowKey(for: window, app: app)]
        return customName ?? window.title ?? app.name
    }

    func rename(_ window: WindowFocusTarget, in app: RunningAppItem, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = windowKey(for: window, app: app)
        var names = customWindowNames

        if trimmedName.isEmpty || trimmedName == window.title {
            names.removeValue(forKey: key)
        } else {
            names[key] = trimmedName
        }

        UserDefaults.standard.set(names, forKey: Self.windowCustomNamesKey)
        windowRenameRevision += 1
    }

    private var customWindowNames: [String: String] {
        UserDefaults.standard.dictionary(forKey: Self.windowCustomNamesKey) as? [String: String] ?? [:]
    }

    private func windowKey(for window: WindowFocusTarget, app: RunningAppItem) -> String {
        "\(app.application.bundleIdentifier ?? app.name)-\(window.windowID)"
    }

    private func sortedWindows(_ windows: [WindowFocusTarget], for app: NSRunningApplication) -> [WindowFocusTarget] {
        let recentWindowIDs = recentWindowIDsByPID[app.processIdentifier] ?? []

        return windows.sorted { lhs, rhs in
            let lhsIndex = recentWindowIDs.firstIndex(of: lhs.windowID)
            let rhsIndex = recentWindowIDs.firstIndex(of: rhs.windowID)

            switch (lhsIndex, rhsIndex) {
            case let (lhsIndex?, rhsIndex?):
                if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }

            return lhs.frame.width * lhs.frame.height > rhs.frame.width * rhs.frame.height
        }
    }

    private func focusWindow(_ target: WindowFocusTarget?, for app: NSRunningApplication) -> Bool {
        guard let target else { return false }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement]
        else {
            return false
        }

        let bestWindow = windows
            .compactMap { window -> (window: AXUIElement, score: CGFloat)? in
                let score = matchScore(for: window, target: target)
                return score > 0 ? (window, score) : nil
            }
            .max { lhs, rhs in lhs.score < rhs.score }?
            .window

        guard let bestWindow else { return false }

        app.activate(options: [.activateIgnoringOtherApps])
        AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, bestWindow)
        AXUIElementPerformAction(bestWindow, kAXRaiseAction as CFString)
        return true
    }

    private func matchScore(for window: AXUIElement, target: WindowFocusTarget) -> CGFloat {
        var score: CGFloat = 0

        if let targetTitle = target.title,
           let axTitle = stringAttribute(kAXTitleAttribute, from: window),
           axTitle == targetTitle {
            score += 1_000_000
        }

        if let frame = frame(of: window) {
            let intersection = frame.intersection(target.frame)
            if !intersection.isNull {
                score += intersection.width * intersection.height
            }

            let distance = abs(frame.midX - target.frame.midX) + abs(frame.midY - target.frame.midY)
            score -= min(distance, 10_000)
        }

        return score
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func compareByRecentUsage(_ lhs: NSRunningApplication, _ rhs: NSRunningApplication) -> Bool {
        let lhsRecentIndex = recentApplicationPIDs.firstIndex(of: lhs.processIdentifier)
        let rhsRecentIndex = recentApplicationPIDs.firstIndex(of: rhs.processIdentifier)

        switch (lhsRecentIndex, rhsRecentIndex) {
        case let (lhsIndex?, rhsIndex?):
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }

        switch (lhs.launchDate, rhs.launchDate) {
        case let (lhsDate?, rhsDate?):
            if lhsDate != rhsDate { return lhsDate > rhsDate }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }

        return displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedAscending
    }

    private func itemID(for app: NSRunningApplication) -> String {
        "\(app.processIdentifier)"
    }

    private func coreGraphicsFrame(for screen: NSScreen) -> CGRect {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return screen.frame
        }

        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        return CGDisplayBounds(displayID)
    }

    private static var savedDisplayedAppCount: Int {
        let savedCount = UserDefaults.standard.integer(forKey: displayedAppCountKey)
        return savedCount == 0 ? 5 : min(max(savedCount, 1), 12)
    }

    private func displayName(for app: NSRunningApplication) -> String {
        app.localizedName ?? app.bundleIdentifier ?? "Unknown"
    }

    deinit {
        timer?.invalidate()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let displayedAppCountObserver {
            NotificationCenter.default.removeObserver(displayedAppCountObserver)
        }
        pendingActivationWorkItem?.cancel()
    }
}
