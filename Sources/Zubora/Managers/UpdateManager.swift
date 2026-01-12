import Foundation
import Sparkle

@MainActor
class UpdateManager: NSObject {
    static let shared = UpdateManager()
    private var updaterController: SPUStandardUpdaterController?

    override init() {
        super.init()
        // Initialize the updater controller with the default bundle
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    
    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
