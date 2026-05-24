import AppKit
import SwiftUI

struct FloatingBarView: View {
    @ObservedObject var provider: RunningAppProvider

    var body: some View {
        HStack(spacing: 6) {
            if provider.apps.isEmpty {
                Color.clear
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(provider.apps) { app in
                            AppButton(app: app)
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
    @AppStorage("showMenuButton") private var showMenuButton = true

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

            Button(showMenuButton ? "Masquer le bouton menu" : "Afficher le bouton menu") {
                showMenuButton.toggle()
            }

            Divider()

            Button("Quitter complètement") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Group {
                if showMenuButton {
                    Image(systemName: "ellipsis.circle.fill")
                        .resizable()
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 18, height: 18)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                } else {
                    Circle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 6, height: 6)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 11)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: showMenuButton ? 34 : 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(showMenuButton ? 0.08 : 0.02))
        )
    }
}

private struct AppButton: View {
    let app: RunningAppItem
    @State private var isHovered = false

    var body: some View {
        Button {
            app.application.activate(options: [.activateIgnoringOtherApps])
        } label: {
            HStack(spacing: 5) {
                AppIconView(image: app.icon)

                Text(app.name)
                    .lineLimit(1)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.16 : 0.08))
        )
        .onHover { isHovered = $0 }
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
