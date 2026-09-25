# Smooth Buff Bars — Implementation Specification

## Goal

Add an optional **Smooth Buff Bars** setting to the addon.

When enabled, buff-duration status bars should move smoothly as their remaining duration changes instead of visually stepping or snapping between discrete updates.

Use Blizzard's native status-bar interpolation:

```lua
Enum.StatusBarInterpolation.ExponentialEaseOut
```

Do not implement a custom `Lerp`, animation group, or manual smoothing algorithm unless native interpolation is unavailable.

The timer text itself should remain accurate and should not be artificially interpolated.

---

## User-Facing Setting

Add a boolean option:

```lua
smoothBuffBars = true
```

Suggested UI:

**Smooth Buff Bars**

Tooltip:

> Smoothly animates buff duration bars as their remaining time changes.

Recommended default:

```lua
true
```

Changing the option should take effect immediately without requiring `/reload`.

---

## Core Behavior

The normal unsmoothed update is:

```lua
bar:SetValue(remaining)
```

When smoothing is enabled and the bar is already initialized for its current aura:

```lua
bar:SetValue(
    remaining,
    Enum.StatusBarInterpolation.ExponentialEaseOut
)
```

Conceptually:

```lua
if smoothingEnabled and canUseNativeInterpolation and barIsInitialized then
    bar:SetValue(remaining, Enum.StatusBarInterpolation.ExponentialEaseOut)
else
    bar:SetValue(remaining)
end
```

The addon should continue calculating the real target value normally. Native StatusBar interpolation is only responsible for how the bar visually travels toward that target.

---

## Native API Detection

Do not assume interpolation exists.

Create a reusable constant:

```lua
local SMOOTH_INTERPOLATION =
    Enum
    and Enum.StatusBarInterpolation
    and Enum.StatusBarInterpolation.ExponentialEaseOut
```

Then smoothing is available when:

```lua
local canSmooth = SMOOTH_INTERPOLATION ~= nil
```

If unavailable, silently fall back to:

```lua
bar:SetValue(value)
```

The addon should continue functioning normally on clients where the interpolation API does not exist.

---

## First-Show / Initialization Rule

A newly appearing buff must **snap immediately to its correct value**.

Do not interpolate from the status bar's previous value, zero, or the value used by a previously assigned aura.

Bad behavior:

```text
0 sec ───────────────► 30 sec
```

when a new 30-second buff appears.

Correct behavior:

```text
New buff appears
      ↓
Immediately display 30 sec
      ↓
Smoothly decrease on subsequent updates
```

Each bar should therefore maintain initialization state.

Example:

```lua
if not bar._smoothInitialized then
    bar:SetValue(remaining)
    bar._smoothInitialized = true
else
    SetSmoothValue(bar, remaining)
end
```

---

## Aura Identity Changes

If a reusable/pool bar changes from one aura to another, reset its smoothing state.

For example:

```lua
local auraKey = auraInstanceID or spellID

if bar._smoothAuraKey ~= auraKey then
    bar._smoothAuraKey = auraKey
    bar._smoothInitialized = false
end
```

The exact identity key depends on the addon's architecture.

Prefer:

```lua
auraInstanceID
```

when it reliably identifies the tracked aura.

Otherwise use whatever stable identity the addon already uses when assigning CDM entries to bars.

The important requirement is:

> A recycled frame must never smoothly transition from the previous buff's duration into the newly assigned buff's duration.

---

## Hide / Release Behavior

When a bar is hidden, released to a pool, or loses its tracked aura, clear its smoothing state.

Example:

```lua
local function ResetSmoothState(bar)
    bar._smoothInitialized = false
    bar._smoothAuraKey = nil
end
```

Call this when appropriate:

```lua
bar:Hide()
ResetSmoothState(bar)
```

or when returning a bar to the frame pool.

---

## Recommended Helper Function

Centralize the behavior instead of scattering interpolation checks throughout the addon.

```lua
local SMOOTH_INTERPOLATION =
    Enum
    and Enum.StatusBarInterpolation
    and Enum.StatusBarInterpolation.ExponentialEaseOut

local function SetBuffBarValue(bar, value, smoothEnabled)
    if smoothEnabled
        and SMOOTH_INTERPOLATION
        and bar._smoothInitialized
    then
        bar:SetValue(value, SMOOTH_INTERPOLATION)
    else
        bar:SetValue(value)
        bar._smoothInitialized = true
    end
end
```

Usage:

```lua
bar:SetMinMaxValues(0, duration)

SetBuffBarValue(
    bar,
    remaining,
    profile.smoothBuffBars
)
```

---

## Update Frequency

Smoothing does not eliminate the need to update the bar's target value regularly.

