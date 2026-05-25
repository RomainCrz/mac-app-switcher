import AppKit
import SwiftUI

struct FloatingBarView: View {
    @ObservedObject var provider: RunningAppProvider
    @AppStorage("hideRecentItems") private var hideRecentItems = false

    var body: some View {
        HStack(spacing: 6) {
            if hideRecentItems || provider.apps.isEmpty {
                Color.clear
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(provider.apps) { app in
                            AppButton(app: app, provider: provider) {
                                provider.activate(app)
                            } onRemove: {
                                provider.removeFromRecent(app)
                            }
                        }
                    }
                    .frame(minWidth: 638, alignment: .center)
                    .padding(.horizontal, 8)
                }
            }

            DisplayCountMenu(provider: provider)
        }
        .frame(height: 40)
        .padding(4)
    }
}

private struct DisplayCountMenu: View {
    @ObservedObject var provider: RunningAppProvider
    @AppStorage("hideRecentItems") private var hideRecentItems = false

    private let options = [3, 5, 8, 12]

    var body: some View {
        Menu {
            Picker("Éléments affichés", selection: Binding(
                get: { provider.maxDisplayedApps },
                set: { provider.setMaxDisplayedApps($0) }
            )) {
                ForEach(options, id: \.self) { count in
                    Text("\(count) éléments").tag(count)
                }
            }

            Divider()

            Button(hideRecentItems ? "Afficher les éléments récents" : "Masquer les éléments récents") {
                hideRecentItems.toggle()
            }

            Divider()

            Button("Quitter complètement") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: hideRecentItems ? "eye.slash.circle.fill" : "ellipsis.circle.fill")
                .resizable()
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18, height: 18)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 34)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
    }
}

private struct AppButton: View {
    let app: RunningAppItem
    @ObservedObject var provider: RunningAppProvider
    let onActivate: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false
    @State private var isWindowPopoverPresented = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                onActivate()
            } label: {
                HStack(spacing: 5) {
                    AppIconView(image: app.icon)

                    Text(app.name)
                        .lineLimit(1)
                        .font(.caption)
                }
                .padding(.leading, 8)
                .padding(.trailing, 2)
                .padding(.vertical, 5)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 12, height: 12)
                    .padding(.trailing, 6)
                    .opacity(isHovered ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .help("Retirer des récents")
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.16 : 0.08))
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering, app.windows.count > 1 {
                isWindowPopoverPresented = true
            }
        }
        .popover(isPresented: $isWindowPopoverPresented, arrowEdge: .top) {
            AppWindowsPopover(app: app, provider: provider) { window in
                provider.activate(app, window: window)
                isWindowPopoverPresented = false
            }
        }
    }
}

private struct AppWindowsPopover: View {
    let app: RunningAppItem
    @ObservedObject var provider: RunningAppProvider
    let onActivate: (WindowFocusTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.name)
                .font(.headline)

            ForEach(app.windows) { window in
                WindowRow(app: app, window: window, provider: provider) {
                    onActivate(window)
                }
            }
        }
        .padding(10)
        .frame(width: 280)
    }
}

private struct WindowRow: View {
    let app: RunningAppItem
    let window: WindowFocusTarget
    @ObservedObject var provider: RunningAppProvider
    let onActivate: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onActivate()
            } label: {
                Image(systemName: window.windowID == app.targetWindow?.windowID ? "circle.fill" : "circle")
                    .font(.system(size: 8))
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            .help("Activer cette fenêtre")

            TextField(
                "Nom de la fenêtre",
                text: Binding(
                    get: { provider.displayName(for: window, in: app) },
                    set: { provider.rename(window, in: app, to: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(.caption)
        }
    }
}

private struct AppIconView: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
            } else {
                Image(systemName: "app")
                    .resizable()
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: 18, height: 18)
    }
}
