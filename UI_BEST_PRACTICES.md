# UI Best Practices

Guidelines for building UI with the DMHub `gui` framework.

## Panel Rendering

Panels must have a `bgimage` to draw anything on screen. Without one, a panel is
an invisible grouping container (though `gui.Label` still renders its text).

Set `bgimage = true` as shorthand for a plain filled rectangle (equivalent to
`bgimage = "panels/square.png"`). Use a path string for a specific image asset.

```lua
-- This panel is visible and draws its bgcolor:
gui.Panel{
    bgimage = true,
    bgcolor = "#333333",
    width = 100, height = 40,
}

-- This panel is invisible -- it only groups its children:
gui.Panel{
    bgcolor = "#333333",  -- has no effect without bgimage
    width = 100, height = 40,
}
```

## Panels Must Be Parented Immediately

Every panel created with `gui.Panel{}` (or `gui.Label{}`, etc.) **must** be attached
to a parent by the end of the frame it was created in. If a panel is created but
never set as a child of another panel or returned as part of a panel tree, the
engine raises an error:

> Panel ID-XXXXX was created but not attached to a parent.

This means you cannot speculatively create panels "just in case" and discard them.
If you need a panel only sometimes, guard the creation with a conditional so the
panel is never allocated unless it will be used. When reusing an existing embedded
panel (e.g. the roll dialog in the ability sidebar), find and reference the existing
panel in the tree rather than creating a new one.

## Avoid Recreating Panels

Panel creation is expensive. Never rebuild a panel tree on every data change.
Instead, prefer event-driven updates to modify existing panels in place.

**Bad** -- rebuilds the roll info panel on every document tick:
```lua
refreshGame = function(element)
    local panel = CreateExpensivePanel(data)
    element.children = { panel }
end
```

**Good** -- only rebuild when the state actually changes:
```lua
refreshGame = function(element)
    if data.state ~= lastState then
        lastState = data.state
        local panel = CreateExpensivePanel(data)
        element.children = { panel }
    end
end
```

**Better** -- fire events into the existing panel to update it:
```lua
refreshGame = function(element)
    existingPanel:FireEventTree("updateData", data)
end
```

This is especially important for panels with live event subscriptions (e.g. dice
event listeners). Replacing such a panel destroys the subscriptions and breaks
in-progress animations.

## Event-Driven Updates

Use `FireEvent` and `FireEventTree` to push changes into existing panels:

- `element:FireEvent("name", ...)` -- fires on this element only.
- `element:FireEventTree("name", ...)` -- fires on this element and all
  descendants.

Define a handler on the target panel to receive the event:

```lua
gui.Panel{
    updateData = function(element, newData)
        element.children[1].text = newData.label
    end,
}
```

## Monitoring Data Changes

Panels can automatically refresh when external data changes:

| Field | Paired callback | Watches |
|---|---|---|
| `monitorGame = path` | `refreshGame` | Shared documents (cross-client sync) |
| `monitor = id` | `events.monitor` | Settings by ID |

```lua
gui.Panel{
    monitorGame = mod:GetDocumentSnapshot("docId").path,
    refreshGame = function(element)
        local doc = mod:GetDocumentSnapshot("docId")
        -- update UI from doc.data
    end,
}
```

Keep `refreshGame` lightweight since it fires on every remote change.

## Style Selectors and Class Cascading

Styles use selector arrays to apply properties conditionally:

```lua
styles = {
    { selectors = {"row", "highlight"}, bgcolor = "white" },
    { selectors = {"label", "highlight"}, color = "black" },
}
```

**Important**: `gui.Table` / `gui.TableRow` have built-in `"row"` and `"label"`
selectors that cascade to children correctly via `SetClassTree`. Plain
`gui.Panel` with custom class names does not cascade the same way. When you need
style changes to propagate through a subtree, use `gui.Table` / `gui.TableRow`
or apply styles to each child explicitly.

Useful pseudo-selectors:
- `"parent:hover"` -- matches when the parent is hovered.
- `"parent:selected"` -- matches when the parent has the `selected` class.
- `"~state"` -- negation: matches when the element does NOT have that class.

## Class Management

Toggle visual states without recreating panels:

- `element:SetClass("name", bool)` -- add/remove a class on one element.
- `element:SetClassTree("name", bool)` -- add/remove recursively on subtree.
- `element:AddClass("name")` / `element:RemoveClass("name")` -- explicit
  add/remove.
- `element:PulseClass("name")` -- briefly add then remove (used for fade-in
  animations).

## Collapsed vs Visible

Use `collapsed` (not a `visible` property) to hide/show elements:

```lua
-- Hidden and takes no layout space:
element.collapsed = 1

-- Visible:
element.collapsed = 0
```

`collapsed` works with `transitionTime` in styles for animated show/hide.

## Layout

