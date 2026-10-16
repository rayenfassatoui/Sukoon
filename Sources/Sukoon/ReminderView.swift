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
                Label(
                    l10n.text(isPreview ? "Preview reminder" : "Sukoon"),
                    systemImage: isPreview ? "bell" : "moon.stars"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
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
            Divider().overlay(palette.hairline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    PassageReference(library: store.library, content: content)
                    Spacer(minLength: 4)
                    actionButtons
                }
                VStack(alignment: .leading, spacing: 10) {
                    PassageReference(library: store.library, content: content)
                    actionButtons
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .environment(\.layoutDirection, .leftToRight)
                .padding(6)
                .accessibilityHidden(true)
        }
        .background(palette.surface)
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(palette.hairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 10) {
            if let reference = content.reference {
                Button {
                    store.toggleBookmark(surahID: reference.surahID, verseID: reference.verseID)
                } label: {
                    Image(systemName: store.isBookmarked(
                        surahID: reference.surahID,
                        verseID: reference.verseID
                    ) ? "heart.fill" : "heart")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(palette.accent)
                .accessibilityAddTraits(
                    store.isBookmarked(surahID: reference.surahID, verseID: reference.verseID) ? .isSelected : []
                )
                .help(
                    l10n.format(
                        store.isBookmarked(surahID: reference.surahID, verseID: reference.verseID)
                            ? "Remove %@ from Favourites"
                            : "Add %@ to Favourites",
                        l10n.reference(reference),
                        table: "Workspace"
                    )
                )
                .accessibilityLabel(
                    l10n.format(
                        store.isBookmarked(surahID: reference.surahID, verseID: reference.verseID)
                            ? "Remove %@ from Favourites"
                            : "Add %@ to Favourites",
                        l10n.reference(reference),
                        table: "Workspace"
                    )
                )
                .accessibilityIdentifier("reminder.favourite")
            }

            Button(action: onOpen) {
                Image(systemName: "book.closed")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help(l10n.text("Open this ayah in the Quran"))
            .accessibilityLabel(l10n.text("Open this ayah in the Quran"))
            .accessibilityIdentifier("reminder.open")

            if !isPreview,
               (content.kind == .surah || content.kind == .automatic),
               !store.settings.autoAdvance {
                Button(action: onRead) {
                    Label(l10n.text("Read & continue"), systemImage: "checkmark")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .help(l10n.text("Read & continue"))
                .accessibilityLabel(l10n.text("Read & continue"))
                .accessibilityIdentifier("reminder.continue")
                .keyboardShortcut(.return, modifiers: [])
            }
        }
    }
}
