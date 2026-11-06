import AppKit

@main
struct MenuBarLyricsMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = MenuBarLyricsApp()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
