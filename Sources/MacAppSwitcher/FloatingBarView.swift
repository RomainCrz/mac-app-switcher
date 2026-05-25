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

            if app.windows.count > 1 {
                Button {
                    isWindowPopoverPresented = true
                } label: {
                    Image(systemName: "rectangle.stack.fill")
                        .resizable()
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 12, height: 12)
                        .opacity(isHovered ? 1 : 0.55)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Voir les fenêtres")
                .accessibilityLabel("Voir les fenêtres de \(app.name)")
            }

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

            if provider.isAccessibilityTrusted {
                ForEach(app.windows) { window in
                    WindowRow(app: app, window: window, provider: provider) {
                        onActivate(window)
                    }
                }
            } else {
                Text("Accès Accessibilité requis pour choisir une fenêtre.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    @State private var isEditing = false
    @State private var draftName = ""
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if !isEditing {
                Button {
                    onActivate()
                } label: {
                    Image(systemName: window.windowID == app.targetWindow?.windowID ? "circle.fill" : "circle")
                        .font(.system(size: 8))
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .help("Activer cette fenêtre")
            } else {
                Image(systemName: window.windowID == app.targetWindow?.windowID ? "circle.fill" : "circle")
                    .font(.system(size: 8))
                    .frame(width: 12)
            }

            if isEditing {
                TextField("Nom de la fenêtre", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .focused($isNameFieldFocused)
                    .onSubmit(commitRename)
                    .onChange(of: isNameFieldFocused) { focused in
                        if !focused {
                            commitRename()
                        }
                    }
                    .onAppear {
                        draftName = provider.displayName(for: window, in: app)
                        isNameFieldFocused = true
                    }
            } else {
                Button {
                    onActivate()
                } label: {
                    HStack {
                        Text(provider.displayName(for: window, in: app))
                            .lineLimit(1)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Activer cette fenêtre")
            }

            Button {
                draftName = provider.displayName(for: window, in: app)
                isEditing = true
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("Renommer")
        }
    }

    private func commitRename() {
        guard isEditing else { return }
        provider.rename(window, in: app, to: draftName)
        isEditing = false
        isNameFieldFocused = false
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
