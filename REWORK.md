# UX rework development checkout

Branch: ux-rework. Stable checkout: ../.. (main).

The development addons are Ayije_CDMDev and Ayije_CDMDev_Options. Development saved settings use Ayije_CDMDevDB in Ayije_CDMDev.lua, separately from stable Ayije_CDM.lua.

Development-only renaming is a separate baseline commit. Port UX changes back with names normalized; do not merge this branch directly into main or release the development package.

Use the stable checkout dev-tools shortcuts with WoW closed. Stable is active initially. Runtime files are loaded directly through junctions, so there is no copy/install step after editing.
