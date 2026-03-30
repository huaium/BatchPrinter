import SwiftUI

@main
struct BatchPrinterApp: App {
    @StateObject private var viewModel = MainViewModel()
    @AppStorage(L10n.languagePreferenceKey) private var selectedLanguage = L10n.Language.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environment(\.locale, L10n.locale(for: selectedLanguage))
                .frame(minWidth: 1080, minHeight: 860)
        }
        .defaultSize(width: 1240, height: 860)
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
