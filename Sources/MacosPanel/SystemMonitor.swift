import Foundation

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot: Snapshot = .empty

    @Published var refreshInterval: TimeInterval {
        didSet {
            guard refreshInterval != oldValue else { return }
            UserDefaults.standard.set(refreshInterval, forKey: Keys.refreshInterval)
            startTimer()
        }
    }

    private var timer: Timer?

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
