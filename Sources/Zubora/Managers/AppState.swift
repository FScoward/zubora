import SwiftUI
import Combine
import ApplicationServices

enum SwapMode: String, CaseIterable, Identifiable {
    case swapAll = "Mode A (Pos & Size)"
    case swapPos = "Mode B (Pos Only)"
    
    var id: String { self.rawValue }
}

// MARK: - Multi-Space Target Management

struct TargetState {
    var element: AXUIElement
    var swapMode: SwapMode
    var lastSwappedOther: AXUIElement?
    var originalTargetElement: AXUIElement?
    var originalTargetFrame: CGRect?
    var swapChain: [(element: AXUIElement, originalFrame: CGRect)]
    var lastAccessDate: Date
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var swapMode: SwapMode = .swapAll {
        didSet {
            // Sync to current target state if applicable
            if let windowID = targetWindowID {
                storedTargets[windowID]?.swapMode = swapMode
            }
        }
    }
    @Published var isTargetRegistered: Bool = false
    @Published var targetWindowFrame: CGRect?
    @Published var modifierFlags: NSEvent.ModifierFlags = [] {
        didSet {
            UserDefaults.standard.set(modifierFlags.rawValue, forKey: "ModifierFlags")
        }
    }
    
    // Multi-Space Target Management
    private var storedTargets: [CGWindowID: TargetState] = [:]
    
    // The target currently active on the screen (if any)
    var targetElement: AXUIElement? {
        didSet {
            isTargetRegistered = (targetElement != nil)
            if targetElement == nil { targetWindowID = nil }
        }
    }
    // Optimization: Cache ID of current target to avoid re-fetching (expensive fallback)
    private var targetWindowID: CGWindowID?
    
    // These now serve as volatile mirrors of the current TargetState for convenience/logic
    private var lastSwappedOther: AXUIElement? {
        get { targetWindowID.flatMap { storedTargets[$0]?.lastSwappedOther } }
        set { if let id = targetWindowID { storedTargets[id]?.lastSwappedOther = newValue } }
    }
    private var originalTargetElement: AXUIElement? {
        get { targetWindowID.flatMap { storedTargets[$0]?.originalTargetElement } }
        set { if let id = targetWindowID { storedTargets[id]?.originalTargetElement = newValue } }
    }
    private var originalTargetFrame: CGRect? {
        get { targetWindowID.flatMap { storedTargets[$0]?.originalTargetFrame } }
        set { if let id = targetWindowID { storedTargets[id]?.originalTargetFrame = newValue } }
    }
    private var swapChain: [(element: AXUIElement, originalFrame: CGRect)] {
        get { targetWindowID.flatMap { storedTargets[$0]?.swapChain } ?? [] }
        set { if let id = targetWindowID { storedTargets[id]?.swapChain = newValue } }
    }
    
    private var frameUpdateTimer: Timer?
    
    // MARK: - Target State Helpers
    
    private func updateNewTargetState(newElement: AXUIElement, newID: CGWindowID, oldState: TargetState?) {
        self.targetElement = newElement
        self.targetWindowID = newID
        
        if let old = oldState {
            // INHERIT history and original target info from the previous occupant of this slot
            let newState = TargetState(
                element: newElement,
                swapMode: old.swapMode,
                lastSwappedOther: old.element, // The window that just left the position
                originalTargetElement: old.originalTargetElement,
                originalTargetFrame: old.originalTargetFrame,
                swapChain: old.swapChain,
                lastAccessDate: Date()
            )
            
            self.storedTargets[newID] = newState
            self.swapMode = old.swapMode // Restore UI mode
        } else {
            // If no old state (unlikely during swap), use current mode or existing state
            if self.storedTargets[newID] == nil {
                self.storedTargets[newID] = TargetState(
                    element: newElement,
                    swapMode: self.swapMode,
                    lastSwappedOther: nil,
                    originalTargetElement: newElement,
                    originalTargetFrame: AccessibilityService.shared.getWindowFrame(element: newElement),
                    swapChain: [],
                    lastAccessDate: Date()
                )
            }
        }
    }
    
    private init() {
        let savedFlags = UserDefaults.standard.integer(forKey: "ModifierFlags")
        if savedFlags != 0 {
            self.modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(savedFlags))
        } else {
            // Default: Option + Control
            self.modifierFlags = [.option, .control]
        }
        
