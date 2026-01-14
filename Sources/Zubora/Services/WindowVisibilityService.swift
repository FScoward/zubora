import Cocoa
import ApplicationServices

@MainActor
class WindowVisibilityService {
    static let shared = WindowVisibilityService()
    
    enum WindowVisibility {
        case visible
        case covered
        case notOnScreen
    }

    /// Check the visibility state of the target window
    /// - Parameter excludeWindowID: Optional window ID to exclude from coverage check (e.g., highlight window)
    func checkWindowVisibility(element: AXUIElement, excludeWindowID: CGWindowID? = nil) -> WindowVisibility {
        guard let targetFrame = AccessibilityService.shared.getWindowFrame(element: element) else {
            return .notOnScreen
        }
        
        let allWindows = fetchOnScreenWindows()
        
        // Find the target window in the list by matching its frame/ID
        guard let (targetIndex, _) = findTargetInList(allWindows, element: element, targetFrame: targetFrame, excludeWindowID: excludeWindowID) else {
             // Target window not found in list -> Not on current visible screen
             return .notOnScreen
        }
        
        // Check all windows above the target (lower index = higher in z-order)
        if isObscured(targetFrame: targetFrame, windowsAbove: allWindows.prefix(targetIndex), excludeWindowID: excludeWindowID) {
            return .covered
        }
        
        return .visible
    }
    
    // MARK: - Visibility Helpers
    
    // Internal struct for visibility check (differs slightly from CGWindow due to layer/alpha needs)
    private struct VisibleWindow {
        let id: CGWindowID
        let frame: CGRect
        let layer: Int
        let alpha: Double
    }
    
    private func fetchOnScreenWindows() -> [VisibleWindow] {
        guard let windowInfos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        return windowInfos.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"], let y = boundsDict["Y"],
                  let w = boundsDict["Width"], let h = boundsDict["Height"] else { return nil }
            
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1.0
            
            return VisibleWindow(id: id, frame: CGRect(x: x, y: y, width: w, height: h), layer: layer, alpha: alpha)
        }
    }
    
    private func findTargetInList(_ windows: [VisibleWindow], element: AXUIElement, targetFrame: CGRect, excludeWindowID: CGWindowID?) -> (Int, VisibleWindow)? {
        // Pre-calculate target frame props for fast matching
        let tx = targetFrame.origin.x
        let ty = targetFrame.origin.y
        let tw = targetFrame.width
        let th = targetFrame.height
        
        let targetID = AccessibilityService.shared.getWindowID(element: element)
        
        for (index, window) in windows.enumerated() {
            // Match by ID
            if let targetID = targetID, window.id == targetID {
                return (index, window)
            }
            
            // Match by Frame
            // Check if this window's frame matches the target frame (with small tolerance)
            if abs(window.frame.origin.x - tx) < 10 &&
               abs(window.frame.origin.y - ty) < 10 &&
               abs(window.frame.width - tw) < 10 &&
               abs(window.frame.height - th) < 10 {
                
                // Skip our own highlight window if it accidentally matches frame
                if let excludeID = excludeWindowID, window.id == excludeID {
                    continue
                }
                
                return (index, window)
            }
        }
        return nil
    }
    
    private func isObscured(targetFrame: CGRect, windowsAbove: ArraySlice<VisibleWindow>, excludeWindowID: CGWindowID?) -> Bool {
        for window in windowsAbove {
            // Skip the excluded window (e.g., our highlight window)
            if let excludeID = excludeWindowID, window.id == excludeID {
                continue
            }
            
            // Skip small windows
            if window.frame.width < 10 || window.frame.height < 10 { continue }
            
            // Skip invisible windows
            if window.alpha < 0.05 { continue }
            
            // Skip system windows (Menu Bar, Dock, etc are usually Layer > 10)
            if window.layer >= 10 { continue }
            
            // Check coverage
            if checkCoverage(targetFrame: targetFrame, obscuringFrame: window.frame) {
                return true
            }
        }
        return false
    }
    
    private func checkCoverage(targetFrame: CGRect, obscuringFrame: CGRect) -> Bool {
        let intersection = obscuringFrame.intersection(targetFrame)
        if !intersection.isNull {
            let overlapArea = intersection.width * intersection.height
            let targetArea = targetFrame.width * targetFrame.height
            
            // Avoid division by zero
            if targetArea <= 0 { return false }
            
            let overlapPercent = overlapArea / targetArea

            // If overlap is more than 0.5% of target area, consider it covered
            if overlapPercent > 0.005 {
                return true
            }
        }
        return false
    }
}
