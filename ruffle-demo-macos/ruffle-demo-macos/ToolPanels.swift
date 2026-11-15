import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LuaKit

// MARK: - 1. Environment Panel (Drops, Quests, Boosts)

struct EnvironmentPanelView: View {
    @ObservedObject var manager: EnvironmentManager
    @State private var newDropItem = ""
    @State private var newQuestId = ""
    @State private var newRewardId = ""
    @State private var newBoostName = ""

    var body: some View {
        TabView {
            dropsTab
                .tabItem { Label("Drops", systemImage: "tray.and.arrow.down") }

            questsTab
                .tabItem { Label("Quests", systemImage: "checklist") }

            boostsTab
                .tabItem { Label("Boosts", systemImage: "bolt") }
        }
        .padding(14)
        .frame(minWidth: 460, minHeight: 380)
    }

    private var dropsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Auto-Pickup / Whitelist", isOn: $manager.dropsEnabled)
            Toggle("Reject Unregistered Drops", isOn: $manager.rejectUnregisteredDrops)

            HStack {
                TextField("Item name to whitelist...", text: $newDropItem)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addDrop)
                Button("Add", action: addDrop)
                    .disabled(newDropItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            List {
                ForEach(manager.whitelistItems, id: \.self) { item in
                    Text(item)
                }
                .onDelete(perform: manager.removeDropItem)
            }
            .listStyle(.bordered)
        }
        .padding(.top, 8)
    }

    private var questsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Auto-Quest Accept / Complete", isOn: $manager.questsEnabled)

            HStack {
                TextField("Quest ID", text: $newQuestId)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                TextField("Reward ID (optional)", text: $newRewardId)
                    .textFieldStyle(.roundedBorder)
                Button("Add", action: addQuest)
                    .disabled(Int(newQuestId.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
            }

            List {
                ForEach(manager.registeredQuests) { quest in
                    HStack {
                        Text("Quest #\(quest.questId)")
                            .fontWeight(.medium)
                        Spacer()
                        if let reward = quest.rewardItemId {
                            Text("Reward: \(reward)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: manager.removeQuest)
            }
            .listStyle(.bordered)
        }
        .padding(.top, 8)
    }

    private var boostsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Auto-Boost", isOn: $manager.boostsEnabled)

            HStack {
                TextField("Boost item name (e.g. XP Boost)...", text: $newBoostName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addBoost)
                Button("Add", action: addBoost)
                    .disabled(newBoostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            List {
                ForEach(manager.registeredBoosts, id: \.self) { boost in
                    Text(boost)
                }
                .onDelete(perform: manager.removeBoost)
            }
            .listStyle(.bordered)
        }
        .padding(.top, 8)
    }

    private func addDrop() {
        manager.addDropItem(newDropItem)
        newDropItem = ""
    }

    private func addQuest() {
        guard let qid = Int(newQuestId.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        let rid = Int(newRewardId.trimmingCharacters(in: .whitespacesAndNewlines))
        manager.addQuest(id: qid, rewardId: rid)
        newQuestId = ""
        newRewardId = ""
    }

    private func addBoost() {
        manager.addBoost(newBoostName)
        newBoostName = ""
    }
}

// MARK: - 2. Combat Profiles Panel

struct CombatProfilesPanelView: View {
    @ObservedObject var engine: CombatEngine

    private var selectedIndex: Int? {
        engine.profiles.firstIndex(where: { $0.id == engine.selectedProfileId })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(engine.isAutoAttacking ? "Stop Auto-Attack" : "Start Auto-Attack") {
                    engine.toggleAutoAttack()
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Text(engine.statusText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button("New Profile") {
                    engine.createProfile()
                }
                Button("Delete") {
                    engine.deleteSelectedProfile()
                }
                .disabled(engine.profiles.count <= 1)
            }

            Divider()

            HStack(alignment: .top, spacing: 14) {
                List(engine.profiles, selection: $engine.selectedProfileId) { profile in
                    Text(profile.name)
                        .tag(profile.id)
                }
                .listStyle(.bordered)
                .frame(width: 190)

                if let idx = selectedIndex {
                    profileEditor(profile: $engine.profiles[idx])
                } else {
                    Text("Select a combat profile.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 560, minHeight: 360)
    }

    private func profileEditor(profile: Binding<CombatProfile>) -> some View {
        let skillsBinding = Binding<String>(
            get: { profile.wrappedValue.skills.map(String.init).joined(separator: ", ") },
            set: { raw in
                let parsed = raw.split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    .filter { (1...5).contains($0) }
                if !parsed.isEmpty {
                    profile.wrappedValue.skills = parsed
                }
            }
        )

        return Form {
            Section("Rotation") {
                TextField("Profile Name", text: profile.name)
                TextField("Skills (1-5, comma separated)", text: skillsBinding)
                HStack {
                    TextField("Delay (ms)", value: profile.skillDelayMs, format: .number)
                        .frame(width: 90)
                    Text("ms")
                        .foregroundStyle(.secondary)
                }
                TextField("Target Query (* for any)", text: profile.targetQuery)
                Toggle("Pause on Boss Counter-Attack", isOn: profile.antiCounter)
            }

            Section {
                ForEach(profile.skillRules) { $rule in
                    HStack(spacing: 8) {
                        Toggle("", isOn: $rule.enabled)
                            .labelsHidden()

                        Picker("", selection: $rule.slot) {
                            ForEach(1...5, id: \.self) { slot in
                                Text("Skill \(slot)").tag(slot)
                            }
                        }
                        .frame(width: 85)

                        Picker("", selection: $rule.metric) {
                            ForEach(SkillConditionMetric.allCases) { metric in
                                Text(metric.rawValue).tag(metric)
                            }
                        }
                        .frame(width: 120)

                        if rule.metric != .always {
                            TextField("%", value: $rule.threshold, format: .number)
                                .frame(width: 55)
                            Text("%")
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            profile.wrappedValue.skillRules.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button("+ Add Rule (e.g. MP % ≤ 0)") {
                    profile.wrappedValue.skillRules.append(
                        SkillRule(slot: 5, metric: .playerMpBelow, threshold: 0, enabled: true)
                    )
                }
            } header: {
                Text("Conditional Skill Rules (Priority)")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 3. Packets Panel (Logger + Sender/Spammer)

struct PacketsPanelView: View {
    @ObservedObject var manager: PacketManager
    @State private var sendToServer = true

    private var filteredEntries: [PacketLogEntry] {
        let q = manager.filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return manager.entries }
        return manager.entries.filter { $0.payload.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Filter packets...", text: $manager.filterText)
                    .textFieldStyle(.roundedBorder)

                Button(manager.isPaused ? "Resume" : "Pause") {
                    manager.isPaused.toggle()
                }
                Button("Clear") {
                    manager.clear()
                }
            }

            List(filteredEntries) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.timestamp)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(entry.direction.rawValue)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(entry.direction == .client ? .blue : .green)
                    Text(entry.payload)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                .contextMenu {
                    Button("Copy Payload") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.payload, forType: .string)
                    }
                    Button("Use in Sender") {
                        manager.spamPacket = entry.payload
                    }
                }
            }
            .listStyle(.bordered)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Packet payload (e.g. %xt%zm%...)...", text: $manager.spamPacket)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Picker("", selection: $sendToServer) {
                        Text("To Server").tag(true)
                        Text("To Client").tag(false)
                    }
                    .frame(width: 110)

                    Button("Send Once") {
                        manager.sendOnce(manager.spamPacket, toServer: sendToServer)
                    }
                    .disabled(manager.spamPacket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack {
                    Text("Spam Interval (ms):")
                    TextField("ms", value: $manager.spamIntervalMs, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Button(manager.isSpamming ? "Stop Spam" : "Start Spam") {
                        manager.toggleSpam()
                    }
                    .disabled(!manager.isSpamming && manager.spamPacket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 640, minHeight: 440)
    }
}

// MARK: - 4. Loader / Grabber Panel

struct LoaderGrabberPanelView: View {
    @ObservedObject var bridge: LucentBridge
    @State private var shopIdText = ""
    @State private var hairShopIdText = ""
    @State private var questIdText = ""
    @State private var mapSwfText = ""
    @State private var grabbedOutput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Loader") {
                VStack(spacing: 8) {
                    HStack {
                        TextField("Shop ID", text: $shopIdText)
                            .textFieldStyle(.roundedBorder)
                        Button("Load Shop") {
                            if let id = Int(shopIdText.trimmingCharacters(in: .whitespaces)) {
                                bridge.loadShop(id)
                            }
                        }

                        TextField("Hair Shop ID", text: $hairShopIdText)
                            .textFieldStyle(.roundedBorder)
                        Button("Load Hair") {
                            if let id = Int(hairShopIdText.trimmingCharacters(in: .whitespaces)) {
                                bridge.loadHairShop(id)
                            }
                        }
                    }

                    HStack {
                        TextField("Quest ID", text: $questIdText)
                            .textFieldStyle(.roundedBorder)
                        Button("Load Quest") {
                            if let id = Int(questIdText.trimmingCharacters(in: .whitespaces)) {
                                bridge.loadQuest(id)
                            }
                        }

                        TextField("Map SWF path/URL", text: $mapSwfText)
                            .textFieldStyle(.roundedBorder)
                        Button("Load Map SWF") {
                            bridge.loadMapSwf(mapSwfText)
                        }

                        Button("Armor Customize") {
                            bridge.loadArmorCustomize()
                        }
                    }
                }
                .padding(6)
            }

            GroupBox("Grabber (Live Game Data)") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Inventory") { grabbedOutput = bridge.getInventoryJSON() ?? "[]" }
                        Button("Bank") { grabbedOutput = bridge.getBankItemsJSON() ?? "[]" }
                        Button("House") { grabbedOutput = bridge.getHouseJSON() ?? "[]" }
                        Button("Temp Inv") { grabbedOutput = bridge.getTempInventoryJSON() ?? "[]" }
                        Button("Player") { grabbedOutput = bridge.getPlayerDataJSON() ?? "{}" }
                        Button("Quests") { grabbedOutput = bridge.getAcceptedQuestsJSON() ?? "[]" }
                        Button("Cells") { grabbedOutput = bridge.getCells().joined(separator: ", ") }
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(grabbedOutput, forType: .string)
                        }
                        .disabled(grabbedOutput.isEmpty)
                    }

                    TextEditor(text: .constant(grabbedOutput))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(6)
            }
        }
        .padding(14)
        .frame(minWidth: 660, minHeight: 460)
    }
}

// MARK: - 5. Travel, Follower & Auto-Relogin Panel

struct TravelFollowerReloginPanelView: View {
    @ObservedObject var bridge: LucentBridge
    @ObservedObject var follower: FollowerManager
    @ObservedObject var relogin: AutoReloginManager

    @State private var mapName = ""
    @State private var cellName = "Enter"
    @State private var padName = "Spawn"
    @State private var cells: [String] = []
    @State private var pads: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Travel & Map") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Map name (e.g. battleon-1)", text: $mapName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Cell", text: $cellName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        TextField("Pad", text: $padName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        Button("Join Map") {
                            bridge.joinMap(mapName, cell: cellName, pad: padName)
                        }
                        .disabled(mapName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    HStack {
                        Button("Jump to Cell/Pad") {
                            bridge.jump(cell: cellName, pad: padName)
                        }
                        Button("Refresh Cells") {
                            cells = bridge.getCells()
                            pads = bridge.getCellPads()
                        }
                        if !cells.isEmpty {
                            Picker("Cell", selection: $cellName) {
                                ForEach(cells, id: \.self) { Text($0).tag($0) }
                            }
                            .frame(width: 140)
                        }
                        if !pads.isEmpty {
                            Picker("Pad", selection: $padName) {
                                ForEach(pads, id: \.self) { Text($0).tag($0) }
                            }
                            .frame(width: 130)
                        }
                        Spacer()
                        Button("Reload Map") { bridge.reloadMap() }
                        Button("Set Spawn Point") { bridge.setSpawnPoint() }
                    }
                }
                .padding(6)
            }

            GroupBox("Follower") {
                HStack {
                    TextField("Player username to follow", text: $follower.targetPlayer)
                        .textFieldStyle(.roundedBorder)
                    Button(follower.isFollowing ? "Stop Following" : "Follow Player") {
                        follower.toggle()
                    }
                }
                .padding(6)
            }

            GroupBox("Auto-Relogin") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle("Enable Auto-Relogin", isOn: $relogin.isEnabled)
                        Spacer()
                        Text(relogin.statusText)
                            .foregroundStyle(.secondary)
                        Button("Cancel Pending") {
                            relogin.cancelPending()
                        }
                    }

                    HStack {
                        TextField("Username", text: $relogin.username)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Password", text: $relogin.password)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        if relogin.servers.isEmpty {
                            TextField("Server Name", text: $relogin.serverName)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Picker("Server", selection: $relogin.serverName) {
                                ForEach(relogin.servers, id: \.self) { Text($0).tag($0) }
                            }
                        }
                        Button("Refresh Servers") {
                            relogin.refreshServers()
                        }
                        Text("Delay (s):")
                        TextField("s", value: $relogin.delaySeconds, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }
                }
                .padding(6)
            }
        }
        .padding(14)
        .frame(minWidth: 620, minHeight: 420)
    }
}

