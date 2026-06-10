import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var spaceObserver: NSObjectProtocol?
    private var launchAtLoginItem: NSMenuItem?
    private var animationToggleItem: NSMenuItem?
    private var speedLabel: NSTextField?
    private var speedSlider: NSSlider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        SpaceEngine.shared.loadSavedSettings()
        setupMenuBar()
        requestAccessibilityPermission()
        startEngineOrRetry()

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
            withTitle: "Swipe or Ctrl + ← / → to switch instantly",
            action: nil,
            keyEquivalent: ""
        ).isEnabled = false
        menu.addItem(.separator())
        menu.addItem(makeLaunchAtLoginItem())
        menu.addItem(.separator())
        menu.addItem(makeAnimationToggleItem())
        menu.addItem(makeSpeedSliderItem())
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

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Failed to update Launch at Login: \(error.localizedDescription)")
        }

        updateLaunchAtLoginMenuState()
    }

    @objc private func toggleAnimation() {
        SpaceEngine.shared.animationEnabled.toggle()
        updateAnimationMenuState()
    }

    @objc private func speedSliderChanged(_ sender: NSSlider) {
        SpaceEngine.shared.animationSpeed = sender.doubleValue
        updateAnimationMenuState()
    }

    private func makeLaunchAtLoginItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        item.target = self
        launchAtLoginItem = item
        updateLaunchAtLoginMenuState()
        return item
    }

    private func makeAnimationToggleItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Animate Switch",
            action: #selector(toggleAnimation),
            keyEquivalent: ""
        )
        item.target = self
        animationToggleItem = item
        updateAnimationMenuState()
        return item
    }

    private func makeSpeedSliderItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 54))

        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 24, y: 30, width: 272, height: 17)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.alignment = .center
        container.addSubview(label)

        let slider = NSSlider(
            value: SpaceEngine.shared.animationSpeed,
            minValue: 1.0,
            maxValue: 100.0,
            target: self,
            action: #selector(speedSliderChanged(_:))
        )
        slider.frame = NSRect(x: 48, y: 5, width: 224, height: 24)
        slider.isContinuous = true
        container.addSubview(slider)

        speedLabel = label
        speedSlider = slider

        let item = NSMenuItem()
        item.view = container
        updateAnimationMenuState()
        return item
    }

    private func updateAnimationMenuState() {
        let animationEnabled = SpaceEngine.shared.animationEnabled
        let speed = SpaceEngine.shared.animationSpeed

        animationToggleItem?.state = animationEnabled ? .on : .off
        speedSlider?.doubleValue = speed
        speedSlider?.isEnabled = animationEnabled
        speedLabel?.stringValue = "Switch Speed: \(Int(speed.rounded()))%"
        speedLabel?.textColor = animationEnabled ? .labelColor : .disabledControlTextColor
    }

    private func updateLaunchAtLoginMenuState() {
        launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
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

    private func startEngineOrRetry() {
        if AXIsProcessTrusted() {
            if SpaceEngine.shared.start() { return }
        }

        retryEngineStart()
    }

    private func retryEngineStart() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            if SpaceEngine.shared.isRunning { return }
            self.startEngineOrRetry()
        }
    }
}
