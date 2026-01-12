import SwiftUI

struct WindowSwitcherView: View {
    let windows: [WindowInfo]
    let selectedIndex: Int
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { proxy in
                HStack(spacing: 20) {
                    ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                        VStack {
                            Image(nsImage: window.app.icon ?? NSImage(named: NSImage.applicationIconName)!)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 64, height: 64)
                            
                            Text(window.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 120)
                                .foregroundColor(index == selectedIndex ? .white : .secondary)
                        }
                        .id(index) // For ScrollViewReader
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(index == selectedIndex ? Color.blue.opacity(0.3) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(index == selectedIndex ? Color.white : Color.clear, lineWidth: 2)
                        )
                    }
                }
                .padding(30)
                .onChange(of: selectedIndex) { newIndex in
                    withAnimation {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(minWidth: 400, alignment: .center)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).cornerRadius(20))
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
