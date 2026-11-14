//
//  AppDelegate.swift
//  ruffle-demo-macos
//
//  Created by farhandika on 05/11/26.
//

import Cocoa
import SwiftUI
import FlashPlayerKit
import LuaKit
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

    // Native Lucent managers & tool windows
    private let bridge = LucentBridge()
    private lazy var environmentManager = EnvironmentManager(bridge: bridge)
    private lazy var combatEngine = CombatEngine(bridge: bridge)
    private lazy var packetManager = PacketManager(bridge: bridge)
    private lazy var followerManager = FollowerManager(bridge: bridge)
    private lazy var autoReloginManager = AutoReloginManager(bridge: bridge)
    private let luaEngine = LuaEngine()
    private lazy var luaSDK = LuaLucentSDK(
        engine: luaEngine,
        bridge: bridge,
        envManager: environmentManager,
        combatEngine: combatEngine
    )

    private var environmentWindow: NSWindow?
    private var combatWindow: NSWindow?
    private var packetsWindow: NSWindow?
    private var loaderWindow: NSWindow?
    private var travelWindow: NSWindow?
    private var scriptRunnerWindow: NSWindow?

    // Option states (default matching AQW client defaults)
    private var optInfiniteRange = false
    private var optProvokeCell = false
    private var optEnemyMagnet = false
    private var optHidePlayers = false
    private var optSkipCutscenes = false
    private var optAnimationsEnabled = true
    private var optCollisionsEnabled = true
    private var optDeathAdsVisible = true
    private var optLagKiller = false

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupWindowAndPlayer()
        setupMenuBar()
        startMetricsTimer()

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.hasLoadedInitialSWF else { return }
            if let defaultSWF = Bundle.main.url(forResource: "loader-animation", withExtension: "swf") {
                self.loadSWF(url: defaultSWF)
            } else {
                self.openSWFPanel()
            }
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

        // Wire Lucent bridge & ActionScript ExternalInterface calls
        bridge.player = playerView.player
        bridge.onPacketFromClient = { [weak self] payload in
            self?.packetManager.record(direction: .client, payload: payload)
        }
        bridge.onPacketFromServer = { [weak self] payload in
            self?.packetManager.record(direction: .server, payload: payload)
        }
        bridge.onConnectionEvent = { [weak self] event in
            self?.autoReloginManager.handleConnectionEvent(event)
            self?.appendLog(method: "Connection", detail: event, isSystem: true)
        }

        playerView.player?.onExternalCall = { [weak self] name, args in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.bridge.handleExternalCall(name: name, args: args)

                if name == "onProgress" || name == "progress",
                   let pct = args.first as? Int ?? (args.first as? Double).map(Int.init) {
                    self.updateProgress(percent: pct)
                } else if name == "onLoaded" || name == "loaded" {
                    self.hideLoadingOverlay()
                }

                let argsStr = args.map { "\($0)" }.joined(separator: ", ")
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
            bridge.player = playerView.player
            bridge.isGameLoaded = false
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

        // 2. Tools Menu (Bank + Travel Shortcuts)
        let toolsMenu = NSMenu(title: "Game Tools")
        let toolsMenuItem = NSMenuItem(title: "Game Tools", action: nil, keyEquivalent: "")
        toolsMenuItem.submenu = toolsMenu

        let openBankItem = NSMenuItem(title: "Open Bank", action: #selector(openBankAction), keyEquivalent: "b")
        let checkBankItem = NSMenuItem(title: "Check If Bank Is Open", action: #selector(checkBankAction), keyEquivalent: "")
        let reloadMapItem = NSMenuItem(title: "Reload Map", action: #selector(reloadMapAction), keyEquivalent: "r")
        let setSpawnItem = NSMenuItem(title: "Set Spawn Point", action: #selector(setSpawnPointAction), keyEquivalent: "")

        toolsMenu.items = [
            openBankItem,
            checkBankItem,
            NSMenuItem.separator(),
            reloadMapItem,
            setSpawnItem
        ]

        // 3. Options Menu (settings.* parity)
        let optionsMenu = NSMenu(title: "Options")
        let optionsMenuItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        optionsMenuItem.submenu = optionsMenu

        let infiniteRangeItem = NSMenuItem(title: "Infinite Range", action: #selector(toggleInfiniteRange), keyEquivalent: "")
        let provokeCellItem = NSMenuItem(title: "Provoke Cell", action: #selector(toggleProvokeCell), keyEquivalent: "")
        let enemyMagnetItem = NSMenuItem(title: "Enemy Magnet", action: #selector(toggleEnemyMagnet), keyEquivalent: "")
        let hidePlayersItem = NSMenuItem(title: "Hide Other Players", action: #selector(toggleHidePlayers), keyEquivalent: "")
        let skipCutscenesItem = NSMenuItem(title: "Skip Cutscenes", action: #selector(toggleSkipCutscenes), keyEquivalent: "")
        let disableAnimItem = NSMenuItem(title: "Disable Animations", action: #selector(toggleDisableAnimations), keyEquivalent: "")
        let disableCollisionsItem = NSMenuItem(title: "Disable Collisions", action: #selector(toggleDisableCollisions), keyEquivalent: "")
        let disableDeathAdsItem = NSMenuItem(title: "Disable Death Ads", action: #selector(toggleDisableDeathAds), keyEquivalent: "")
        let lagKillerItem = NSMenuItem(title: "Lag Killer", action: #selector(toggleLagKiller), keyEquivalent: "")

        let walkSpeedItem = NSMenuItem(title: "Walk Speed…", action: #selector(promptWalkSpeed), keyEquivalent: "")
        let fpsItem = NSMenuItem(title: "Set FPS…", action: #selector(promptFrameRate), keyEquivalent: "")
        let customNameItem = NSMenuItem(title: "Custom Name…", action: #selector(promptCustomName), keyEquivalent: "")
        let customGuildItem = NSMenuItem(title: "Custom Guild…", action: #selector(promptCustomGuild), keyEquivalent: "")

        optionsMenu.items = [
            infiniteRangeItem,
            provokeCellItem,
            enemyMagnetItem,
            hidePlayersItem,
            skipCutscenesItem,
            disableAnimItem,
            disableCollisionsItem,
            disableDeathAdsItem,
            lagKillerItem,
            NSMenuItem.separator(),
            walkSpeedItem,
            fpsItem,
            NSMenuItem.separator(),
            customNameItem,
            customGuildItem
        ]

        // 4. Combat Menu
        let combatMenu = NSMenu(title: "Combat")
        let combatMenuItem = NSMenuItem(title: "Combat", action: nil, keyEquivalent: "")
        combatMenuItem.submenu = combatMenu

        let toggleAttackItem = NSMenuItem(title: "Toggle Auto-Attack", action: #selector(toggleAutoAttackAction), keyEquivalent: "a")
        toggleAttackItem.keyEquivalentModifierMask = [.command, .shift]
        let combatProfilesItem = NSMenuItem(title: "Combat Profiles…", action: #selector(showCombatWindow), keyEquivalent: "")

        combatMenu.items = [
            toggleAttackItem,
            NSMenuItem.separator(),
            combatProfilesItem
        ]

        // 5. Windows Menu (Native SwiftUI Tool Panels)
        let panelsMenu = NSMenu(title: "Panels")
        let panelsMenuItem = NSMenuItem(title: "Panels", action: nil, keyEquivalent: "")
        panelsMenuItem.submenu = panelsMenu

        let envPanelItem = NSMenuItem(title: "Environment (Drops, Quests, Boosts)…", action: #selector(showEnvironmentWindow), keyEquivalent: "e")
        envPanelItem.keyEquivalentModifierMask = [.command, .shift]
        let packetsPanelItem = NSMenuItem(title: "Packets (Logger & Spammer)…", action: #selector(showPacketsWindow), keyEquivalent: "p")
        packetsPanelItem.keyEquivalentModifierMask = [.command, .shift]
        let loaderPanelItem = NSMenuItem(title: "Loader / Grabber…", action: #selector(showLoaderWindow), keyEquivalent: "g")
        loaderPanelItem.keyEquivalentModifierMask = [.command, .shift]
        let travelPanelItem = NSMenuItem(title: "Travel, Follower & Auto-Relogin…", action: #selector(showTravelWindow), keyEquivalent: "t")
        travelPanelItem.keyEquivalentModifierMask = [.command, .shift]
        let scriptRunnerItem = NSMenuItem(title: "Script Runner (Lua)…", action: #selector(showScriptRunnerWindow), keyEquivalent: "l")
        scriptRunnerItem.keyEquivalentModifierMask = [.command, .shift]
        let telemetryPanelItem = NSMenuItem(title: "Telemetry & Call Logs…", action: #selector(showLogsWindow), keyEquivalent: "l")

        panelsMenu.items = [
            envPanelItem,
            packetsPanelItem,
            loaderPanelItem,
            travelPanelItem,
            scriptRunnerItem,
            NSMenuItem.separator(),
            telemetryPanelItem
        ]

        // 6. Debug & Telemetry Menu
        let debugMenu = NSMenu(title: "Telemetry")
        let debugMenuItem = NSMenuItem(title: "Telemetry", action: nil, keyEquivalent: "")
        debugMenuItem.submenu = debugMenu

        let statusItem = NSMenuItem(title: "FPS: — • CPU: — • RAM: —", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        self.statusMenuItem = statusItem

        let viewLogsItem = NSMenuItem(title: "Show Telemetry & Call Logs...", action: #selector(showLogsWindow), keyEquivalent: "")

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
        mainMenu.insertItem(optionsMenuItem, at: insertIndex + 2)
        mainMenu.insertItem(combatMenuItem, at: insertIndex + 3)
        mainMenu.insertItem(panelsMenuItem, at: insertIndex + 4)
        mainMenu.insertItem(debugMenuItem, at: insertIndex + 5)
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
        if bridge.isBankOpen() {
            appendLog(method: "Bank", detail: "bank.isOpen == true; skipping bank.open request", isSystem: true)
            NSSound.beep()
            return
        }
        appendLog(method: "Bank", detail: "Calling bank.open via ExternalInterface...", isSystem: true)
        bridge.openBank()
    }

    @objc private func checkBankAction() {
        let isBankOpen = bridge.isBankOpen()
        appendLog(method: "Bank", detail: "bank.isOpen result: \(isBankOpen)", isSystem: true)
    }

    @objc private func reloadMapAction() {
        bridge.reloadMap()
        appendLog(method: "Travel", detail: "Reloaded current map", isSystem: true)
    }

    @objc private func setSpawnPointAction() {
        bridge.setSpawnPoint()
        appendLog(method: "Travel", detail: "Set spawn point to current cell/pad", isSystem: true)
    }

    @objc private func toggleAutoAttackAction() {
        combatEngine.toggleAutoAttack()
        appendLog(method: "Combat", detail: combatEngine.isAutoAttacking ? "Auto-Attack Started" : "Auto-Attack Stopped", isSystem: true)
    }

    // MARK: - Options Actions

    @objc private func toggleInfiniteRange(_ sender: NSMenuItem) {
        optInfiniteRange.toggle()
        sender.state = optInfiniteRange ? .on : .off
        bridge.setInfiniteRange(optInfiniteRange)
    }

    @objc private func toggleProvokeCell(_ sender: NSMenuItem) {
        optProvokeCell.toggle()
        sender.state = optProvokeCell ? .on : .off
        bridge.setProvokeCell(optProvokeCell)
    }

    @objc private func toggleEnemyMagnet(_ sender: NSMenuItem) {
        optEnemyMagnet.toggle()
        sender.state = optEnemyMagnet ? .on : .off
        bridge.setEnemyMagnet(optEnemyMagnet)
    }

    @objc private func toggleHidePlayers(_ sender: NSMenuItem) {
        optHidePlayers.toggle()
        sender.state = optHidePlayers ? .on : .off
        bridge.setOtherPlayersVisible(!optHidePlayers)
    }

    @objc private func toggleSkipCutscenes(_ sender: NSMenuItem) {
        optSkipCutscenes.toggle()
        sender.state = optSkipCutscenes ? .on : .off
        bridge.setSkipCutscenes(optSkipCutscenes)
    }

    @objc private func toggleDisableAnimations(_ sender: NSMenuItem) {
        optAnimationsEnabled.toggle()
        sender.state = optAnimationsEnabled ? .off : .on
        bridge.setAnimationsEnabled(optAnimationsEnabled)
    }

    @objc private func toggleDisableCollisions(_ sender: NSMenuItem) {
        optCollisionsEnabled.toggle()
        sender.state = optCollisionsEnabled ? .off : .on
        bridge.setCollisionsEnabled(optCollisionsEnabled)
    }

    @objc private func toggleDisableDeathAds(_ sender: NSMenuItem) {
        optDeathAdsVisible.toggle()
        sender.state = optDeathAdsVisible ? .off : .on
        bridge.setDeathAdsVisible(optDeathAdsVisible)
    }

    @objc private func toggleLagKiller(_ sender: NSMenuItem) {
        optLagKiller.toggle()
        sender.state = optLagKiller ? .on : .off
        bridge.setLagKillerEnabled(optLagKiller)
    }

    @objc private func promptWalkSpeed() {
        promptTextInput(title: "Walk Speed", message: "Enter walk speed (default 8):", defaultValue: "8") { [weak self] value in
            if let speed = Int(value) {
                self?.bridge.setWalkSpeed(speed)
            }
        }
    }

    @objc private func promptFrameRate() {
        promptTextInput(title: "Set Frame Rate", message: "Enter target FPS (e.g. 24, 30, 60):", defaultValue: "24") { [weak self] value in
            if let fps = Int(value) {
                self?.bridge.setFrameRate(fps)
            }
        }
    }

    @objc private func promptCustomName() {
        promptTextInput(title: "Custom Name", message: "Enter custom character name (leave empty to reset):", defaultValue: "") { [weak self] value in
            if value.isEmpty {
                self?.bridge.resetCustomName()
            } else {
                self?.bridge.setCustomName(value)
            }
        }
    }

    @objc private func promptCustomGuild() {
        promptTextInput(title: "Custom Guild", message: "Enter custom guild name (leave empty to reset):", defaultValue: "") { [weak self] value in
            if value.isEmpty {
                self?.bridge.resetCustomGuild()
            } else {
                self?.bridge.setCustomGuild(value)
            }
        }
    }

    private func promptTextInput(title: String, message: String, defaultValue: String, onConfirm: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = defaultValue
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            onConfirm(input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - Native SwiftUI Tool Windows

    @objc private func showEnvironmentWindow() {
        presentPanel(
            title: "Environment — Drops, Quests & Boosts",
            size: NSSize(width: 500, height: 420),
            existing: &environmentWindow,
            rootView: EnvironmentPanelView(manager: environmentManager)
        )
    }

    @objc private func showCombatWindow() {
        presentPanel(
            title: "Combat Profiles & Auto-Attack",
            size: NSSize(width: 600, height: 390),
            existing: &combatWindow,
            rootView: CombatProfilesPanelView(engine: combatEngine)
        )
    }

    @objc private func showPacketsWindow() {
        presentPanel(
            title: "Packets — Logger & Spammer",
            size: NSSize(width: 680, height: 470),
            existing: &packetsWindow,
            rootView: PacketsPanelView(manager: packetManager)
        )
    }

    @objc private func showLoaderWindow() {
        presentPanel(
            title: "Loader / Grabber",
            size: NSSize(width: 700, height: 500),
            existing: &loaderWindow,
            rootView: LoaderGrabberPanelView(bridge: bridge)
        )
    }

    @objc private func showTravelWindow() {
        presentPanel(
            title: "Travel, Follower & Auto-Relogin",
            size: NSSize(width: 650, height: 450),
            existing: &travelWindow,
            rootView: TravelFollowerReloginPanelView(
                bridge: bridge,
                follower: followerManager,
                relogin: autoReloginManager
            )
        )
    }

    @objc private func showScriptRunnerWindow() {
        presentPanel(
            title: "Script Runner — Lua 5.4",
            size: NSSize(width: 720, height: 520),
            existing: &scriptRunnerWindow,
            rootView: ScriptRunnerPanelView(engine: luaEngine, sdk: luaSDK)
        )
    }

    private func presentPanel<Content: View>(
        title: String,
        size: NSSize,
        existing: inout NSWindow?,
        rootView: Content
    ) {
        if let win = existing {
            win.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: rootView)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = title
        win.isReleasedWhenClosed = false
        win.contentViewController = hosting
        win.center()
        win.makeKeyAndOrderFront(nil)
        existing = win
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
