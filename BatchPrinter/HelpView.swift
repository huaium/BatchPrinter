import AppKit
import SwiftUI

struct HelpView: View {
    static let windowID = "help-window"
    @AppStorage(L10n.languagePreferenceKey) private var selectedLanguage = L10n.Language.system.rawValue
    @State private var window: NSWindow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("help.menu.title")
                    .font(.largeTitle.bold())

                Text("help.subtitle")
                    .foregroundStyle(.secondary)

                helpSection(
                    "help.quick_start.title",
                    [
                        "help.quick_start.step1",
                        "help.quick_start.step2",
                        "help.quick_start.step3",
                        "help.quick_start.step4"
                    ]
                )

                helpSection(
                    "help.preprocess.title",
                    [
                        "help.preprocess.line1",
                        "help.preprocess.line2"
                    ]
                )

                helpSection(
                    "help.permissions.title",
                    [
                        "help.permissions.line1"
                    ]
                )

                helpSection(
                    "help.logs.title",
                    [
                        "help.logs.line1"
                    ]
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .background(
            WindowAccessor { nsWindow in
                window = nsWindow
                updateWindowTitle()
            }
        )
        .onChange(of: selectedLanguage) { _ in
            updateWindowTitle()
        }
    }

    @ViewBuilder
    private func helpSection(_ titleKey: LocalizedStringKey, _ lineKeys: [LocalizedStringKey]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titleKey)
                .font(.title3.weight(.semibold))
            ForEach(lineKeys.indices, id: \.self) { index in
                Text(lineKeys[index])
            }
        }
    }

    private func updateWindowTitle() {
        guard let window else { return }
        window.title = String(
            localized: String.LocalizationValue("help.menu.title"),
            bundle: .main,
            locale: L10n.locale(for: selectedLanguage)
        )
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onResolve(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView.window)
        }
    }
}
