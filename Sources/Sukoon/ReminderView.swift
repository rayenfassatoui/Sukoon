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
                .foregroundStyle(.tertiary)
                .padding(6)
                .help(l10n.text("Resize reminder", table: "Workspace"))
                .accessibilityLabel(l10n.text("Resize reminder", table: "Workspace"))
        }
        .background(palette.canvas)
        .clipShape(.rect(cornerRadius: 18))
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
                .buttonStyle(.plain)
                .foregroundStyle(
                    store.isBookmarked(surahID: reference.surahID, verseID: reference.verseID)
                        ? palette.gold
                        : palette.accent
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
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
                .help(l10n.text("Read & continue"))
                .accessibilityLabel(l10n.text("Read & continue"))
                .accessibilityIdentifier("reminder.continue")
                .keyboardShortcut(.return, modifiers: [])
            }
        }
    }
}
