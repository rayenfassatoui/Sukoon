import SwiftUI
import SukoonCore

struct QuranFontPicker: View {
    @Environment(\.sukoonLocalization) private var l10n
    @Environment(\.sukoonPalette) private var palette
    @Bindable var store: AppStore
    @State private var fonts = QuranFonts.shared
    @State private var isPresented = false
    @FocusState private var isListFocused: Bool

    private var selectedName: String {
        fonts.resolvedFontName(store.settings.quranFontName)
    }

    private var selectedFont: QuranFontOption? {
        fonts.options.first { $0.id == selectedName }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { selectedName },
            set: { name in
                if let name { store.settings.quranFontName = name }
            }
        )
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                Text(selectedFont?.name ?? selectedName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
        }
        .buttonStyle(.bordered)
        .frame(minWidth: 140, idealWidth: 180, maxWidth: 240)
        .help(l10n.text("Choose a font and preview it", table: "Preferences"))
        .accessibilityLabel(l10n.text("Quran font", table: "Preferences"))
        .accessibilityValue(selectedFont?.name ?? selectedName)
        .accessibilityIdentifier("settings.quranFont")
        .popover(isPresented: $isPresented) {
            chooser
        }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(l10n.text("Quran font", table: "Preferences"))
                    .font(.headline)
                Spacer()
                Button(l10n.text("Done", table: "Preferences")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }

            Text(l10n.text("Select a font to preview it. Changes apply immediately.", table: "Preferences"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(selection: selection) {
                ForEach(fonts.options) { font in
                    Button {
                        store.settings.quranFontName = font.id
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(font.name)
                                if font.isBundled {
                                    Text(l10n.text("Included with Sukoon", table: "Preferences"))
                                        .font(.caption)
                                        .foregroundStyle(font.id == selectedName ? Color.white.opacity(0.85) : Color.secondary)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if font.id == selectedName {
                                Image(systemName: "checkmark")
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(font.id == selectedName ? Color.white : palette.primary)
                    .accessibilityLabel(font.name)
                    .accessibilityAddTraits(font.id == selectedName ? .isSelected : [])
                    .tag(font.id)
                }
            }
            .listStyle(.inset)
            .tint(palette.controlAccent)
            .frame(height: 220)
            .focused($isListFocused)
            .accessibilityLabel(l10n.text("Available Quran fonts", table: "Preferences"))
            .accessibilityIdentifier("settings.fontChoices")

            Divider()

            if let surah = store.library.surah(1), let verse = surah.verses.first {
                Text(selectedFont?.name ?? selectedName)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    ArabicText(verse.text, size: store.settings.arabicFontSize)
                        .environment(\.sukoonQuranFontName, selectedName)
                        .padding(.vertical, 4)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 180)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.fontChoicePreview")
                Text(l10n.format(
                    "Quran %@ · %@",
                    l10n.reference(VerseReference(surahID: surah.id, verseID: verse.id)),
                    l10n.surahName(surah),
                    table: "Preferences"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 440)
        .background(palette.canvas)
        .environment(\.layoutDirection, l10n.isArabic ? .rightToLeft : .leftToRight)
        .defaultFocus($isListFocused, true)
    }
}