// MARK: - 6. Script Runner (Lua 5.4) Panel

struct ScriptRunnerPanelView: View {
    @ObservedObject var engine: LuaEngine
    let sdk: LuaLucentSDK

    @State private var scriptName = "bot.lua"
    @State private var scriptSource = """
    -- Sample Lucent Lua Script
    print("Map:", player.map(), "HP:", player.hp(), "/", player.maxHp())

    env.whitelistDrop("Bone Dust")
    env.enableDrops(true)

    for i = 1, 5 do
        if player.isLoaded() then
            if player.hp() < (player.maxHp() * 0.4) then
                print("Low HP, resting...")
                player.rest()
                sleep(1500)
            else
                kill("*")
            end
        end
        sleep(250)
    end
    print("Done!")
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Open .lua…") { openScript() }
                Button("Save .lua…") { saveScript() }
                Button("Reset State") { sdk.resetAndReload() }
                    .disabled(engine.isRunning)

                Spacer()

                Text(engine.statusText)
                    .font(.caption)
                    .foregroundStyle(engine.lastError != nil ? .red : .secondary)

                Button(engine.isRunning ? "Stop" : "Run") {
                    if engine.isRunning {
                        engine.stop()
                    } else {
                        engine.run(scriptSource, name: scriptName)
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }

            VSplitView {
                TextEditor(text: $scriptSource)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Console")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") { engine.clearLogs() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }

                    List(engine.consoleLogs) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.timestamp)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(entry.isError ? .red : .primary)
                                .textSelection(.enabled)
                        }
                    }
                    .listStyle(.bordered)
                    .frame(minHeight: 110)
                }
                .padding(.top, 6)
            }
        }
        .padding(14)
        .frame(minWidth: 680, minHeight: 500)
    }

    private func openScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let luaType = UTType(filenameExtension: "lua") {
            panel.allowedContentTypes = [luaType, .plainText]
        }
        if panel.runModal() == .OK, let url = panel.url,
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            scriptSource = contents
            scriptName = url.lastPathComponent
        }
    }

    private func saveScript() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = scriptName
        if let luaType = UTType(filenameExtension: "lua") {
            panel.allowedContentTypes = [luaType, .plainText]
        }
        if panel.runModal() == .OK, let url = panel.url {
            try? scriptSource.write(to: url, atomically: true, encoding: .utf8)
            scriptName = url.lastPathComponent
        }
    }
}