        // Observe Space changes for immediate update
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSpaceChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleSpaceChange() {
        Task { @MainActor in
            self.updateTargetFrame()
        }
    }
    
    func toggleModifier(_ flag: NSEvent.ModifierFlags) {
        if modifierFlags.contains(flag) {
            modifierFlags.remove(flag)
        } else {
            modifierFlags.insert(flag)
        }
    }
    
    func registerTarget(window: AXUIElement) {
        guard let windowID = AccessibilityService.shared.getWindowID(element: window) else {
            print("Error: Could not get Window ID for registration")
            return
        }
        
        // Initialize state for new target
        let frame = AccessibilityService.shared.getWindowFrame(element: window)
        let state = TargetState(
            element: window,
            swapMode: self.swapMode, // Inherit current global setting initially
            lastSwappedOther: nil,
            originalTargetElement: window,
            originalTargetFrame: frame,
            swapChain: [],
            lastAccessDate: Date()
        )
        
        storedTargets[windowID] = state
        print("Target Registered: ID \(windowID). Total stored targets: \(storedTargets.count)")
        
        // Immediately make it active since user just clicked it
        self.targetElement = window
        self.targetWindowID = windowID
        
        if let f = frame {
            self.targetWindowFrame = f
            
            // Check visibility state (covers Ghosting/Spaces handling)
            let highlightID = SwapAnimationController.shared.highlightWindowID
            let visibility = WindowVisibilityService.shared.checkWindowVisibility(element: window, excludeWindowID: highlightID)
            
            // Should be visible since we just clicked it, but good to run logic
            switch visibility {
            case .visible:
                SwapAnimationController.shared.updateTargetHighlight(frame: f, windowID: windowID, isCovered: false)
            case .covered:
                SwapAnimationController.shared.updateTargetHighlight(frame: f, windowID: windowID, isCovered: true)
            case .notOnScreen:
                SwapAnimationController.shared.hideTargetHighlight()
            }
        }
        startFrameTracking()
    }
    