Recommended target update interval:

```lua
~0.016 seconds
```

Approximately 60 updates per second.

Example accumulator:

```lua
local accumulator = 0

frame:SetScript("OnUpdate", function(self, elapsed)
    accumulator = accumulator + elapsed

    if accumulator < 0.016 then
        return
    end

    local dt = accumulator
    accumulator = 0

    UpdateBuffBars(dt)
end)
```

Exact 60 Hz timing is not mandatory.

If the addon already has an efficient shared CDM ticker, reuse it rather than creating one `OnUpdate` handler per bar.

Preferred architecture:

```text
One shared ticker
    ↓
Update all active bars
    ↓
Set new target values
    ↓
WoW StatusBar interpolation renders smooth movement
```

Avoid:

```text
Bar 1 OnUpdate
Bar 2 OnUpdate
Bar 3 OnUpdate
Bar 4 OnUpdate
...
```

unless the addon already works that way and performance is acceptable.

---

## Remaining-Time Calculation

The smoothing feature must not change the underlying timer calculation.

Typical calculation:

```lua
local now = GetTime()
local remaining = expirationTime - now

remaining = math.max(0, remaining)
```

Then:

```lua
bar:SetMinMaxValues(0, duration)
SetBuffBarValue(bar, remaining, smoothEnabled)
```

The displayed timer text should use the actual `remaining` value, not the visually interpolated bar value.

Example:

```lua
timerText:SetText(FormatDuration(remaining))
```

Do not do:

```lua
timerText:SetText(FormatDuration(bar:GetValue()))
```

The animation is visual only.

---

## Blizzard/CDM Mirroring

If this addon is reskinning or mirroring an existing Blizzard CDM status bar rather than calculating duration independently, use Blizzard's bar as the source of truth.

Example:

```lua
local minValue, maxValue = sourceBar:GetMinMaxValues()
local value = sourceBar:GetValue()

bar:SetMinMaxValues(minValue, maxValue)
SetBuffBarValue(bar, value, smoothEnabled)
```

This is preferable when the underlying CDM frame already handles special duration logic that the addon does not need to duplicate.

---

## Buff Refreshes

If an active buff refreshes while the same aura/bar remains assigned, allow native interpolation to handle the value increase.

Example:

```text
5.0 sec remaining
       ↓
buff refreshes
       ↓
30.0 sec target
       ↓
bar smoothly moves toward refreshed value
```

Do not reset smoothing merely because the duration or expiration time changed.

Reset smoothing only when the bar represents a different logical aura/frame assignment or has been newly shown/recycled.

If later testing shows that large refresh transitions feel undesirable, an optional snap-on-refresh policy can be added separately. It should not be required for the initial implementation.

---

## Duration / Maximum Changes

Always update the min/max range before setting the value:

```lua
bar:SetMinMaxValues(0, duration)
SetBuffBarValue(bar, remaining, smoothEnabled)
```

Clamp invalid values where appropriate:

```lua
remaining = math.max(0, math.min(remaining, duration))
```

Do not attempt to smooth invalid or missing duration data.

For permanent/infinite auras, retain the addon's existing handling rather than forcing them through this system.

---

## Disabling Smooth Bars at Runtime

When the user switches the setting OFF, bars should immediately use direct `SetValue`.

Example:

```lua
SetBuffBarValue(bar, remaining, false)
```

However, because the helper above considers initialized bars, explicitly snapping may be clearer when the option changes:

```lua
for _, bar in ipairs(activeBars) do
    local value = GetCurrentRemainingTime(bar)
    bar:SetValue(value)
end
```

Future updates then continue using:

```lua
bar:SetValue(value)
```

No reload should be required.

---

## Enabling Smooth Bars at Runtime

When the user enables smoothing, do not cause every existing bar to animate from a stale value.

Recommended behavior:

1. Snap all active bars to their current correct value.
2. Mark them initialized.
3. Subsequent timer updates use `ExponentialEaseOut`.

Conceptually:

```lua
for _, bar in ipairs(activeBars) do
    bar:SetValue(GetCurrentRemainingTime(bar))
    bar._smoothInitialized = true
end
```

---

## Suggested State

Each buff bar may contain:

```lua
bar._smoothInitialized = false
bar._smoothAuraKey = nil
```

No additional smoothing variables should be necessary.

Do NOT add state like:

```lua
bar.currentValue
bar.targetValue
bar.smoothSpeed
bar.lerpProgress
```

unless required for compatibility fallback.

The native interpolation system should own the visual transition.

---

## Suggested Complete Pattern

