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
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.ignoresMouseEvents = true
            panel.setAccessibilityElement(false)
            panel.contentView = NSHostingView(rootView: OverlayView())
            self.window = panel
        }
        
        // Convert frame if needed? 
        // AccessibilityService returns App frame which is top-left.
        // NSWindow uses bottom-left.
        // We need to flip Y.
        if let screenFrame = NSScreen.main?.frame {
            let newY = screenFrame.height - frame.origin.y - frame.height
            let newOrigin = CGPoint(x: frame.origin.x, y: newY)
            let newFrame = CGRect(origin: newOrigin, size: frame.size)
            
            DispatchQueue.main.async {
                self.window?.setFrame(newFrame, display: true)
                self.window?.orderFront(nil)
            }
        }
    }
}

struct OverlayView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue, lineWidth: 5)
                .shadow(color: .blue.opacity(0.8), radius: 10, x: 0, y: 0)
        }
        .edgesIgnoringSafeArea(.all)
    }
}
