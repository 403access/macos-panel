import Foundation

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot: Snapshot = .empty
    @Published private(set) var devices: [DeviceBattery] = []
    @Published private(set) var needsInputMonitoring = false

    @Published var refreshInterval: TimeInterval {
        didSet {
            guard refreshInterval != oldValue else { return }
            UserDefaults.standard.set(refreshInterval, forKey: Keys.refreshInterval)
            startTimer()
        }
    }

    private var timer: Timer?
    private let batteryQueue = DispatchQueue(label: "dev.olivermolnar.macos-panel.battery", qos: .utility)
    private var lastBatteryRefresh = Date.distantPast
    private var isReadingBatteries = false
    private let batteryRefreshInterval: TimeInterval = 30

    private enum Keys {
        static let refreshInterval = "refreshInterval"
    }

    init() {
        let stored = UserDefaults.standard.object(forKey: Keys.refreshInterval) as? Double
        refreshInterval = stored ?? 2
        refresh()
        startTimer()
    }

    func refresh() {
        snapshot = SystemSampler.snapshot()
        refreshDevices()
    }

    /// Reads peripheral charge levels on a background queue. Wireless device batteries change
    /// slowly, so this runs on its own cadence instead of with every system sample.
    func refreshDevices(force: Bool = false) {
        guard !isReadingBatteries else { return }
        if !force, Date().timeIntervalSince(lastBatteryRefresh) < batteryRefreshInterval { return }

        isReadingBatteries = true
        lastBatteryRefresh = Date()

        batteryQueue.async { [weak self] in
            let reading = DeviceBatterySampler.read()
            DispatchQueue.main.async {
                guard let self else { return }
                self.devices = reading.devices
                self.needsInputMonitoring = reading.needsInputMonitoring
                self.isReadingBatteries = false
            }
        }
    }

    /// Asks macOS for Input Monitoring and retries the Logitech battery read.
    func requestInputMonitoring() {
        _ = HIDAccess.request()
        refreshDevices(force: true)
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        timer.tolerance = min(0.5, refreshInterval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
