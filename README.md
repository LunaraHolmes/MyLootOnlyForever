# MyLootOnlyForever

A lightweight, standalone World of Warcraft: **Forever** addon that filters out other players' loot, crafting, and roll messages while keeping your own drops, crafts, and rolls clearly visible.

## ✨ Features
* **Only Your Loot:** Hides `[Player] receives loot:` messages while preserving your own `You receive loot:` pickups.
* **Item Quality Threshold (New in v1.1.0):** Optionally allow **Uncommon (Green)**, **Rare (Blue)**, **Epic (Purple)**, or **Legendary (Orange)** drops from party/raid members to still show in chat while hiding lower-rarity spam.
* **No Crafting Spam:** Hides nearby `[Player] creates ...` notifications while keeping your own `You create ...` lines.
* **Optional Roll Filtering:** Optionally hide other players' Need, Greed, Pass, and roll winner lines while keeping your own roll results.
* **Native Settings Panel:** Configure everything easily under **Escape > Options > AddOns > MyLootOnlyForever** with persistent `SavedVariables`.
* **Multi-Language Support:** Uses Blizzard's built-in `GlobalStrings` to adapt automatically to English, German, French, Spanish, and other client languages.
* **Zero Dependencies:** Completely standalone—no external libraries required.

## 💬 Slash Commands

| Command | Action |
| :--- | :--- |
| `/mlo` or `/mylootonly` | Opens the in-game settings panel |
| `/mlo toggle` | Enables or disables the addon |
| `/mlo loot` | Toggles hiding other players' loot |
| `/mlo quality <tier>` | Sets minimum party loot quality (`all`, `uncommon`, `rare`, `epic`, `legendary`) |
| `/mlo craft` | Toggles hiding other players' crafting |
| `/mlo rolls` | Toggles hiding other players' loot rolls |
| `/mlo status` | Displays current filter settings in chat |

## 📦 Installation
1. Download the latest release from [CurseForge](https://curseforge.com) or the [Releases](../../releases) page.
2. Place the **`MyLootOnlyForever`** folder inside:
   ```text
   World of Warcraft\_forever_\Interface\AddOns\
   ```
3. Restart WoW: Forever (or type `/reload` if updating) and ensure **MyLootOnlyForever** is enabled in your AddOns list.

## ⚠️ Known Limitations
Due to WoW: Forever's client restrictions on protected chat events during active raid boss encounters, raid boss loot messages generated mid-combat cannot be filtered by addons until combat ends. Open-world, town, and dungeon filtering works immediately.

## 📄 License
Licensed under the [MIT License](LICENSE).
