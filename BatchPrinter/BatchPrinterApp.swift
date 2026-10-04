import SwiftUI

@main
struct BatchPrinterApp: App {
  @StateObject private var viewModel = MainViewModel()
  @AppStorage(L10n.languagePreferenceKey) private var selectedLanguage = L10n.Language.system
    .rawValue

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(viewModel)
        .environment(\.locale, L10n.locale(for: selectedLanguage))
        .frame(minWidth: 1120, minHeight: 840)
    }
    .defaultSize(width: 1200, height: 900)
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.automatic)

    Window(L10n.tr("help.menu.title"), id: HelpView.windowID) {
      HelpView()
        .environment(\.locale, L10n.locale(for: selectedLanguage))
        .frame(minWidth: 700, minHeight: 520)
    }
    .defaultSize(width: 760, height: 620)
    .commands {
      CommandGroup(replacing: .newItem) {}
      BatchPrinterHelpCommands()
    }
  }
}

private struct BatchPrinterHelpCommands: Commands {
  @Environment(\.openWindow) private var openWindow
  @AppStorage(L10n.languagePreferenceKey) private var selectedLanguage = L10n.Language.system
    .rawValue

  private var helpMenuTitle: String {
    String(
      localized: String.LocalizationValue("help.menu.title"),
      bundle: .main,
      locale: L10n.locale(for: selectedLanguage)
    )
  }

  var body: some Commands {
    CommandGroup(replacing: .help) {
      Button(helpMenuTitle) {
        openWindow(id: HelpView.windowID)
      }
      .keyboardShortcut("/", modifiers: [.command, .shift])
    }
  }
}
