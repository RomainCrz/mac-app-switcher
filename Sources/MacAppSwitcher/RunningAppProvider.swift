import AppKit
import Combine
import CoreGraphics

struct RunningAppItem: Identifiable, Equatable {
    let id: Int32
    let name: String
    let icon: NSImage?
    let application: NSRunningApplication

    static func == (lhs: RunningAppItem, rhs: RunningAppItem) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}

@MainActor
final class RunningAppProvider: ObservableObject {
    @Published private(set) var apps: [RunningAppItem] = []
    @Published private(set) var maxDisplayedApps: Int

    private static let displayedAppCountKey = "displayedAppCount"
    private static let displayedAppCountDidChange = Notification.Name("RunningAppProviderDisplayedAppCountDidChange")

    private let screenProvider: () -> NSScreen?
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var displayedAppCountObserver: NSObjectProtocol?
    private var pendingActivationWorkItem: DispatchWorkItem?
    private var recentApplicationPIDs: [pid_t] = []
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
        let visiblePIDs = targetScreen.map { visibleApplicationPIDs(on: $0) } ?? []

        let regularApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }

        let screenApps = targetScreen == nil
            ? regularApps
            : regularApps.filter { visiblePIDs.contains($0.processIdentifier) }

        let visibleApps = screenApps
            .sorted { lhs, rhs in
                compareByRecentUsage(lhs, rhs)
            }
            .prefix(maxDisplayedApps)
            .map { app in
                RunningAppItem(
                    id: app.processIdentifier,
                    name: displayName(for: app),
                    icon: app.icon,
                    application: app
                )
            }

        let updatedApps = Array(visibleApps)

        if updatedApps != apps {
            apps = updatedApps
        }
    }

    private func visibleApplicationPIDs(on screen: NSScreen) -> Set<pid_t> {
        guard let windowInfos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let screenFramesByID = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (NSNumber, CGRect)? in
            guard let screenID = screen.screenID else { return nil }
            return (screenID, coreGraphicsFrame(for: screen))
        })
        guard let targetScreenID = screen.screenID else { return [] }

        var bestScreenForPID: [pid_t: (screenID: NSNumber, area: CGFloat)] = [:]

        for info in windowInfos {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
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

            for (screenID, screenFrame) in screenFramesByID {
                let intersection = windowFrame.intersection(screenFrame)
                guard !intersection.isNull else { continue }

                let intersectionArea = intersection.width * intersection.height
                let windowArea = windowFrame.width * windowFrame.height
                let coverage = intersectionArea / windowArea
                guard intersectionArea > 10_000, coverage > 0.20 else { continue }

                if let currentBest = bestScreenForPID[pid] {
                    if intersectionArea > currentBest.area {
                        bestScreenForPID[pid] = (screenID, intersectionArea)
                    }
                } else {
                    bestScreenForPID[pid] = (screenID, intersectionArea)
                }
            }
        }

        return Set(bestScreenForPID.compactMap { pid, bestScreen in
            bestScreen.screenID == targetScreenID ? pid : nil
        })
    }

    func setMaxDisplayedApps(_ count: Int) {
        let clampedCount = min(max(count, 1), 12)
        UserDefaults.standard.set(clampedCount, forKey: Self.displayedAppCountKey)
        applyDisplayedAppCount(clampedCount)
        NotificationCenter.default.post(name: Self.displayedAppCountDidChange, object: nil)
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
                self?.recordActivation(of: app)
            }
        }
        pendingActivationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + activationStabilityDelay, execute: workItem)
    }

    private func recordActivation(of app: NSRunningApplication) {
        guard app.activationPolicy == .regular, !app.isTerminated else { return }

        let pid = app.processIdentifier
        recentApplicationPIDs.removeAll { $0 == pid }
        recentApplicationPIDs.insert(pid, at: 0)
        recentApplicationPIDs = Array(recentApplicationPIDs.prefix(30))
        refresh()
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
