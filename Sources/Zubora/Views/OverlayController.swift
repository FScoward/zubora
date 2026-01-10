import SwiftUI
import Combine

@MainActor
class OverlayController: ObservableObject {
    static let shared = OverlayController()
    
    private var window: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupBindings()
    }
    
    private func setupBindings() {
        AppState.shared.$targetWindowFrame
            .sink { [weak self] frame in
                self?.updateWindow(frame: frame)
            }
            .store(in: &cancellables)
            
        AppState.shared.$isTargetRegistered
            .sink { [weak self] isRegistered in
                if !isRegistered {
                    self?.window?.orderOut(nil)
                } else if let frame = AppState.shared.targetWindowFrame {
                    self?.updateWindow(frame: frame)
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateWindow(frame: CGRect?) {
        guard let frame = frame else {
            window?.orderOut(nil)
            return
        }
        
        if window == nil {
            let panel = NSPanel(
                contentRect: frame,
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .normal  // Same level as target window, not floating above
            panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.ignoresMouseEvents = true
            panel.setAccessibilityElement(false)
            panel.hasShadow = false // Remove window shadow
            
            let hostingView = NSHostingView(rootView: OverlayView())
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = CGColor.clear
            panel.contentView = hostingView
            self.window = panel
        }
        
        // Convert frame if needed? 
        // AccessibilityService returns App frame which is top-left.
        // NSWindow uses bottom-left.
        // We need to flip Y.
        // Also add margin so overlay is OUTSIDE the window
        let margin: CGFloat = 6
        let expandedFrame = CGRect(
            x: frame.origin.x - margin,
            y: frame.origin.y - margin,
            width: frame.size.width + margin * 2,
            height: frame.size.height + margin * 2
        )
        
        if let screenFrame = NSScreen.main?.frame {
            let newY = screenFrame.height - expandedFrame.origin.y - expandedFrame.height
            let newOrigin = CGPoint(x: expandedFrame.origin.x, y: newY)
            let newFrame = CGRect(origin: newOrigin, size: expandedFrame.size)
            
            DispatchQueue.main.async {
                self.window?.setFrame(newFrame, display: true)
                self.window?.orderFront(nil)
            }
        }
    }
}

struct OverlayView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.blue, lineWidth: 5)
            .shadow(color: .blue.opacity(0.8), radius: 10, x: 0, y: 0)
            .edgesIgnoringSafeArea(.all)
    }
}
