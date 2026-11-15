#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import CoreVideo
import Metal
import QuartzCore

/// A native macOS `NSView` backed by a `CAMetalLayer` that renders SWF movies via Ruffle's Metal renderer
/// and supports macOS mouse, trackpad, keyboard, and window resizing events.
@MainActor
public final class NSFlashPlayerView: NSView, NSTextInputClient {
    /// The underlying `RufflePlayer` instance driving this view.
    public private(set) var player: RufflePlayer?

    /// Multiplier applied to the screen's backing scale factor (`0.25` to `1.0`).
    public var renderScale: CGFloat = 1.0 {
        didSet {
            let clamped = max(0.25, min(1.0, renderScale))
            if renderScale != clamped {
                renderScale = clamped
                return
            }
            syncDrawableSizeIfNeeded()
        }
    }

    /// When `true` (the default), playback and rendering pause while the macOS application is not active.
    /// Set to `false` to keep Flash timers, scripts, and rendering running in the background.
    public var pausesWhenInactive: Bool = true

    /// Rolling display render frames per second.
    public private(set) var currentRenderFPS: Double = 0.0
    /// Rolling SWF logical frames per second.
    public private(set) var currentSwfFPS: Double = 0.0

    private var metalLayer: CAMetalLayer? {
        layer as? CAMetalLayer
    }

    private var cvDisplayLink: CVDisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var lastDrawableSize: CGSize = .zero
    private var lastScaleFactor: CGFloat = 0.0
    private var isAppActive: Bool = true
    private var fpsSampleStartTimestamp: CFTimeInterval = 0
    private var fpsSampleRenderCount: Int = 0
    private var fpsSampleStartSwfFrames: UInt64 = 0

    // MARK: - Initialization

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    /// Convenience initializer that creates the view and loads a local `.swf` file URL.
    public convenience init(frame: NSRect = .zero, fileURL: URL) throws {
        self.init(frame: frame)
        try load(fileURL: fileURL)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let link = cvDisplayLink {
            CVDisplayLinkStop(link)
        }
    }

    // MARK: - View Setup

    override public var isFlipped: Bool {
        // Keeps coordinate origin at top-left, matching Flash and UIKit
        true
    }

    override public var acceptsFirstResponder: Bool {
        true
    }

    private var effectiveScaleFactor: CGFloat {
        let screenScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        return max(1.0, screenScale * renderScale)
    }

    private var canTick: Bool {
        window != nil
            && !isHidden
            && (isAppActive || !pausesWhenInactive)
    }

    private var canRender: Bool {
        guard canTick, let window else { return false }
        return bounds.width > 0
            && bounds.height > 0
            && !window.isMiniaturized
            && window.occlusionState.contains(.visible)
    }

    private func commonInit() {
        wantsLayer = true
        let layer = CAMetalLayer()
        self.layer = layer

        let scale = effectiveScaleFactor
        layer.contentsScale = scale
        layer.isOpaque = true

        let initialWidth = max(1.0, (bounds.width * scale).rounded())
        let initialHeight = max(1.0, (bounds.height * scale).rounded())
        let initialDrawableSize = CGSize(width: initialWidth, height: initialHeight)
        layer.drawableSize = initialDrawableSize
        lastDrawableSize = initialDrawableSize
        lastScaleFactor = scale

        self.player = try? RufflePlayer(
            metalLayer: layer,
            drawableSize: initialDrawableSize,
            scaleFactor: scale
        )

        self.player?.onNavigateURL = { url in
            NSWorkspace.shared.open(url)
        }

        registerLifecycleObservers()
    }

    private func registerLifecycleObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appDidResignActive() {
        isAppActive = false
        if pausesWhenInactive {
            lastTimestamp = nil
        }
    }

    @objc private func appDidBecomeActive() {
        isAppActive = true
        lastTimestamp = nil
        syncDrawableSizeIfNeeded()
        renderIfPossible()
    }

    // MARK: - Public Loading API

    public func load(fileURL: URL) throws {
        syncDrawableSizeIfNeeded()
        try player?.load(fileURL: fileURL)
        renderIfPossible()
    }

    public func load(data: Data, baseURL: URL? = Bundle.main.resourceURL) throws {
        syncDrawableSizeIfNeeded()
        try player?.load(data: data, baseURL: baseURL)
        renderIfPossible()
    }

