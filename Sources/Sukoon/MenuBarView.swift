import SwiftUI
import SukoonCore

struct MenuBarView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    @Bindable var store: AppStore
    let onOpen: (AppSection) -> Void
    let onPreview: () -> Void
    let onQuit: () -> Void

    var body: some View {
        let content = store.lastReminder ?? store.previewReminder()
        let automaticComplete = store.settings.mode == .automatic && store.isAutomaticComplete
        VStack(spacing: 18) {
            if let content {
                ScrollView {
                    ArabicText(content.arabic, size: store.settings.arabicFontSize)
                        .textSelection(.enabled)
                        .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.center, for: .alignment)
                .scrollBounceBehavior(.basedOnSize)
                .id(content.id)
            } else {
                Button { onOpen(automaticComplete ? .journey : .quran) } label: {
                    Text(l10n.text(automaticComplete ? "Automatic Quran complete" : "Choose a surah"))
                        .font(.custom("Geeza Pro", size: 28))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.text(automaticComplete ? "Automatic Quran complete" : "Choose a surah"))
            }

            HStack(spacing: 14) {
                if let content {
                    PassageReference(library: store.library, content: content)
                }
                Spacer()
                Button { onOpen(.quran) } label: {
                    Image(systemName: "book.closed")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(l10n.text("Open the Quran"))
                .accessibilityLabel(l10n.text("Open the Quran"))
                .accessibilityIdentifier("workspace.open")

                Menu {
                    Button {
                        store.settings.remindersEnabled.toggle()
                    } label: {
                        Label(l10n.text(store.settings.remindersEnabled ? "Pause reminders" : "Resume reminders"),
                              systemImage: store.settings.remindersEnabled ? "pause" : "play")
                    }
                    Button(l10n.text("Preview reminder"), systemImage: "sparkle", action: onPreview)
                        .disabled(store.previewReminder() == nil)
                    Divider()
                    Button(l10n.text("Settings"), systemImage: "slider.horizontal.3") { onOpen(.settings) }
                    Button(l10n.text("Reading progress"), systemImage: "checkmark.circle") { onOpen(.journey) }
                    Divider()
                    Button(l10n.text("Quit Sukoon"), action: onQuit)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(l10n.text("Sukoon actions"))
                .accessibilityLabel(l10n.text("Sukoon actions"))
                .accessibilityIdentifier("sukoon.actions")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 360, height: 240)
        .background(palette.canvas)
    }
}
