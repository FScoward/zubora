import Cocoa
import SwiftUI

class WindowSwitcherPanel: NSPanel {
    static let shared = WindowSwitcherPanel()
    
    private var hostingView: NSHostingView<WindowSwitcherView>?
    
    private init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        // Use a very high level to ensure it appears above everything
        self.level = .screenSaver
        
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isOpaque = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
    }
    
    private func createView() -> WindowSwitcherView {
        return WindowSwitcherView(
            windows: EventManager.shared.switchableWindows,
            selectedIndex: EventManager.shared.currentSwitchIndex
        )
    }
    
    func show() {
        print("WindowSwitcherPanel: show() called")
        
        if self.contentViewController == nil {
            let hv = NSHostingView(rootView: createView())
            hv.translatesAutoresizingMaskIntoConstraints = false
            self.hostingView = hv
            
            let controller = NSViewController()
            controller.view = NSView() // Container view
            controller.view.addSubview(hv)
            
            // Pin edges
            NSLayoutConstraint.activate([
                hv.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
                hv.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
                hv.topAnchor.constraint(equalTo: controller.view.topAnchor),
                hv.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor)
            ])
            
            self.contentViewController = controller
        }
        
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            
            // Calculate size based on content
            var size = self.contentViewController?.view.fittingSize ?? CGSize(width: 600, height: 200)
            
            // Ensure width is within screen bounds (with margin)
            let maxWidth = screenFrame.width - 100
            if size.width > maxWidth {
                size.width = maxWidth
            }
            // Ensure min size
            if size.width < 400 { size.width = 400 }
            if size.height < 150 { size.height = 150 }

            let x = screenFrame.midX - (size.width / 2)
            let y = screenFrame.midY - (size.height / 2)
            
            let newFrame = CGRect(x: x, y: y, width: size.width, height: size.height)
            print("WindowSwitcherPanel: Setting frame to \(newFrame)")
            self.setFrame(newFrame, display: true)
        }
        
        // Force front
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true) 
    }
    
    /// Force SwiftUI to re-render by assigning a new rootView with current data
    func refreshContent() {
        hostingView?.rootView = createView()
    }
    
    func hide() {
        self.orderOut(nil)
    }
}