    private func startFrameTracking() {
        stopFrameTracking()
        frameUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in // Relaxed timer to 50ms for multi-check
            Task { @MainActor in
                self?.updateTargetFrame()
            }
        }
    }
    
    private func stopFrameTracking() {
        frameUpdateTimer?.invalidate()
        frameUpdateTimer = nil
    }
    
    private func updateTargetFrame() {
        // 1. If we have a current target, check its status first (Optimization)
        // 2. If current target is gone (off-screen), scan for other candidates
        
        let highlightID = SwapAnimationController.shared.highlightWindowID
        
        // Helper to validate a candidate
        func checkCandidate(_ element: AXUIElement, id: CGWindowID) -> (isVisible: Bool, frame: CGRect?, isCovered: Bool) {
            guard let frame = AccessibilityService.shared.getWindowFrame(element: element) else { return (false, nil, false) }
            let state = WindowVisibilityService.shared.checkWindowVisibility(element: element, excludeWindowID: highlightID)
            return (state != .notOnScreen, frame, state == .covered)
        }
        
        // A. Check Current Target (using Cached ID)
        var currentTargetStillValid = false
        if let current = targetElement, let currentID = targetWindowID {
            let (visible, frame, covered) = checkCandidate(current, id: currentID)
            
            if visible, let f = frame {
                // Update State
                if f != targetWindowFrame { targetWindowFrame = f }
                SwapAnimationController.shared.updateTargetHighlight(frame: f, windowID: currentID, isCovered: covered)
                
                // Update access time to keep it fresh
                if var state = storedTargets[currentID] {
                    state.lastAccessDate = Date()
                    storedTargets[currentID] = state
                }
                
                currentTargetStillValid = true
            }
        }
        
        if currentTargetStillValid {
            return
        }
        
        // B. Current target not valid/visible -> Scan stored targets
        var candidates: [(id: CGWindowID, element: AXUIElement, frame: CGRect, covered: Bool, date: Date)] = []
        var foundNewTargetKey: CGWindowID? = nil
        var foundNewTargetElement: AXUIElement? = nil
        var foundNewFrame: CGRect? = nil
        var foundNewCovered = false

        // Iterate dictionary
        for (id, state) in storedTargets {
            // Skip the one we just checked (if any)
            if let currentID = targetWindowID, id == currentID { continue }
            
            let (visible, frame, covered) = checkCandidate(state.element, id: id)
            if visible, let f = frame {
                candidates.append((id, state.element, f, covered, state.lastAccessDate))
            }
        }
        
        // Sort by last access date (newest first)
        if let bestMatch = candidates.sorted(by: { $0.date > $1.date }).first {
            print("DEBUG: Found visible stored target ID \(bestMatch.id) (Date: \(bestMatch.date)). Activating.")
            
            foundNewTargetKey = bestMatch.id
            foundNewTargetElement = bestMatch.element
            foundNewFrame = bestMatch.frame
            foundNewCovered = bestMatch.covered
        }
        
        if let newElement = foundNewTargetElement, let newID = foundNewTargetKey, let f = foundNewFrame {
            // Activate new target
            self.targetElement = newElement
            self.targetWindowID = newID
            self.targetWindowFrame = f
            
            // Sync global swapMode to what was saved for this target
            if let targetState = storedTargets[newID] {
                self.swapMode = targetState.swapMode
            }
            
            SwapAnimationController.shared.updateTargetHighlight(frame: f, windowID: newID, isCovered: foundNewCovered)
        } else {
            // No targets visible on this screen
            if targetElement != nil {
                print("DEBUG: No targets visible. Deactivating.")
                targetElement = nil
                // targetWindowID is cleared in didSet
            }
            SwapAnimationController.shared.hideTargetHighlight()
        }
    }
    
    func handleSwapRequest(at point: CGPoint) {
        guard let clickedElement = AccessibilityService.shared.getElementAtPosition(point) else {
            print("No window found at click")
            return
        }
        processSwap(with: clickedElement)
    }
    
    /// Public method to trigger swap with a specific window (e.g. from Shortcut)
    func swapWithTarget(_ window: AXUIElement) {
        processSwap(with: window)
    }
    
    private func processSwap(with clickedElement: AXUIElement) {
        guard let target = targetElement, let targetFrame = AccessibilityService.shared.getWindowFrame(element: target) else {
            print("No target registered or target invalid")
            isTargetRegistered = false
            SwapAnimationController.shared.removeTargetHighlight() // Remove highlight if invalid
            return
        }
        
        // Check if clicked the target window itself
        if CFEqual(target, clickedElement) {
            // If we have a previous swap partner, swap with them again
            if let lastOther = lastSwappedOther,
               let lastOtherFrame = AccessibilityService.shared.getWindowFrame(element: lastOther) {
                let targetTitle = AccessibilityService.shared.getTitle(element: target)
                let otherTitle = AccessibilityService.shared.getTitle(element: lastOther)
                print("Re-swapping target '\(targetTitle)' with previous partner '\(otherTitle)'")
                performSwap(target: target, targetFrame: targetFrame, other: lastOther, otherFrame: lastOtherFrame)
            } else {
                print("Clicked target window, but no previous swap partner available")
            }
            return
        }
        
        if let clickedFrame = AccessibilityService.shared.getWindowFrame(element: clickedElement) {
            let targetTitle = AccessibilityService.shared.getTitle(element: target)
            let clickedTitle = AccessibilityService.shared.getTitle(element: clickedElement)
            
            // Check if this is a rotation scenario (we already have swap history)
            if !swapChain.isEmpty {
                print("Rotation: '\(targetTitle)' returns to original, '\(clickedTitle)' goes to target slot")
                performRotation(currentTarget: target, currentTargetFrame: targetFrame, 
                               newWindow: clickedElement, newWindowFrame: clickedFrame)
            } else {
                // First swap - regular swap behavior
                print("First swap: '\(targetTitle)' \(targetFrame) with '\(clickedTitle)' \(clickedFrame)")
                performSwap(target: target, targetFrame: targetFrame, other: clickedElement, otherFrame: clickedFrame)
                
                // Add original target (A) to swap chain with its original position
                if let origTarget = originalTargetElement, let origFrame = originalTargetFrame {
                    swapChain.append((element: origTarget, originalFrame: origFrame))
                }
                
                // Also add the swap partner (B) with its original position (clickedFrame)
                // B will become the new target after performSwap, and we need to remember where it came from
                swapChain.append((element: clickedElement, originalFrame: clickedFrame))
            }
            
            // Remember this as the last swap partner
            self.lastSwappedOther = clickedElement
        }
    }
    
    private func performSwap(target: AXUIElement, targetFrame: CGRect, other: AXUIElement, otherFrame: CGRect) {
        print("DEBUG: performSwap started")
        
        // Pause frame tracking during swap to prevent interference
        stopFrameTracking()
        
        let swapMode = self.swapMode
        
        // Calculate target frames
        var newTargetFrame: CGRect
        var newOtherFrame: CGRect
        
        if swapMode == .swapAll {
            // Mode A: Full swap - exchange position AND size completely
            newTargetFrame = otherFrame   // Target gets other's position and size
            newOtherFrame = targetFrame   // Other gets target's position and size
        } else {
            // Mode B: Position only, keep original sizes, center-based
            let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
            let otherCenter = CGPoint(x: otherFrame.midX, y: otherFrame.midY)
            
            // Move target's center to other's center position
            newTargetFrame = CGRect(
                x: otherCenter.x - targetFrame.size.width / 2,
                y: otherCenter.y - targetFrame.size.height / 2,
                width: targetFrame.size.width,
                height: targetFrame.size.height
            )
            
            // Move other's center to target's center position
            newOtherFrame = CGRect(
                x: targetCenter.x - otherFrame.size.width / 2,
                y: targetCenter.y - otherFrame.size.height / 2,
                width: otherFrame.size.width,
                height: otherFrame.size.height
            )
        }
        
        
        // Closure to perform the actual window move
        let moveWindows = { [self] in
            print("DEBUG: Setting frames...")
            let oldState = targetWindowID.flatMap { storedTargets[$0] }
            
            if swapMode == .swapAll {
                print("DEBUG: Setting Target Frame to \(newTargetFrame)")
                AccessibilityService.shared.setWindowFrame(element: target, frame: newTargetFrame)
                print("DEBUG: Setting Other Frame to \(newOtherFrame)")
                AccessibilityService.shared.setWindowFrame(element: other, frame: newOtherFrame)
            } else {
                print("DEBUG: Setting Target Position to \(newTargetFrame.origin)")
                AccessibilityService.shared.setWindowPosition(element: target, position: newTargetFrame.origin)
                print("DEBUG: Setting Other Position to \(newOtherFrame.origin)")
                AccessibilityService.shared.setWindowPosition(element: other, position: newOtherFrame.origin)
            }
            print("DEBUG: Frames set.")
            
            // The window that moved INTO the target position becomes the new target
            if let newID = AccessibilityService.shared.getWindowID(element: other) {
                updateNewTargetState(newElement: other, newID: newID, oldState: oldState)
            }
            
            // Resume frame tracking
            self.startFrameTracking()
        }
        
        // Move windows first, then show visual feedback
        moveWindows()
        
        // Show lightweight visual feedback (border animation)
        SwapAnimationController.shared.showSwapFeedback(
            targetFrame1: newTargetFrame,
            targetFrame2: newOtherFrame
        ) {
            print("DEBUG: Visual feedback complete")
        }
    }
    
    /// Perform rotation: new window goes to target position, current target returns to its original position,
    /// original target (A) goes to new window's original position
    private func performRotation(currentTarget: AXUIElement, currentTargetFrame: CGRect,
                                  newWindow: AXUIElement, newWindowFrame: CGRect) {
        print("DEBUG: performRotation started")
        
        stopFrameTracking()
        
        guard let origTargetElement = originalTargetElement,
              let origTargetFrame = originalTargetFrame else {
            print("ERROR: No original target info for rotation")
            startFrameTracking()
            return
        }
        
        // Find current target's original position from swapChain
        // Current target should be in the chain if it was previously swapped
        var currentTargetOriginalFrame: CGRect? = nil
        for (element, frame) in swapChain {
            if CFEqual(element, currentTarget) {
                currentTargetOriginalFrame = frame
                break
            }
        }
        
        // If current target is the original target, use originalTargetFrame
        if CFEqual(currentTarget, origTargetElement) {
            currentTargetOriginalFrame = origTargetFrame
        }
        
        // If we still don't have it, it means current target was swapped in as "other" 
        // and we stored its frame when it first swapped. Check lastSwappedOther logic.
        // Actually, when B swaps with A, B becomes targetElement. B's original position was otherFrame at that time.
        // We need to track this better. Let's use swapChain to store each window that entered the target slot.
        
        let swapMode = self.swapMode
        
        // Determine positions:
        // 1. newWindow -> originalTargetFrame (the holy target position)
        // 2. currentTarget -> its original position (before it became target)
        // 3. originalTarget (A) -> newWindowFrame (where newWindow currently is)
        
        let newWindowDestination = origTargetFrame  // Goes to target slot
        let originalTargetDestination = newWindowFrame  // A goes to where C was
        
        // For currentTarget (B), we need its original position
        // If we don't have it, fall back to swapping just currentTarget and newWindow
        let currentTargetDestination: CGRect
        if let origPos = currentTargetOriginalFrame {
            currentTargetDestination = origPos
        } else {
            // Fallback: B goes to where the new window was (simple swap)
            print("WARNING: Could not find original position for current target, using newWindowFrame")
            currentTargetDestination = newWindowFrame
        }
        
        print("DEBUG: Rotation plan:")
        print("  - New window (\(AccessibilityService.shared.getTitle(element: newWindow))) -> \(newWindowDestination)")
        print("  - Current target (\(AccessibilityService.shared.getTitle(element: currentTarget))) -> \(currentTargetDestination)")
        print("  - Original target (\(AccessibilityService.shared.getTitle(element: origTargetElement))) -> \(originalTargetDestination)")
        
        // Perform the moves
        // Logic: Move windows in an order that minimizes overlap conflicts
        // 1. Move Original Target (A) to New Window's spot (posC) - clearing the way? No, covering C.
        // 2. Move Current Target (B) to its original spot (posB) - clearing target slot (posA).
        // 3. Move New Window (C) to Target slot (posA).
        
        print("DEBUG: Executing rotation moves...")
        
        // 1. Move A -> posC
        if swapMode == .swapAll {
            let res = AccessibilityService.shared.setWindowFrame(element: origTargetElement, frame: originalTargetDestination)
            print("  - Moved Original Target (A): \(res ? "Success" : "Failed")")
        } else {
            AccessibilityService.shared.setWindowPosition(element: origTargetElement, position: originalTargetDestination.origin)
            print("  - Moved Original Target (A) (Pos)")
        }
        
        // 2. Move B -> posB (Only if B != A)
        if !CFEqual(currentTarget, origTargetElement) {
            if swapMode == .swapAll {
                let res = AccessibilityService.shared.setWindowFrame(element: currentTarget, frame: currentTargetDestination)
                print("  - Moved Current Target (B): \(res ? "Success" : "Failed")")
            } else {
                AccessibilityService.shared.setWindowPosition(element: currentTarget, position: currentTargetDestination.origin)
                print("  - Moved Current Target (B) (Pos)")
            }
        }
        
        // 3. Move C -> posA
        if swapMode == .swapAll {
            let res = AccessibilityService.shared.setWindowFrame(element: newWindow, frame: newWindowDestination)
            print("  - Moved New Window (C): \(res ? "Success" : "Failed")")
        } else {
            AccessibilityService.shared.setWindowPosition(element: newWindow, position: newWindowDestination.origin)
            print("  - Moved New Window (C) (Pos)")
        }
        
        
        // Add NEW WINDOW (which becomes the new target) and its original position to swap chain
        // This ensures that in the next rotation, we know where to return this window to.
        swapChain.append((element: newWindow, originalFrame: newWindowFrame))
        
        // New window becomes the new target
        if let newID = AccessibilityService.shared.getWindowID(element: newWindow) {
            let oldState = targetWindowID.flatMap { storedTargets[$0] }
            updateNewTargetState(newElement: newWindow, newID: newID, oldState: oldState)
        }
        
        print("DEBUG: Rotation complete.")
        print("  - New Target: \(AccessibilityService.shared.getTitle(element: newWindow))")
        print("  - Target Slot: \(newWindowDestination)")
        
        startFrameTracking()
        
        // Visual feedback
        SwapAnimationController.shared.showSwapFeedback(
            targetFrame1: newWindowDestination,
            targetFrame2: originalTargetDestination
        ) {
            print("DEBUG: Rotation visual feedback complete")
        }
    }
}
