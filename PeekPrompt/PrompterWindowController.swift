import AppKit
import SwiftUI
import Combine

/// Where the notch is on the current screen. The SwiftUI view reads this.
final class NotchLayout: ObservableObject {
    static let shared = NotchLayout()
    /// Height of the notch (or menu bar on Macs without one). Text starts below this.
    @Published var topInset: CGFloat = 32
    /// Width of the physical notch. 0 if the screen has none.
    @Published var notchWidth: CGFloat = 0
    private init() {}
}

extension NSScreen {
    var hasNotch: Bool { safeAreaInsets.top > 0 }

    var notchWidth: CGFloat {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return 0 }
        return frame.width - left.width - right.width
    }

    /// The built-in MacBook screen if it has a notch, otherwise the main screen.
    static var preferredForPrompter: NSScreen? {
        NSScreen.screens.first(where: { $0.hasNotch }) ?? NSScreen.main ?? NSScreen.screens.first
    }
}

/// A borderless floating panel that never steals focus from the app you're recording in.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Normally macOS pushes windows below the menu bar. We want to sit right in it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Hosting view that reports hover and trackpad scrolling back to the engine.
final class PrompterHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    private var trackingArea: NSTrackingArea?

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange?(false)
    }

    override func scrollWheel(with event: NSEvent) {
        // Trackpads report precise points; mouse wheels report "lines".
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        onScroll?(-event.scrollingDeltaY * multiplier)
    }

    /// Lets the hover buttons respond to the first click, without activating the app.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PrompterWindowController {
    private let panel: NotchPanel
    private let settings: PrompterSettings
    private let layout: NotchLayout
    private var cancellables = Set<AnyCancellable>()
    private let animationDuration: TimeInterval = 0.3

    init(settings: PrompterSettings, engine: ScrollEngine, mic: MicrophoneMonitor, layout: NotchLayout) {
        self.settings = settings
        self.layout = layout

        panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the menu bar and full-screen apps.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let hosting = PrompterHostingView(
            rootView: PrompterView(settings: settings, engine: engine, mic: mic, layout: layout)
        )
        // We size the panel ourselves; stop SwiftUI from resizing the window.
        hosting.sizingOptions = []
        hosting.onHoverChange = { hovering in engine.isHovering = hovering }
        hosting.onScroll = { delta in engine.nudge(by: delta) }
        panel.contentView = hosting

        applyCaptureSetting(settings.hideFromCapture)

        settings.$hideFromCapture
            .receive(on: RunLoop.main)
            .sink { [weak self] hide in self?.applyCaptureSetting(hide) }
            .store(in: &cancellables)

        settings.$width.combineLatest(settings.$height)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.reposition(animated: false) }
            .store(in: &cancellables)

        settings.$isPrompterVisible
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in visible ? self?.show() : self?.hide() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reposition(animated: false) }
            .store(in: &cancellables)
    }

    // MARK: Hiding from screen capture

    /// `.none` asks macOS to leave this window out of screenshots, screen sharing and recordings.
    /// Works with Zoom, Google Meet in a browser, QuickTime and the screenshot tool.
    /// Note: since macOS 15.4, some recorders built on ScreenCaptureKit (e.g. Loom's full-screen mode)
    /// can still see it. Apple offers no public way to prevent that. See the README.
    private func applyCaptureSetting(_ hide: Bool) {
        panel.sharingType = hide ? .none : .readOnly
    }

    // MARK: Positioning

    private func targetFrame(on screen: NSScreen) -> NSRect {
        let topInset = screen.hasNotch ? screen.safeAreaInsets.top : 8
        if layout.topInset != topInset { layout.topInset = topInset }
        let notchWidth = screen.notchWidth
        if layout.notchWidth != notchWidth { layout.notchWidth = notchWidth }

        let width = CGFloat(settings.width)
        let height = topInset + CGFloat(settings.height)
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private func reposition(animated: Bool) {
        guard settings.isPrompterVisible, let screen = NSScreen.preferredForPrompter else { return }
        panel.setFrame(targetFrame(on: screen), display: true, animate: animated)
    }

    /// Slides down out of the notch.
    private func show() {
        guard let screen = NSScreen.preferredForPrompter else { return }
        let finalFrame = targetFrame(on: screen)
        var startFrame = finalFrame
        startFrame.origin.y = screen.frame.maxY

        panel.alphaValue = 0
        panel.setFrame(startFrame, display: false)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(finalFrame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    /// Slides back up into the notch.
    private func hide() {
        guard let screen = NSScreen.preferredForPrompter else {
            panel.orderOut(nil)
            return
        }
        var endFrame = panel.frame
        endFrame.origin.y = screen.frame.maxY

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(endFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.settings.isPrompterVisible else { return }
            self.panel.orderOut(nil)
        })
    }
}
