import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var spaceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        requestAccessibilityPermission()

        if !SpaceEngine.shared.start() {
            showPermissionAlert()
            retryEngineStart()
        }

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            SpaceEngine.shared.resetPredictions()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        SpaceEngine.shared.stop()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = menuBarIcon()
            button.image?.size = NSSize(width: 18, height: 18)
        }

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Ctrl + ← / → to switch instantly",
            action: nil,
            keyEquivalent: ""
        ).isEnabled = false
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit SPACE",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        statusItem?.menu = menu
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func menuBarIcon() -> NSImage? {
        let image = NSImage(
            systemSymbolName: "arrow.left.arrow.right.square",
            accessibilityDescription: "SPACE"
        )
        image?.isTemplate = true
        return image
    }

    private func requestAccessibilityPermission() {
        guard !AXIsProcessTrusted() else { return }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func retryEngineStart() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            if SpaceEngine.shared.start() { return }
            self.retryEngineStart()
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        SPACE needs Accessibility access to intercept Ctrl + arrow keys and switch spaces instantly.

        Open System Settings → Privacy & Security → Accessibility, enable SPACE, then relaunch.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
