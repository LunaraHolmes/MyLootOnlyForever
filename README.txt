================================================================================
MyLootOnlyForever (v1.1.0)
================================================================================

A lightweight, standalone chat filter addon for World of Warcraft: Forever
that hides other players' loot, crafting, and roll messages while keeping
your own drops, crafts, and rolls clearly visible.

FEATURES
--------
- Hides other players' loot pickups ("[Player] receives loot: [Item]")
- Item Quality Threshold: optionally allow Uncommon, Rare, Epic, or Legendary
  drops from party/raid members through while hiding lower-rarity trash
- Hides other players' crafting spam ("[Player] creates [Item]")
- Optional filter for other players' Need/Greed/Pass and roll winner lines
- Always preserves your own loot ("You receive loot:"), crafts ("You create"),
  and roll results
- Automatic multi-language support via Blizzard GlobalStrings
- Native Settings panel under Options > AddOns > MyLootOnlyForever
- Zero external dependencies

INSTALLATION
------------
1. Extract the "MyLootOnlyForever" folder into:
   World of Warcraft\_forever_\Interface\AddOns\
2. Verify the file path looks like:
   ...\Interface\AddOns\MyLootOnlyForever\MyLootOnlyForever.toc
3. Launch WoW: Forever (or type /reload if already in-game).

SLASH COMMANDS
--------------
/mlo                  - Opens the MyLootOnlyForever settings panel
/mlo toggle           - Turns the addon on or off
/mlo loot             - Toggles filtering of other players' loot messages
/mlo quality <tier>   - Sets minimum party loot quality (all, uncommon, rare, epic, legendary)
/mlo craft            - Toggles filtering of other players' crafting messages
/mlo rolls            - Toggles filtering of other players' loot roll messages
/mlo status           - Prints current filter states in chat

KNOWN LIMITATIONS
-----------------
WoW: Forever restricts addons from modifying or hiding certain protected chat
events during active raid boss encounters. Loot messages generated mid-fight
during raid bosses may still appear until combat ends.
