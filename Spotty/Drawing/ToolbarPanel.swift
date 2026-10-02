import AppKit
import SwiftUI

/// The toolbar shown while drawing is toggled on, centered at the top of the display with the
/// pointer. It never takes key focus, so tool keys keep reaching the overlay.
@MainActor
final class ToolbarPanel {
    private let controller: DrawingController
    private lazy var panel: NSPanel = makePanel()

    init(controller: DrawingController) {
        self.controller = controller
    }

    func show() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let size = panel.contentView?.fittingSize ?? .zero
        let area = screen.visibleFrame
        panel.setFrame(CGRect(x: area.midX - size.width / 2, y: area.maxY - size.height - 12, width: size.width, height: size.height),
                       display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Chrome.reduceMotion ? 0 : Chrome.fadeDuration
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Chrome.reduceMotion ? 0 : Chrome.fadeDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [panel] in
            MainActor.assumeIsolated { if panel.alphaValue == 0 { panel.orderOut(nil) } }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = Chrome.toolbarLevel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.becomesKeyOnlyIfNeeded = true
        let host = FirstMouseHostingView(rootView: ToolbarView(controller: controller))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        return panel
    }
}

/// Buttons respond to the first click, though Spotty is never the active app while drawing.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct ToolbarView: View {
    let controller: DrawingController

    var body: some View {
        HStack(spacing: Bar.groupSpacing) {
            ToolStrip(controller: controller)
            ColorMenu(controller: controller)
            Button("Done") { controller.stop() }
                .buttonStyle(.barProminent)
                .help("Stop drawing (Escape)")
        }
        .padding(.horizontal, Bar.edgeInset)
        .frame(height: Bar.height)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
        .padding(1)
        .fixedSize()
    }
}

/// The drawing tools as one capsule strip, as in Shotty's editor. Thin separators divide tools,
/// except beside the active or hovered tool, whose capsule fills the strip's height.
private struct ToolStrip: View {
    let controller: DrawingController
    @State private var hovered: DrawingTool?

    var body: some View {
        let tools = DrawingTool.allCases
        let highlighted = Set([controller.session.tool, hovered].compactMap { $0 })
        HStack(spacing: 0) {
            ForEach(Array(tools.enumerated()), id: \.element) { index, tool in
                if index > 0 {
                    Rectangle().fill(.primary.opacity(0.15)).frame(width: 1, height: 12)
                        .opacity(highlighted.contains(tool) || highlighted.contains(tools[index - 1]) ? 0 : 1)
                }
                ToolButton(controller: controller, tool: tool, isHovered: hovered == tool)
                    .onHover { inside in
                        if inside { hovered = tool } else if hovered == tool { hovered = nil }
                    }
            }
        }
        .background(Bar.groupFill, in: Capsule())
    }
}

private struct ToolButton: View {
    let controller: DrawingController
    let tool: DrawingTool
    let isHovered: Bool

    var body: some View {
        let active = controller.session.tool == tool
        Button { controller.pick(tool) } label: {
            Image(systemName: tool.symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: Bar.toolWidth, height: Bar.toolHeight)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Color.white : .primary)
        .background(active ? Color.accentColor : isHovered ? Bar.buttonFill : .clear, in: Capsule())
        .help([tool.title, controller.commands.shortcut(for: .pick(tool))?.displayString].compactMap { $0 }.joined(separator: " "))
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// The current tool's color. An AppKit menu, because macOS 27 hides the swatch images of SwiftUI
/// menu items.
private struct ColorMenu: View {
    let controller: DrawingController

    var body: some View {
        let tool = controller.session.tool
        let highlighter = tool == .highlighter
        let current = controller.preferences.drawing.style(for: tool).color
        Button {
            ColorMenuTarget.popUp(current: current) { controller.preferences.drawing.setColor($0, for: tool) }
        } label: {
            ColorDot(color: current, size: 14)
        }
        .buttonStyle(BarButtonStyle(width: 36))
        .help(highlighter ? "Highlighter color" : "Color")
        .accessibilityLabel(highlighter ? "Highlighter color" : "Color")
    }
}


@MainActor
private final class ColorMenuTarget: NSObject {
    private let choose: (RGBAColor) -> Void

    private init(choose: @escaping (RGBAColor) -> Void) {
        self.choose = choose
    }

    /// Shows the palette below the toolbar, under the pointer, and reports the chosen color.
    static func popUp(current: RGBAColor, choose: @escaping (RGBAColor) -> Void) {
        let target = ColorMenuTarget(choose: choose)
        let menu = NSMenu()
        for (index, swatch) in RGBAColor.palette.enumerated() {
            let item = NSMenuItem(title: swatch.name, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = target
            item.tag = index
            item.image = ColorDot.image(swatch.color, size: 12)
            if #available(macOS 27, *) { item.preferredImageVisibility = .visible }
            item.state = swatch.color == current ? .on : .off
            menu.addItem(item)
        }
        let mouse = NSEvent.mouseLocation
        let toolbarBottom = NSApp.windows.first { $0.level == Chrome.toolbarLevel && $0.isVisible }?.frame.minY ?? mouse.y
        // popUp blocks until the menu closes, which keeps `target` alive.
        menu.popUp(positioning: nil, at: NSPoint(x: mouse.x - 24, y: toolbarBottom - 4), in: nil)
    }

    @objc private func pick(_ item: NSMenuItem) {
        choose(RGBAColor.palette[item.tag].color)
    }
}

/// A color swatch with a hairline, so white and black stay visible on any background.
struct ColorDot: View {
    let color: RGBAColor
    var size: CGFloat = 14

    var body: some View {
        Image(nsImage: Self.image(color, size: size))
    }

    /// Menus render images, not SwiftUI shapes.
    static func image(_ color: RGBAColor, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor(cgColor: color.cgColor)?.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            NSColor(white: 0.5, alpha: 0.6).setStroke()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
    }
}