    // MARK: - Layout & Rendering

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            window?.acceptsMouseMovedEvents = true
            isAppActive = NSApplication.shared.isActive
            syncDrawableSizeIfNeeded()
            startDisplayLink()
            renderIfPossible()
        } else {
            stopDisplayLink()
        }
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncDrawableSizeIfNeeded()
    }

    override public func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncDrawableSizeIfNeeded()
    }

    private func syncDrawableSizeIfNeeded() {
        guard let metalLayer else { return }
        let scale = effectiveScaleFactor
        if metalLayer.contentsScale != scale {
            metalLayer.contentsScale = scale
        }

        let drawableWidth = max(1.0, (bounds.width * scale).rounded())
        let drawableHeight = max(1.0, (bounds.height * scale).rounded())
        let newDrawableSize = CGSize(width: drawableWidth, height: drawableHeight)

        if newDrawableSize != lastDrawableSize || scale != lastScaleFactor {
            lastDrawableSize = newDrawableSize
            lastScaleFactor = scale
            metalLayer.drawableSize = newDrawableSize
            player?.setViewportDimensions(
                width: UInt32(drawableWidth),
                height: UInt32(drawableHeight),
                scaleFactor: Double(scale)
            )
            renderIfPossible()
        }
    }

    private func renderIfPossible() {
        guard canRender, let player else { return }
        player.render()
    }

    // MARK: - Display Link (CVDisplayLink)

    private func startDisplayLink() {
        guard cvDisplayLink == nil else { return }

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }

        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, context -> CVReturn in
            guard let context else { return kCVReturnSuccess }
            let view = Unmanaged<NSFlashPlayerView>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                view.stepFrame()
            }
            return kCVReturnSuccess
        }, opaqueSelf)

        CVDisplayLinkStart(link)
        cvDisplayLink = link
    }

    private func stopDisplayLink() {
        if let link = cvDisplayLink {
            CVDisplayLinkStop(link)
            cvDisplayLink = nil
        }
        lastTimestamp = nil
    }

    private func stepFrame() {
        guard canTick, let player else { return }
        let now = CACurrentMediaTime()
        let dtSeconds: CFTimeInterval
        if let last = lastTimestamp {
            dtSeconds = max(0.0, min(0.25, now - last))
        } else {
            dtSeconds = 1.0 / 60.0
        }
        lastTimestamp = now

        player.tick(dtMillis: dtSeconds * 1000.0)
        if canRender && player.needsRender {
            player.render()
            fpsSampleRenderCount += 1
        }

        if fpsSampleStartTimestamp == 0 {
            fpsSampleStartTimestamp = now
            fpsSampleStartSwfFrames = player.frameTimings.framesRun
        } else {
            let elapsed = now - fpsSampleStartTimestamp
            if elapsed >= 0.5 {
                let timings = player.frameTimings
                let swfDelta = timings.framesRun >= fpsSampleStartSwfFrames
                    ? (timings.framesRun - fpsSampleStartSwfFrames)
                    : 0
                currentRenderFPS = Double(fpsSampleRenderCount) / elapsed
                currentSwfFPS = Double(swfDelta) / elapsed
                fpsSampleStartTimestamp = now
                fpsSampleRenderCount = 0
                fpsSampleStartSwfFrames = timings.framesRun
            }
        }
    }

    // MARK: - Mouse Event Handling

    private func pixelLocation(for event: NSEvent) -> CGPoint {
        syncDrawableSizeIfNeeded()
        let loc = convert(event.locationInWindow, from: nil)
        let scale = effectiveScaleFactor
        return CGPoint(x: loc.x * scale, y: loc.y * scale)
    }

    override public func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let player else { return }
        let loc = pixelLocation(for: event)
        player.touchDown(x: Double(loc.x), y: Double(loc.y))
        renderIfPossible()
    }

    override public func mouseDragged(with event: NSEvent) {
        guard let player else { return }
        let loc = pixelLocation(for: event)
        player.touchMove(x: Double(loc.x), y: Double(loc.y))
        if player.needsRender {
            renderIfPossible()
        }
    }

    override public func mouseUp(with event: NSEvent) {
        guard let player else { return }
        let loc = pixelLocation(for: event)
        player.touchUp(x: Double(loc.x), y: Double(loc.y))
        renderIfPossible()
    }

    override public func rightMouseDown(with event: NSEvent) {
        // Flash right click can also be sent as touch down or handled
        mouseDown(with: event)
    }

    override public func rightMouseUp(with event: NSEvent) {
        mouseUp(with: event)
    }

    override public func mouseMoved(with event: NSEvent) {
        guard let player else { return }
        let loc = pixelLocation(for: event)
        player.touchMove(x: Double(loc.x), y: Double(loc.y))
        if player.needsRender {
            renderIfPossible()
        }
    }

    override public func scrollWheel(with event: NSEvent) {
        guard let player else { return }
        // Keep mouse location updated under cursor
        let loc = pixelLocation(for: event)
        player.touchMove(x: Double(loc.x), y: Double(loc.y))

        // In AppKit, event.scrollingDeltaY is in points/pixels or lines depending on hasPreciseScrollingDeltas.
        // For discrete mouse wheels: deltaY is in lines (~1.0, -1.0).
        // For trackpads: hasPreciseScrollingDeltas is true and scrollingDeltaY is in points.
        let deltaY: Double
        let deltaX: Double
        if event.hasPreciseScrollingDeltas {
            deltaY = Double(event.scrollingDeltaY) / 10.0
            deltaX = Double(event.scrollingDeltaX) / 10.0
        } else {
            deltaY = Double(event.deltaY)
            deltaX = Double(event.deltaX)
        }

        if abs(deltaY) > 0.01 || abs(deltaX) > 0.01 {
            player.mouseWheel(deltaX: deltaX, deltaY: deltaY)
            renderIfPossible()
        }
    }

    // MARK: - Keyboard Handling

    override public func keyDown(with event: NSEvent) {
        guard let player else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 36, 76: // Enter / Return
            player.insertNewline()
            renderIfPossible()
        case 51: // Backspace / Delete
            player.deleteBackward()
            renderIfPossible()
        default:
            // Allow input system to handle characters or pass string
            if let chars = event.characters, !chars.isEmpty {
                // Filter out control characters (function keys, arrow keys with unicode scalars)
                let first = chars.unicodeScalars.first
                if let val = first?.value, val >= 0xF700 && val <= 0xF8FF {
                    // macOS private use area for function/arrow keys
                    super.keyDown(with: event)
                } else {
                    player.insertText(chars)
                    renderIfPossible()
                }
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override public func keyUp(with event: NSEvent) {
        // Flash keyUp
        renderIfPossible()
    }

    // MARK: - NSTextInputClient

    public func insertText(_ string: Any, replacementRange: NSRange) {
        guard let player else { return }
        if let str = string as? String {
            if str == "\n" || str == "\r" {
                player.insertNewline()
            } else {
                player.insertText(str)
            }
            renderIfPossible()
        }
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
    public func unmarkText() {}
    public func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    public func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    public func hasMarkedText() -> Bool { false }
    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect { .zero }
    public func characterIndex(for point: NSPoint) -> Int { 0 }
}
#endif

