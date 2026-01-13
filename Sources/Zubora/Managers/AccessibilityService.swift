import ApplicationServices
import CoreGraphics
import Foundation
import AppKit

@MainActor
class AccessibilityService {
    static let shared = AccessibilityService()
    
    // MARK: - Caching
    private let systemWideElement = AXUIElementCreateSystemWide() // Restored
    private var appElementCache: [pid_t: AXUIElement] = [:]
    
    private func getAppElement(_ pid: pid_t) -> AXUIElement {
        if let element = appElementCache[pid] {
            return element
        }
        let element = AXUIElementCreateApplication(pid)
        appElementCache[pid] = element
        return element
    }

    /// Get all visible windows from regular applications
    func getVisibleWindows() -> [WindowInfo] {
        // 1. Get list of all visual windows on screen
        guard let windowInfos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        // Structure to hold CGWindowList data
        struct CGWindow {
            let id: CGWindowID
            let frame: CGRect
            let ownerPID: pid_t
        }
        
        let visibleCGWindows: [CGWindow] = windowInfos.compactMap { info -> CGWindow? in
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
        
        var results: [WindowInfo] = []
        
        // 2. Iterate running apps
        // 2. Iterate running apps
        var availableCGWindows = visibleCGWindows // Copy matched candidates
        
        let myPID = NSRunningApplication.current.processIdentifier
        // print("DEBUG: Current App PID: \(myPID)")
        
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            
            // Skip own app to avoid self-inception
            if app.processIdentifier == myPID || app.localizedName == "Zubora" {
                print("DEBUG: Skipping own app (PID \(app.processIdentifier), Name: \(app.localizedName ?? "nil"))")
                continue
            }
            
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
                    
                    // Match AXElement to CGWindow
                    var matchedIndex: Int? = nil
                    
                    // 1. Try ID Match
                    if let axID = getWindowID(element: windowElement) {
                        matchedIndex = availableCGWindows.firstIndex { $0.id == axID }
                        if matchedIndex != nil {
                           // print("DEBUG: MATCHED via ID: \(axID)")
                        }
                    }
                    
                    // 2. Try Frame Match (if no ID match)
                    if matchedIndex == nil, let axFrame = getWindowFrame(element: windowElement) {
                        // Relaxed frame matching
                        let tolerance: CGFloat = 5.0
                        matchedIndex = availableCGWindows.firstIndex { cgWin in
                            let match = cgWin.ownerPID == pid &&
                                        abs(cgWin.frame.origin.x - axFrame.origin.x) <= tolerance &&
                                        abs(cgWin.frame.origin.y - axFrame.origin.y) <= tolerance &&
                                        abs(cgWin.frame.width - axFrame.width) <= tolerance &&
                                        abs(cgWin.frame.height - axFrame.height) <= tolerance
                            
                            if match {
                                print("DEBUG: Frame Match Success: AX \(axFrame) vs CG \(cgWin.frame)")
                            }
                            return match
                        }
                        
                        if matchedIndex != nil {
                            print("DEBUG: MATCHED via FRAME: \(getTitle(element: windowElement)) to CGWindow \(matchedIndex!)")
                        }
                    }
                    
                    if let axID = getWindowID(element: windowElement), matchedIndex == nil {
                        // Log failure to find ID match if we have an ID
                         print("DEBUG: Failed to match AXID \(axID) for \(getTitle(element: windowElement))")
                    }
                    
                    if let index = matchedIndex {
                        let match = availableCGWindows[index]
                        // Remove from pool to prevent reuse
                        availableCGWindows.remove(at: index)
                        
                        let title = getTitle(element: windowElement)
                        let info = WindowInfo(
                            id: match.id,
                            element: windowElement,
                            app: app,
                            frame: match.frame,
                            title: title
                        )
                        results.append(info)
                    }
                }
            }
        }
        
        print("DEBUG: getVisibleWindows found \(results.count) windows via WindowInfo")
        
        // Re-order results based on visibleCGWindows order
        let orderedResults = visibleCGWindows.compactMap { cgWin in
            results.first { $0.id == cgWin.id }
        }
        
        return orderedResults
    }
    
    /// Activate a specific window and bring to front
    func activateWindow(_ element: AXUIElement) {
        // 1. Activate the application
        if let app = getApplication(for: element) {
            var pid: pid_t = 0
            if AXUIElementGetPid(app, &pid) == .success {
                if let nsApp = NSRunningApplication(processIdentifier: pid) {
                    nsApp.activate(options: [.activateIgnoringOtherApps])
                }
            }
        }
        
        // 2. Raise the window
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        
        // 3. Set Main
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        
        print("DEBUG: Activated Window Element with Title: \(getTitle(element: element))")
    }

    func getElementAtPosition(_ point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &element)
        
        if result == .success, let foundElement = element {
            print("AX Found element at \(point)")
            // Traverse up to find the window
            return getWindowElement(for: foundElement)
        } else {
            print("AX Failed to find any element at \(point). Error: \(result.rawValue)")
        }
        return nil
    }
    
    private func getWindowElement(for element: AXUIElement) -> AXUIElement? {
        // 1. Try direct Window Attribute
        var windowRef: AnyObject?
        if AXUIElementCopyAttributeValue(element, "AXWindow" as CFString, &windowRef) == .success,
           let window = windowRef {
            // print("Found via AXWindow attribute")
            return (window as! AXUIElement)
        }

        // 2. Try Top Level UI Element
        var topLevel: AnyObject?
        if AXUIElementCopyAttributeValue(element, "AXTopLevelUIElement" as CFString, &topLevel) == .success,
           let top = topLevel {
             // Verify it is a window
             // print("Found via AXTopLevelUIElement attribute")
             return (top as! AXUIElement)
        }
        
        // 3. Fallback: Manual Traversal
        var currentElement = element
        
        // Loop to find the window role
        // Increased limit to 50 for deep hierarchies (e.g. Electron apps)
        for _ in 0..<50 {
            var role: AnyObject?
            AXUIElementCopyAttributeValue(currentElement, kAXRoleAttribute as CFString, &role)
            
            if let roleStr = role as? String {
                // print("Ancestor [\(i)]: Role = \(roleStr)")
                if roleStr == kAXWindowRole as String {
                    return currentElement
                }
            }
            
            var parent: AnyObject?
            let err = AXUIElementCopyAttributeValue(currentElement, kAXParentAttribute as CFString, &parent)
            
            if err == .success, let parentElement = parent {
                currentElement = parentElement as! AXUIElement
            } else {
                // print("Ancestor [\(i)]: No Parent (Error: \(err.rawValue))")
                break
            }
        }
        return nil
    }
    
    // MARK: - Window Manipulation
    
    func getWindowFrame(element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        
        guard let posVal = positionValue, let sizeVal = sizeValue else { return nil }
        
        var point = CGPoint.zero
        var size = CGSize.zero
        
        AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        
        return CGRect(origin: point, size: size)
    }
    
    @discardableResult
    func setWindowFrame(element: AXUIElement, frame: CGRect) -> Bool {
        guard let originalFrame = getWindowFrame(element: element) else {
            return false
        }
        
        // Get the application and disable AXEnhancedUserInterface temporarily
        // (This is what Amethyst/Silica does for reliability)
        let app = getApplication(for: element)
        let hadEnhancedUI = disableEnhancedUserInterface(app: app)
        
        // Determine if we should set size (only if changed significantly)
        let threshold: CGFloat = 25.0
        let shouldSetSize = abs(originalFrame.size.width - frame.size.width) >= threshold ||
                            abs(originalFrame.size.height - frame.size.height) >= threshold
        
        // Silica pattern: Size → Position → Size (no delays!)
        if shouldSetSize {
            setSize(element, frame.size)
        }
        
        if originalFrame.origin != frame.origin {
            setPosition(element, frame.origin)
        }
        
        if shouldSetSize {
            setSize(element, frame.size)
        }
        
        // Restore AXEnhancedUserInterface
        if hadEnhancedUI {
            enableEnhancedUserInterface(app: app)
        }
        
        return true
    }
    
    // MARK: - Enhanced UI Interface Control
    
    private func getApplication(for element: AXUIElement) -> AXUIElement? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return AXUIElementCreateApplication(pid)
    }
    
    private func disableEnhancedUserInterface(app: AXUIElement?) -> Bool {
        guard let app = app else { return false }
        
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &value)
        
        if err == .success, let num = value as? NSNumber, num.boolValue {
            // Disable it
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
            return true
        }
        return false
    }
    
    private func enableEnhancedUserInterface(app: AXUIElement?) {
        guard let app = app else { return }
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }
    
    func setWindowPosition(element: AXUIElement, position: CGPoint) {
        setPosition(element, position)
    }
    
    private func setSize(_ element: AXUIElement, _ size: CGSize) {
        var sizeVal = size
        if let value = AXValueCreate(.cgSize, &sizeVal) {
             let err = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
             if err != .success { print("Failed to set Size: \(err.rawValue)") }
        }
    }
    
    private func setPosition(_ element: AXUIElement, _ point: CGPoint) {
        var pointVal = point
        if let value = AXValueCreate(.cgPoint, &pointVal) {
             let err = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
             if err != .success { print("Failed to set Position: \(err.rawValue)") }
        }
    }
    
    func getTitle(element: AXUIElement) -> String {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        return value as? String ?? "Unknown"
    }
    
    func getWindowID(element: AXUIElement) -> CGWindowID? {
        var value: AnyObject?
        
        // Check for common variations
        let attributeNames = ["AXWindowNumber", "_AXWindowNumber", "AXWindowID"]
        
        for name in attributeNames {
             let err = AXUIElementCopyAttributeValue(element, name as CFString, &value)
            if err == .success, let number = value as? NSNumber {
                 return CGWindowID(number.intValue)
             }
        }
        
        // Fallback: If AXWindowNumber is missing (e.g. Orion, some Electron apps),
        // try to find the window in CGWindowList by matching PID and Frame.
        
        // 1. Get PID
        var pid: pid_t = 0
        if AXUIElementGetPid(element, &pid) != .success {
             print("DEBUG: Failed to get PID for fallback ID lookup")
             return nil
        }
        
        // 2. Get Frame
        guard let axFrame = getWindowFrame(element: element) else {
             print("DEBUG: Failed to get Frame for fallback ID lookup")
             return nil
        }
        
        // 3. Query CGWindowList for this PID
        guard let windowInfos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        
        // 4. Find match
        for info in windowInfos {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid else { continue }
            
            if let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
               let x = bounds["X"], let y = bounds["Y"],
               let w = bounds["Width"], let h = bounds["Height"] {
                
                // Match Frame with tolerance
                if abs(x - axFrame.origin.x) < 10 &&
                   abs(y - axFrame.origin.y) < 10 &&
                   abs(w - axFrame.width) < 10 &&
                   abs(h - axFrame.height) < 10 {
                    
                    if let id = info[kCGWindowNumber as String] as? CGWindowID {
                        // print("DEBUG: Recovered Window ID \(id) via Frame Matching for PID \(pid)")
                        return id
                    }
                }
            }
        }
        
        print("DEBUG: Failed to find matching CGWindow for Frame: \(axFrame) PID: \(pid)")
        
        // DEBUG LOGGING (Restored for unmatched cases)
        var names: CFArray?
        if AXUIElementCopyAttributeNames(element, &names) == .success, let nsNames = names as? [String] {
             print("DEBUG: Window Attributes for '\(getTitle(element: element))': \(nsNames)")
        }
        
        return nil
    }
    
    func getWindowLevel(element: AXUIElement) -> Int? {
        guard let windowID = getWindowID(element: element) else { return nil }
        
        let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]]
        if let windowInfo = windowList?.first,
           let layer = windowInfo[kCGWindowLayer as String] as? Int {
            // kCGWindowLayer values:
            // - Normal windows typically have layer 0
            // - Floating windows have negative values (e.g., -1, -2)
            // - Desktop level has high positive values
            //
            // For NSWindow.Level, we use the corresponding CGWindowLevel constants:
            // - kCGNormalWindowLevel = 0
            // - kCGFloatingWindowLevel = 3 (but CGWindowLayer returns different values)
            //
            // Since kCGWindowLayer doesn't directly map to NSWindow.Level,
            // we return the raw layer value and the caller should interpret it
            // For normal app windows (layer 0), use NSWindow.Level.normal
            return layer
        }
        return nil
    }
    
    enum WindowVisibility {
        case visible
        case covered
        case notOnScreen
    }

    /// Check the visibility state of the target window
    /// - Parameter excludeWindowID: Optional window ID to exclude from coverage check (e.g., highlight window)
    func checkWindowVisibility(element: AXUIElement, excludeWindowID: CGWindowID? = nil) -> WindowVisibility {
        guard let targetFrame = getWindowFrame(element: element) else {
            return .notOnScreen
        }
        
        // Get all on-screen windows ordered from front to back
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return .notOnScreen
        }
        
        // Find the target window in the list by matching its frame
        var foundTargetIndex: Int? = nil
        
        // Pre-calculate target frame props for fast matching
        let tx = targetFrame.origin.x
        let ty = targetFrame.origin.y
        let tw = targetFrame.width
        let th = targetFrame.height
        
        // Try to match by ID first if available
        let targetID = getWindowID(element: element)
        
        for (index, windowInfo) in windowList.enumerated() {
            // Match by ID
            if let targetID = targetID,
               let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
               windowID == targetID {
                foundTargetIndex = index
                break
            }
            
            // Match by Frame
            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"] else {
                continue
            }
            
            // Check if this window's frame matches the target frame (with small tolerance)
            if abs(x - tx) < 10 &&
               abs(y - ty) < 10 &&
               abs(width - tw) < 10 &&
               abs(height - th) < 10 {
                
                // Skip our own highlight window if it accidentally matches frame (unlikely but possible)
                if let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                   let excludeID = excludeWindowID,
                   windowID == excludeID {
                    continue
                }
                
                foundTargetIndex = index
                break
            }
        }
        
        guard let targetIndex = foundTargetIndex else {
            // Target window not found in list -> Not on current visible screen
            return .notOnScreen
        }
        
        // Check all windows above the target (lower index = higher in z-order)
        for i in 0..<targetIndex {
            let windowInfo = windowList[i]
            
            // Skip the excluded window (e.g., our highlight window)
            if let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
               let excludeID = excludeWindowID,
               windowID == excludeID {
                continue
            }
            
            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"] else {
                continue
            }
            
            // Skip small windows
            if width < 10 || height < 10 { continue }
            
            // Skip invisible windows
            if let alpha = windowInfo[kCGWindowAlpha as String] as? Double, alpha < 0.05 {
                continue
            }
            
            // Skip system windows (Menu Bar, Dock, etc are usually Layer > 10)
            let layer = windowInfo[kCGWindowLayer as String] as? Int ?? 0
            if layer >= 10 {
                continue
            }
            
            let windowFrame = CGRect(x: x, y: y, width: width, height: height)
            
            // Check coverage
            let intersection = windowFrame.intersection(targetFrame)
            if !intersection.isNull {
                let overlapArea = intersection.width * intersection.height
                let targetArea = targetFrame.width * targetFrame.height
                let overlapPercent = overlapArea / targetArea

                // If overlap is more than 0.5% of target area, consider it covered
                if overlapPercent > 0.005 {
                    return .covered
                }
            }
        }
        
        return .visible
    }
    
    // Deprecated compatibility wrapper if needed, but we will update call sites
    func isWindowCovered(element: AXUIElement, excludeWindowID: CGWindowID? = nil) -> Bool {
        return checkWindowVisibility(element: element, excludeWindowID: excludeWindowID) == .covered
    }
    
    private func logSizeConstraints(_ element: AXUIElement) {
        // Check AXMinimumSize
        var minSizeValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, "AXMinimumSize" as CFString, &minSizeValue) == .success,
           let val = minSizeValue {
            var minSize = CGSize.zero
            AXValueGetValue(val as! AXValue, .cgSize, &minSize)
            print("DEBUG: Window MinSize = \(minSize)")
        }
        
        // Check AXMaximumSize
        var maxSizeValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, "AXMaximumSize" as CFString, &maxSizeValue) == .success,
           let val = maxSizeValue {
            var maxSize = CGSize.zero
            AXValueGetValue(val as! AXValue, .cgSize, &maxSize)
            print("DEBUG: Window MaxSize = \(maxSize)")
        }
    }
}
