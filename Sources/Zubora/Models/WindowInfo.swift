import Cocoa
import ApplicationServices

struct WindowInfo: Identifiable, Equatable {
    let id: CGWindowID
    let element: AXUIElement
    let app: NSRunningApplication
    let frame: CGRect
    let title: String
    
    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        return lhs.id == rhs.id
    }
    
    // Helper to activate this specific window
    @MainActor
    func activate() {
        AccessibilityService.shared.activateWindow(element)
    }
}
