import AppKit
import SukoonCore

@main
@MainActor
struct SukoonApp {
    static func main() {
        let application = NSApplication.shared
        do {
            let library = try QuranLibrary.load()
            let controller = AppController(store: AppStore(library: library))
            application.delegate = controller
            withExtendedLifetime(controller) { application.run() }
        } catch {
            let l10n = AppLocalization(language: AppStore.savedLanguage())
            application.setActivationPolicy(.regular)
            application.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = l10n.text("Sukoon couldn’t open the Quran library")
            alert.informativeText = l10n.text("The bundled Quran resource could not be loaded. Please rebuild or reinstall the complete app.")
                + "\n\n" + l10n.libraryError(error)
            alert.alertStyle = .critical
            alert.addButton(withTitle: l10n.text("Quit"))
            alert.runModal()
        }
    }

}
