//
//  AppDelegate.swift
//  ruffle-demo-macos
//
//  Created by farhandika on 05/11/26.
//

import Cocoa
import FlashPlayerKit
import UniformTypeIdentifiers

struct TelemetryLogEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let method: String
    let detail: String
    let isSystem: Bool
}

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {

    @IBOutlet var window: NSWindow!
    private var flashPlayerView: NSFlashPlayerView?

    // Loading overlay & empty state
    private var hasLoadedInitialSWF = false
    private let emptyStateButton = NSButton(title: "Open SWF… (⌘O)", target: nil, action: nil)
    private let loadingOverlay = NSVisualEffectView()
    private let progressIndicator = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: "Loading game files...")

    // Status / metrics
    private var metricsTimer: Timer?
    private var statusMenuItem: NSMenuItem?
    private var logEntries: [TelemetryLogEntry] = []
    private var logsWindow: NSWindow?
    private var logsTableView: NSTableView?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupWindowAndPlayer()
        setupMenuBar()
        startMetricsTimer()

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.hasLoadedInitialSWF else { return }
            self.openSWFPanel()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if flashPlayerView != nil {
            loadSWF(url: url)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.loadSWF(url: url)
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        metricsTimer?.invalidate()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Window & Player Setup

    private func setupWindowAndPlayer() {
        guard let window = self.window else { return }

        window.title = "Ruffle macOS — FlashPlayerKit"
        window.setContentSize(NSSize(width: 1280, height: 720))
        window.center()

        guard let contentView = window.contentView else { return }

        let playerView = NSFlashPlayerView(frame: contentView.bounds)
        playerView.autoresizingMask = [.width, .height]
        contentView.addSubview(playerView)
        self.flashPlayerView = playerView

        setupLoadingOverlay(in: contentView)
        setupEmptyStateButton(in: contentView)

        // Wire ActionScript ExternalInterface calls
        playerView.player?.onExternalCall = { [weak self] name, args in
            guard let self = self else { return }

            if name == "onProgress" || name == "progress",
               let pct = args.first as? Int ?? (args.first as? Double).map(Int.init) {
                DispatchQueue.main.async {
                    self.updateProgress(percent: pct)
                }
            } else if name == "onLoaded" || name == "loaded" {
                DispatchQueue.main.async {
                    self.hideLoadingOverlay()
                }
            }

            let argsStr = args.map { "\($0)" }.joined(separator: ", ")
            DispatchQueue.main.async {
                self.appendLog(method: name, detail: argsStr.isEmpty ? "—" : argsStr, isSystem: false)
            }
        }

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(playerView)
    }

    // MARK: - SWF File Picker & Loading

    @objc private func openSWFPanel() {
        let panel = NSOpenPanel()
        panel.title = "Select a Flash SWF File"
        panel.message = "Choose an .swf file to play in Ruffle"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let swfType = UTType(filenameExtension: "swf") {
            panel.allowedContentTypes = [swfType]
        }

        let handleResult: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            self.loadSWF(url: url)
        }

        if let window = self.window {
            panel.beginSheetModal(for: window, completionHandler: handleResult)
        } else if panel.runModal() == .OK, let url = panel.url {
            loadSWF(url: url)
        }
    }

    private func loadSWF(url: URL) {
        guard let playerView = self.flashPlayerView else { return }
        hasLoadedInitialSWF = true
        emptyStateButton.isHidden = true
        loadingOverlay.isHidden = true
        loadingOverlay.alphaValue = 1.0
        progressIndicator.stopAnimation(nil)

        do {
            try playerView.load(fileURL: url)
            window?.title = "Ruffle macOS — \(url.lastPathComponent)"
            appendLog(method: "Load SWF", detail: url.path, isSystem: true)
            window?.makeFirstResponder(playerView)
        } catch {
            appendLog(method: "Load Error", detail: error.localizedDescription, isSystem: true)
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    // MARK: - Menu Bar Setup (Flash, Quality, Tools, Logs)

    private func setupMenuBar() {
        guard let mainMenu = NSApplication.shared.mainMenu else { return }

        // 0. File -> Open SWF... (⌘O)
        let openItem = NSMenuItem(title: "Open SWF…", action: #selector(openSWFPanel), keyEquivalent: "o")
        if let fileMenu = mainMenu.item(withTitle: "File")?.submenu {
            fileMenu.insertItem(openItem, at: 0)
            fileMenu.insertItem(NSMenuItem.separator(), at: 1)
        } else {
            let fileMenu = NSMenu(title: "File")
            fileMenu.addItem(openItem)
            let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
            fileMenuItem.submenu = fileMenu
            mainMenu.insertItem(fileMenuItem, at: min(1, mainMenu.items.count))
        }

        // 1. Flash Controls Menu
        let flashMenu = NSMenu(title: "Flash")
        let flashMenuItem = NSMenuItem(title: "Flash", action: nil, keyEquivalent: "")
        flashMenuItem.submenu = flashMenu

        // Quality Submenu
        let qualityItem = NSMenuItem(title: "Quality", action: nil, keyEquivalent: "")
        let qualityMenu = NSMenu(title: "Quality")
        let lowItem = NSMenuItem(title: "Low", action: #selector(setQualityLow), keyEquivalent: "1")
        let medItem = NSMenuItem(title: "Medium", action: #selector(setQualityMedium), keyEquivalent: "2")
        let highItem = NSMenuItem(title: "High (MSAA 4x)", action: #selector(setQualityHigh), keyEquivalent: "3")
        highItem.state = .on
        qualityMenu.items = [lowItem, medItem, highItem]
        qualityItem.submenu = qualityMenu

        // Smooth Motion Item
        let smoothMotionItem = NSMenuItem(title: "Smooth Motion (Interpolation)", action: #selector(toggleSmoothMotion), keyEquivalent: "m")
        smoothMotionItem.state = .off

        // Play / Pause Item
        let playPauseItem = NSMenuItem(title: "Pause Playback", action: #selector(togglePlayPause), keyEquivalent: "p")

        // Free Memory Item
        let freeMemoryItem = NSMenuItem(title: "Free Memory & GC", action: #selector(freeMemory), keyEquivalent: "k")

        flashMenu.items = [
            qualityItem,
            smoothMotionItem,
            NSMenuItem.separator(),
            playPauseItem,
            freeMemoryItem
        ]

        // 2. Tools Menu (In-game Actions like Bank)
        let toolsMenu = NSMenu(title: "Game Tools")
        let toolsMenuItem = NSMenuItem(title: "Game Tools", action: nil, keyEquivalent: "")
        toolsMenuItem.submenu = toolsMenu

        let openBankItem = NSMenuItem(title: "Open Bank", action: #selector(openBankAction), keyEquivalent: "b")
        let checkBankItem = NSMenuItem(title: "Check If Bank Is Open", action: #selector(checkBankAction), keyEquivalent: "")

        toolsMenu.items = [
            openBankItem,
            checkBankItem
        ]

        // 3. Debug & Telemetry Menu
        let debugMenu = NSMenu(title: "Telemetry")
        let debugMenuItem = NSMenuItem(title: "Telemetry", action: nil, keyEquivalent: "")
        debugMenuItem.submenu = debugMenu

        let statusItem = NSMenuItem(title: "FPS: — • CPU: — • RAM: —", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        self.statusMenuItem = statusItem

        let viewLogsItem = NSMenuItem(title: "Show Telemetry & Call Logs...", action: #selector(showLogsWindow), keyEquivalent: "l")

        debugMenu.items = [
            statusItem,
            NSMenuItem.separator(),
            viewLogsItem
        ]

        // Insert before Window menu
        let windowIndex = mainMenu.indexOfItem(withTitle: "Window")
        let insertIndex = windowIndex > 0 ? windowIndex : mainMenu.items.count - 1
        mainMenu.insertItem(flashMenuItem, at: insertIndex)
        mainMenu.insertItem(toolsMenuItem, at: insertIndex + 1)
        mainMenu.insertItem(debugMenuItem, at: insertIndex + 2)
    }

    // MARK: - Menu Actions

    @objc private func setQualityLow(_ sender: NSMenuItem) {
        flashPlayerView?.player?.quality = .low
        updateQualityMenuState(selected: sender)
        appendLog(method: "Quality", detail: "Set to Low", isSystem: true)
    }

    @objc private func setQualityMedium(_ sender: NSMenuItem) {
        flashPlayerView?.player?.quality = .medium
        updateQualityMenuState(selected: sender)
        appendLog(method: "Quality", detail: "Set to Medium", isSystem: true)
    }

    @objc private func setQualityHigh(_ sender: NSMenuItem) {
        flashPlayerView?.player?.quality = .high
        updateQualityMenuState(selected: sender)
        appendLog(method: "Quality", detail: "Set to High (MSAA 4x)", isSystem: true)
    }

    private func updateQualityMenuState(selected: NSMenuItem) {
        guard let parent = selected.parent?.submenu else { return }
        for item in parent.items {
            item.state = (item == selected) ? .on : .off
        }
    }

    @objc private func toggleSmoothMotion(_ sender: NSMenuItem) {
        guard let player = flashPlayerView?.player else { return }
        let current = player.isSmoothMotionEnabled
        player.isSmoothMotionEnabled = !current
        sender.state = !current ? .on : .off
        appendLog(method: "Smooth Motion", detail: !current ? "Enabled" : "Disabled", isSystem: true)
    }

    @objc private func togglePlayPause(_ sender: NSMenuItem) {
        guard let player = flashPlayerView?.player else { return }
        let current = player.isPlaying
        player.isPlaying = !current
        sender.title = !current ? "Pause Playback" : "Resume Playback"
        appendLog(method: "Playback", detail: !current ? "Playing" : "Paused", isSystem: true)
    }

    @objc private func freeMemory() {
        flashPlayerView?.player?.releaseMemory()
        appendLog(method: "Memory", detail: "Garbage collection & GPU buffers purged", isSystem: true)
    }

    @objc private func openBankAction() {
        guard let player = flashPlayerView?.player else { return }

        let isOpenResult = player.callExternalInterface(name: "bank.isOpen", arguments: [])
        let isBankOpen = (isOpenResult as? Bool) ?? false

        if isBankOpen {
            appendLog(method: "Bank", detail: "bank.isOpen == true; skipping bank.open request", isSystem: true)
            NSSound.beep()
            return
        }

        appendLog(method: "Bank", detail: "Calling bank.open via ExternalInterface...", isSystem: true)
        player.callExternalInterface(name: "bank.open", arguments: [])
    }

    @objc private func checkBankAction() {
        guard let player = flashPlayerView?.player else { return }
        let isOpenResult = player.callExternalInterface(name: "bank.isOpen", arguments: [])
        let isBankOpen = (isOpenResult as? Bool) ?? false
        appendLog(method: "Bank", detail: "bank.isOpen result: \(isBankOpen)", isSystem: true)
    }

    // MARK: - Telemetry & Metrics Loop

    private func startMetricsTimer() {
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let playerView = self.flashPlayerView else { return }
            let fps = Int(playerView.currentSwfFPS.rounded())
            let cpu = Int(Self.readProcessCPUPercent().rounded())
            let ram = Int(Self.readPhysicalFootprintMB().rounded())
            self.statusMenuItem?.title = "FPS: \(fps) • CPU: \(cpu)% • RAM: \(ram) MB"
        }
    }

    private static func readProcessCPUPercent() -> Double {
        var threadsList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let kerr = task_threads(mach_task_self_, &threadsList, &threadCount)
        guard kerr == KERN_SUCCESS, let threads = threadsList else { return 0.0 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), vm_size_t(threadCount * UInt32(MemoryLayout<thread_t>.size)))
        }
        var totalUsageMicroseconds: Double = 0.0
        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            let res = withUnsafeMutablePointer(to: &threadInfo) { ptr in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), intPtr, &count)
                }
            }
            if res == KERN_SUCCESS && (threadInfo.flags & TH_FLAGS_IDLE) == 0 {
                totalUsageMicroseconds += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }
        return totalUsageMicroseconds
    }

    private static func readPhysicalFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0.0 }
        return Double(info.phys_footprint) / (1024.0 * 1024.0)
    }

    // MARK: - Logs Window

    private func appendLog(method: String, detail: String, isSystem: Bool) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let entry = TelemetryLogEntry(timestamp: timestamp, method: method, detail: detail, isSystem: isSystem)
        logEntries.append(entry)
        if logEntries.count > 300 {
            logEntries.removeFirst(logEntries.count - 300)
        }
        logsTableView?.reloadData()
        logsTableView?.scrollToEndOfDocument(nil)
    }

    @objc private func showLogsWindow() {
        if let window = logsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Telemetry & ActionScript Logs"
        window.center()

        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true

        let tableView = NSTableView(frame: scrollView.bounds)
        tableView.autoresizingMask = [.width, .height]

        let timeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("time"))
        timeCol.title = "Time"
        timeCol.width = 90

        let methodCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("method"))
        methodCol.title = "Method"
        methodCol.width = 160

        let detailCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("detail"))
        detailCol.title = "Detail"
        detailCol.width = 380

        tableView.addTableColumn(timeCol)
        tableView.addTableColumn(methodCol)
        tableView.addTableColumn(detailCol)

        tableView.dataSource = self
        tableView.delegate = self
        scrollView.documentView = tableView
        window.contentView?.addSubview(scrollView)

        self.logsTableView = tableView
        self.logsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        logEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < logEntries.count else { return nil }
        let entry = logEntries[row]
        let identifier = tableColumn?.identifier.rawValue ?? ""

        let text: String
        var color: NSColor = .labelColor
        if identifier == "time" {
            text = entry.timestamp
            color = .secondaryLabelColor
        } else if identifier == "method" {
            text = entry.method
            color = entry.isSystem ? .systemBlue : .systemOrange
        } else {
            text = entry.detail
        }

        let textField = NSTextField(labelWithString: text)
        textField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textField.textColor = color
        return textField
    }

    // MARK: - Empty State & Loading Overlay Helpers

    private func setupEmptyStateButton(in container: NSView) {
        emptyStateButton.bezelStyle = .rounded
        emptyStateButton.controlSize = .large
        emptyStateButton.font = .systemFont(ofSize: 14, weight: .semibold)
        emptyStateButton.target = self
        emptyStateButton.action = #selector(openSWFPanel)
        emptyStateButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(emptyStateButton)

        NSLayoutConstraint.activate([
            emptyStateButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyStateButton.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
    }

    private func setupLoadingOverlay(in container: NSView) {
        loadingOverlay.isHidden = true
        loadingOverlay.material = .hudWindow
        loadingOverlay.blendingMode = .withinWindow
        loadingOverlay.state = .active
        loadingOverlay.wantsLayer = true
        loadingOverlay.layer?.cornerRadius = 16
        loadingOverlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(loadingOverlay)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.startAnimation(nil)
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.addSubview(progressIndicator)

        progressLabel.font = .systemFont(ofSize: 13, weight: .medium)
        progressLabel.textColor = .white
        progressLabel.alignment = .center
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.addSubview(progressLabel)

        NSLayoutConstraint.activate([
            loadingOverlay.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            loadingOverlay.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            loadingOverlay.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            loadingOverlay.heightAnchor.constraint(equalToConstant: 90),

            progressIndicator.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            progressIndicator.topAnchor.constraint(equalTo: loadingOverlay.topAnchor, constant: 18),

            progressLabel.leadingAnchor.constraint(equalTo: loadingOverlay.leadingAnchor, constant: 16),
            progressLabel.trailingAnchor.constraint(equalTo: loadingOverlay.trailingAnchor, constant: -16),
            progressLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 10)
        ])
    }

    private func updateProgress(percent: Int) {
        if loadingOverlay.isHidden {
            loadingOverlay.isHidden = false
            loadingOverlay.alphaValue = 1.0
            progressIndicator.startAnimation(nil)
        }
        progressLabel.stringValue = "Loading game: \(percent)%"
        window?.title = "Ruffle macOS — FlashPlayerKit (\(percent)%)"
    }

    private func hideLoadingOverlay() {
        window?.title = "Ruffle macOS — FlashPlayerKit"
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            loadingOverlay.animator().alphaValue = 0.0
        } completionHandler: {
            self.loadingOverlay.isHidden = true
            self.progressIndicator.stopAnimation(nil)
        }
    }
}
