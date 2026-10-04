# List available commands.
default:
    @just --list

# Format all app and test Swift files.
format:
    xcrun swift-format format --in-place --recursive BatchPrinter BatchPrinterTests

# Check Swift formatting without changing files.
lint:
    xcrun swift-format lint --strict --recursive BatchPrinter BatchPrinterTests
