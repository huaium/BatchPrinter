import SwiftUI

@main
struct BatchPrinterApp: App {
    @StateObject private var viewModel = MainViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 1080, minHeight: 860)
        }
        .defaultSize(width: 1240, height: 860)
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
