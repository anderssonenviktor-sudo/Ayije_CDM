# Development spell overrides

Status: implemented for native Essential/Utility spells and cooldown-group spells;
requires in-game validation. This is not a release validation report.

## Storage and identity

Uses the existing profile/spec `ungroupedCooldownOverrides` and
`cooldownGroups[spec].spellOverrides` maps. New optional fields are
`keepColoredOnCooldown`, `thresholdSeconds`, `thresholdDecimals`,
`thresholdColorEnabled`, `thresholdColor` (RGBA table), `cooldownSwipe`
(`nil`, `reverse`, `hide`), `suppressGCD`, `replaceBuffSpellID`, and
`replaceBuffCooldownID`. No existing saved data is moved; no migration or new
top-level default is needed. Default swipe removes the override.

Current icon identity uses the existing group matching and spell-candidate
resolver. Cooldown queries also resolve the live spell override through
`C_SpellBook.FindSpellOverrideByID`. Hooks resolve settings when invoked, rather
than capturing a spell when the pooled frame is first encountered.

## Runtime ownership

- `Modules/SpellOverrides.lua`: monotonic feature gates; shared resolution;
  guarded post-hooks on desaturation, swipe direction/visibility, cooldown
  updates, and formatter changes. State is in `CDM.GetFrameData`.
- `Core/CooldownFormatter.lua`: cached immutable per-spell engine formatters,
  0–59 seconds, independent decimal and color rules, and API availability guard.
  Above the threshold, the formatter uses whole seconds and normal larger units.
  Disabling restores the existing global formatter.
- `Core/Style.lua`: applies overrides at the end of the ordinary appearance pass.
- `Modules/BuffReplacement.lua`: tracked-native-buff picker, uniqueness checks,
  route preparation, active-state hooks, and restoration.
- `Core/Layout/Reanchor.lua`: excludes routed buffs from the regular buff row
  and updates the replacement after existing slot layout.
- `Core/Main.lua`: queues preparation after frame acquisition and defers
  protected replacement anchor correction during combat.
- `Modules/embeds.xml`: loads the two new modules after existing cooldown groups.
- `Options/CascadeMenu.lua`: exposes the controls using the custom menu widgets.

No new `OnUpdate` or Lua countdown polling is added. Layout work is coalesced
with a zero-delay callback. Appearance hooks have re-entry guards; an unused
configuration does not build replacement routes or install these widget hooks.

## Precedence

Resource-starved desaturation and explicit inactive-aura desaturation win over
Keep Colored. Reverse inverts the last baseline written by the existing owner.
Hide Swipe preserves charge-spell swipe handling. Suppress GCD checks
`isOnGCD`; active charge recharge is exempt, using stable charge metadata.
Secret charge metadata is handled conservatively by retaining the swipe.

## Replacement architecture and limits

The original cooldown remains the layout slot carrier, so its ordering does not
change. The actual native buff frame is anchored to that slot outside combat.
While the buff is active, the original is transparent and the buff displays its
own duration, stacks, icon and swipe. When inactive, the original becomes visible.
Neither frame is reparented. Threshold formatting can apply to the buff's aura
timer; the cooldown's GCD and saturation overrides are not applied to that buff.

This differs from removing the original from a layout array on every transition:
keeping the slot carrier avoids changing protected anchors during buff gain/loss.
The existing buff collection skips assigned replacement frames. Routing therefore
uses the native buff exclusively; it cannot simultaneously appear in the normal
buff row. Group-assigned, resource-hidden and promoted buff entries are excluded
from the picker. Duplicate imported assignments have one deterministic winner.

Existing prepared replacements can switch presentation during combat. If Blizzard
first acquires the chosen native buff frame in combat, or changes a protected
anchor/identity, the original cooldown remains the fallback until safe preparation
after combat. This limitation needs live testing before considering the requested
combat/reload acceptance criteria satisfied.

## Validation

Static checks: parse changed Lua files; verify XML load order/file references;
review saved-variable scope, recursion guards, and protected anchor paths.
No WoW client or Lua execution runtime is available in this workspace.

Required in-game checks:

1. Compare two ordinary cooldowns, only one using Keep Colored. Toggle it off
   while cooling down; verify resource-starved/inactive-aura greying still wins.
2. Threshold 5: check 5 → 4.9, decimals-only, color-only, both, and 0 disabled;
   also check minutes/hours and restoration of global formatting.
3. Reverse/Hide/Default through repeated Blizzard cooldown updates and frame reuse.
4. Suppress GCD on filler, long cooldown, active two-charge recharge, and a
   talent-replaced ability. Real cooldown/recharge must remain visible.
5. Replace A with tracked B: inactive, gain, falloff, repeated gains, reload while
   active, missing frame, duplicate assignment, disabled setting, and independent
   buff/cooldown fading settings. Verify position, timer, stacks and restoration.
6. Repeat across profile/spec/talent changes and combat. Verify the combat fallback
   for a buff frame that was not available before combat. Check taint/error logs.

Reference consulted for behavior only:
[EllesmereUI cooldown manager](https://github.com/EllesmereGaming/EllesmereUI/blob/main/EllesmereUICooldownManager/EllesmereUICooldownManager.lua).
