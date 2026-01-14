import Cocoa
import ApplicationServices

@MainActor
class WindowDiscoveryService {
    static let shared = WindowDiscoveryService()
    
    // MARK: - Caching
    private var appElementCache: [pid_t: AXUIElement] = [:]
    
    // MARK: - Discovery
    
    func getVisibleWindows() -> [WindowInfo] {
        // 1. Get list of all visual windows on screen
        let visibleCGWindows = fetchCGWindows()
        
        var availableCGWindows = visibleCGWindows // Copy matched candidates
        var results: [WindowInfo] = []
        
        // Use standard NSRunningApplication to filter for regular apps
        let myPID = NSRunningApplication.current.processIdentifier
        
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            
            // Skip own app
            if app.processIdentifier == myPID || app.localizedName == "Zubora" {
                continue
            }
            
            let appWindows = processApplication(app, availableWindows: &availableCGWindows)
            results.append(contentsOf: appWindows)
        }
        
        print("DEBUG: WindowDiscoveryService found \(results.count) windows")
        
        // Re-order results based on visibleCGWindows order (z-order)
        let orderedResults = visibleCGWindows.compactMap { cgWin in
            results.first { $0.id == cgWin.id }
        }
        
        return orderedResults
    }
    
    private func getAppElement(_ pid: pid_t) -> AXUIElement {
        if let element = appElementCache[pid] {
            return element
        }
        let element = AXUIElementCreateApplication(pid)
        appElementCache[pid] = element
        return element
    }
    
    private func processApplication(_ app: NSRunningApplication, availableWindows: inout [CGWindow]) -> [WindowInfo] {
        var appResults: [WindowInfo] = []
        let pid = app.processIdentifier
        let appElement = getAppElement(pid)
        
        var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let appWindows = windowsRef as? [AXUIElement] {
            
            for windowElement in appWindows {
                // Minimized check
                var minimizedVal: AnyObject?
                if AXUIElementCopyAttributeValue(windowElement, kAXMinimizedAttribute as CFString, &minimizedVal) == .success,
                   let minimized = minimizedVal as? Bool, minimized {
                    continue
                }
                
                guard let index = findMatchingCGWindow(element: windowElement, pid: pid, availableWindows: availableWindows) else {
                    continue
                }
                
                let match = availableWindows[index]
                // Remove from pool to prevent reuse
                availableWindows.remove(at: index)
                
                let title = AccessibilityService.shared.getTitle(element: windowElement)
                let info = WindowInfo(
                    id: match.id,
                    element: windowElement,
                    app: app,
                    frame: match.frame,
                    title: title
                )
                appResults.append(info)
            }
        }
        return appResults
    }
    
    private func findMatchingCGWindow(element: AXUIElement, pid: pid_t, availableWindows: [CGWindow]) -> Int? {
        // 1. Try ID Match
        if let axID = AccessibilityService.shared.getWindowID(element: element) {
            if let index = availableWindows.firstIndex(where: { $0.id == axID }) {
                return index
            }
        }
        
        // 2. Try Frame Match (if no ID match)
        guard let axFrame = AccessibilityService.shared.getWindowFrame(element: element) else { return nil }
        
        // Relaxed frame matching
        let tolerance: CGFloat = 5.0
        let matchedIndex = availableWindows.firstIndex { cgWin in
            let match = cgWin.ownerPID == pid &&
                        abs(cgWin.frame.origin.x - axFrame.origin.x) <= tolerance &&
                        abs(cgWin.frame.origin.y - axFrame.origin.y) <= tolerance &&
                        abs(cgWin.frame.width - axFrame.width) <= tolerance &&
                        abs(cgWin.frame.height - axFrame.height) <= tolerance
            return match
        }
        
        return matchedIndex
    }
    
    // MARK: - CGWindow Helpers
    
    private struct CGWindow {
        let id: CGWindowID
        let frame: CGRect
        let ownerPID: pid_t
    }
    
    private func fetchCGWindows() -> [CGWindow] {
        guard let windowInfos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        return windowInfos.compactMap { info -> CGWindow? in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w > 10, h > 10 else { return nil }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.1 { return nil }
            guard let id = info[kCGWindowNumber as String] as? CGWindowID else { return nil }
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32 else { return nil }
            
            return CGWindow(id: id, frame: CGRect(x: x, y: y, width: w, height: h), ownerPID: pid)
        }
    }
}
