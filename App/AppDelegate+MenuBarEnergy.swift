import AppKit

/// What this app draws now, beside the menu bar icon when Settings › General asks for it and in the
/// menu bar panel's Energy use row while that is open (`MenuBarEnergyMeter`). The figure follows the
/// choice at once (`MenuBarEnergyPreference.didChangeNotification`) and stops while nobody is at the
/// Mac (`WallpaperPresentationPolicy.onAttendanceChanged`).
extension AppDelegate {
    func makeMenuBarEnergy() -> MenuBarEnergyMeter {
        let monitor = EnergyUsageMonitor()
        // What the engine routed to the native player, as Settings' readout asks.
        monitor.nativeVideoPlaying = { [weak self] in
            self?.store?.settingsSnapshot.videoBackends.contains { $0.backend == "native" } ?? false
        }
        return MenuBarEnergyMeter(monitor: monitor, showsInMenuBar: MenuBarEnergyPreference.isOn())
    }

    /// After the status item exists.
    func installMenuBarEnergy() {
        menuBarEnergy.onChange = { [weak self] in self?.updateStatusItemEnergy() }
        menuBarEnergyObserver = NotificationCenter.default.addObserver(
            forName: MenuBarEnergyPreference.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuBarEnergy.setShowsInMenuBar(MenuBarEnergyPreference.isOn()) }
        }
        updateStatusItemEnergy()
    }

    /// The icon alone, or the icon and the figure in the menu bar's font with steady digits. A
    /// figure a caveat qualifies (a plain video, a busy GPU) is drawn dimmed; the tooltip says why.
    func updateStatusItemEnergy() {
        guard let item = statusItem, let button = item.button else { return }
        let readout = EnergyReadout(
            reading: menuBarEnergy.reading, comparison: nil, batteryCapacityWattHours: menuBarEnergy.batteryCapacity)
        guard menuBarEnergy.showsTitle, let title = readout.menuBarTitle() else {
            guard item.length != NSStatusItem.squareLength else { return }
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = nil
            item.length = NSStatusItem.squareLength
            return
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if !readout.caveats.isEmpty { attributes[.foregroundColor] = NSColor.secondaryLabelColor }
        let text = NSAttributedString(string: title, attributes: attributes)
        if button.attributedTitle != text { button.attributedTitle = text }
        let help = readout.summary
        if button.toolTip != help { button.toolTip = help }
        if button.imagePosition != .imageLeading { button.imagePosition = .imageLeading }
        if item.length != NSStatusItem.variableLength { item.length = NSStatusItem.variableLength }
    }
}
