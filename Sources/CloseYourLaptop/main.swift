import AppKit

if let status = HiddenCLI.runIfRequested() {
    exit(status)
}

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.run()
