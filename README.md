# DragonUI for WoW 3.3.5a

## mod-playerbots-portable fork

A modular, retail-inspired interface for **WoW 3.3.5a, build 12340
(Interface 30300)**, maintained for
[mod-playerbots-portable](https://github.com/Syntax555/mod-playerbots-portable).
DragonUI provides configurable action bars, unit frames, bags, tooltips and
other interface modules. This fork adds the talent-canvas support used by the
server's EraTalents integration.

## Install and update

1. Download [DragonUI-latest.zip](https://github.com/Syntax555/DragonUI/releases/latest/download/DragonUI-latest.zip)
   from this fork's [Latest release](https://github.com/Syntax555/DragonUI/releases/latest).
2. Close WoW completely. Back up your existing `DragonUI/` and
   `DragonUI_Options/` folders before replacing them in `Interface/AddOns/`.
   The installed paths must be `Interface/AddOns/DragonUI/DragonUI.toc` and
   `Interface/AddOns/DragonUI_Options/DragonUI_Options.toc`.
3. Keep `WTF/`: it contains your saved settings. Start WoW and enable both
   addons in the character screen's AddOns list. `DragonUI_Options` loads when
   you open settings with `/dui` or `/dragonui`.

Repeat these steps to update. The packaged `SOURCE_REVISION.txt` in each addon
folder identifies its source commit. `/dui edit` opens Editor Mode;
`/dui help` lists commands and `/duicomp` shows compatibility diagnostics.

## Earned-era integration

Install the server's matching
[EraTalents client pack](https://github.com/Syntax555/mod-playerbots-portable/blob/main/docs/era-talents.md#install-the-matching-client-files)
for historical talents and spell data. EraTalents supplies the integration:

- Historical player and inspected-character trees use DragonUI's existing
  canvas, with the character's own era and server-provided talent ranks.
  Authorized controlled altbots can spend their available points through this
  view; other inspected characters remain read-only.
- MultiBot can open a controlled bot's talents and spellbook in DragonUI.
  The player's talent micro-button remains separate from an inspected bot.
- The player's spellbook and level-up notice use the server's trainer list,
  earned-era riding and expansion information. Glyphs remain unavailable until
  that character earns Wrath.

Without the matching EraTalents addon and server replies, DragonUI uses its
ordinary Wrath interface data. DragonUI does not unlock content or grant
spells, talents or items. See the
[integration guide](https://github.com/Syntax555/mod-playerbots-portable/blob/main/docs/era-talents.md#dragonui).

Client validation is still required for parts of this integration, party and
raid edge cases, and combinations with other UI addons. Disable overlapping
modules in `/dui` when diagnosing conflicts; include the error and reproduction
when [reporting a problem](https://github.com/Syntax555/DragonUI/issues).

## Source and contributing

Work happens on [`main`](https://github.com/Syntax555/DragonUI/tree/main).
Its [Latest workflow](https://github.com/Syntax555/DragonUI/blob/main/.github/workflows/latest.yml)
checks packaged Lua with Lua 5.1 and verifies the ZIP before publishing. These
checks do not establish complete in-game compatibility. The server records its
exact tested addon commit in
[versions.lock.json](https://github.com/Syntax555/mod-playerbots-portable/blob/main/versions.lock.json).

Read the server's [repository rules](https://github.com/Syntax555/mod-playerbots-portable/blob/main/AGENTS.md)
and [fork workflow](https://github.com/Syntax555/mod-playerbots-portable/blob/main/CONTRIBUTING.md#changing-the-server)
before contributing. Propose fork-specific changes here; preserve upstream
credits and notices when merging source updates.

This fork imports [NeticSoul/DragonUI](https://github.com/NeticSoul/DragonUI) at
[`6cfcd75a2e57`](https://github.com/NeticSoul/DragonUI/commit/6cfcd75a2e5762637322fd495cd4302b203b77df).
The [original README](https://github.com/NeticSoul/DragonUI/blob/6cfcd75a2e5762637322fd495cd4302b203b77df/README.md)
covers the general UI features and retains the full author, contributor and
reference credits. Use this fork's download above for its integration changes.

## License and credits

DragonUI is by **NeticSoul and DragonUI contributors**. Project-authored code
uses the [MIT License](https://github.com/Syntax555/DragonUI/blob/main/LICENSE).
Bundled libraries, fonts and adapted code retain their own terms; see
[third-party notices](https://github.com/Syntax555/DragonUI/blob/main/DragonUI/THIRD_PARTY_NOTICES.md)
and [license texts](https://github.com/Syntax555/DragonUI/tree/main/DragonUI/LICENSES),
also shipped in `DragonUI/`. World of Warcraft artwork is © Blizzard
Entertainment, is outside the MIT license and is included only for use with the
game. DragonUI is a fan-made addon, unaffiliated with Blizzard Entertainment.
