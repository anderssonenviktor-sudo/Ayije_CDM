# UX rework development checkout

Branch: ux-rework. Stable checkout: ../.. (main).

The development addons are Ayije_CDMDev and Ayije_CDMDev_Options. Development saved settings use Ayije_CDMDevDB in Ayije_CDMDev.lua, separately from stable Ayije_CDM.lua.

Development-only renaming is a separate baseline commit. Port UX changes back with names normalized; do not merge this branch directly into main or release the development package.

Use the stable checkout dev-tools shortcuts with WoW closed. Stable is active initially. Runtime files are loaded directly through junctions, so there is no copy/install step after editing.

## Current slice: familiar-style Cooldowns screen

The original 920 x 720 Blizzard-style window, sidebar, fonts, gold headings, and tab styling are retained. The previous Workspace wrapper is removed from the addon load list; its prior code is archived under the stable checkout's ignored design folder.

Cooldowns now opens on Essential/Utility selection, the existing spell strip, and a two-column settings area below it. This pass brings together icon sizes, spacing, row limits, timer/charge font sizes and colors, swipe opacity/GCD visibility, and basic border controls. Shared settings are explicitly labeled. The other existing sidebar pages remain accessible for controls not yet consolidated.

Manage Groups toggles the existing group editor. Choosing another specialization retains that editor and prevents opening the current-viewer appearance panel. Left-click still exposes the existing individual editor; native spell right-click opens the cascading menus. Cascading checkboxes and sliders now use the same UI helpers as the normal settings.

Stable addon code and saved settings are unchanged. No schema changes or release have been made.

Validation: changed Lua files parsed successfully, XML references and load order checked, whitespace checks passed. In-game appearance and interaction still need review. On Rework, reload and open /acdm -> Cooldowns. Check Essential/Utility, scroll settings, Manage Groups, and a spell right-click. Review a screenshot before expanding this work to buffs/bars.
