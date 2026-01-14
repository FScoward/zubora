import Foundation
import Sparkle
import os

@MainActor
class UpdateManager: NSObject {
    static let shared = UpdateManager()
    private var updaterController: SPUStandardUpdaterController?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fscoward.zubora", category: "Update")

    override init() {
        super.init()
        // Initialize the updater controller with the default bundle
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }
    
    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}

extension UpdateManager: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fscoward.zubora", category: "Update")
        logger.error("Sparkle Update Error: \(error.localizedDescription, privacy: .public)")
    }
    
    nonisolated func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fscoward.zubora", category: "Update")
        logger.error("Sparkle Download Error: \(error.localizedDescription, privacy: .public)")
    }
    
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fscoward.zubora", category: "Update")
        logger.info("Sparkle found valid update: \(item.displayVersionString, privacy: .public)")
    }
    
    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fscoward.zubora", category: "Update")
        logger.info("Sparkle did not find any updates")
    }
}
