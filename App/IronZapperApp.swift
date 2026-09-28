import SwiftUI
import AppKit

@main struct IronZapperApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Use this build's compiled icon for the running app instead of a stale
        // Launch Services rendition left over from a previous local build.
        if let iconURL = Bundle.main.url(forResource: "IronAppIcon", withExtension: "icns") {
            NSApp.applicationIconImage = NSImage(contentsOf: iconURL)
        }
        if CommandLine.arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if CommandLine.arguments.contains("--light") { NSApp.appearance = NSAppearance(named: .aqua) }
        let controller = NSHostingController(rootView: ContentView(model: model))
        // Let NSWindow own the outer edge and corner clipping. A full-window
        // NSGlassEffectView adds a second refractive rim with competing corners.
        let backdrop = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 600, height: 640))
        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .followsWindowActiveState
        controller.view.frame = backdrop.bounds
        controller.view.autoresizingMask = [.width, .height]
        backdrop.addSubview(controller.view)
        let contentController = NSViewController()
        contentController.addChild(controller)
        contentController.view = backdrop
        let window = NSWindow(contentViewController: contentController)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.title = "Iron Zapper"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.toolbar = NSToolbar(identifier: "IronZapperToolbar")
        window.setContentSize(NSSize(width: 600, height: 640))
        window.minSize = NSSize(width: 540, height: 550)
        window.center(); window.delegate = self; window.isReleasedWhenClosed = false
        self.window = window
        installMenu()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let index = CommandLine.arguments.firstIndex(of: "--scan"), CommandLine.arguments.count > index + 1 {
            model.scan(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--capture"), CommandLine.arguments.count > index + 1 {
            let path = CommandLine.arguments[index + 1]
            Task { @MainActor in
                for _ in 0..<120 { try? await Task.sleep(for: .milliseconds(500)); if model.phase != .scanning { break } }
                try? await Task.sleep(for: .seconds(2))
                let content = ContentView(model: self.model)
                    .frame(width: 600, height: 640)
                    .environment(\.colorScheme, CommandLine.arguments.contains("--dark") ? .dark : .light)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff) {
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
            }
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.count == 1, let url = urls.first else { model.errorMessage = "Drop one application at a time."; return }
        model.scan(url); window?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window?.makeKeyAndOrderFront(nil); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowShouldClose(_ sender: NSWindow) -> Bool { canClose() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { canClose() ? .terminateNow : .terminateCancel }
    private func canClose() -> Bool {
        guard model.phase != .removing else {
            let alert = NSAlert(); alert.messageText = "Cleanup is still running"; alert.informativeText = "Wait for the result before closing Iron Zapper."; alert.runModal(); return false
        }
        return true
    }
    private func installMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(title: "Iron Zapper"); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Iron Zapper", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        item("Enable System Cleanup…", action: #selector(enableHelper), to: appMenu)
        item("Disable System Cleanup", action: #selector(disableHelper), to: appMenu)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Iron Zapper", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Iron Zapper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileItem = NSMenuItem(); menu.addItem(fileItem)
        let file = NSMenu(title: "File"); fileItem.submenu = file
        item("Choose Application…", action: #selector(choose), key: "o", to: file)
        item("Start Over", action: #selector(reset), key: "n", to: file)
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let editItem = NSMenuItem(); menu.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = menu
    }
    private func item(_ title: String, action: Selector, key: String = "", to menu: NSMenu) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key); item.target = self
    }
    @objc private func choose() { if !model.busy { model.choose() } }
    @objc private func reset() { model.reset() }
    @objc private func enableHelper() { if !model.busy { model.enableHelper() } }
    @objc private func disableHelper() { if !model.busy { model.disableHelper() } }
}
