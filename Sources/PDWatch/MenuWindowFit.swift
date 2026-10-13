import AppKit
import SwiftUI

extension View {
    /// The MenuBarExtra window grows when a section expands but doesn't shrink
    /// back when it collapses, leaving the content centered in empty space.
    /// This shrinks the window to the content, keeping its top edge in place.
    func shrinksMenuWindowToFit() -> some View {
        modifier(ShrinkMenuWindowToFit())
    }
}

private struct ShrinkMenuWindowToFit: ViewModifier {
    private let window = WindowReference()

    func body(content: Content) -> some View {
        content
            .background(WindowReader(reference: window))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                window.shrink(toContent: size)
            }
    }
}

@MainActor
private final class WindowReference {
    weak var window: NSWindow?

    func shrink(toContent size: CGSize) {
        guard let window, size.width > 0, size.height > 0 else { return }
        let current = window.contentRect(forFrameRect: window.frame).size
        guard size.height < current.height - 0.5 || size.width < current.width - 0.5 else { return }

        let target = NSSize(width: min(size.width, current.width), height: min(size.height, current.height))
        window.contentMinSize = target
        var frame = window.frame
        let newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: target))
        frame.origin.y += frame.height - newFrame.height
        frame.size = newFrame.size
        window.setFrame(frame, display: true, animate: false)
    }
}

private struct WindowReader: NSViewRepresentable {
    let reference: WindowReference

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { reference.window = view.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if reference.window == nil {
            DispatchQueue.main.async { reference.window = view.window }
        }
    }
}
