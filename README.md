# BatchPrinter

A native macOS app for scanning, preprocessing, and batch printing local Word and PDF files.

## Features

- Choose a folder containing printable files.
- Automatically refresh file list right after selecting a folder.
- Manual refresh via `Refresh Files`.
- Optional recursive scan via `Scan subfolders`.
- Logs whether subfolder scan is On/Off for each scan run.
- Supports `.doc`, `.docx`, `.docm`, `.dot`, `.dotx`, `.dotm`, `.pdf`.
- Skips hidden files and Word lock/temp files (`~$...`).
- Queue management with per-file status, selection, and logs.
- Queue sorting by clicking the `File` table header (ascending/descending).
- Preprocess flow asks output destination each run:
  - system temporary folder
  - user-selected folder
- Page range support:
  - single page: `3`
  - range: `2-6`
  - comma-separated explicit pages: `1,2,5` or `4, 2, 1`
  - whitespace is ignored
- For explicit page lists, print order is preserved exactly as entered.
- Cancel support during runs (cooperative between files).

## How Printing Works

- Word documents are automated through Microsoft Word via AppleScript to preserve Word rendering fidelity.
- PDF inputs can be printed directly or used in preprocess/output flows.
- `Print to PDF` output mode is supported.

## Project Structure

- `BatchPrinter.xcodeproj` — Xcode project.
- `BatchPrinter/` — app source code.
  - `BatchPrinterApp.swift`
  - `ContentView.swift`
  - `Models/PrintJob.swift`
  - `Services/FileScanner.swift`
  - `Services/WordPrinter.swift`
  - `ViewModels/MainViewModel.swift`
  - `Utilities/LogStore.swift`

## Requirements

- macOS 13+
- Xcode 16+ (Swift 6 language mode)
- Microsoft Word for Mac installed (for Word automation/Word source printing)

## Run

1. Open `BatchPrinter.xcodeproj` in Xcode.
2. Configure signing team if prompted.
3. Build and run.
4. Allow Automation permission when prompted for Microsoft Word.

## Behavior Notes

- Printing is silent (no print dialog).
- Word may come to foreground while automated actions run.
- Word source files already open in Word are skipped with an error; save and close
  them before running BatchPrinter. Automation opens sources read-only and targets
  the specific document, including cleanup after an export or print error.
- If Word shows modal dialogs, queue progress can pause until dismissed.
- During active print/preprocess runs, folder selection and scan refresh are blocked to avoid state corruption.

## Known Constraints

- Cancellation is best-effort and typically takes effect between files.
- Temporary-folder cleanup is controlled by macOS when system temp output is selected.
