# Code Structure
- `BatchPrinter/BatchPrinterApp.swift`: app entry point and window sizing.
- `BatchPrinter/ContentView.swift`: primary SwiftUI UI (controls, table queue, logs, dialogs/popovers).
- `BatchPrinter/ViewModels/MainViewModel.swift`: app state + workflows (scan, preprocess, print, cancel, logs).
- `BatchPrinter/Services/FileScanner.swift`: recursive/non-recursive file discovery and filtering.
- `BatchPrinter/Services/WordPrinter.swift`: Word AppleScript automation, PDF print/export/page-range handling.
- `BatchPrinter/Models/PrintJob.swift`: queue item model and status metadata.
- `BatchPrinter/Utilities/LogStore.swift`: in-memory line-based logging for UI display/copy.