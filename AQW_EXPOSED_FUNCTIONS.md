# AQW `loader.swf` (`lucent`) Exposed ExternalInterface Functions

This document lists all functions exposed by `loader.swf` (`lucent:Externalizer` / `BridgeRegistryGenerated`) via ActionScript 3's `flash.external.ExternalInterface`.

You can call any of these directly from Swift using:
```swift
flashPlayerView.player?.call(functionName: "<functionName>", args: [...])
```
*(via Ruffle's `ruffle_player_call_external_interface` FFI)*.

---

## 🏦 1. Bank (`bank.*`)
Control the player's bank remotely (deposit, withdraw, check slots, or open the bank screen).

| Function Name | Description / Typical Arguments |
| :--- | :--- |
| `bank.open` | **Opens the Bank interface** (exact match for pinning to an "Open Bank" UIKit button!) |
| `bank.isOpen` | Returns whether the bank UI is currently open (`Boolean`) |
| `bank.isLoaded` | Returns whether bank items have finished loading (`Boolean`) |
| `bank.loadItems` | Requests/triggers loading items from the bank server |
| `bank.getItems` | Returns an array of items currently stored in the bank |
| `bank.getItem` | Gets specific item details from the bank by ID/name |
| `bank.getSlots` | Returns total purchased bank slots count (`Number`) |
| `bank.getUsedSlots` | Returns currently occupied bank slots count (`Number`) |
| `bank.contains` | Checks if a specific item is in the bank (`itemId` or `itemName`) |
| `bank.deposit` | Deposits an item from player inventory into the bank |
| `bank.withdraw` | Withdraws an item from the bank into player inventory |
| `bank.swap` | Swaps an inventory item with a bank item |

---

## 🎒 2. Inventory & Temporary Inventory (`inventory.*`, `tempInventory.*`)

| Function Name | Description |
| :--- | :--- |
| `inventory.getItems` | Returns all items currently in player inventory |
| `inventory.getItem` | Returns data for a specific inventory item |
| `inventory.getSlots` | Total inventory slots count |
| `inventory.getUsedSlots` | Occupied inventory slots count |
| `inventory.getMiscSlots` | Miscellaneous inventory slots count |
| `inventory.contains` | Checks if an item is present in inventory |
| `inventory.equip` | Equips an item (weapon, armor, helm, cape, etc.) |
| `inventory.wear` | Wears/previews an item |
| `inventory.use` | Uses an item / consumable potion |
| `inventory.unequipConsumable` | Unequips a consumable item from active potion slot |
| `tempInventory.getItems` | Returns all quest items in temporary inventory |
| `tempInventory.getItem` | Returns specific temporary item |
| `tempInventory.contains` | Checks if a temporary quest item exists |

---

## ⚔️ 3. Combat & Skills (`combat.*`)

| Function Name | Description |
| :--- | :--- |
| `combat.useSkill` | Casts a skill (e.g. skill 1, 2, 3, 4, 5) |
| `combat.attackMonster` | Targets and auto-attacks a monster |
| `combat.cancelAutoAttack` | Stops auto-attacking |
| `combat.getTarget` | Returns current target data (monster or player) |
| `combat.hasTarget` | Returns whether the player currently has a target |
| `combat.cancelTarget` | Clears current target |
| `combat.castConsumableOnMonster`| Casts a scroll/potion item onto target monster |
| `combat.getConsumableSkillItem` | Gets current equipped scroll/potion in skill slot 5 |
| `combat.getSkillCooldownRemaining`| Gets remaining cooldown in seconds/ms for a skill |

---

## 👤 4. Player Status & Movement (`player.*`)

| Function Name | Description |
| :--- | :--- |
| `player.getHp` | Current HP |
| `player.getMaxHp` | Maximum HP |
| `player.getMp` | Current MP |
| `player.getMaxMp` | Maximum MP |
| `player.getGold` | Current Gold |
| `player.getLevel` | Current character level |
| `player.getClassName` | Active class name |
| `player.getData` | Full player data object |
| `player.isLoaded` | Whether player avatar and data are fully loaded |
| `player.isAfk` | Whether player is flagged AFK |
| `player.isMember` | Whether player has active Upgrade / Membership |
| `player.rest` | Rests player (regenerates HP & MP quickly) |
| `player.jump` | Jumps to another player or cell |
| `player.walkTo` | Moves player to `(x, y)` coordinate |
| `player.goToPlayer` | Teleports / jumps to a specific player in room |
| `player.joinMap` | Joins a room / map (e.g., `joinMap("battleon", "Enter", "Spawn")`) |
| `player.getMap` | Current map name |
| `player.getCell` | Current cell name |
| `player.getPad` | Current pad name |
| `player.getPosition` | Current coordinate `{x, y}` |
| `player.getState` | Player state (idle, in combat, etc.) |
| `player.getCharId` | Character ID |
| `player.getUserId` | User ID |
| `player.getGender` | Character gender (`"M"` / `"F"`) |
| `player.getFactions` | Player faction reputations list |
| `player.hasActiveBoost` | Returns if an XP / Gold / Class / Rep boost is active |

---

## 🗺️ 5. World & Map (`world.*`)

| Function Name | Description |
| :--- | :--- |
| `world.isLoaded` | Whether current map SWF is loaded |
| `world.isCellReady` | Whether current room cell is ready |
| `world.getCells` | List of all cells in the current map |
| `world.getCellPads` | List of spawn pads for a given cell |
| `world.getMonster` | Details of monster by moniker / ID in the cell |
| `world.isMonsterAvailable` | Checks if monster is spawned and alive |
| `world.getAvailableMonsterMapIds`| List of alive monster IDs in current cell |
| `world.requestMonsterDrops` | Requests drop list from monsters |
| `world.getMapItem` | Gets interactive map items / quest clickables |
| `world.isActionAvailable` | Checks if a world interaction is available |
| `world.reload` | Reloads current map |
| `world.setSpawnPoint` | Sets custom respawn point |
| `world.loadSwf` | Loads a custom SWF into world |

---

## 📜 6. Quests (`quests.*`)

| Function Name | Description |
| :--- | :--- |
| `quests.load` | Loads quest data by Quest ID |
| `quests.loadMultiple` | Loads multiple quest IDs at once |
| `quests.get` | Gets cached quest data by ID |
| `quests.getMultiple` | Gets multiple cached quests |
| `quests.getAccepted` | Returns list of currently active accepted quests |
| `quests.getTree` | Returns entire quest tree |
| `quests.accept` | Accepts quest by ID |
| `quests.complete` | Turns in / completes quest by ID (and optional turn-in item ID) |
| `quests.abandon` | Drops / abandons quest by ID |
| `quests.isAvailable` | Checks if quest requirements are met |
| `quests.isInProgress` | Checks if quest is currently in progress |
| `quests.canComplete` | Checks if all quest requirements / items are satisfied |
| `quests.getMaxTurnIns` | Max times quest can be turned in simultaneously |

---

## 🛍️ 7. Shops & Customization (`shops.*`)

| Function Name | Description |
| :--- | :--- |
| `shops.load` | Loads a shop by Shop ID |
| `shops.isOpen` | Whether shop window is open |
| `shops.close` | Closes shop window |
| `shops.getItem` | Gets shop item details by ID |
| `shops.canBuyItem` | Checks if player has required gold / items / rank |
| `shops.buy` | Buys item by ID |
| `shops.sell` | Sells inventory item by ID |
| `shops.enhance` | Applies enhancement to gear |
| `shops.getMaxBuyQuantity` | Max items player can buy with current bag slots/gold |
| `shops.isMergeShop` | Whether current shop is a merge/crafting shop |
| `shops.loadArmorCustomize` | Opens armor color customization interface |
| `shops.loadHairShop` | Opens hair salon interface |

---

## 🎁 8. Drops (`drops.*`)

| Function Name | Description |
| :--- | :--- |
| `drops.accept` | Picks up / accepts dropped item by ID |
| `drops.reject` | Dismisses / rejects dropped item by ID |
| `drops.toggleUi` | Shows/hides custom drop notification UI |
| `drops.isUsingCustomDrops` | Checks if custom drop manager is enabled |

---

## 👔 9. Outfits / Loadouts (`outfits.*`)

| Function Name | Description |
| :--- | :--- |
| `outfits.getAll` | Returns all saved gear loadouts/outfits |
| `outfits.get` | Returns specific loadout by name/index |
| `outfits.equip` | Equips all items in a saved loadout |
| `outfits.wear` | Previews saved loadout |

---

## 🏡 10. House (`house.*`)

| Function Name | Description |
| :--- | :--- |
| `house.getItems` | Returns all housing items owned |
| `house.getItem` | Returns details of specific housing item |
| `house.getSlots` | Total house inventory slots |
| `house.getUsedSlots` | Occupied house inventory slots |

---

## ⚙️ 11. Settings & Quality of Life Tweaks (`settings.*`)

| Function Name | Description |
| :--- | :--- |
| `settings.setLagKillerEnabled` | Hides ground effects, shadows, and unnecessary visuals |
| `settings.setOtherPlayersVisible` | Hides/shows other players (huge FPS boost in busy rooms!) |
| `settings.setAnimationsEnabled` | Toggles skill and weapon animations |
| `settings.setCollisionsEnabled` | Disables player-wall collision limits |
| `settings.setWalkSpeed` | Adjusts character walk speed |
| `settings.setFrameRate` | Overrides game tick framerate |
| `settings.setDeathAdsVisible` | Toggles death respawn countdown ads |
| `settings.skipCutscenes` | Automatically skips in-game story cutscenes |
| `settings.setCustomName` | Sets client-side custom player display name |
| `settings.resetCustomName` | Resets custom name to default |
| `settings.setCustomGuild` | Sets client-side custom guild name |
| `settings.resetCustomGuild` | Resets custom guild name |
| `settings.provokeCell` | Aggros / provokes all monsters in current cell |
| `settings.enemyMagnet` | Pulls monsters to player's position |
| `settings.infiniteRange` | Allows targeting/attacking from across the cell |

---

## 🔐 12. Authentication & Server Connection (`auth.*`)

| Function Name | Description |
| :--- | :--- |
| `auth.getServers` | Gets list of AQW servers (name, IP, population, upgraded only) |
| `auth.login` | Sends login credentials |
| `auth.logout` | Logs out of game server |
| `auth.connectTo` | Connects to a specific game server |
| `auth.isLoggedIn` | Returns whether player is authenticated on SmartFoxServer |
| `auth.isTemporarilyKicked` | Returns if account is on temporary relog cooldown |

---

## 🛠️ 13. Low-Level Core Flash Access (`flash.*`)

| Function Name | Description |
| :--- | :--- |
| `flash.getGameObject` | Reads an object path on Flash `root` (e.g. `world.myAvatar.objData`) |
| `flash.getGameObjectS` | Reads object property as String |
| `flash.getGameObjectKey` | Reads a specific key from game object |
| `flash.setGameObject` | Sets property value on Flash `root` |
| `flash.setGameObjectKey` | Sets specific key on game object |
| `flash.callGameFunction` | Directly invokes an ActionScript function with arguments on game root |
| `flash.callGameFunction0` | Invokes an ActionScript function with 0 arguments |
| `flash.sendClientPacket` | Sends a raw SmartFoxServer packet string to the game server |
| `flash.getArrayObject` | Reads an array index from game state |
| `flash.setArrayObject` | Sets an array index on game state |
| `flash.selectArrayObjects` | Filters/queries an array in game state |
| `flash.isTextFieldFocused` | Returns whether Flash text field has input focus |
| `flash.hideConnMc` | Hides connection modal / loading screen |
| `flash.getConnMcText` | Gets current loading status text |
| `flash.isConnMcBackButtonVisible`| Returns whether back button is showing on loading screen |
| `flash.isNull` | Checks if a path on game root is null/undefined |

---

## 💡 Example: Pinning an "Open Bank" Button in UIKit

In `ruffle-demo-ios/ruffle-demo-ios/ViewController.swift`:

```swift
let openBankButton = UIButton(type: .system)
openBankButton.setTitle("Bank", for: .normal)
openBankButton.setImage(UIImage(systemName: "building.columns.fill"), for: .normal)

openBankButton.addAction(UIAction { [weak self] _ in
    // Calls bank.open via Ruffle's ExternalInterface
    self?.flashPlayerView.player?.call(functionName: "bank.open", args: [])
}, for: .touchUpInside)
```

