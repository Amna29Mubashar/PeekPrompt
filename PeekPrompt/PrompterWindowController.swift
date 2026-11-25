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
    /// True in "Anywhere" mode: rounded card, draggable.
    @Published var isFloating = false
    private init() {}
}

extension NSScreen {
    var hasNotch: Bool { safeAreaInsets.top > 0 }

    var notchWidth: CGFloat {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return 0 }
        return frame.width - left.width - right.width
    }

    /// The built-in MacBook screen if it has a notch, otherwise the main screen.
    static var automaticForPrompter: NSScreen? {
        NSScreen.screens.first(where: { $0.hasNotch }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// The screen to use for a Display setting.
    static func forPrompter(_ choice: DisplayChoice) -> NSScreen? {
        switch choice {
        case .automatic:
            return automaticForPrompter
        case .followMouse:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? automaticForPrompter
        case .display(let id):
            return NSScreen.screens.first(where: { $0.displayID == id }) ?? automaticForPrompter
        }
    }

    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
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
    /// Returns true when the prompter may be dragged around (Anywhere mode).
    var canDrag: (() -> Bool)?
    /// Called with the window's new origin after the user finishes dragging.
    var onDragEnded: ((NSPoint) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var didDrag = false

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

    // MARK: Dragging (Anywhere mode)

    override func mouseDown(with event: NSEvent) {
        if canDrag?() == true, let window {
            dragStartMouse = NSEvent.mouseLocation
            dragStartOrigin = window.frame.origin
            didDrag = false
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startMouse = dragStartMouse, let startOrigin = dragStartOrigin, let window else {
            super.mouseDragged(with: event)
            return
        }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: startOrigin.x + mouse.x - startMouse.x,
                                      y: startOrigin.y + mouse.y - startMouse.y))
        didDrag = true
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag, let window {
            onDragEnded?(window.frame.origin)
        }
        dragStartMouse = nil
        dragStartOrigin = nil
        didDrag = false
        super.mouseUp(with: event)
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
        hosting.canDrag = { settings.placement == .floating }
        hosting.onDragEnded = { origin in settings.floatingOrigin = origin }
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

        settings.$placement
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Wait one runloop so settings.placement already holds the new value.
                DispatchQueue.main.async { self?.reposition(animated: true) }
            }
            .store(in: &cancellables)

        // Display setting changed: move there (a floating prompter starts fresh on that screen).
        settings.$displayChoice
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.settings.placement == .floating { self.settings.floatingOrigin = nil }
                self.updateMouseFollowing()
                DispatchQueue.main.async { self.reposition(animated: false) }
            }
            .store(in: &cancellables)
        updateMouseFollowing()

        // "Reset position" in Settings clears the saved spot.
        settings.$floatingOrigin
            .dropFirst()
            .filter { $0 == nil }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.reposition(animated: true) }
            }
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

    private var currentScreen: NSScreen? { NSScreen.forPrompter(settings.displayChoice) }
    private var mouseTimer: Timer?
    private var lastScreenID: UInt32?

    /// In "Follow mouse" mode, hop to the pointer's screen when it changes.
    private func updateMouseFollowing() {
        mouseTimer?.invalidate()
        mouseTimer = nil
        guard settings.displayChoice == .followMouse else { return }
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self, self.settings.isPrompterVisible,
                  let screen = self.currentScreen, screen.displayID != self.lastScreenID else { return }
            if self.settings.placement == .floating { self.settings.floatingOrigin = nil }
            self.reposition(animated: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    private func targetFrame(on screen: NSScreen) -> NSRect {
        let floating = settings.placement == .floating
        if layout.isFloating != floating { layout.isFloating = floating }

        // No notch (e.g. an external monitor): hang from the top like a virtual notch,
        // with room for the status row.
        let topInset: CGFloat = floating ? 24 : (screen.hasNotch ? screen.safeAreaInsets.top : 24)
        if layout.topInset != topInset { layout.topInset = topInset }
        let notchWidth = floating ? 0 : screen.notchWidth
        if layout.notchWidth != notchWidth { layout.notchWidth = notchWidth }

        let width = CGFloat(settings.width)
        let height = topInset + CGFloat(settings.height)

        if floating {
            // Use the saved spot if it's still on a connected screen.
            if let origin = settings.floatingOrigin {
                let frame = NSRect(origin: origin, size: NSSize(width: width, height: height))
                if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                    return frame
                }
            }
            // First time: just below the menu bar, centered.
            let visible = screen.visibleFrame
            return NSRect(x: visible.midX - width / 2, y: visible.maxY - height - 40,
                          width: width, height: height)
        }

        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private func reposition(animated: Bool) {
        guard settings.isPrompterVisible, let screen = currentScreen else { return }
        lastScreenID = screen.displayID
        panel.setFrame(targetFrame(on: screen), display: true, animate: animated)
    }

    /// Slides down out of the notch.
    private func show() {
        guard let screen = currentScreen else { return }
        lastScreenID = screen.displayID
        let finalFrame = targetFrame(on: screen)
        var startFrame = finalFrame
        if settings.placement == .notch {
            startFrame.origin.y = screen.frame.maxY // slide down out of the notch
        }

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
        guard let screen = currentScreen else {
            panel.orderOut(nil)
            return
        }
        var endFrame = panel.frame
        if settings.placement == .notch {
            endFrame.origin.y = screen.frame.maxY // slide back up into the notch
        }

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

/// An entry in the Display menu.
struct DisplayOption {
    let choice: DisplayChoice
    let name: String

    static var all: [DisplayOption] {
        var options = [
            DisplayOption(choice: .automatic, name: String(localized: "Stay on the MacBook screen")),
            DisplayOption(choice: .followMouse, name: String(localized: "Move with my mouse to any screen"))
        ]
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            options.append(DisplayOption(choice: .display(id), name: screen.localizedName))
        }
        // Keep a chosen screen in the list even while it's unplugged.
        let current = PrompterSettings.shared.displayChoice
        if case .display = current, !options.contains(where: { $0.choice == current }) {
            options.append(DisplayOption(choice: current, name: String(localized: "Disconnected display")))
        }
        return options
    }
}
