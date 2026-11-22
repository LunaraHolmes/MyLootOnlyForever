# MyLootOnlyForever

MyLootOnlyForever is a lightweight, standalone World of Warcraft: Forever addon that filters other players' loot, crafting, and loot roll messages while keeping your chat focused on the messages you want to see.

## Features

- **Loot filtering:** Hide other players' loot messages and choose the minimum item quality to show.
- **Crafting and roll filters:** Choose whether to hide other players' crafting messages and loot rolls.
- **Loot exceptions:** Always show loot from specific players. Add and remove exceptions in the settings panel.
- **Social filters:** Allow loot from party and raid members, and allow loot and crafting messages from guildmates or friends.
- **Special loot:** Choose to show other players' mount, companion pet, toy, and recipe items even when their other loot is filtered.
- **Per-character settings:** Each character has its own settings profile. The options panel identifies the current character by name and game mode, and lets you copy settings and loot exceptions from another character.
- **In-game settings:** Open **Escape > Options > AddOns > MyLootOnlyForever**, or type `/mlo`. The panel displays the installed addon version.
- **Login notice:** The addon confirms when it is active and announces when its version changes.
- **Standalone:** No external libraries or dependencies are required.

By default, the addon is enabled and hides other players' loot and crafting. Other filters and special loot options start disabled.

## Slash commands

| Command | Action |
| :--- | :--- |
| `/mlo` or `/mylootonly` | Opens the settings panel |
| `/mlo toggle` | Enables or disables the addon |
| `/mlo loot` | Toggles hiding other players' loot |
| `/mlo quality <tier>` | Sets the minimum loot quality (`all`, `uncommon`, `rare`, `epic`, or `legendary`) |
| `/mlo exception add <player>` | Adds a player's loot exception |
| `/mlo exception remove <player>` | Removes a player's loot exception |
| `/mlo exception list` | Lists loot exceptions |
| `/mlo craft` | Toggles hiding other players' crafting |
| `/mlo rolls` | Toggles hiding other players' loot rolls |
| `/mlo status` | Shows the current filter settings in chat |
| `/mlo profiles` | Lists saved character profiles |
| `/mlo copy <profile name>` | Copies settings from a saved profile; use the profile name shown by `/mlo profiles` |

## Installation

1. Download the latest release from [CurseForge](https://curseforge.com) or the project's [Releases](../../releases) page.
2. Place the `MyLootOnlyForever` folder inside:

   ```text
   World of Warcraft\_forever_\Interface\AddOns\
   ```

3. Restart WoW: Forever, or type `/reload` when updating, and make sure **MyLootOnlyForever** is enabled in the AddOns list.

## Known limitations

Due to WoW: Forever's restrictions on protected chat events during active raid boss encounters, raid boss loot messages generated during combat may not be filterable until combat ends. Filtering works immediately in open-world areas, towns, and dungeons.

## Community and support

Join the [Discord server](https://discord.gg/WYD7WmYrqz) to request features, report bugs, or get help. When reporting a bug, please include what you expected to happen, the steps needed to reproduce it, and screenshots when they would help show the issue.

## License

Licensed under the [MIT License](LICENSE).