- `flow = "vertical"` (default) or `"horizontal"` -- child layout direction.
- `flow = "none"` -- children are positioned absolutely.
- `wrap = true` -- children wrap to the next line (horizontal flow).
- `halign` / `valign` -- alignment within parent (`"left"`, `"center"`,
  `"right"` / `"top"`, `"center"`, `"bottom"`).
- `floating = true` -- element floats over siblings (for overlays, dropdowns).

### Padding (hpad / vpad) Is Additive

**Important gotcha:** `hpad` and `vpad` add to the element's size -- they do
not shrink the content area. An element with `width = "100%"` and `hpad = 10`
will be 20px wider than its parent (10px on each side).

To keep a padded element within its parent, subtract the padding from the width:

```lua
-- WRONG: overflows parent by 20px
gui.Panel{ width = "100%", hpad = 10 }

-- CORRECT: fits exactly within parent
gui.Panel{ width = "100%-20", hpad = 10 }
```

The same applies to `vpad` and `height`.

### Inline Properties Override Styles

Properties set directly on a panel (inline) always take precedence over entries
in `styles`, regardless of selectors. This means hover/state styles cannot
override an inline property.

```lua
-- WRONG: bgcolor is set inline, so the hover style is ignored
gui.Panel{
    bgimage = true,
    bgcolor = "clear",
    styles = {
        { selectors = {"hover"}, bgcolor = "white" },  -- never applies!
    },
}

-- CORRECT: move the default bgcolor into styles so hover can override it
gui.Panel{
    bgimage = true,
    styles = {
        { bgcolor = "clear" },
        { selectors = {"hover"}, bgcolor = "white" },
    },
}
```

This applies to all properties -- if you need a style selector to change a
property, that property must not be set inline on the panel.

## Transitions and Animation

Add `transitionTime` to style selectors to animate property changes:

```lua
styles = {
    { selectors = {"panel"}, opacity = 0.5, transitionTime = 0.3 },
    { selectors = {"panel", "hover"}, opacity = 1.0, transitionTime = 0.1 },
}
```

## Periodic Work with thinkTime

Set `thinkTime` to call a `think` handler at a regular interval:

```lua
gui.Panel{
    thinkTime = 1.0,
    think = function(element)
        -- called every 1 second
    end,
}
```

Set `element.thinkTime = 0` to stop the timer. Adjust dynamically as needed.

## Deferred Positioning

Panel dimensions (`renderedWidth`, `renderedHeight`) are not available until
after the first render. Use `dmhub.Schedule` with a small delay for positioning
that depends on rendered size:

```lua
create = function(element)
    dmhub.Schedule(0.05, function()
        if element.valid then
            element.x = element.parent.renderedWidth
        end
    end)
end,
```

## Validity Checks

Panels can be destroyed asynchronously. Always check `element.valid` before
accessing a panel from a deferred callback or stored reference:

```lua
dmhub.Schedule(1.0, function()
    if panel ~= nil and panel.valid then
        panel.text = "updated"
    end
end)
```

## Module Lifecycle Cleanup

Register cleanup handlers so long-lived panels are destroyed when a mod unloads:

```lua
local mod = dmhub.GetModLoading()
mod.unloadHandlers[#mod.unloadHandlers+1] = function()
    if dialog ~= nil and dialog.valid then
        dialog:DestroySelf()
    end
end
```

Also guard scheduled callbacks with `mod.unloaded`:

```lua
dmhub.Schedule(delay, function()
    if mod.unloaded then return end
    -- do work
end)
```

## Panel Data Storage

Use `element.data` to store per-panel state that persists across event
callbacks. This is the standard place for internal bookkeeping:

```lua
gui.Panel{
    create = function(element)
        element.data = { count = 0 }
    end,
    click = function(element)
        element.data.count = element.data.count + 1
    end,
}
```

## Scrollable Lists with Virtual Children

For large lists, use `Scrollable` with `expose` to lazy-load children only
when they scroll into view:

```lua
expose = function(element)
    if element.data.child == nil then
        element.data.child = createExpensiveChild()
        element.children = { element.data.child }
    end
end,
```

## Interactivity Control

- `interactable = false` blocks mouse input but keeps the panel visible.
- `element:MakeNonInteractiveRecursive()` disables interaction on an entire
  subtree (useful for read-only displays of interactive templates).

## Conditional Children

Nil entries in a children array are skipped, so use inline conditionals:

```lua
gui.Panel{
    children = {
        headerPanel,
        showDetails and detailsPanel or nil,
        footerPanel,
    },
}
```

## Input Tables and DeepCopy

When a helper function receives an options table, `DeepCopy` it before mutating
to avoid side effects on the caller:

```lua
function CreateMyPanel(args)
    local options = DeepCopy(args or {})
    options.bgimage = true
    return gui.Panel(options)
end
```