```lua
local SMOOTH_INTERPOLATION =
    Enum
    and Enum.StatusBarInterpolation
    and Enum.StatusBarInterpolation.ExponentialEaseOut

local function ResetBuffBarSmoothing(bar)
    bar._smoothInitialized = false
    bar._smoothAuraKey = nil
end

local function SetBuffBarValue(bar, value, smoothEnabled)
    if smoothEnabled
        and SMOOTH_INTERPOLATION
        and bar._smoothInitialized
    then
        bar:SetValue(value, SMOOTH_INTERPOLATION)
    else
        bar:SetValue(value)
        bar._smoothInitialized = true
    end
end

local function UpdateBuffBar(bar, aura, profile)
    if not aura then
        ResetBuffBarSmoothing(bar)
        bar:Hide()
        return
    end

    local auraKey = aura.auraInstanceID or aura.spellId

    if bar._smoothAuraKey ~= auraKey then
        bar._smoothAuraKey = auraKey
        bar._smoothInitialized = false
    end

    local now = GetTime()
    local duration = aura.duration or 0
    local expirationTime = aura.expirationTime or 0

    if duration <= 0 or expirationTime <= 0 then
        -- Preserve whatever handling the addon already uses
        -- for timeless/permanent buffs.
        return
    end

    local remaining = math.max(0, expirationTime - now)

    bar:SetMinMaxValues(0, duration)

    SetBuffBarValue(
        bar,
        remaining,
        profile.smoothBuffBars
    )

    if not bar:IsShown() then
        bar:Show()
    end
end
```

Adapt the field names to the addon.

---

## Performance Requirements

The smoothing option must not create additional per-bar animation systems.

Native `StatusBar` interpolation should do the rendering work.

The timer update system should:

```text
Use one shared ticker where practical.
Skip hidden/inactive bars.
Avoid rebuilding bar assignments every tick.
Avoid unnecessary aura queries every frame.
Avoid allocations inside the hot OnUpdate path where practical.
```

If the addon already receives the current values from Blizzard CDM frames, reuse those values instead of performing additional aura scans.

---

## Scope

Initial implementation applies to:

```text
Buff duration status bars
```

It should not automatically affect unrelated UI elements such as:

```text
Cooldown icons
Cooldown swipe animations
Cast bars
Resource bars
Timer text
Progress bars unrelated to CDM buffs
```

Those can use separate settings later if desired.

---

## Acceptance Criteria

### 1. Setting OFF

With `smoothBuffBars = false`:

```lua
bar:SetValue(value)
```

is effectively used and bars behave exactly as before the feature was added.

### 2. Setting ON

With `smoothBuffBars = true`, existing active buff bars visually transition between updated values using:

```lua
Enum.StatusBarInterpolation.ExponentialEaseOut
```

### 3. New Buff

A newly created/shown buff immediately appears at its actual remaining duration.

It must not visibly animate from zero or an old value.

### 4. Recycled Bar

If a frame previously displayed Buff A and is reused for Buff B, Buff B snaps immediately to its correct starting value.

There must be no transition from Buff A's previous value.

### 5. Normal Countdown

After initialization, the countdown appears continuous/smooth rather than visibly stepping between updates.

### 6. Buff Refresh

Refreshing the same active aura does not break the bar or leave it stuck at the previous duration.

### 7. Buff Removed

When a buff disappears:

```text
bar hides
smoothing initialization is reset
aura identity is cleared
```

### 8. Toggle at Runtime

Changing Smooth Buff Bars ON/OFF takes effect immediately without `/reload`.

### 9. Unsupported API

If:

```lua
Enum.StatusBarInterpolation
```

or:

```lua
Enum.StatusBarInterpolation.ExponentialEaseOut
```

does not exist, the addon falls back safely to normal `SetValue(value)` behavior.

### 10. Timer Accuracy

Timer text continues representing the real calculated remaining time and is not derived from the interpolated visual position of the bar.

---

## Important Implementation Principle

The addon should think in terms of:

```text
calculate correct value
        ↓
send target to StatusBar
        ↓
let Blizzard animate toward target
```

not:

```text
calculate target
        ↓
calculate custom intermediate value
        ↓
lerp manually every frame
        ↓
write intermediate value
```

Blizzard's native `StatusBarInterpolation.ExponentialEaseOut` should be the smoothing engine.

---

## Reference Behavior

The intended behavior is based on the EllesmereUI approach:

```text
• normal target updates continue
• smoothing is optional
• ExponentialEaseOut is used for native StatusBar interpolation
• newly appearing bars snap to their correct starting value
• subsequent value changes are smoothed
```

The result should look like Ellesmere-style smooth buff bars while remaining isolated enough to integrate into an existing CDM addon's bar update pipeline.