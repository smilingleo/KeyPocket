import Foundation
import WatchConnectivity

@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    var onReceive: ((Data) -> Void)?
    private var pending: Data?
    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func send(_ data: Data) throws {
        guard WCSession.isSupported() else { throw NSError(domain: "Watch", code: 1, userInfo: [NSLocalizedDescriptionKey: "当前设备不支持手表同步"]) }
        pending = data
        if WCSession.default.activationState == .activated {
            try WCSession.default.updateApplicationContext(["keyPocket": data])
            pending = nil
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext["keyPocket"] as? Data
        Task { @MainActor in
            if activationState == .activated, let data = self.pending {
                try? session.updateApplicationContext(["keyPocket": data]); self.pending = nil
            }
            if let context { self.onReceive?(context) }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["keyPocket"] as? Data else { return }
        Task { @MainActor in self.onReceive?(data) }
    }
#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) { }
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
#endif
}
