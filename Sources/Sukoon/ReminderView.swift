import SwiftUI
import SukoonCore

struct ReminderView: View {
    @Environment(\.sukoonPalette) private var palette
    @Environment(\.sukoonLocalization) private var l10n
    let store: AppStore
    let content: ReminderContent
    let isPreview: Bool
    let onDismiss: () -> Void
    let onRead: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(l10n.text(isPreview ? "Close preview; progress stays unchanged" : "Dismiss reminder"))
                .accessibilityLabel(l10n.text("Dismiss reminder"))
                .accessibilityIdentifier("reminder.dismiss")
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                ArabicText(content.arabic, size: store.settings.arabicFontSize)
                    .textSelection(.enabled)
                    .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.center, for: .alignment)
            .scrollBounceBehavior(.basedOnSize)
            .id(content.id)

            HStack(spacing: 14) {
                PassageReference(library: store.library, content: content)
                Spacer()
                Button(action: onOpen) {
                    Image(systemName: "book.closed")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(l10n.text("Open this ayah in the Quran"))
                .accessibilityLabel(l10n.text("Open this ayah in the Quran"))
                .accessibilityIdentifier("reminder.open")

                if !isPreview,
                   (content.kind == .surah || content.kind == .automatic),
                   !store.settings.autoAdvance {
                    Button(action: onRead) {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.accent)
                    .help(l10n.text("Read & continue"))
                    .accessibilityLabel(l10n.text("Read & continue"))
                    .accessibilityIdentifier("reminder.continue")
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 400, height: 280)
        .background(palette.canvas)
        .clipShape(.rect(cornerRadius: 18))
    }
}
