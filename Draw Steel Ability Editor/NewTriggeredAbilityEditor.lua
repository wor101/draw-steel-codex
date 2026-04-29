local mod = dmhub.GetModLoading()

-- Opt-out toggle. The sectioned Triggered Ability Editor is the default; this
-- lets a user fall back to the classic editor if they hit a regression.
-- Mirrors the classicAbilityEditor setting pattern in AbilityEditor.lua.
setting{
    id = "classicTriggeredAbilityEditor",
    description = "Use classic triggered ability editor",
    editor = "check",
    default = false,
    storage = "preference",
    section = "game",
}

-- Preserve a reference to the classic GenerateEditor so we can fall through
-- to it when aura-embed options or the opt-out setting are in effect.
local classicGenerateEditor = TriggeredAbility.GenerateEditor

-- Nav column width matches the New Ability Editor's layout so the shared
-- nae-nav-button rule (width = NAV_WIDTH - 24 = 196) fits inside the padded
-- column. Hpad/vpad also mirror AbilityEditor's LAYOUT.COL_HPAD/VPAD.
local LAYOUT = {
    NAV_WIDTH = 220,
    COL_HPAD = 16,
    COL_VPAD = 16,
    -- Mirrors AbilityEditor's LAYOUT.PREVIEW_WIDTH. The preview column is
    -- always visible in the sectioned editor; fixed-width so the card has
    -- a consistent rendering target.
    PREVIEW_WIDTH = 440,
    -- Reserved gutter on the right of the preview scroll area so the
    -- vertical scrollbar doesn't visually overlap card borders. Cards
    -- are widened to PREVIEW_WIDTH - 2*COL_HPAD - SCROLL_GUTTER so the
    -- scroll track sits in the empty strip at the far right.
    SCROLL_GUTTER = 14,
}

-- Fallback palette used if AbilityEditor hasn't published COLORS yet. Keeps
-- the editor renderable even if load order shifts.
local FALLBACK_COLORS = {
    BG = "#080B09",
    PANEL_BG = "#10110F",
    -- Card background for the Trigger Preview / How This Triggers panes.
    -- Uses the DS "rich black" swatch (#040807 -- see
    -- `Draw Steel Core Rules\MCDMCharacterPanel.lua:34` where it's the
    -- canonical card fill). Slightly darker than the column BG so the
    -- cards read as inset / recessed; the 2px gold border carries the
    -- visual separation so cards pop against the column despite being
    -- darker. This matches the DS card styling guideline the user
    -- referenced.
    CARD_BG = "#040807",
    GOLD = "#966D4B",
    GOLD_BRIGHT = "#F1D3A5",
    GOLD_DIM = "#E9B86F",
    CREAM = "#BC9B7B",
    CREAM_BRIGHT = "#DFCFC0",
    GRAY = "#666663",
}

local function getColors()
    local AE = rawget(_G, "AbilityEditor")
    if AE ~= nil and AE.COLORS ~= nil then
        -- AE.COLORS predates CARD_BG (this file introduced it). Splice in
        -- the latest value on every call so iterative tuning of CARD_BG
        -- propagates across reloads without stale caching.
        AE.COLORS.CARD_BG = FALLBACK_COLORS.CARD_BG
        return AE.COLORS
    end
    return FALLBACK_COLORS
end

-- Ordered section list. IDs stable; labels can change later. (Setup was
-- renamed from Response 2026-04-24 when the trigger-level Target Type +
-- companion targeting fields landed inside it -- "Response" no longer fit.)
local SECTIONS = {
    { id = "trigger",  label = "Trigger" },
    { id = "setup",    label = "Setup" },
    { id = "effects",  label = "Effects" },
    { id = "display",  label = "Display" },
}

-- Inherit the full New Ability Editor style pack. Covers nav buttons, section
-- headings, field rows, checkbox skinning, button chrome, form-widget label
-- alignment, and everything else the two editors should look identical in.
-- Fall back to the bare Styles.Form if AbilityEditor is unavailable (should
-- not happen in practice -- both files live in the same mod -- but keeps the
-- editor renderable if load order shifts).
local function buildStyles()
    local AE = rawget(_G, "AbilityEditor")
    local styles
    if AE ~= nil and AE.GetEditorStyles ~= nil then
        styles = AE.GetEditorStyles()
    else
        styles = { Styles.Form }
    end

    -- Classic-code alignment fixup. The upstream appearancePanel inside
    -- ActivatedAbility:IconEditorPanel (DMHub Compendium/ActivatedAbilityEditor.lua
    -- line ~1203) is width="auto" with no halign, so a vertical-flow parent
    -- centers it. Pinning by its "appearance" class pulls it left without
    -- touching classic code.
    styles[#styles + 1] = gui.Style{
        selectors = {"appearance"},
        priority = 3,
        halign = "left",
    }
    -- The shared "More options" row in the Targeting stack (AbilityEditor.lua
    -- ~line 563) uses halign="center" by default so the New Ability Editor
    -- shows it as a centered fold-out. Inside the Triggered Ability Editor
    -- we want it flush-left like every other Setup-section field row, per
    -- 2026-04-24 design feedback. Scoped priority beats the base halign.
    styles[#styles + 1] = gui.Style{
        selectors = {"nae-more-options-row"},
        priority = 3,
        halign = "left",
    }
    -- Note: the classic TargetTypeEditor's abilityFilterPanel (DMHub Compendium
    -- ActivatedAbilityEditor.lua line ~1825) has no halign and no class hook,
    -- so its "Add Ability Filter" button still renders centered. Same story
    -- for the Reasoned Filter wrapper at line ~2260. Fix lands naturally in
    -- phase 2 when we replace BehaviorEditor with sectioned behavior cards.

    return styles
end

-- Simple vertical row with a label above a child element. Matches the
-- Character Builder / New Ability Editor stacked-field convention so the
-- detail column reads cleanly without horizontal label wrapping.
local function fieldRow(labelText, child, hintText)
    local children = {
        gui.Label{
            classes = {"nae-field-label"},
            text = labelText,
        },
        child,
    }
    if hintText ~= nil and hintText ~= "" then
        children[#children + 1] = gui.Label{
            classes = {"nae-field-hint"},
            text = hintText,
        }
    end
    return gui.Panel{
        classes = {"nae-field-row"},
        children = children,
    }
end

local function sectionHeading(text)
    return gui.Label{
        classes = {"nae-section-heading"},
        text = text,
    }
end

--[[
    ============================================================================
    Trigger section
    ============================================================================
    Fields: Name, Trigger Event, Trigger Subject, When Active, Requires
    Condition (+ inflicted-by), Trigger Range, Triggers Only When.
    Icon and Description now live in the Display section.
]]
local SUBJECT_OPTIONS = {
    {id = "self",           text = "Self"},
    {id = "any",            text = "Self or Any Creature"},
    {id = "selfandheroes",  text = "Self or a Hero"},
    {id = "otherheroes",    text = "Any Hero (Not Self)"},
    {id = "selfandallies",  text = "Self or an Ally"},
    {id = "allies",         text = "Any Ally (Not Self)"},
    {id = "enemy",          text = "Any Enemy"},
    {id = "other",          text = "Any Creature (Not Self)"},
}

local WHEN_ACTIVE_OPTIONS = {
    {id = "always", text = "Always Active"},
    {id = "combat", text = "Only During Combat"},
}

-- Corrected display labels per the design doc. The underlying ids ("remove"
-- and "corpse") match TriggeredAbility.DespawnBehaviors; we only override the
-- display text so the classic editor keeps its original labels unaffected.
local DESPAWN_OPTIONS = {
    {id = "remove", text = "Skip Despawned Targets"},
    {id = "corpse", text = "Retarget to Corpse"},
}

--[[
    ============================================================================
    Trigger Event picker metadata
    ============================================================================
    Categorized metadata for each registered trigger id. Bands, approved
    display renames, and per-id descriptions come from the design doc's
    "Trigger Event picker modal" section.

    The Common band uses sortOrder for priority ordering; all others sort
    alphabetically on the resolved display label.

    The `label` field overrides the registered `text` (used only for the
    approved renames); `description` renders under the title on each card;
    `tags` are searchable alongside id/label/description; `group` picks
    the band.

    Ids the picker must not show:
      * miss, attacked -- 5e-only, registered via dnd5e.lua but no DS usage
        for new authoring (attacked still loads from existing content).
      * fumble -- has a hide() predicate gated on power-roll outcome structure
        that DS never satisfies; the standard filter already drops it.
      * hit -- deregistered in MCDMRules.lua:1277.
      * Aura-specific ids (onenter, casterendturnaura) never hit the main
        picker because they live in Aura.lua and are only surfaced in the
        aura-embed editor (which falls through to classic dispatch).
]]
local TRIGGER_METADATA = {
    -- Common (priority-sorted)
    losehitpoints = {
        label = "Take Damage",
        description = "Fires when the creature loses stamina from damage.",
        tags = {"damage", "hit", "hurt", "retaliate", "stamina"},
        group = "common",
        sortOrder = 1,
    },
    dealdamage = {
        label = "Damage an Enemy",
        description = "Fires when the creature deals damage.",
        tags = {"damage", "deal", "on-hit", "rider"},
        group = "common",
        sortOrder = 2,
    },
    rollpower = {
        label = "Roll Power",
        description = "Fires on any power roll, with the 2d10 results available as symbols.",
        tags = {"power", "roll", "2d10", "tier", "crit", "natural"},
        group = "common",
        sortOrder = 3,
    },
    inflictcondition = {
        label = "Condition Applied",
        description = "Fires when a condition is inflicted on the subject.",
        tags = {"condition", "status", "dazed", "prone", "grabbed"},
        group = "common",
        sortOrder = 4,
    },
    useability = {
        label = "Use an Ability",
        description = "Fires when the creature uses any ability.",
        tags = {"ability", "cast", "use", "economy"},
        group = "common",
        sortOrder = 5,
    },
    beginturn = {
        label = "Start of Turn",
        description = "Fires at the start of the creature's turn.",
        tags = {"turn", "begin", "round", "ongoing", "aura"},
        group = "common",
        sortOrder = 6,
    },

    -- Combat (alphabetical)
    attack = {
        label = "Attack an Enemy",
        description = "Fires when the creature makes an attack against an enemy.",
        tags = {"attack", "strike", "enemy"},
        group = "combat",
    },
    dying = {
        label = "Become Dying (Heroes Only)",
        description = "Fires when a hero drops to dying.",
        tags = {"dying", "hero", "death saves"},
        group = "combat",
    },
    winded = {
        label = "Become Winded",
        description = "Fires when the creature becomes winded.",
        tags = {"winded", "half", "bloodied", "stamina"},
        group = "combat",
    },
    fallenon = {
        label = "Creature Lands On You",
        description = "Fires when a falling creature lands on this creature.",
        tags = {"fall", "land", "impact", "above"},
        group = "combat",
    },
    creaturedeath = {
        label = "Death",
        description = "Fires when the creature dies.",
        tags = {"death", "die", "dead", "kill"},
        group = "combat",
    },
    zerohitpoints = {
        label = "Drop to Zero Stamina",
        description = "Fires when the creature reaches zero stamina.",
        tags = {"zero", "stamina", "down", "defeated"},
        group = "combat",
    },
    gaintempstamina = {
        label = "Gain Temporary Stamina",
        description = "Fires when the creature gains temporary stamina.",
        tags = {"temporary", "stamina", "shield", "buffer"},
        group = "combat",
    },
    kill = {
        label = "Kill a Creature",
        description = "Fires when the creature kills another creature.",
        tags = {"kill", "slay", "finisher"},
        group = "combat",
    },
    saveagainstdamage = {
        label = "Made Reactive Roll Against damage",
        description = "Fires when the creature makes a reactive roll to reduce damage.",
        tags = {"save", "reactive", "roll", "reduce"},
        group = "combat",
    },
    regainhitpoints = {
        label = "Regain Stamina",
        description = "Fires when the creature regains stamina.",
        tags = {"heal", "regain", "stamina", "recover"},
        group = "combat",
    },

    -- Abilities & Power Rolls (alphabetical)
    finishability = {
        label = "Finish Using an Ability",
        description = "Fires after the creature finishes resolving an ability.",
        tags = {"ability", "finish", "end", "resolve"},
        group = "abilities",
    },
    targetwithability = {
        label = "Targeted by an Ability",
        description = "Fires when the creature is targeted by another creature's ability.",
        tags = {"targeted", "target", "ability", "by"},
        group = "abilities",
    },
    castsignature = {
        label = "Use Signature Attack or Area",
        description = "Fires when the creature uses a signature Strike or Area ability.",
        tags = {"signature", "strike", "area", "cast"},
        group = "abilities",
    },

    -- Movement (alphabetical)
    leaveadjacent = {
        label = "Adjacent Creature Moves Away",
        description = "Fires when a creature adjacent to this one moves away.",
        tags = {"adjacent", "leave", "move", "away", "opportunity"},
        group = "movement",
    },
    move = {
        label = "Begin Movement",
        description = "Fires at the start of the creature's movement.",
        tags = {"move", "begin", "start"},
        group = "movement",
    },
    wallbreak = {
        label = "Break Through a Wall",
        description = "Fires when the creature breaks through a wall.",
        tags = {"wall", "break", "smash", "burst"},
        group = "movement",
    },
    collide = {
        label = "Collide with a Creature or Object",
        description = "Fires when the creature collides with something during forced movement.",
        tags = {"collide", "crash", "impact", "forced"},
        group = "movement",
    },
    finishmove = {
        label = "Complete Movement",
        description = "Fires when the creature finishes moving.",
        tags = {"move", "complete", "finish", "end"},
        group = "movement",
    },
    forcemove = {
        label = "Force Moved",
        description = "Fires when the creature is pushed, pulled, or slid.",
        tags = {"push", "pull", "slide", "forced", "move"},
        group = "movement",
    },
    fall = {
        label = "Land From a Fall",
        description = "Fires when the creature lands after a fall.",
        tags = {"fall", "land", "drop"},
        group = "movement",
    },
    movethrough = {
        label = "Move Through Creature",
        description = "Fires when the creature moves through another creature's space.",
        tags = {"move", "through", "pass", "phase"},
        group = "movement",
    },
    pressureplate = {
        label = "Stepped on a Pressure Plate",
        description = "Fires when a creature steps on a pressure plate tile.",
        tags = {"pressure", "plate", "trap", "step"},
        group = "movement",
    },
    teleport = {
        label = "Teleport",
        description = "Fires when the creature teleports.",
        tags = {"teleport", "blink", "instant"},
        group = "movement",
    },

    -- Resources & Victory
    earnvictory = {
        label = "Earn Victory",
        description = "Fires when the creature earns victories.",
        tags = {"victory", "earn", "heroic"},
        group = "resources",
    },
    gainresource = {
        label = "Gain Resource",
        description = "Fires when the creature gains a resource.",
        tags = {"resource", "gain", "heroic"},
        group = "resources",
    },
    useresource = {
        label = "Use Resource",
        description = "Fires when the creature spends a resource.",
        tags = {"resource", "use", "spend", "heroic"},
        group = "resources",
    },

    -- Turn & Game Mode
    prestartturn = {
        label = "Before Start of Turn",
        description = "Fires just before the start of the creature's turn.",
        tags = {"turn", "before", "pre", "start"},
        group = "turn",
    },
    rollinitiative = {
        label = "Draw Steel",
        description = "Fires when the creature rolls initiative.",
        tags = {"initiative", "draw steel", "start", "combat"},
        group = "turn",
    },
    endcombat = {
        label = "End of Combat",
        description = "Fires when combat ends.",
        tags = {"end", "combat", "over"},
        group = "turn",
    },
    endrespite = {
        label = "End Respite",
        description = "Fires when a respite ends.",
        tags = {"respite", "end", "rest"},
        group = "turn",
    },
    endturn = {
        label = "End Turn",
        description = "Fires when the creature ends its turn.",
        tags = {"turn", "end"},
        group = "turn",
    },
    startdowntime = {
        label = "Start Downtime",
        description = "Fires when downtime begins.",
        tags = {"downtime", "start"},
        group = "turn",
    },
    beginround = {
        label = "Start of Round",
        description = "Fires at the start of each round.",
        tags = {"round", "begin", "start"},
        group = "turn",
    },
    startrespite = {
        label = "Start Respite",
        description = "Fires when a respite begins.",
        tags = {"respite", "start", "rest"},
        group = "turn",
    },

    -- Custom
    custom = {
        label = "Custom Trigger",
        description = "Fires on a named custom trigger raised by a macro or behavior.",
        tags = {"custom", "macro", "event", "named"},
        group = "custom",
    },
}

local TRIGGER_GROUPS = {
    {id = "common",    label = "Common"},
    {id = "combat",    label = "Combat"},
    {id = "abilities", label = "Abilities & Power Rolls"},
    {id = "movement",  label = "Movement"},
    {id = "resources", label = "Resources & Victory"},
    {id = "turn",      label = "Turn & Game Mode"},
    {id = "custom",    label = "Custom"},
}

-- Ids excluded from the picker. Items with hide() predicates (fumble in DS)
-- are filtered separately via the standard hide-check below.
local EXCLUDED_TRIGGER_IDS = {
    miss     = true,  -- 5e-only, registered via dnd5e.lua
    attacked = true,  -- 5e-only; existing content loads but no new authoring
}

local function getTriggerLabel(triggerId)
    if triggerId == nil then
        return "(none)"
    end
    local meta = TRIGGER_METADATA[triggerId]
    if meta ~= nil and meta.label ~= nil then
        return meta.label
    end
    local info = TriggeredAbility.GetTriggerById(triggerId)
    if info ~= nil then
        return info.text or triggerId
    end
    return triggerId
end

local function _filterTriggers(query, entries)
    local results = {}
    for _, entry in ipairs(entries) do
        local match = true
        if query ~= nil and query ~= "" then
            match = false
            local q = string.lower(query)
            if string.find(string.lower(entry.label), q, 1, true) then
                match = true
            elseif string.find(string.lower(entry.id), q, 1, true) then
                match = true
            elseif string.find(string.lower(entry.description or ""), q, 1, true) then
                match = true
            else
                for _, tag in ipairs(entry.tags or {}) do
                    if string.find(string.lower(tag), q, 1, true) then
                        match = true
                        break
                    end
                end
            end
        end
        if match then
            results[#results + 1] = entry
        end
    end
    return results
end

local function _makeTriggerCard(entry, onSelect, COLORS)
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        hpad = 10,
        vpad = 6,
        bmargin = 4,
        bgimage = "panels/square.png",
        bgcolor = COLORS.PANEL_BG,
        borderWidth = 1,
        borderColor = COLORS.GOLD,
        cornerRadius = 3,
        borderBox = true,
        press = function()
            onSelect(entry.id)
        end,
        gui.Label{
            width = "100%",
            height = "auto",
            fontSize = 14,
            bold = true,
            color = COLORS.CREAM_BRIGHT,
            textAlignment = "left",
            text = entry.label,
        },
        gui.Label{
            width = "100%",
            height = "auto",
            fontSize = 12,
            italics = true,
            color = COLORS.GRAY,
            textAlignment = "left",
            text = entry.description or "",
        },
    }
end

local function _buildTriggerGroupPanel(groupDef, entries, onSelect, COLORS)
    if groupDef.id == "common" then
        table.sort(entries, function(a, b)
            local sa = a.sortOrder or 99
            local sb = b.sortOrder or 99
            if sa ~= sb then return sa < sb end
            return a.label < b.label
        end)
    else
        table.sort(entries, function(a, b) return a.label < b.label end)
    end

    local cards = {}
    for _, entry in ipairs(entries) do
        cards[#cards + 1] = _makeTriggerCard(entry, onSelect, COLORS)
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bmargin = 12,
        bgcolor = "clear",
        children = {
            gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 16,
                bold = true,
                color = COLORS.GOLD_DIM,
                textAlignment = "left",
                bmargin = 4,
                text = groupDef.label,
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                bgcolor = "clear",
                children = cards,
            },
        },
    }
end

local function openTriggerEventPicker(currentId, onChosen)
    local COLORS = getColors()

    -- Build the filtered entry list from the live trigger registry. Skip
    -- excluded ids, items whose hide() predicate returns true, and
    -- unrecognised entries (they would end up with no description and no
    -- group). The last case is effectively an authoring bug alert: add
    -- metadata to TRIGGER_METADATA above.
    local entries = {}
    for _, trig in ipairs(TriggeredAbility.triggers) do
        if not EXCLUDED_TRIGGER_IDS[trig.id]
                and (trig.hide == nil or not trig.hide()) then
            local meta = TRIGGER_METADATA[trig.id]
            if meta ~= nil then
                entries[#entries + 1] = {
                    id = trig.id,
                    label = meta.label or trig.text,
                    description = meta.description,
                    tags = meta.tags,
                    group = meta.group,
                    sortOrder = meta.sortOrder,
                }
            end
        end
    end

    local function onSelect(triggerId)
        gui.CloseModal()
        onChosen(triggerId)
    end

    local searchInput
    local resultsPanel

    searchInput = gui.Input{
        width = "100%",
        height = 30,
        placeholderText = "Search trigger events...",
        bgimage = "panels/square.png",
        bgcolor = COLORS.PANEL_BG,
        borderWidth = 1,
        borderColor = COLORS.GOLD,
        cornerRadius = 3,
        hpad = 8,
        vpad = 4,
        borderBox = true,
        fontSize = 14,
        color = COLORS.CREAM_BRIGHT,
        bmargin = 8,
        textAlignment = "left",
        editlag = 0.15,
        edit = function(element)
            resultsPanel:FireEvent("updateResults")
        end,
        create = function(element)
            element.hasFocus = true
        end,
    }

    resultsPanel = gui.Panel{
        width = "100%",
        height = "100%-80",
        flow = "vertical",
        vscroll = true,
        bgcolor = "clear",
        halign = "left",
        valign = "top",

        create = function(element)
            element:FireEvent("updateResults")
        end,

        updateResults = function(element)
            local rawQuery = searchInput.text or ""
            local query = rawQuery
            if query == "" then query = nil end

            local children = {}
            local filtered = _filterTriggers(query, entries)

            for _, groupDef in ipairs(TRIGGER_GROUPS) do
                local groupEntries = {}
                for _, entry in ipairs(filtered) do
                    if entry.group == groupDef.id then
                        groupEntries[#groupEntries + 1] = entry
                    end
                end
                if #groupEntries > 0 then
                    children[#children + 1] = _buildTriggerGroupPanel(groupDef, groupEntries, onSelect, COLORS)
                end
            end

            if #filtered == 0 and query ~= nil then
                children[#children + 1] = gui.Label{
                    width = "100%",
                    height = "auto",
                    fontSize = 14,
                    italics = true,
                    color = COLORS.GRAY,
                    textAlignment = "center",
                    vmargin = 24,
                    text = "No trigger events match \"" .. rawQuery .. "\"",
                }
            end

            element.children = children
        end,
    }

    local dialogPanel = gui.Panel{
        classes = {"framedPanel"},
        styles = {Styles.Default, Styles.Panel},
        width = 600,
        height = 600,
        flow = "vertical",
        pad = 16,
        borderBox = true,
        halign = "center",
        valign = "center",
        fontFace = "Berling",
        children = {
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "left",
                valign = "center",
                bmargin = 8,
                bgcolor = "clear",
                children = {
                    gui.Label{
                        width = "auto",
                        height = "auto",
                        fontSize = 20,
                        bold = true,
                        color = COLORS.GOLD_BRIGHT,
                        textAlignment = "left",
                        text = "Select Trigger Event",
                    },
                },
            },
            searchInput,
            resultsPanel,
            gui.CloseButton{
                halign = "right",
                valign = "top",
                floating = true,
                escapeActivates = true,
                escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                click = function()
                    gui.CloseModal()
                end,
            },
        },
    }

    gui.ShowModal(dialogPanel)
end

-- Trigger Event field: shows the current event's display label with an
-- inline "Change" button that opens the picker modal. Mirrors the Ability
-- Editor's "Advanced Target..." convention (label + action button) rather
-- than miming a dropdown with modal behaviour. TriggeredAbility.Create
-- always sets a default trigger id ("losehitpoints"), so the field never
-- needs an empty state.
local function makeTriggerEventButton(ability, refreshSection)
    local COLORS = getColors()
    return gui.Panel{
        width = "auto",
        height = 30,
        flow = "horizontal",
        halign = "left",
        valign = "center",
        bgcolor = "clear",
        children = {
            gui.Panel{
                width = "auto",
                height = 28,
                flow = "horizontal",
                halign = "left",
                valign = "center",
                rmargin = 12,
                bgcolor = "clear",
                children = {
                    gui.Panel{
                        width = 3,
                        height = 20,
                        halign = "left",
                        valign = "center",
                        rmargin = 10,
                        bgimage = "panels/square.png",
                        bgcolor = COLORS.GOLD,
                    },
                    gui.Label{
                        width = "auto",
                        height = "auto",
                        valign = "center",
                        textAlignment = "left",
                        fontSize = 14,
                        bold = true,
                        color = COLORS.CREAM_BRIGHT,
                        text = getTriggerLabel(ability.trigger),
                    },
                },
            },
            gui.Button{
                text = "Change",
                fontSize = 14,
                width = 100,
                height = 28,
                halign = "left",
                valign = "center",
                click = function()
                    openTriggerEventPicker(ability.trigger, function(triggerId)
                        ability.trigger = triggerId
                        refreshSection()
                    end)
                end,
            },
        },
    }
end

local function buildTriggerSection(ability, refreshSection, fireChange)
    local children = {}

    children[#children + 1] = sectionHeading("Trigger")

    -- Name
    children[#children + 1] = fieldRow("Name",
        gui.Input{
            classes = {"formInput"},
            width = 280,
            placeholderText = "Enter trigger name...",
            text = ability.name or "",
            change = function(element)
                ability.name = element.text
            end,
        })

    -- Trigger Event -- categorized picker modal (phase 2).
    children[#children + 1] = fieldRow("Trigger Event",
        makeTriggerEventButton(ability, refreshSection))

    -- Trigger Subject
    children[#children + 1] = fieldRow("Trigger Subject",
        gui.Dropdown{
            classes = {"formDropdown"},
            width = 280,
            height = 30,
            options = SUBJECT_OPTIONS,
            idChosen = ability:try_get("subject", "self"),
            change = function(element)
                ability.subject = element.idChosen
                refreshSection()
            end,
        },
        "Who the editor is listening for the trigger event to occur on.")

    -- When Active
    children[#children + 1] = fieldRow("When Active",
        gui.Dropdown{
            classes = {"formDropdown"},
            width = 280,
            height = 30,
            options = WHEN_ACTIVE_OPTIONS,
            idChosen = ability:try_get("whenActive", "always"),
            change = function(element)
                ability.whenActive = element.idChosen
            end,
        })

    -- Requires Condition
    local conditionOptions = {
        {id = "none", text = "None"},
    }
    CharacterCondition.FillDropdownOptions(conditionOptions)
    children[#children + 1] = fieldRow("Requires Condition",
        gui.Dropdown{
            classes = {"formDropdown"},
            width = 280,
            height = 30,
            hasSearch = true,
            options = conditionOptions,
            idChosen = ability:try_get("characterConditionRequired", "none"),
            change = function(element)
                if element.idChosen == "none" then
                    ability.characterConditionRequired = nil
                else
                    ability.characterConditionRequired = element.idChosen
                end
                refreshSection()
            end,
        })

    if ability:try_get("characterConditionRequired", "none") ~= "none" then
        children[#children + 1] = gui.Check{
            text = "Condition must be inflicted by you",
            value = ability:try_get("characterConditionInflictedBySelf", false),
            vmargin = 6,
            change = function(element)
                ability.characterConditionInflictedBySelf = element.value
            end,
        }
    end

    -- Trigger Range (GoblinScript) -- hidden when Subject is Self.
    if ability:try_get("subject", "self") ~= "self" then
        children[#children + 1] = fieldRow("Trigger Range",
            gui.GoblinScriptInput{
                value = ability:try_get("subjectRange", ""),
                change = function(element)
                    ability.subjectRange = element.value
                end,
                documentation = {
                    help = "GoblinScript used to determine the range at which this triggered ability can activate.",
                    output = "number",
                    subject = creature.helpSymbols,
                    subjectDescription = "The creature the ability will trigger on",
                    symbols = {
                        subject = {
                            name = "Subject",
                            type = "creature",
                            desc = "The creature that the event occurred on. This will be the same as Self for triggered abilities that only affect self.",
                        },
                    },
                },
            })
    end

    -- Triggers Only When (GoblinScript condition formula)
    local helpSymbols = {
        caster = {
            name = "Caster",
            type = "creature",
            desc = "The creature that controls the aura triggering this ability.\n\n<color=#ffaaaa><i>This field is only available for triggered abilities that are triggered by an aura.</i></color>",
        },
        subject = {
            name = "Subject",
            type = "creature",
            desc = "The creature that the event occurred on. This will be the same as Self for triggered abilities that only affect self.",
        },
    }
    local examples = {
        {
            script = "hitpoints < 5",
            text = "The triggered ability only activates when stamina is below 5.",
        },
    }
    local triggerInfo = TriggeredAbility.GetTriggerById(ability.trigger)
    if triggerInfo ~= nil then
        for k, v in pairs(triggerInfo.symbols or {}) do
            if type(v) == "table" and v.name then
                k = string.lower(string.gsub(v.name, "%s+", ""))
            end
            helpSymbols[k] = v
        end
        for _, example in ipairs(triggerInfo.examples or {}) do
            examples[#examples + 1] = example
        end
    end

    children[#children + 1] = fieldRow("Triggers Only When",
        gui.GoblinScriptInput{
            value = ability.conditionFormula,
            change = function(element)
                ability.conditionFormula = element.value
            end,
            documentation = {
                help = "GoblinScript used to determine whether the triggered ability activates.",
                output = "boolean",
                examples = examples,
                subject = creature.helpSymbols,
                subjectDescription = "The creature the ability will trigger on",
                symbols = helpSymbols,
            },
        })

    -- Modes & Variations (No Modes / Multiple Modes / Ability Variations).
    -- Parity with the classic editor, which surfaced these via
    -- BehaviorEditor -> TargetTypeEditor. Real-world usage is sparse (1
    -- ability in the bestiary uses variations) but the flow exists so
    -- authors have access without dropping back to the classic editor.
    -- Injected here rather than in Setup per 2026-04-24 feedback -- Modes
    -- are a trigger-level concept, not a firing / targeting concern.
    if AbilityEditor and AbilityEditor.BuildModesSection then
        -- fireChange (cross-editor preview + mech view refresh) is the
        -- right hook here; refreshSection would only rebuild the Trigger
        -- section locally. Modes visibility + preview both care about
        -- multipleModes state changes globally.
        local modesChildren = AbilityEditor.BuildModesSection(ability, fireChange or refreshSection)
        for _, c in ipairs(modesChildren) do
            children[#children + 1] = c
        end
    end

    return children
end

--[[
    ============================================================================
    Setup section (formerly Response, renamed 2026-04-24)
    ============================================================================
    Holds everything that shapes how the trigger fires + where it lands:
    Trigger Mode, Prompt Text, Resource Cost, Action Used, Manual Version,
    full Target Type / Range / numTargets / AOE / proximity stack lifted
    from the New Ability Editor, then When Target Despawns at the bottom.
]]

-- Trigger Mode values. The two common ones are surfaced as a segmented
-- toggle; the three advanced ones live under an expander with radios.
-- Labels come from the design doc's Trigger Mode table.
local TRIGGER_MODE_COMMON = {
    {id = false, label = "Prompt the Player"},
    {id = true,  label = "Occurs Automatically"},
}

local TRIGGER_MODE_ADVANCED = {
    {id = "local",                       label = "Occurs Automatically (Local Only)"},
    {id = "prompt_remote",               label = "Prompt Remote Player, Auto for Local"},
    {id = "game:heroicresourcetriggers", label = "Automatic Heroic Resource Setting"},
}

local function isAdvancedMode(value)
    for _, opt in ipairs(TRIGGER_MODE_ADVANCED) do
        if opt.id == value then return true end
    end
    return false
end

local function buildTriggerModeControl(ability, refreshSection)
    local COLORS = getColors()
    local currentMode = ability.mandatory

    -- Segmented-toggle button for a common mode. Highlights gold when this
    -- id matches the current value.
    local function segmentedButton(option)
        local selected = (option.id == currentMode)
        return gui.Panel{
            width = 160,
            height = 30,
            flow = "horizontal",
            halign = "center",
            valign = "center",
            hpad = 8,
            vpad = 4,
            borderBox = true,
            bgimage = "panels/square.png",
            bgcolor = selected and COLORS.GOLD or COLORS.PANEL_BG,
            borderWidth = 1,
            borderColor = COLORS.GOLD,
            cornerRadius = 0,
            press = function()
                if ability.mandatory ~= option.id then
                    ability.mandatory = option.id
                    refreshSection()
                end
            end,
            children = {
                gui.Label{
                    width = "100%",
                    height = "100%",
                    textAlignment = "center",
                    fontSize = 14,
                    color = selected and COLORS.BG or COLORS.CREAM_BRIGHT,
                    bold = selected,
                    text = option.label,
                },
            },
        }
    end

    local segmented = gui.Panel{
        width = "auto",
        height = 30,
        flow = "horizontal",
        halign = "left",
        valign = "center",
        bgcolor = "clear",
        children = {
            segmentedButton(TRIGGER_MODE_COMMON[1]),
            segmentedButton(TRIGGER_MODE_COMMON[2]),
        },
    }

    -- Radio-row for an advanced mode. A filled circle when selected, a ring
    -- otherwise. Clicking sets the mode.
    local function advancedRadio(option)
        local selected = (option.id == currentMode)
        return gui.Panel{
            width = "auto",
            height = 24,
            flow = "horizontal",
            halign = "left",
            valign = "center",
            vmargin = 2,
            bgcolor = "clear",
            press = function()
                if ability.mandatory ~= option.id then
                    ability.mandatory = option.id
                    refreshSection()
                end
            end,
            children = {
                gui.Panel{
                    width = 14,
                    height = 14,
                    rmargin = 8,
                    halign = "left",
                    valign = "center",
                    bgimage = "panels/square.png",
                    bgcolor = selected and COLORS.GOLD or "clear",
                    borderWidth = 1,
                    borderColor = COLORS.GOLD,
                    cornerRadius = 7,
                },
                gui.Label{
                    width = "auto",
                    height = "auto",
                    textAlignment = "left",
                    fontSize = 14,
                    color = COLORS.CREAM_BRIGHT,
                    text = option.label,
                },
            },
        }
    end

    local advancedChildren = {}
    for _, opt in ipairs(TRIGGER_MODE_ADVANCED) do
        advancedChildren[#advancedChildren + 1] = advancedRadio(opt)
    end

    -- Start the foldout open when the current value is an advanced one so
    -- the author sees which radio is active.
    local startExpanded = isAdvancedMode(currentMode)

    local advancedPanel
    advancedPanel = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "left",
        classes = {cond(startExpanded, nil, "collapsed-anim")},
        bgcolor = "clear",
        children = advancedChildren,
    }

    -- Match the Ability Editor's Targeting-section "More options" foldout
    -- styling (nae-more-options-row / -label / -chevron), left-aligned to
    -- sit flush under the segmented toggle. collapsed-anim on the content
    -- panel animates height to 0 so no dead space is reserved when hidden.
    local moreChevron
    moreChevron = gui.Panel{
        classes = {"nae-more-options-chevron", cond(startExpanded, nil, "nae-collapsed")},
    }
    local moreRow = gui.Panel{
        classes = {"nae-more-options-row"},
        halign = "left",
        tmargin = 6,
        press = function()
            local wasCollapsed = advancedPanel:HasClass("collapsed-anim")
            advancedPanel:SetClass("collapsed-anim", not wasCollapsed)
            moreChevron:SetClass("nae-collapsed", not wasCollapsed)
        end,
        gui.Label{
            classes = {"nae-more-options-label"},
            text = "Advanced modes",
        },
        moreChevron,
    }

    return gui.Panel{
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "left",
        bgcolor = "clear",
        children = {segmented, moreRow, advancedPanel},
    }
end

-- Setup section (renamed from Response 2026-04-24). Holds everything that
-- shapes how the trigger fires and where it lands: Trigger Mode + cost +
-- action (the "how it fires" half), the full Target Type / Range /
-- numTargets / AOE / proximity stack lifted from the New Ability Editor
-- (the "what it hits" half), and the Despawn cleanup field.
local function buildSetupSection(ability, refreshSection, fireChange)
    local children = {}

    children[#children + 1] = sectionHeading("Setup")

    -- Trigger Mode (progressive disclosure: segmented toggle + advanced
    -- expander). The control writes directly to ability.mandatory so
    -- existing IsMandatory / MayBePrompted helpers keep working unchanged.
    children[#children + 1] = fieldRow("Trigger Mode",
        buildTriggerModeControl(ability, refreshSection))

    -- Prompt Text -- hidden when the chosen mode doesn't allow prompting.
    if ability:MayBePrompted() then
        children[#children + 1] = fieldRow("Prompt Text",
            gui.Input{
                classes = {"formInput"},
                width = 360,
                characterLimit = 300,
                placeholderText = "Prompt shown to the player...",
                text = ability:try_get("triggerPrompt", ""),
                change = function(element)
                    ability.triggerPrompt = element.text
                end,
            })

        -- Resource Cost (numeric). Only relevant when prompting is possible.
        children[#children + 1] = fieldRow("Resource Cost",
            gui.Input{
                classes = {"formInput"},
                width = 80,
                placeholderText = "Cost...",
                characterLimit = 3,
                text = cond(ability.resourceCost == "none", "", ability.resourceNumber),
                change = function(element)
                    local text = trim(element.text)
                    if tonumber(text) ~= nil then
                        ability.resourceCost = character.resourceid
                        ability.resourceNumber = tonumber(text)
                    else
                        ability.resourceCost = "none"
                    end
                    element.text = cond(ability.resourceCost == "none", "", ability.resourceNumber)
                end,
            })
    end

    -- Action Used
    local actionOptions = CharacterResource.GetActionOptions()
    actionOptions[#actionOptions + 1] = {id = "none", text = "None"}
    children[#children + 1] = fieldRow("Action Used",
        gui.Dropdown{
            classes = {"formDropdown"},
            width = 260,
            height = 30,
            idChosen = ability:ActionResource() or "none",
            options = actionOptions,
            change = function(element)
                if element.idChosen == "none" then
                    ability.actionResourceId = nil
                else
                    ability.actionResourceId = element.idChosen
                end
            end,
        })

    -- Manual Version checkbox
    children[#children + 1] = gui.Check{
        text = "Create manual version of this trigger",
        value = ability:try_get("hasManualVersion", false),
        vmargin = 6,
        change = function(element)
            ability.hasManualVersion = element.value
        end,
    }

    -- Targeting block (Target Type + Range + numTargets + AOE shape +
    -- proximity + Affects + Can Target Self + Object ID + Target Filter +
    -- Range Text + Target Text + "More options" -> Ability Filters /
    -- Reasoned Filters). Lifted from the New Ability Editor via
    -- AbilityEditor.BuildTargetingSection so the conditional-visibility
    -- behaviour and all the per-targetType companion fields stay
    -- consistent with the active-ability surface authors already know.
    -- Target Type options are event-aware via ability:GetDisplayedTargetTypeOptions
    -- which filters TriggeredAbility.TargetTypes by each entry's
    -- condition(ability) predicate (e.g. "attacker" only valid for
    -- attacked / hit / losehitpoints / inflictcondition / winded / dying;
    -- "pathmoved" / "pathmovednodest" only for finishmove; "aura" only
    -- for casterendturnaura; "subject" only when subject ~= self -- the
    -- last shows as "The Trigger Subject" per design doc gotcha 6).
    local targetingChildren = AbilityEditor.BuildTargetingSection(ability, fireChange)
    for _, c in ipairs(targetingChildren) do
        children[#children + 1] = c
    end

    -- When Target Despawns (cleanup field, kept at the bottom of the
    -- section so it reads as the last "what if something goes wrong"
    -- step after firing + targeting are configured).
    children[#children + 1] = fieldRow("When Target Despawns",
        gui.Dropdown{
            classes = {"formDropdown"},
            width = 280,
            height = 30,
            idChosen = ability.despawnBehavior,
            options = DESPAWN_OPTIONS,
            change = function(element)
                ability.despawnBehavior = element.idChosen
            end,
        },
        "If a target leaves the map before the trigger resolves, skip them or retarget to their corpse.")

    return children
end

--[[
    ============================================================================
    Effects section
    ============================================================================
    Per-behaviour cards (nae-behavior-item) lifted from the New Ability
    Editor via AbilityEditor.BuildEffectsSection + an inline "+ Add Behavior"
    button that opens the shared behaviour picker modal. This replaces the
    classic ability:BehaviorEditor() renderer (which leaked centered
    alignment on the Add Ability Filter / Add Reasoned Filter buttons).

    ability.Types / ability.TypesById resolve to TriggeredAbility.Types for
    TriggeredAbility instances (via the RegisterGameType inheritance chain),
    so the momentary behaviour entry reaches both the picker and the
    createBehavior lookup here without any special-casing.
]]
local function buildEffectsSection(ability, refreshSection, fireChange)
    local children = {}
    children[#children + 1] = sectionHeading("Effects")

    -- AbilityEditor.BuildEffectsSection returns a children array containing
    -- the behaviour list panel. The list's refreshAbility handler is
    -- key-guarded on add/remove/reorder so per-field edits inside a card
    -- won't tear down the section. + Add Behavior / Paste Behavior live in
    -- the fixed bottom bar (see generateSectionedEditor), not inline here.
    local effectsChildren = AbilityEditor.BuildEffectsSection(ability, fireChange)
    for _, c in ipairs(effectsChildren) do
        children[#children + 1] = c
    end
    return children
end

--[[
    ============================================================================
    Display section
    ============================================================================
    Icon + Description (presentation fields lifted from the classic right
    column) + per-field card overrides (phase 7). Each override stores to a
    `display*` field on the TriggeredAbility; blank passes through to
    derivation in buildTriggerPreviewCard. Card Type is the only override
    without a derived default -- the dropdown picks one of three values.
]]

local CARD_TYPE_OPTIONS = {
    {id = "trigger", text = "Triggered Action"},
    {id = "free",    text = "Free Triggered Action"},
    {id = "passive", text = "Passive"},
}

-- Keyword picker for the Display section's Keywords row. Writes to
-- ability.displayKeywords as a set table (keys are keyword ids, values
-- are truthy) -- same shape as ActivatedAbility.keywords. Mirrors the
-- classic ActivatedAbilityEditor keyword picker pattern (dropdown to
-- add, chip rows with delete buttons to show + remove). Kept local to
-- the Display section because the fields it writes to (`displayKeywords`)
-- are preview-card overrides, not the ability's real `keywords` field.
local function buildKeywordsPicker(ability, fireChange)
    local panel
    panel = gui.Panel{
        flow = "vertical",
        width = 280,
        height = "auto",
        halign = "left",
    }

    local function rebuild()
        local chosen = ability:try_get("displayKeywords") or {}
        local children = {}

        -- Chip rows, sorted by canonical display name.
        local chipItems = {}
        for id, v in pairs(chosen) do
            if v then
                local text = (rawget(_G, "ActivatedAbility") and ActivatedAbility.CanonicalKeyword)
                    and ActivatedAbility.CanonicalKeyword(id) or id
                chipItems[#chipItems + 1] = { id = id, text = text }
            end
        end
        table.sort(chipItems, function(a, b) return a.text < b.text end)

        for _, item in ipairs(chipItems) do
            local itemId = item.id
            -- Chip row: label + delete button sit flush next to each other
            -- (no halign=right on the bin) so the chip reads as a single
                -- "keyword [x]" unit. Font + icon shrunk per 2026-04-24
            -- feedback so the chip list doesn't overwhelm the section.
            children[#children + 1] = gui.Panel{
                halign = "left",
                width = "auto",
                height = "auto",
                flow = "horizontal",
                valign = "center",
                vmargin = 2,
                bgcolor = "clear",
                gui.Label{
                    text = item.text,
                    fontSize = 11,
                    bold = true,
                    halign = "left",
                    valign = "center",
                    width = "auto",
                    height = "auto",
                    rmargin = 4,
                },
                gui.DeleteItemButton{
                    halign = "left",
                    valign = "center",
                    width = 12,
                    height = 12,
                    click = function(element)
                        local set = ability:get_or_add("displayKeywords", {})
                        set[itemId] = nil
                        rebuild()
                        if fireChange then fireChange() end
                    end,
                },
            }
        end

        -- Add-dropdown with remaining keywords. Collapsed if nothing left
        -- to pick, same UX as the classic keyword picker.
        local options = {}
        if rawget(_G, "GameSystem") and GameSystem.abilityKeywords then
            for kw, _ in pairs(GameSystem.abilityKeywords) do
                if not chosen[kw] then
                    local text = (rawget(_G, "ActivatedAbility") and ActivatedAbility.CanonicalKeyword)
                        and ActivatedAbility.CanonicalKeyword(kw) or kw
                    options[#options + 1] = { id = kw, text = text }
                end
            end
            table.sort(options, function(a, b) return a.text < b.text end)
        end

        if #options > 0 then
            children[#children + 1] = gui.Dropdown{
                classes = {"formDropdown"},
                sort = false,
                textOverride = "Add keyword...",
                hasSearch = true,
                idChosen = "none",
                options = options,
                halign = "left",
                width = 240,
                change = function(element)
                    if element.idChosen ~= "none" then
                        local set = ability:get_or_add("displayKeywords", {})
                        set[element.idChosen] = true
                        rebuild()
                        if fireChange then fireChange() end
                    end
                end,
            }
        end

        panel.children = children
    end

    rebuild()
    return panel
end

-- Build a one-line text input that writes back to ability[fieldName].
-- placeholderText shows the derived fallback ("(auto: <value>)" or just
-- the derived value as a hint) so authors see what blank means.
local function buildOverrideInput(ability, fieldName, placeholder, fireChange, opts)
    opts = opts or {}
    return gui.Input{
        classes = {"formInput"},
        width = opts.width or "100%",
        height = opts.height or "auto",
        minHeight = opts.minHeight or nil,
        multiline = opts.multiline or false,
        textAlignment = opts.multiline and "topleft" or "left",
        placeholderText = placeholder or "",
        characterLimit = opts.characterLimit or 1024,
        text = ability:try_get(fieldName) or "",
        change = function(element)
            ability[fieldName] = element.text
            if fireChange then fireChange() end
        end,
    }
end

local function buildDisplaySection(ability, refreshSection, fireChange)
    local children = {}

    children[#children + 1] = sectionHeading("Display")

    children[#children + 1] = fieldRow("Icon", ability:IconEditorPanel())

    children[#children + 1] = fieldRow("Description",
        gui.Input{
            classes = {"formInput"},
            placeholderText = "Enter ability details...",
            multiline = true,
            width = "100%",
            height = "auto",
            minHeight = 120,
            textAlignment = "topleft",
            characterLimit = 8192,
            text = ability.description or "",
            change = function(element)
                ability.description = element.text
                if fireChange then fireChange() end
            end,
        })

    -- Card overrides. Each row maps to a Trigger Preview card row; blank
    -- passes through to derivation. Keep this group below the Icon/Description
    -- pair so the "core" presentation fields stay together.

    children[#children + 1] = fieldRow("Display Name",
        buildOverrideInput(ability, "displayName",
            ability:try_get("name") or "Triggered Ability", fireChange),
        "Override the card title. Blank uses the ability Name.")

    children[#children + 1] = fieldRow("Card Type",
        gui.Dropdown{
            classes = {"formDropdown"},
            width = 280,
            height = 30,
            idChosen = ability:try_get("displayCardType") or "trigger",
            options = CARD_TYPE_OPTIONS,
            change = function(element)
                ability.displayCardType = element.idChosen
                if fireChange then fireChange() end
            end,
        },
        "Card title-bar colour and Type row label.")

    children[#children + 1] = fieldRow("Cost",
        buildOverrideInput(ability, "displayCost",
            "Free text shown in the card title, e.g. '1 Heroic Resource'",
            fireChange),
        "Blank uses the numeric resource cost as a fallback.")

    children[#children + 1] = fieldRow("Keywords",
        buildKeywordsPicker(ability, fireChange),
        "Shown in the Keywords row on the card.")

    children[#children + 1] = fieldRow("Distance",
        buildOverrideInput(ability, "displayDistance",
            "Blank = derived from behaviour range", fireChange),
        nil)

    children[#children + 1] = fieldRow("Target",
        buildOverrideInput(ability, "displayTarget",
            "Blank = derived from behaviour target", fireChange),
        nil)

    children[#children + 1] = fieldRow("Flavor",
        buildOverrideInput(ability, "displayFlavor",
            "Optional italic flavour line above the card body", fireChange,
            {multiline = true, minHeight = 50}),
        nil)

    children[#children + 1] = fieldRow("Trigger",
        buildOverrideInput(ability, "displayTriggerProse",
            "Blank = auto-derived from event + condition", fireChange,
            {multiline = true, minHeight = 60, characterLimit = 2048}),
        "Card only -- the Mechanical View always shows the raw formula.")

    children[#children + 1] = fieldRow("Effect",
        buildOverrideInput(ability, "displayEffectProse",
            "Blank = auto-derived from behaviour list", fireChange,
            {multiline = true, minHeight = 60, characterLimit = 2048}),
        nil)

    return children
end

local SECTION_BUILDERS = {
    trigger  = buildTriggerSection,
    setup    = buildSetupSection,
    effects  = buildEffectsSection,
    display  = buildDisplaySection,
}

local function makeNavButton(sectionDef, onSelect)
    return gui.Label{
        classes = {"nae-nav-button"},
        id = "ts_nav_" .. sectionDef.id,
        text = sectionDef.label,
        data = {sectionId = sectionDef.id},
        click = function(element)
            onSelect(sectionDef.id)
        end,
    }
end

local function makeSectionContent(sectionDef, ability, fireChange)
    local content
    content = gui.Panel{
        classes = {"nae-section-content", "inactive"},
        id = "ts_section_" .. sectionDef.id,
        data = {sectionId = sectionDef.id},
    }

    -- Rebuild helper lets change handlers drive conditional fields (e.g.
    -- Prompt Text visibility keyed off the Trigger Mode value). fireChange
    -- is the broader "structural change happened" dispatcher that fires
    -- refreshAbility across the whole root (used by the Effects section
    -- so the bottom-bar paste button and the behaviour list both react).
    local function refresh()
        local builder = SECTION_BUILDERS[sectionDef.id]
        content.children = builder(ability, refresh, fireChange)
    end
    refresh()

    return content
end

-- Helpers for the Effects bottom bar paste button. Mirror the ones in
-- AbilityEditor.GenerateEditor (not exposed there, so we duplicate the
-- 4-line logic rather than couple editors through another public hook).
local function clipboardHasBehavior()
    local item = dmhub.GetInternalClipboard()
    if item == nil then return false end
    local tn = item.typeName or ""
    return string.starts_with(tn, "ActivatedAbility") and string.ends_with(tn, "Behavior")
end

--[[
    ============================================================================
    Trigger Preview card
    ============================================================================
    Mirrors TriggeredAbilityDisplay:Render (DSModifyTriggerDisplay.lua:321) --
    the classic on-sheet trigger card authors recognise -- but derives every
    slot from the TriggeredAbility fields instead of a separate display
    object. Phase 7 will layer per-field overrides on top (Display section's
    override fields fill any slot the author wants to diverge from).

    Visual mapping (TriggeredAbility field -> card slot):
      name              -> title
      resourceNumber    -> title cost in parens (numeric, no resource name --
                            lacks caster context at edit time)
      conditionFormula  -> Trigger row, via GoblinScriptProse.Render
      behaviors[]       -> Effect row, comma-joined type names until the
                            behaviour prose engine (opt-in #5) lands
      flavor, keywords, -> blank placeholders until phase 7 overrides ship
      distance, target,
      card type
]]

local TRIGGER_TYPE_LABELS = {
    trigger = "Triggered Action",
    free = "Free Triggered Action",
    passive = "Passive",
}

local function getTitleBarColor(cardType)
    local T = rawget(_G, "Styles") and Styles.Triggers or nil
    if T == nil then
        return "#aaaa00" -- fallback to the trigger gold
    end
    if cardType == "free" then return T.freeColorAgainstText end
    if cardType == "passive" then return T.passiveColorAgainstText end
    return T.triggerColorAgainstText
end

-- Render the ability's behaviour list as a chained prose sentence using the
-- behaviour prose engine (opt-in #5; see BEHAVIOUR_PROSE.md). Falls back to
-- per-behaviour SummarizeBehavior comma-join if the engine is unavailable.
local function behaviorsFallbackText(ability)
    local GSP = rawget(_G, "GoblinScriptProse")
    if GSP ~= nil and type(GSP.RenderBehaviourList) == "function" then
        local ok, text, isEmpty = pcall(GSP.RenderBehaviourList, ability)
        if ok and not isEmpty then return text end
        if ok and isEmpty then return "" end
    end
    local behaviors = ability:try_get("behaviors")
    if behaviors == nil or #behaviors == 0 then return "" end
    local names = {}
    for _, b in ipairs(behaviors) do
        local label
        local ok, summary = pcall(function() return b:SummarizeBehavior(ability) end)
        if ok and type(summary) == "string" and summary ~= "" then
            label = summary
        else
            local typeId = b:try_get("behavior") or b:try_get("typeName") or "?"
            local typeEntry = ability.TypesById and ability.TypesById[typeId] or nil
            label = (typeEntry and typeEntry.text) or typeId
        end
        names[#names + 1] = label
    end
    return table.concat(names, ", ")
end

-- Trigger row composition. Pulls subject + event template + optional
-- condition prose through GoblinScriptProse.RenderTriggerSentence so the
-- player-facing sentence reads like a real card ("At the start of your
-- turn.", "When any enemy takes damage, if the damage is at least 5.").
-- Falls back to the raw condition formula if the engine is unavailable;
-- returns empty string for abilities with neither a trigger id nor a
-- condition formula so the card leaves the row blank instead of showing
-- a synthesised "When the creature triggers." placeholder.
local function renderTriggerProse(ability)
    local triggerId = ability:try_get("trigger") or ""
    local formula = ability:try_get("conditionFormula") or ""
    if triggerId == "" and formula == "" then return "" end
    local GSP = rawget(_G, "GoblinScriptProse")
    if GSP == nil or GSP.RenderTriggerSentence == nil then
        return formula
    end
    return GSP.RenderTriggerSentence(ability)
end

-- Build a single Trigger Preview card from the current TriggeredAbility
-- state. Called on every refreshPreview event; cheap to rebuild from
-- scratch so we don't bother with diffing children.
-- Empty / nil / whitespace-only strings count as "no override".
local function nonBlank(s)
    if type(s) ~= "string" then return false end
    if s == "" then return false end
    return string.find(s, "%S") ~= nil
end

-- Pick the override when present, otherwise the derived value. Both are
-- treated as opaque strings; nil / blank derived just produces nil so the
-- caller's blank-renderer can show its placeholder.
local function pickOverride(override, derived)
    if nonBlank(override) then return override end
    if derived == nil or derived == "" then return nil end
    return derived
end

local function buildTriggerPreviewCard(ability)
    local COLORS = getColors()
    local CARD_WIDTH = LAYOUT.PREVIEW_WIDTH - 2 * LAYOUT.COL_HPAD - LAYOUT.SCROLL_GUTTER

    -- Card Type: explicit override only (no derivation; the dropdown picks
    -- one of three values, default "trigger" for new abilities).
    local cardType = ability:try_get("displayCardType") or "trigger"
    if TRIGGER_TYPE_LABELS[cardType] == nil then cardType = "trigger" end
    local titleColor = getTitleBarColor(cardType)

    -- Display Name override -> falls back to ability.name. Cost is a
    -- free-text override that renders IN the title bar parens alongside
    -- the name (mirroring the classic TriggeredAbilityDisplay card; see
    -- 2026-04-24 feedback). When displayCost is blank, fall back to the
    -- numeric resourceNumber value as a last-resort derivation.
    local displayName = pickOverride(ability:try_get("displayName"),
                                     ability:try_get("name") or "Triggered Ability")
                        or "Triggered Ability"
    local displayCostText = ability:try_get("displayCost")
    local costInTitle
    if nonBlank(displayCostText) then
        costInTitle = displayCostText
    else
        local costNumber = ability:try_get("resourceNumber")
        if type(costNumber) == "number" and costNumber ~= 0 then
            costInTitle = tostring(costNumber)
        end
    end
    local titleText = costInTitle
        and string.format("%s (%s)", displayName, costInTitle)
        or displayName

    -- Keywords row composition. `displayKeywords` is a set table (keys
    -- are keyword ids, values are truthy) mirroring ActivatedAbility.keywords
    -- shape. Render as comma-joined display names via CanonicalKeyword so
    -- the row reads "Keywords: Melee, Strike" rather than showing raw ids.
    local function renderKeywordList(kw)
        if type(kw) ~= "table" then return nil end
        local parts = {}
        for id, v in pairs(kw) do
            if v then
                local text = (rawget(_G, "ActivatedAbility") and ActivatedAbility.CanonicalKeyword)
                    and ActivatedAbility.CanonicalKeyword(id) or id
                parts[#parts + 1] = text
            end
        end
        if #parts == 0 then return nil end
        table.sort(parts)
        return table.concat(parts, ", ")
    end

    -- Per-row overrides. `pickOverride` returns nil when both override and
    -- derived are blank, which the existing blank-renderers turn into a
    -- grey italic dash / "(no condition)" placeholder.
    local flavorText   = ability:try_get("displayFlavor")
    local keywordsText = renderKeywordList(ability:try_get("displayKeywords"))

    -- Distance derives from the trigger-level subject range: self-subject
    -- reads as "Self"; any other subject with a non-blank subjectRange
    -- reads as "Ranged <value>". displayDistance override beats both.
    local function deriveDistance()
        local subj = ability:try_get("subject") or "self"
        if subj == "self" then return "Self" end
        local sr = ability:try_get("subjectRange")
        if nonBlank(sr) then return "Ranged " .. sr end
        return nil
    end
    local distText = pickOverride(ability:try_get("displayDistance"), deriveDistance())

    -- Target derives from the Setup-section Target Type + companion
    -- fields via DescribeTarget(), which handles all the combinations
    -- (AOE -> "Each enemy" / "Each creature"; target -> "1 creature" /
    -- "N creatures"; self -> "None/self"; emptyspace, etc). Per-behaviour
    -- applyto is not used here: the preview card rolls up the trigger's
    -- overall target, not per-behaviour. displayTarget in the Display
    -- section overrides this derivation.
    local function deriveTarget()
        local ok, phrase = pcall(function() return ability:DescribeTarget() end)
        if ok and nonBlank(phrase) then return phrase end
        return nil
    end
    local targetText = pickOverride(ability:try_get("displayTarget"), deriveTarget())
    local triggerProse = pickOverride(ability:try_get("displayTriggerProse"),
                                      renderTriggerProse(ability))
    local effectText   = pickOverride(ability:try_get("displayEffectProse"),
                                      behaviorsFallbackText(ability))

    local BLANK = "-"

    local function derivedOrBlank(value)
        if value == nil or value == "" then
            return gui.Label{
                text = BLANK,
                color = COLORS.GRAY,
                italics = true,
                fontSize = 13,
                height = "auto",
                width = "auto",
                halign = "left",
            }
        end
        return gui.Label{
            text = value,
            color = COLORS.CREAM_BRIGHT,
            fontSize = 13,
            height = "auto",
            width = "auto",
            halign = "left",
        }
    end

    -- Build a single key+value segment. The value label is width-bounded
    -- and textWrap=true so long values (e.g. a long keywords list) wrap
    -- to a new line INSIDE the segment instead of bleeding into the right
    -- half. `valueMax` is "100%-<keyLabelWidth>" -- tuned per key so the
    -- wider "Keywords:" / "Distance:" keys still leave room for a short
    -- value on the same line.
    local function segment(key, value, valueMax, align)
        local valueLabel
        if value == nil or value == "" then
            valueLabel = gui.Label{
                text = BLANK,
                color = COLORS.GRAY,
                italics = true,
                fontSize = 13,
                height = "auto",
                width = "auto",
                halign = "left",
                valign = "top",
            }
        else
            valueLabel = gui.Label{
                text = value,
                color = COLORS.CREAM_BRIGHT,
                fontSize = 13,
                height = "auto",
                width = valueMax,
                textWrap = true,
                halign = "left",
                valign = "top",
            }
        end
        return gui.Panel{
            width = "50%",
            height = "auto",
            flow = "horizontal",
            halign = align,
            bgcolor = "clear",
            children = {
                gui.Label{
                    text = key,
                    color = COLORS.GOLD_DIM,
                    bold = true,
                    fontSize = 13,
                    height = "auto",
                    width = "auto",
                    rmargin = 4,
                    valign = "top",
                },
                valueLabel,
            },
        }
    end

    -- kvRow composes two segments side by side. hpad = 6 (matched with
    -- borderBox) indents the row to line up with the Display Name in the
    -- title bar + flavour text -- both of which sit at x = content_left + 6
    -- because of their own hpad=6. Without this, Keywords/Distance labels
    -- hugged the card's padding edge and looked misaligned with the title.
    local function kvRow(leftKey, leftValue, rightKey, rightValue)
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            bgcolor = "clear",
            hpad = 6,
            borderBox = true,
            children = {
                segment(leftKey, leftValue, "100%-90", "left"),
                segment(rightKey, rightValue, "100%-60", "left"),
            },
        }
    end

    local function fullRow(key, value, isProse)
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            bgcolor = "clear",
            tmargin = 4,
            hpad = 6,
            borderBox = true,
            children = {
                gui.Label{
                    text = key,
                    color = COLORS.GOLD_DIM,
                    bold = true,
                    fontSize = 13,
                    height = "auto",
                    width = "auto",
                    rmargin = 4,
                    valign = "top",
                },
                (value == nil or value == "") and gui.Label{
                    text = isProse and "(no condition)" or BLANK,
                    color = COLORS.GRAY,
                    italics = true,
                    fontSize = 13,
                    height = "auto",
                    width = CARD_WIDTH - 96,
                    halign = "left",
                    textWrap = true,
                } or gui.Label{
                    text = value,
                    color = COLORS.CREAM_BRIGHT,
                    fontSize = 13,
                    height = "auto",
                    width = CARD_WIDTH - 96,
                    halign = "left",
                    textWrap = true,
                },
            },
        }
    end

    return gui.Panel{
        width = CARD_WIDTH,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        -- bgimage required for bgcolor + borderColor to paint; bgcolor alone
        -- is a no-op in the DMHub GUI runtime.
        bgimage = "panels/square.png",
        bgcolor = COLORS.CARD_BG,
        borderWidth = 2,
        borderColor = COLORS.GOLD_DIM,
        cornerRadius = 4,
        vpad = 10,
        hpad = 12,
        borderBox = true,
        children = {
            gui.Label{
                text = titleText,
                bold = true,
                fontSize = 15,
                color = "white",
                bgimage = "panels/square.png",
                bgcolor = titleColor,
                width = "100%",
                height = "auto",
                hpad = 6,
                vpad = 4,
                borderBox = true,
                textAlignment = "left",
            },
            -- Flavor row -- collapsed (no layout space) when blank. hpad
            -- matches the title label's hpad so the italic text lines up
            -- with where the title text sits inside the yellow bar (per
            -- 2026-04-24 feedback that flavour was offset slightly).
            gui.Label{
                text = flavorText or "",
                italics = true,
                color = COLORS.CREAM_BRIGHT,
                fontSize = 13,
                width = "100%",
                height = "auto",
                hpad = 6,
                tmargin = 4,
                wrap = true,
                borderBox = true,
                collapsed = not nonBlank(flavorText),
            },
            kvRow("Keywords:", keywordsText, "Type:", TRIGGER_TYPE_LABELS[cardType]),
            kvRow("Distance:", distText, "Target:", targetText),
            -- Divider
            gui.Panel{
                width = "100%",
                height = 1,
                bgimage = "panels/square.png",
                bgcolor = COLORS.GOLD,
                tmargin = 6,
                bmargin = 4,
            },
            fullRow("Trigger:", triggerProse, true),
            fullRow("Effect:", effectText, false),
        },
    }
end

--[[
    ============================================================================
    Mechanical View pane (phase 4)
    ============================================================================
    Diagnostic mirror below the Trigger Preview card. Tells the author whether
    the trigger is wired up correctly in a single glance:
      * rollup header ("Trigger ready" / "N issues")
      * six rows (Event / Subject / Triggers When / Behaviours / Mode / When
        Active) with the raw value and an optional status chip when something
        is wrong
      * two-clause Trigger Summary at the bottom ("Triggers when: ... / Then:
        ...") -- the when-clause reuses GoblinScriptProse.RenderTriggerSentence.

    Static structural validation only at launch. Runtime log-hook integration
    (gotcha 10 -- subject mismatch, missing attacker, etc.) is deferred to a
    follow-up pass that parses actual Lua log entries.
]]

local VALID_SUBJECT_IDS = {
    self = true, any = true, selfandheroes = true, otherheroes = true,
    selfandallies = true, allies = true, enemy = true, other = true,
}

-- Subjects that include the caster in their match set. For truly global
-- events (no creature-context dispatched via symbols.subject) the
-- TriggeredAbility.lua:746 resolver rejects any other subject filter, so
-- an author picking e.g. subject=enemy on `beginround` would silently
-- never fire.
local CASTER_INCLUSIVE_SUBJECTS = {
    self = true, any = true, selfandallies = true, selfandheroes = true,
}

-- Triggers that fire without a specific creature context -- the engine
-- dispatches them once globally rather than via DispatchEventOnOthers,
-- so symbols.subject is nil in the ability's evaluation context. For
-- these, only caster-inclusive subjects evaluate sensibly; pick an
-- exclusive subject like `enemy` and the ability never fires. List is
-- conservative -- add here only if verified from runtime dispatch.
local GLOBAL_SUBJECTLESS_TRIGGERS = {
    beginround = true,
    endcombat = true,
    rollinitiative = true,
}

local MODE_LABELS = {
    [false]                           = "prompt the player",
    [true]                            = "occurs automatically",
    ["local"]                         = "occurs automatically (local only)",
    ["prompt_remote"]                 = "prompt remote player, auto for local",
    ["game:heroicresourcetriggers"]   = "automatic heroic resource setting",
}

local WHEN_ACTIVE_LABELS = {
    always = "always active",
    combat = "only during combat",
}

-- Check whether the trigger event id is registered. Uses GetTriggerById
-- because it walks the full TriggeredAbility.triggers table (populated by
-- both inline definitions in TriggeredAbility.lua and RegisterTrigger
-- calls in MCDMRules.lua / elsewhere).
local function isValidTriggerId(id)
    if id == nil or id == "" then return false end
    return TriggeredAbility.GetTriggerById(id) ~= nil
end

-- Compile the condition formula. Returns (ok, errorMessage). Empty formula
-- is considered valid -- the condition is optional, many triggers omit it.
local function compileCondition(formula)
    if formula == nil or formula == "" then return true, nil end
    local out = {}
    local ok = pcall(function()
        dmhub.CompileGoblinScriptDeterministic(formula, out)
    end)
    if not ok then return false, "compile error" end
    if out.error then return false, tostring(out.error) end
    return true, nil
end

-- Normalise a symbol name for matching against allowed-reference sets:
-- lowercase + strip spaces. The runtime injects symbols under this form
-- (Creature.lua:1999 sets `symbols.damagetype` for a "Damage Type" symbol)
-- and creature.helpSymbols keys follow the same convention.
local function normaliseSymbolReference(name)
    if name == nil then return "" end
    return string.lower((string.gsub(tostring(name), "%s+", "")))
end

-- Build the allowed top-level reference set for a trigger event:
--   * Ambient (Subject / Self / Caster) -- always present.
--   * Event-payload symbols declared on the trigger (keyed map AND bare
--     array forms; see discoverTestInputs comment for why both exist).
--   * Bare creature properties accessible without a `Self.` prefix
--     (resolved against the receiver token's properties at evaluation).
-- A reference not in this set is almost certainly a typo or a leftover
-- from copying a formula off a different trigger event.
local function buildAllowedReferences(triggerId)
    local allowed = { subject = true, self = true, caster = true }
    local trigger = TriggeredAbility.GetTriggerById(triggerId)
    if trigger ~= nil and type(trigger.symbols) == "table" then
        for k, def in pairs(trigger.symbols) do
            if type(def) == "table" then
                if type(k) == "string" then
                    allowed[normaliseSymbolReference(k)] = true
                end
                if def.name ~= nil then
                    allowed[normaliseSymbolReference(def.name)] = true
                end
            end
        end
    end
    if creature ~= nil and type(creature.helpSymbols) == "table" then
        for k, def in pairs(creature.helpSymbols) do
            if type(k) == "string" and not k:find("^__") then
                allowed[normaliseSymbolReference(k)] = true
                if type(def) == "table" and def.name ~= nil then
                    allowed[normaliseSymbolReference(def.name)] = true
                end
            end
        end
    end
    return allowed
end

-- Return the list of references in `formula` that are not in `allowed`.
-- Used by the Mech View's Triggers When row to flag typos / unrecognised
-- symbols ("Trigger ready" lying when the formula references something
-- the trigger event never exposes).
local function unknownReferences(formula, allowed)
    if formula == nil or formula == "" then return {} end
    local list = GoblinScriptProse.ListReferencedSymbols(formula)
    local unknown = {}
    for _, name in ipairs(list) do
        if allowed[normaliseSymbolReference(name)] == nil then
            unknown[#unknown + 1] = name
        end
    end
    return unknown
end

-- Canonical-table lookup for unknown-literal validation.
-- Each entry: {labelSingular, lookup(literal) -> bool found, source}
-- `lookup` does case-insensitive name matching against the canonical table.
-- Damage types use lowercase comparison since the runtime injects the
-- lowercase form (Resource.lua mirrors this for resources). The other
-- categories normalise to lowercase before comparison so author casing
-- doesn't false-positive ("Grabbed" matches "grabbed" in the table).
local LITERAL_VALIDATORS = {
    characterOngoingEffects = {
        label = "ongoing effect",
        lookup = function(literal)
            local needle = string.lower(literal or "")
            local t = dmhub.GetTable("characterOngoingEffects") or {}
            for _, e in pairs(t) do
                if not e:try_get("hidden") and e.name and string.lower(e.name) == needle then
                    return true
                end
            end
            return false
        end,
    },
    charConditions = {
        label = "condition",
        lookup = function(literal)
            local needle = string.lower(literal or "")
            local t = dmhub.GetTable("charConditions") or {}
            for _, c in pairs(t) do
                if not c:try_get("hidden") and c.name and string.lower(c.name) == needle then
                    return true
                end
            end
            return false
        end,
    },
    damageTypes = {
        label = "damage type",
        lookup = function(literal)
            local needle = string.lower(literal or "")
            local t = dmhub.GetTable(DamageType.tableName) or {}
            for _, v in pairs(t) do
                if not v:try_get("hidden") and v.name and string.lower(v.name) == needle then
                    return true
                end
            end
            return false
        end,
    },
    characterResources = {
        label = "resource",
        lookup = function(literal)
            local needle = string.lower(literal or "")
            local t = dmhub.GetTable("characterResources") or {}
            for _, r in pairs(t) do
                if r.name and string.lower(r.name) == needle then return true end
            end
            return false
        end,
    },
}

-- Resolve a `hasEq` / `isEq` LHS atom to a canonical-table source id.
-- Returns the source key ("characterOngoingEffects", "charConditions",
-- "damageTypes", "characterResources") or nil if the LHS isn't a known
-- canonical-set field.
--
-- Two dispatch paths:
--   1. Dotted-tail or bare ident matching a canonical-set creature
--      property (Ongoing Effects, Conditions). Match by the last
--      identifier component, normalised.
--   2. Top-level ident matching a trigger.symbols entry that carries
--      `valueOptionsSource` (post-C3). Match by the symbol name.
local SET_TAIL_TO_SOURCE = {
    ongoingeffects = "characterOngoingEffects",
    conditions = "charConditions",
}

local function resolveLiteralSource(lhs, triggerId, op)
    if lhs == nil then return nil end
    if lhs.kind ~= "ident" and lhs.kind ~= "dotted" then return nil end

    local parts = lhs.parts or { lhs.name }
    -- Dotted-tail OR bare set field (Ongoing Effects, Conditions): only
    -- meaningful for the `has` operator (set membership).
    if op == "has" then
        local tail = parts[#parts]
        if tail then
            local key = normaliseSymbolReference(tail)
            local source = SET_TAIL_TO_SOURCE[key]
            if source then return source end
        end
    end

    -- Top-level trigger.symbols match: only the bare-ident case (dotted
    -- LHS like Subject.DamageType doesn't apply here; `Damage Type` lives
    -- as a top-level event payload symbol). Look up valueOptionsSource on
    -- the symbol declaration.
    if (op == "is" or op == "=" or op == "!=") and #parts == 1 then
        local trigger = TriggeredAbility.GetTriggerById(triggerId)
        if trigger == nil or type(trigger.symbols) ~= "table" then return nil end
        local target = normaliseSymbolReference(parts[1])
        for k, def in pairs(trigger.symbols) do
            if type(def) == "table" then
                local nameKey = def.name and normaliseSymbolReference(def.name) or nil
                local declKey = type(k) == "string" and normaliseSymbolReference(k) or nil
                if (nameKey == target or declKey == target) and def.valueOptionsSource then
                    return def.valueOptionsSource
                end
            end
        end
    end

    return nil
end

-- Walks `formula` for hasEq / isEq leaves whose string-literal RHS isn't
-- present in the canonical table for that LHS. Returns a list of
-- `{label, literal}` entries -- e.g. `{label = "ongoing effect", literal = "Invasable"}`.
-- Mech View renders the first entry as a gold "Unknown <label>: <literal>"
-- chip alongside the existing red "Unknown: <ident>" chip system.
local function unknownLiterals(formula, triggerId)
    if formula == nil or formula == "" then return {} end
    local results = {}
    GoblinScriptProse.WalkLiteralComparisons(formula, function(info)
        local sourceKey = resolveLiteralSource(info.lhs, triggerId, info.op)
        if sourceKey == nil then return end
        local validator = LITERAL_VALIDATORS[sourceKey]
        if validator == nil then return end
        if not validator.lookup(info.rhs) then
            results[#results + 1] = { label = validator.label, literal = info.rhs }
        end
    end)
    return results
end

-- Collapse the behaviour list using the behaviour prose engine (opt-in #5;
-- BEHAVIOUR_PROSE.md). Falls back to per-behaviour SummarizeBehavior +
-- type-label comma join if the engine is unavailable. Returns (text, isEmpty).
local function summariseBehaviours(ability)
    local GSP = rawget(_G, "GoblinScriptProse")
    if GSP ~= nil and type(GSP.RenderBehaviourList) == "function" then
        local ok, text, isEmpty = pcall(GSP.RenderBehaviourList, ability)
        if ok then return text, isEmpty end
    end
    local behaviors = ability:try_get("behaviors")
    if behaviors == nil or #behaviors == 0 then return "", true end
    local parts = {}
    for _, b in ipairs(behaviors) do
        local label
        local ok, summary = pcall(function() return b:SummarizeBehavior(ability) end)
        if ok and type(summary) == "string" and summary ~= "" then
            label = summary
        else
            local typeId = b:try_get("behavior") or b:try_get("typeName") or "?"
            local typeEntry = ability.TypesById and ability.TypesById[typeId] or nil
            label = (typeEntry and typeEntry.text) or typeId
        end
        parts[#parts + 1] = label
    end
    return table.concat(parts, ", "), false
end

-- Render the "Then" clause of the Trigger Summary. The prose engine
-- (opt-in #5) returns full per-behaviour phrases chained with the
-- worksheet's ", then " convention.
local function renderThenClause(ability)
    local text, isEmpty = summariseBehaviours(ability)
    if isEmpty then return "(no behaviours)" end
    return text
end

-- Builds the Mechanical View card body and returns (card, rollupInfo).
-- The caller lifts rollupInfo (text + color) into the pane sub-heading so
-- the chip reads as part of the "How This Triggers" label row instead of
-- taking its own row inside the card.
local function buildMechanicalView(ability)
    local COLORS = getColors()
    local CARD_WIDTH = LAYOUT.PREVIEW_WIDTH - 2 * LAYOUT.COL_HPAD - LAYOUT.SCROLL_GUTTER

    -- Gather row values + validation status in one pass so the rollup chip
    -- can report the total issue count without a second walk.
    local rows = {}
    local issueCount = 0

    -- Chip can be either:
    --   nil                      -- no issue
    --   string                   -- legacy red/amber chip ("Unknown: foo")
    --   { text, color }          -- explicit color (gold for unknown literals)
    local function addRow(label, value, chipText)
        local hasIssue = chipText ~= nil
        if hasIssue then issueCount = issueCount + 1 end
        rows[#rows + 1] = {
            label = label,
            value = value,
            chip = chipText,
            hasIssue = hasIssue,
        }
    end

    -- Event
    local triggerId = ability:try_get("trigger") or ""
    addRow("Event", triggerId ~= "" and triggerId or "(unset)",
        triggerId == "" and "Missing" or (not isValidTriggerId(triggerId) and "Unregistered" or nil))

    -- Subject. Two failure modes surfaced as chips:
    --   * Unknown subject id (data corruption / schema change)
    --   * Compatibility: trigger fires globally (no creature context) and
    --     author picked a subject that excludes the caster. At runtime
    --     this silently never fires -- the resolver at
    --     TriggeredAbility.lua:746 rejects. Warn at author time.
    local subjectId = ability:try_get("subject") or "self"
    local subjectChip
    if not VALID_SUBJECT_IDS[subjectId] then
        subjectChip = "Unknown"
    elseif GLOBAL_SUBJECTLESS_TRIGGERS[triggerId] and not CASTER_INCLUSIVE_SUBJECTS[subjectId] then
        subjectChip = "Never fires"
    end
    addRow("Subject", subjectId, subjectChip)

    -- Triggers When (condition). Two failure modes:
    --   * Compile error -- formula is malformed.
    --   * Undeclared symbol -- formula references a name that is not an
    --     ambient role, an event-payload symbol on this trigger, or a
    --     creature property. GoblinScript compiles unknown identifiers
    --     leniently (returns nil/0 at evaluation), so the runtime would
    --     silently never match. Author probably typed a symbol that
    --     belongs to a different trigger event.
    local condition = ability:try_get("conditionFormula") or ""
    local condOk, condErr = compileCondition(condition)
    local condChip
    if not condOk then
        condChip = "Error: " .. (condErr or "compile failed")
    else
        local unknown = unknownReferences(condition, buildAllowedReferences(triggerId))
        if #unknown > 0 then
            condChip = "Unknown: " .. unknown[1]
        else
            -- Edit-time canonical-table validation. Catches typos in string
            -- literals on hasEq / isEq leaves where the LHS is a known
            -- canonical-set field (Ongoing Effects, Conditions, Damage
            -- Type, Resource). Chip uses a gold warning color to
            -- distinguish from the red "Unknown: <ident>" chip; the latter
            -- represents a structural problem (formula references a
            -- symbol that doesn't exist on this trigger), the former a
            -- typo-class issue (literal won't match anything at runtime).
            local literals = unknownLiterals(condition, triggerId)
            if #literals > 0 then
                local first = literals[1]
                local extra = #literals > 1 and string.format(" +%d more", #literals - 1) or ""
                condChip = {
                    text = string.format('Unknown %s: "%s"%s', first.label, first.literal, extra),
                    color = "#cca350",
                }
            end
        end
    end
    addRow("Triggers When", condition ~= "" and condition or "(none)", condChip)

    -- Behaviours
    local behText, behEmpty = summariseBehaviours(ability)
    local silent = ability:try_get("silent")
    addRow("Behaviours", behEmpty and "(empty)" or behText,
        (behEmpty and not silent) and "Empty" or nil)

    -- Mode
    local modeId = ability:try_get("mandatory")
    if modeId == nil then modeId = false end
    addRow("Mode", MODE_LABELS[modeId] or tostring(modeId),
        MODE_LABELS[modeId] == nil and "Unknown" or nil)

    -- When Active
    local whenActive = ability:try_get("whenActive") or "always"
    addRow("When Active", WHEN_ACTIVE_LABELS[whenActive] or whenActive,
        WHEN_ACTIVE_LABELS[whenActive] == nil and "Unknown" or nil)

    -- Rollup chip text and colour.
    local rollupText = (issueCount == 0) and "Trigger ready"
        or string.format("%d issue%s", issueCount, issueCount == 1 and "" or "s")
    local rollupColor = (issueCount == 0) and "#5e8c4a" or "#c47e2c"

    -- Trigger Summary (when / then clauses). When-clause goes through the
    -- prose engine's RenderTriggerSentence so we get the same composition
    -- as the card's Trigger row. Then-clause uses the behaviour-summary
    -- fallback until opt-in #5 ships.
    local GSP = rawget(_G, "GoblinScriptProse")
    local whenClause = ""
    if GSP ~= nil and GSP.RenderTriggerSentence then
        local ok, sentence = pcall(GSP.RenderTriggerSentence, ability)
        if ok and sentence ~= nil then whenClause = sentence end
    end
    local thenClause = renderThenClause(ability)

    -- Row renderer. Label left-aligned in a fixed-width column so values
    -- line up across rows; chip pinned to the right.
    -- Chip can be a string (legacy, defaults to amber "issue" color) or
    -- {text, color} (explicit color). Gold (#cca350) is used for typo-class
    -- warnings (unknown literals); amber (#c47e2c) for structural errors
    -- (compile failures, unknown identifiers, never-fires subjects).
    local function buildRow(entry)
        local chipText, chipColor
        if type(entry.chip) == "string" then
            chipText = entry.chip
            chipColor = "#c47e2c"
        elseif type(entry.chip) == "table" then
            chipText = entry.chip.text
            chipColor = entry.chip.color or "#c47e2c"
        end
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            bgcolor = "clear",
            vpad = 3,
            borderBox = true,
            children = {
                gui.Label{
                    text = entry.label,
                    color = COLORS.GOLD_DIM,
                    bold = true,
                    fontSize = 13,
                    width = 110,
                    height = "auto",
                    halign = "left",
                },
                gui.Label{
                    text = entry.value,
                    color = entry.hasIssue and COLORS.GRAY or COLORS.CREAM_BRIGHT,
                    fontSize = 13,
                    width = CARD_WIDTH - 110 - (chipText and 140 or 0),
                    height = "auto",
                    halign = "left",
                    textWrap = true,
                },
                -- Chip is width-bounded with textWrap so longer text
                -- ("Unknown: <symbol>", "Error: <reason>") wraps to a
                -- second line inside the card rather than overflowing
                -- the right border.
                chipText ~= nil and gui.Label{
                    text = chipText,
                    color = "white",
                    fontSize = 11,
                    bold = true,
                    bgimage = "panels/square.png",
                    bgcolor = chipColor,
                    width = 130,
                    height = "auto",
                    hpad = 6,
                    vpad = 2,
                    halign = "right",
                    textWrap = true,
                    borderBox = true,
                } or nil,
            },
        }
    end

    local rowPanels = {}
    for _, r in ipairs(rows) do
        rowPanels[#rowPanels + 1] = buildRow(r)
    end

    local card = gui.Panel{
        width = CARD_WIDTH,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        -- bgimage required for bgcolor + borderColor to paint; bgcolor alone
        -- is a no-op in the DMHub GUI runtime.
        bgimage = "panels/square.png",
        bgcolor = COLORS.CARD_BG,
        borderWidth = 2,
        borderColor = COLORS.GOLD_DIM,
        cornerRadius = 4,
        vpad = 10,
        hpad = 12,
        borderBox = true,
        children = {
            -- Rows
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                halign = "left",
                bgcolor = "clear",
                children = rowPanels,
            },
            -- Divider
            gui.Panel{
                width = "100%",
                height = 1,
                bgimage = "panels/square.png",
                bgcolor = COLORS.GOLD,
                tmargin = 8,
                bmargin = 8,
            },
            -- Trigger Summary. Markdown is enabled so the "Triggers when:"
            -- and "Then:" leads render bold (Unity rich-text <b> tags) while
            -- the rest of the clause stays regular weight.
            gui.Label{
                text = "<b>Triggers when:</b> " .. (whenClause ~= "" and whenClause or "(no trigger set)"),
                markdown = true,
                color = COLORS.CREAM_BRIGHT,
                fontSize = 13,
                italics = true,
                width = "100%",
                height = "auto",
                wrap = true,
                halign = "left",
                bmargin = 4,
            },
            gui.Label{
                text = "<b>Then:</b> " .. thenClause,
                markdown = true,
                color = COLORS.CREAM_BRIGHT,
                fontSize = 13,
                italics = true,
                width = "100%",
                height = "auto",
                wrap = true,
                halign = "left",
            },
        },
    }

    return card, { text = rollupText, color = rollupColor }
end

--[[
    ============================================================================
    Test Trigger card (Phase 6)
    ============================================================================
    Compiles + evaluates the condition formula against author-supplied inputs
    using existing GoblinScript eval. No new eval infrastructure -- reuses
    dmhub.CompileGoblinScriptDeterministic + ExecuteGoblinScript with
    casterToken.properties:LookupSymbol(symbols) the same way
    TriggeredAbility.lua:864 does at runtime.

    Two states:
      * Collapsed strip (default) -- 32px row matching the other panes' sub-
        heading style: "Test Trigger" label + last-run chip + "Run Test" button.
      * Expanded card -- gold-bordered card with role slots from real scene
        tokens, per-symbol input widgets keyed off trigger.symbols, result
        block (with sub-clause attribution on AND-fail), and behaviour preview.

    No scenario persistence -- last-run state is closure-local, lost on editor
    close (per design rev 3 / open question 2).
]]

-- Subject filter applied to scene-token dropdowns in role slots. Mirrors the
-- runtime resolver's allegiance checks at TriggeredAbility.lua:814-851.
local function tokenMatchesSubjectFilter(subjectToken, casterToken, subjectId)
    if subjectToken == nil then return false end
    -- Subjects ending in "...notself" semantics (allies / otherheroes /
    -- other) must exclude the caster itself, otherwise the auto-pick on
    -- the test panel hands back the caster (since IsFriend(self,self) is
    -- true) and the user sees "Subject = caster" for an "any ally" filter.
    local isCaster = casterToken ~= nil and subjectToken.id == casterToken.id
    if subjectId == "self" then
        return isCaster
    elseif subjectId == "any" then
        return true
    elseif subjectId == "other" then
        return not isCaster
    elseif subjectId == "selfandallies" then
        if casterToken == nil then return true end
        return casterToken:IsFriend(subjectToken)
    elseif subjectId == "allies" then
        if casterToken == nil then return not isCaster end
        return (not isCaster) and casterToken:IsFriend(subjectToken)
    elseif subjectId == "enemy" then
        if casterToken == nil then return not isCaster end
        return (not isCaster) and (not casterToken:IsFriend(subjectToken))
    elseif subjectId == "selfandheroes" then
        local props = subjectToken.properties
        return props ~= nil and props.IsHero ~= nil and props:IsHero()
    elseif subjectId == "otherheroes" then
        local props = subjectToken.properties
        return (not isCaster) and props ~= nil and props.IsHero ~= nil and props:IsHero()
    end
    return true
end

-- Preferred-list detection. Returns true if `token` has a triggered ability
-- defined on its modifier chain that matches `ability`.
--
-- Walks the UNFILTERED modifier set (FillBaseActiveModifiers +
-- FillTemporalActiveModifiers + FillModifiersFromModifiers) -- bypassing
-- FilterModifiers which would gate out conditional grants. A monster with
-- a triggered ability whose filterCondition is currently false (e.g. See
-- Through with `Ongoing Effects has "Invisible"`) is still an "owner" of
-- the ability for caster-default purposes -- the ability lives on this
-- creature, the runtime just hasn't activated the modifier yet.
-- GetActiveModifiers / GetTriggeredAbilities both run the filter step and
-- would miss conditional grants entirely.
--
-- Three matching layers because the editor's `ability` instance is not
-- always the same Lua table as the live runtime instance:
--   1. Identity     -- editor opened the live modifier directly.
--   2. Guid         -- both sides carry a stable guid (use try_get since
--                      it's not a declared field).
--   3. Name+trigger -- last-resort content match for compendium-driven
--                      edits that fork the ability out of the modifier.
--                      Collisions on a single creature are vanishingly
--                      rare (two distinct triggered abilities sharing
--                      BOTH name and trigger event).
local function tokenHasTriggeredAbility(token, ability)
    if token == nil or token.properties == nil or ability == nil then return false end
    local props = token.properties
    local entries = {}
    pcall(function() props:FillBaseActiveModifiers(entries) end)
    pcall(function() props:FillTemporalActiveModifiers(entries) end)
    pcall(function() props:FillModifiersFromModifiers(entries) end)
    local agid = ability:try_get("guid")
    local aname = ability:try_get("name")
    local atrig = ability:try_get("trigger")
    for _, entry in ipairs(entries) do
        local m = entry and entry.mod
        if m ~= nil and m.has_key ~= nil and m:has_key("triggeredAbility") then
            local a = m.triggeredAbility
            if a == ability then return true end
            if agid ~= nil then
                local bgid = a:try_get("guid")
                if bgid ~= nil and bgid == agid then return true end
            end
            if aname ~= nil and atrig ~= nil
                    and a:try_get("name") == aname
                    and a:try_get("trigger") == atrig then
                return true
            end
        end
    end
    return false
end

-- Categorise scene tokens into preferred (have this triggered ability) and
-- secondary (everyone else), filtered by the subject id constraint when
-- supplied. Caster filter applies the subject filter relative to the
-- chosen caster token. Returns two arrays of tokens.
local function categoriseSceneTokens(ability, casterToken, subjectId)
    local preferred, secondary = {}, {}
    local tokens = dmhub.allTokens or {}
    for _, tok in ipairs(tokens) do
        local matches = (subjectId == nil) or tokenMatchesSubjectFilter(tok, casterToken, subjectId)
        if matches then
            if tokenHasTriggeredAbility(tok, ability) then
                preferred[#preferred + 1] = tok
            else
                secondary[#secondary + 1] = tok
            end
        end
    end
    return preferred, secondary
end

-- Resolve the human-readable display name for a token. For minions
-- (squad members), the per-token name is typically blank or a generic
-- placeholder; the squad name (e.g. "Goblin Squad 1") is what users
-- recognise -- mirrors how minions are named everywhere else in DS
-- (initiative queue, action bar, chat). Falls back to tok.name for
-- non-minions and pcall-wraps the MinionSquad() lookup since not every
-- token type guarantees the method.
local function tokenDisplayName(tok)
    if tok == nil then return "" end
    local props = tok.properties
    if props ~= nil and type(props.MinionSquad) == "function" then
        local ok, squad = pcall(props.MinionSquad, props)
        if ok and type(squad) == "string" and squad ~= "" then
            return squad
        end
    end
    return tok.name or ""
end

-- Build a modal picker that lists tokens with their portrait next to the
-- name. Preferred group appears first (tokens that already have this
-- triggered ability), followed by a divider and the secondary group.
-- onSelect is invoked with the chosen token's id and the modal closes.
local function openTokenPicker(title, preferred, secondary, currentId, onSelect)
    local COLORS = getColors()

    -- Matches _makeTriggerCard in the Trigger Event picker: PANEL_BG fill,
    -- gold border, press-handler (not click), cornerRadius 3. Selected row
    -- gets a brighter border so the current choice is obvious.
    local function buildTokenRow(tok)
        local selected = tok.id == currentId
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            bgimage = "panels/square.png",
            bgcolor = COLORS.PANEL_BG,
            borderWidth = 1,
            borderColor = selected and COLORS.GOLD_BRIGHT or COLORS.GOLD,
            cornerRadius = 3,
            hpad = 10,
            vpad = 6,
            bmargin = 4,
            borderBox = true,
            press = function()
                gui.CloseModal()
                onSelect(tok.id)
            end,
            children = {
                gui.CreateTokenImage(tok, {
                    width = 42,
                    height = 42,
                    halign = "left",
                    valign = "center",
                }),
                gui.Label{
                    text = tokenDisplayName(tok),
                    color = COLORS.CREAM_BRIGHT,
                    fontSize = 16,
                    bold = selected,
                    width = "100%-54",
                    height = "auto",
                    halign = "left",
                    valign = "center",
                    lmargin = 12,
                    textWrap = true,
                },
            },
        }
    end

    local function buildGroupHeader(text)
        return gui.Label{
            text = text,
            color = COLORS.GOLD_DIM,
            bold = true,
            fontSize = 14,
            width = "100%",
            height = "auto",
            halign = "left",
            tmargin = 8,
            bmargin = 4,
        }
    end

    local rows = {}
    if #preferred > 0 then
        rows[#rows + 1] = buildGroupHeader("Tokens with this ability")
        for _, tok in ipairs(preferred) do rows[#rows + 1] = buildTokenRow(tok) end
    end
    if #secondary > 0 then
        rows[#rows + 1] = buildGroupHeader(#preferred > 0 and "Other tokens on this map" or "Tokens on this map")
        for _, tok in ipairs(secondary) do rows[#rows + 1] = buildTokenRow(tok) end
    end
    if #rows == 0 then
        rows[#rows + 1] = gui.Label{
            text = "No tokens on this map.",
            color = COLORS.GRAY,
            italics = true,
            fontSize = 14,
            width = "100%",
            height = "auto",
            halign = "left",
        }
    end

    local dialogPanel = gui.Panel{
        classes = {"framedPanel"},
        styles = {Styles.Default, Styles.Panel},
        width = 480,
        height = 560,
        flow = "vertical",
        pad = 16,
        borderBox = true,
        halign = "center",
        valign = "center",
        fontFace = "Berling",
        children = {
            gui.Label{
                text = title,
                fontSize = 20,
                bold = true,
                color = COLORS.GOLD_BRIGHT,
                width = "auto",
                height = "auto",
                halign = "left",
                bmargin = 8,
            },
            gui.Panel{
                width = "100%",
                height = "100%-40",
                vscroll = true,
                bgcolor = "clear",
                halign = "left",
                valign = "top",
                -- Inner auto-height wrapper so rows stack tightly at the
                -- top of the viewport rather than distributing across the
                -- scroll area. Mirrors the New Ability dialog's content
                -- panel pattern (AbilityEditorTemplates.lua:1436-1453).
                children = {
                    gui.Panel{
                        width = "100%",
                        height = "auto",
                        flow = "vertical",
                        bgcolor = "clear",
                        halign = "left",
                        valign = "top",
                        children = rows,
                    },
                },
            },
            gui.CloseButton{
                halign = "right",
                valign = "top",
                floating = true,
                escapeActivates = true,
                escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                click = function() gui.CloseModal() end,
            },
        },
    }

    gui.ShowModal(dialogPanel)
end

-- Picker button showing the current token's portrait + name, opens the
-- modal picker on click. Replaces the dropdown as the primary role-slot
-- control so authors can tell tokens apart visually (two goblins with
-- the same name become distinguishable by portrait).
local function buildTokenPickerButton(ability, casterToken, subjectFilter, currentId, onSelect, pickerTitle)
    local COLORS = getColors()
    local preferred, secondary = categoriseSceneTokens(ability, casterToken, subjectFilter)

    if #preferred == 0 and #secondary == 0 then
        return gui.Label{
            text = subjectFilter
                and ("No tokens on this map match the " .. subjectFilter .. " filter.")
                or "No tokens on this map.",
            color = COLORS.GRAY,
            italics = true,
            fontSize = 12,
            width = "100%-100",
            height = "auto",
            halign = "left",
            textWrap = true,
        }
    end

    -- Resolve the current token from the combined list; fall back to the
    -- first preferred (or secondary) token if the stored id isn't in scope.
    local function findToken(id)
        for _, t in ipairs(preferred) do if t.id == id then return t end end
        for _, t in ipairs(secondary) do if t.id == id then return t end end
        return nil
    end
    local tok = findToken(currentId)
    if tok == nil then
        tok = preferred[1] or secondary[1]
        if tok ~= nil then onSelect(tok.id) end
    end

    return gui.Panel{
        width = "100%-100",
        height = 36,
        flow = "horizontal",
        halign = "left",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = COLORS.PANEL_BG,
        borderWidth = 1,
        borderColor = COLORS.GOLD,
        cornerRadius = 2,
        hpad = 6,
        vpad = 2,
        borderBox = true,
        hover = function(element) element.borderColor = COLORS.GOLD_BRIGHT end,
        dehover = function(element) element.borderColor = COLORS.GOLD end,
        click = function()
            openTokenPicker(pickerTitle or "Choose Token",
                preferred, secondary, currentId, onSelect)
        end,
        children = {
            tok and gui.CreateTokenImage(tok, {
                width = 28, height = 28,
                halign = "left", valign = "center",
            }) or gui.Panel{ width = 28, height = 28, bgcolor = "clear" },
            gui.Label{
                text = tok and tokenDisplayName(tok) or "(choose a token)",
                color = tok and COLORS.CREAM_BRIGHT or COLORS.GRAY,
                fontSize = 13,
                width = "100%-40",
                height = "auto",
                halign = "left",
                valign = "center",
                lmargin = 8,
                textWrap = false,
            },
        },
    }
end

-- Discover which role slots and per-symbol inputs the current trigger
-- requires. Returns { roleSlots = {...}, symbolInputs = {...} } where:
--   roleSlot  = { id, name, isSubject, defaultSubjectFilter }
--   symbolInp = { id, name, kind = "number"|"text"|"boolean"|"set"|"unsupported", desc, displayType }
-- The Subject slot is included only when ability.subject ~= "self" since
-- self triggers always resolve subject = caster automatically.
local function discoverTestInputs(ability)
    local roleSlots = {}
    local symbolInputs = {}
    local trigger = TriggeredAbility.GetTriggerById(ability:try_get("trigger") or "")
    local subjectId = ability:try_get("subject") or "self"

    -- Always include the Subject role slot when subject is non-self -- the
    -- behaviour list will need a concrete subject token to make sense.
    if subjectId ~= "self" then
        roleSlots[#roleSlots + 1] = {
            id = "subject",
            name = "Subject",
            isSubject = true,
            defaultSubjectFilter = subjectId,
        }
    end

    if trigger == nil or trigger.symbols == nil then
        return { roleSlots = roleSlots, symbolInputs = symbolInputs }
    end

    -- Only surface symbols the condition actually references, so the panel
    -- doesn't drown the user in inputs they don't care about. Always include
    -- all creature-typed symbols though, since they may be needed by the
    -- behaviour list even when the condition doesn't reference them.
    local condition = ability:try_get("conditionFormula") or ""
    local _, refSet = GoblinScriptProse.ListReferencedSymbols(condition)

    -- Trigger symbol declarations come in two forms:
    --   keyed map:    `damagetype = { name = "Damage Type", type = "text" }`
    --   bare array:   `{ name = "Damage Type", type = "text" }`
    -- The runtime injects values under a normalised key (lowercase, no
    -- spaces) e.g. `symbols.damagetype = damageType` (Creature.lua:1999).
    -- For keyed maps the key already matches; for bare arrays we must
    -- derive the normalised key from .name so our scenario.symbolValues
    -- write lands at the same slot GoblinScript looks up.
    local function evalKey(rawKey, def)
        if type(rawKey) == "string" then return rawKey end
        local nm = (def and def.name) or ""
        return string.lower((string.gsub(nm, "%s+", "")))
    end

    for symKey, symDef in pairs(trigger.symbols) do
        if type(symDef) == "table" then
            local symName = symDef.name or tostring(symKey)
            local symType = symDef.type or "text"
            local id = evalKey(symKey, symDef)
            local referenced = refSet[string.lower(id)] ~= nil
                or refSet[string.lower(symName)] ~= nil

            if symType == "creature" then
                -- Only surface a role slot when the condition formula
                -- actually references it. The trigger event declares
                -- many creature symbols (Attacker, Pusher, Target, ...)
                -- but most conditions touch zero or one of them; showing
                -- the whole set adds noise the author has to mentally
                -- filter. Subject is the always-required exception and is
                -- added unconditionally above.
                if referenced then
                    roleSlots[#roleSlots + 1] = {
                        id = id,
                        name = symName,
                        isSubject = false,
                        desc = symDef.desc,
                    }
                end
            elseif referenced then
                local kind = "text"
                if symType == "number" then kind = "number"
                elseif symType == "boolean" then kind = "boolean"
                elseif symType == "set" then kind = "set"
                elseif symType == "creaturelist" or symType == "path" or symType == "loc" then
                    kind = "unsupported"
                end
                symbolInputs[#symbolInputs + 1] = {
                    id = id,
                    name = symName,
                    kind = kind,
                    desc = symDef.desc,
                    displayType = symType,
                    valueOptionsSource = symDef.valueOptionsSource,
                }
            end
        end
    end

    -- Stable order for symbol inputs (pairs() iteration is undefined in Lua).
    table.sort(symbolInputs, function(a, b) return a.name < b.name end)
    table.sort(roleSlots, function(a, b)
        if a.isSubject ~= b.isSubject then return a.isSubject end
        return a.name < b.name
    end)

    return { roleSlots = roleSlots, symbolInputs = symbolInputs }
end

-- Bounded-value option builders for symbols carrying a `valueOptionsSource`.
-- Each builder returns a list of `{id, text}` records suitable for gui.Dropdown.
-- The `id` field MUST equal what the runtime injects into the symbol context for
-- that trigger event (so authoring formulas like `Damage Type is "fire"` match
-- when a user picks "fire" from the dropdown). Identity per category was
-- verified during C3 implementation:
--   damageTypes              -> lowercase damage type name (e.g. "fire") --
--                               matches YAML convention.
--   charConditions           -> conditionInfo.name (PascalCase, e.g. "Grabbed")
--                               -- see MCDMCreature.lua:3114.
--   characterResources       -> string.lower(resourceInfo.name) -- see
--                               Resource.lua:624.
-- Patterns follow the existing inline builders at:
--   damageTypes              -> CharacterSheet.lua:2090
--   charConditions           -> Condition.lua:79 (FillDropdownOptions; we
--                               REJECT its GUID-as-id format because GoblinScript
--                               compares against the name, not the GUID)
--   characterResources       -> ActivatedAbilityEditor.lua:76 (we drop the
--                               "None" sentinel since the test panel uses a
--                               blank value for "unspecified")
local TEST_OPTION_BUILDERS = {
    damageTypes = function()
        local options = {}
        local t = dmhub.GetTable(DamageType.tableName) or {}
        for _, v in unhidden_pairs(t) do
            local name = string.lower(v.name)
            options[#options + 1] = { id = name, text = name }
        end
        table.sort(options, function(a, b) return a.text < b.text end)
        return options
    end,
    charConditions = function()
        local options = {}
        local t = dmhub.GetTable("charConditions") or {}
        for _, c in unhidden_pairs(t) do
            options[#options + 1] = { id = c.name, text = c.name }
        end
        table.sort(options, function(a, b) return a.text < b.text end)
        return options
    end,
    characterResources = function()
        local options = {}
        local t = dmhub.GetTable("characterResources") or {}
        for _, r in pairs(t) do
            if r.grouping ~= "Actions" and not r:try_get("hidden", false) then
                options[#options + 1] = { id = string.lower(r.name), text = r.name }
            end
        end
        table.sort(options, function(a, b) return a.text < b.text end)
        return options
    end,
}

-- Convert a per-symbol typed input into the value GoblinScript will see at
-- the corresponding slot. Strings stay strings, numbers parse, booleans
-- map to true/false, sets parse comma-separated text into a {key=true} map.
local function coerceSymbolInputValue(kind, raw)
    if kind == "number" then
        local n = tonumber(raw)
        return n or 0
    elseif kind == "boolean" then
        return raw == true or raw == "true"
    elseif kind == "set" then
        local s = {}
        if type(raw) == "string" and raw ~= "" then
            for piece in string.gmatch(raw, "([^,]+)") do
                local trimmed = piece:gsub("^%s+", ""):gsub("%s+$", "")
                if trimmed ~= "" then s[trimmed] = true end
            end
        end
        return s
    end
    return raw or ""
end

-- Render a "satisfying" value back into the raw input form the editor's
-- inputs expect. Numeric stays numeric, string stays string, boolean -> bool,
-- set table ({Melee=true, Ranged=true}) -> comma-joined keys ("Melee, Ranged").
local function satisfyingValueToRaw(kind, value)
    if value == nil then return nil end
    if kind == "set" then
        if type(value) ~= "table" then return nil end
        local keys = {}
        for k in pairs(value) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        return table.concat(keys, ", ")
    end
    if kind == "boolean" then
        return value == true
    end
    if kind == "number" then
        return tonumber(value) or 0
    end
    -- text/string
    return tostring(value)
end

-- Build the symbols table that mirrors what the runtime would pass to
-- ExecuteGoblinScript. casterToken provides the LookupSymbol receiver;
-- subjectToken (if separate) populates symbols.subject; per-symbol inputs
-- + role tokens populate the rest.
local function buildEvalContext(ability, scenario)
    local symbols = {}
    symbols.mode = 1

    if scenario.subjectToken ~= nil and scenario.casterToken ~= nil
            and scenario.subjectToken.id ~= scenario.casterToken.id then
        symbols.subject = scenario.subjectToken.properties
    end

    for symKey, tok in pairs(scenario.roleTokens or {}) do
        if symKey ~= "subject" and tok ~= nil and tok.properties ~= nil then
            symbols[symKey] = tok.properties
            -- Trigger symbol pairs (attacker / hasattacker) commonly co-vary;
            -- if a hasX boolean is declared and we have X set, default it true.
            local hasKey = "has" .. symKey
            if scenario.symbolValues and scenario.symbolValues[hasKey] == nil then
                symbols[hasKey] = true
            end
        end
    end

    for symKey, info in pairs(scenario.symbolValues or {}) do
        symbols[symKey] = info.value
    end

    return symbols
end

-- Run the test against the supplied scenario. Returns a result struct:
--   { kind = "pass"|"fail"|"error"|"empty"|"no-caster",
--     value, errorMsg, attribution, symbols, casterToken, subjectToken }
-- "empty" = condition formula is blank (always fires).
-- "no-caster" = could not resolve a caster token (no scene / no tokens).
-- attribution is the GoblinScriptProse.AttributeFailure result, may be nil.
local function runTriggerTest(ability, scenario)
    local result = {
        casterToken = scenario.casterToken,
        subjectToken = scenario.subjectToken,
    }

    if scenario.casterToken == nil then
        result.kind = "no-caster"
        return result
    end

    local condition = ability:try_get("conditionFormula") or ""
    if condition == "" then
        result.kind = "empty"
        return result
    end

    local symbols = buildEvalContext(ability, scenario)
    result.symbols = symbols

    local ctx = scenario.casterToken.properties:LookupSymbol(symbols)

    local ok, value = pcall(function()
        return ExecuteGoblinScript(condition, ctx, 0, "Test Trigger")
    end)

    if not ok then
        result.kind = "error"
        result.errorMsg = tostring(value)
        return result
    end

    result.value = value

    if tonumber(value) == 0 or value == false or value == nil then
        result.kind = "fail"
        local attribution = GoblinScriptProse.AttributeFailure(
            condition,
            { subject = ability:try_get("subject") or "self", trigger = ability:try_get("trigger") or "" },
            function(leafSrc)
                local lok, lv = pcall(function()
                    return ExecuteGoblinScript(leafSrc, ctx, 0, "Test Trigger leaf")
                end)
                if not lok then return nil, tostring(lv) end
                return lv, nil
            end
        )
        result.attribution = attribution
        return result
    end

    result.kind = "pass"
    return result
end

-- Stringify a runtime value for display in the resolved-values grid.
local function describeValueForDisplay(v)
    if v == nil then return "nil" end
    if v == true then return "true" end
    if v == false then return "false" end
    if type(v) == "number" then return tostring(v) end
    if type(v) == "string" then return '"' .. v .. '"' end
    if type(v) == "table" then
        local keys = {}
        for k, _ in pairs(v) do keys[#keys + 1] = tostring(k) end
        if #keys == 0 then return "{}" end
        table.sort(keys)
        return "{" .. table.concat(keys, ", ") .. "}"
    end
    return tostring(v)
end

-- Builds the Test Trigger card body. Returns the panel; persistence of the
-- expanded/collapsed state and the last-run summary lives on the panel's
-- data field so refreshTest can rebuild without losing UI state.
local function buildTestTriggerCard(ability)
    local COLORS = getColors()
    local CARD_WIDTH = LAYOUT.PREVIEW_WIDTH - 2 * LAYOUT.COL_HPAD - LAYOUT.SCROLL_GUTTER

    -- State carried across rebuilds. roleSelections and symbolValues survive
    -- because the card's data table is preserved across refreshTest.
    -- `lastPrefillKey` tracks the formula + trigger the prefill was built
    -- from; if the author edits the condition, we clear symbolValues so the
    -- fresh pre-fill lands (otherwise the stale values from the old formula
    -- stick around).
    local state = {
        expanded = false,
        lastRun = nil,
        roleSelections = {},   -- [roleId] = tokenId
        symbolValues = {},      -- [symKey] = { raw = ..., kind = ... }
        lastPrefillKey = nil,
    }

    local cardPanel
    local function refreshTest()
        if cardPanel == nil then return end
        cardPanel:FireEvent("refreshTest")
    end

    -- Resolve a token by id from the active scene. Returns nil if the
    -- token has been deleted/moved off scene since the dropdown filled.
    local function tokenById(id)
        if id == nil or id == "__divider__" then return nil end
        local tokens = dmhub.allTokens or {}
        for _, t in ipairs(tokens) do
            if t.id == id then return t end
        end
        return nil
    end

    -- Builds the current scenario from state + the role/symbol declarations.
    local function buildScenario(inputs)
        local scenario = { roleTokens = {}, symbolValues = {} }

        -- Caster selection. Default = first preferred token; falls back to
        -- first scene token via tokensOnScene.
        local preferredAll, secondaryAll = categoriseSceneTokens(ability, nil, nil)
        local casterId = state.roleSelections.__caster
        local casterToken = casterId and tokenById(casterId) or nil
        if casterToken == nil then
            casterToken = preferredAll[1] or secondaryAll[1]
            if casterToken ~= nil then
                state.roleSelections.__caster = casterToken.id
            end
        end
        scenario.casterToken = casterToken

        -- Subject and per-symbol creature roles. Subject defaults to the
        -- first preferred matching the subject filter; per-symbol roles
        -- (Attacker, Pusher, Target) default to the first scene token that
        -- is not the caster, preferring enemies of the caster -- the runtime
        -- meaning of these roles is "the other party", so auto-filling with
        -- the caster's own token produces nonsensical test scenarios (the
        -- attacker in a Take Damage trigger is almost never the victim).
        local function pickOtherToken(caster)
            local tokens = dmhub.allTokens or {}
            local fallback
            for _, t in ipairs(tokens) do
                if caster == nil or t.id ~= caster.id then
                    if fallback == nil then fallback = t end
                    if caster ~= nil and caster.IsFriend and not caster:IsFriend(t) then
                        return t
                    end
                end
            end
            return fallback or tokens[1]
        end
        for _, slot in ipairs(inputs.roleSlots) do
            local tokId = state.roleSelections[slot.id]
            local tok = tokId and tokenById(tokId) or nil
            if tok == nil then
                if slot.isSubject then
                    local pref, sec = categoriseSceneTokens(ability, casterToken, slot.defaultSubjectFilter)
                    tok = pref[1] or sec[1]
                else
                    tok = pickOtherToken(casterToken)
                end
                if tok ~= nil then state.roleSelections[slot.id] = tok.id end
            end
            if slot.isSubject then
                scenario.subjectToken = tok
            end
            scenario.roleTokens[slot.id] = tok
        end

        if scenario.subjectToken == nil then
            scenario.subjectToken = casterToken
        end

        -- Pre-fill from satisfying values so the default scenario satisfies
        -- the condition (Passes). The author can then edit values to explore
        -- failure modes, rather than starting at "Fails" and having to guess
        -- what the condition wants. Satisfying map is keyed by symbol name
        -- as written in the formula; we match case-insensitively against
        -- both the symbol id and display name.
        --
        -- When the author edits the condition formula (or changes the trigger
        -- event, which changes which symbols are available), we reset
        -- symbolValues so the fresh prefill lands -- otherwise stale values
        -- from the previous formula stick around and the panel shows a
        -- Fails state that doesn't match the current formula.
        local conditionFormula = ability:try_get("conditionFormula") or ""
        local triggerId = ability:try_get("trigger") or ""
        local prefillKey = triggerId .. "|" .. conditionFormula
        if state.lastPrefillKey ~= prefillKey then
            state.symbolValues = {}
            state.lastPrefillKey = prefillKey
        end
        local satisfying = GoblinScriptProse.ExtractSatisfyingValues(conditionFormula)
        local satisfyingLower = {}
        for k, val in pairs(satisfying) do
            satisfyingLower[string.lower(k)] = val
        end

        for _, sym in ipairs(inputs.symbolInputs) do
            local v = state.symbolValues[sym.id]
            if v == nil then
                local hint = satisfyingLower[string.lower(sym.id)]
                    or satisfyingLower[string.lower(sym.name)]
                local raw
                if hint ~= nil then
                    raw = satisfyingValueToRaw(sym.kind, hint)
                end
                if raw == nil then
                    raw = (sym.kind == "boolean" and false)
                        or (sym.kind == "number" and 0)
                        or ""
                end
                v = { raw = raw, kind = sym.kind }
                state.symbolValues[sym.id] = v
            end
            scenario.symbolValues[sym.id] = {
                value = coerceSymbolInputValue(sym.kind, v.raw),
                raw = v.raw,
            }
        end

        return scenario
    end

    -- ---------------------------------------------------------------------
    -- Sub-builders (collapsed strip + expanded card body)
    -- ---------------------------------------------------------------------

    local function lastRunChip()
        if state.lastRun == nil then
            return { text = "Not yet run", color = "#666663" }
        end
        if state.lastRun.kind == "pass" then return { text = "Passes", color = "#5e8c4a" } end
        if state.lastRun.kind == "empty" then return { text = "Passes (no condition)", color = "#5e8c4a" } end
        if state.lastRun.kind == "fail" then return { text = "Fails", color = "#a14b3a" } end
        if state.lastRun.kind == "error" then return { text = "Error", color = "#a14b3a" } end
        if state.lastRun.kind == "no-caster" then return { text = "No tokens", color = "#666663" } end
        return { text = tostring(state.lastRun.kind), color = "#666663" }
    end

    -- Strip view: rendered when state.expanded == false. Mirrors the
    -- subHeading row layout used by the other two panes so the column
    -- reads as three uniform sub-headings stacked vertically.
    local function buildStrip()
        local chip = lastRunChip()
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            bgcolor = "clear",
            children = {
                gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "horizontal",
                    halign = "left",
                    valign = "center",
                    bgcolor = "clear",
                    children = {
                        gui.Label{
                            text = "Test Trigger",
                            bold = true,
                            fontSize = 16,
                            color = COLORS.GOLD_BRIGHT,
                            width = "auto",
                            height = "auto",
                            halign = "left",
                            valign = "center",
                        },
                        gui.Label{
                            text = chip.text,
                            bold = true,
                            fontSize = 12,
                            color = "white",
                            bgimage = "panels/square.png",
                            bgcolor = chip.color,
                            width = "auto",
                            height = "auto",
                            hpad = 8,
                            vpad = 2,
                            lmargin = 10,
                            halign = "left",
                            valign = "center",
                            borderBox = true,
                        },
                    },
                },
                gui.Button{
                    text = "Run Test",
                    width = 110,
                    height = 28,
                    halign = "right",
                    valign = "center",
                    fontSize = 13,
                    press = function()
                        state.expanded = true
                        refreshTest()
                    end,
                },
            },
        }
    end

    local function buildResultBlock(result)
        local lines = {}
        if result.kind == "no-caster" then
            lines[#lines + 1] = gui.Label{
                text = "Open a map with at least one token to test this trigger.",
                color = COLORS.GRAY,
                italics = true,
                fontSize = 13,
                width = "100%",
                height = "auto",
            }
            return lines
        end

        if result.kind == "empty" then
            lines[#lines + 1] = gui.Label{
                text = "<b>Passes</b> -- this trigger has no condition, so it fires whenever the event occurs.",
                markdown = true,
                color = "#5e8c4a",
                fontSize = 13,
                width = "100%",
                height = "auto",
                wrap = true,
            }
            return lines
        end

        if result.kind == "error" then
            lines[#lines + 1] = gui.Label{
                text = "<b>Error</b> -- " .. (result.errorMsg or "evaluation failed"),
                markdown = true,
                color = "#a14b3a",
                fontSize = 13,
                width = "100%",
                height = "auto",
                wrap = true,
            }
            return lines
        end

        if result.kind == "pass" then
            local valueNote = ""
            if result.value ~= true and result.value ~= 1 and tonumber(result.value) ~= 1 then
                valueNote = string.format(" (returned %s)", describeValueForDisplay(result.value))
            end
            lines[#lines + 1] = gui.Label{
                text = "<b>Passes</b>" .. valueNote,
                markdown = true,
                color = "#5e8c4a",
                fontSize = 13,
                width = "100%",
                height = "auto",
                wrap = true,
            }
            return lines
        end

        -- Fail: build attribution-aware feedback so the author sees which
        -- clause caused the trip rather than just "Fails". Headline leads
        -- with the prose form (plain-English rephrasing of the author's
        -- clause); detail line shows the raw formula + concrete value.
        -- Backticks trigger TextMeshPro code-span rendering in DMHub
        -- (characters get letter-spaced); use <i>...</i> for emphasis
        -- and keep the raw formula text in the lower-weight detail line.
        -- Headline uses markdown-enabled <b> for the Fails label; detail
        -- wraps the raw formula text in <i> for emphasis against regular
        -- surrounding copy. Markdown needs to be enabled on both labels
        -- (see renderer below).
        -- Prose-engine "failingDetail" / per-leaf "detail" semantics:
        --   nil    -> fall back to the generic "Formula clause ... evaluated to ..." line
        --   ""     -> intentionally suppress the detail line (headline self-sufficient)
        --   string -> use verbatim
        local headline
        local detail
        local attr = result.attribution
        if attr == nil then
            headline = "<b>Fails</b> -- the condition was not met."
        elseif attr.kind == "and" then
            local prose = attr.failingProse or attr.failingSrc or "one of the clauses"
            headline = "<b>Fails</b> -- needed " .. prose .. "."
            if attr.failingDetail == nil then
                detail = string.format("Formula clause <i>%s</i> evaluated to %s.",
                    attr.failingSrc or "?", describeValueForDisplay(attr.failingValue))
            elseif attr.failingDetail ~= "" then
                detail = attr.failingDetail
            end
        elseif attr.kind == "or" then
            local proseParts = {}
            for _, c in ipairs(attr.clauses or {}) do
                proseParts[#proseParts + 1] = c.prose or c.src or "?"
            end
            headline = "<b>Fails</b> -- needed at least one of: " .. table.concat(proseParts, "; ") .. "."
            local srcParts = {}
            for _, c in ipairs(attr.clauses or {}) do
                if c.detail and c.detail ~= "" then
                    srcParts[#srcParts + 1] = c.detail
                elseif c.detail == nil then
                    srcParts[#srcParts + 1] = string.format("<i>%s</i> (%s)",
                        c.src or "?", describeValueForDisplay(c.value))
                end
            end
            if #srcParts > 0 then
                detail = "All clauses were false: " .. table.concat(srcParts, ", ")
                if not detail:match("%.$") then detail = detail .. "." end
            end
        elseif attr.kind == "leaf" then
            local prose = attr.prose or attr.src or "the condition"
            headline = "<b>Fails</b> -- needed " .. prose .. "."
            if attr.detail == nil then
                detail = string.format("Formula <i>%s</i> evaluated to %s.",
                    attr.src or "?", describeValueForDisplay(attr.value))
            elseif attr.detail ~= "" then
                detail = attr.detail
            end
        else
            headline = "<b>Fails</b> -- the condition was not met."
        end

        lines[#lines + 1] = gui.Label{
            text = headline,
            markdown = true,
            color = "#a14b3a",
            fontSize = 13,
            width = "100%",
            height = "auto",
            wrap = true,
        }
        if detail ~= nil then
            lines[#lines + 1] = gui.Label{
                text = detail,
                markdown = true,
                color = COLORS.GRAY,
                fontSize = 12,
                width = "100%",
                height = "auto",
                wrap = true,
                tmargin = 2,
            }
        end
        return lines
    end

    -- Resolved-values grid. Shows symbol id + concrete value in a tight
    -- two-column layout. Helps the author cross-reference which input
    -- caused the result without re-reading every form row.
    local function buildResolvedValues(scenario, inputs)
        if #inputs.symbolInputs == 0 and #inputs.roleSlots == 0 then return nil end
        local rows = {}
        for _, slot in ipairs(inputs.roleSlots) do
            local tok = scenario.roleTokens[slot.id]
            rows[#rows + 1] = { label = slot.name, value = tok and tok.name or "(none)" }
        end
        for _, sym in ipairs(inputs.symbolInputs) do
            local v = scenario.symbolValues[sym.id]
            rows[#rows + 1] = {
                label = sym.name,
                value = v and describeValueForDisplay(v.value) or "?",
            }
        end
        local rowPanels = {}
        for _, r in ipairs(rows) do
            rowPanels[#rowPanels + 1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "left",
                valign = "center",
                bgcolor = "clear",
                vpad = 1,
                children = {
                    gui.Label{
                        text = r.label,
                        color = COLORS.GOLD_DIM,
                        fontSize = 11,
                        width = 100,
                        height = "auto",
                        halign = "left",
                    },
                    gui.Label{
                        text = r.value,
                        color = COLORS.CREAM_BRIGHT,
                        fontSize = 11,
                        width = "100%-100",
                        height = "auto",
                        halign = "left",
                        textWrap = true,
                    },
                },
            }
        end
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            halign = "left",
            bgcolor = "clear",
            tmargin = 6,
            children = {
                gui.Label{
                    text = "Resolved values",
                    color = COLORS.GOLD_DIM,
                    bold = true,
                    fontSize = 12,
                    width = "auto",
                    height = "auto",
                    bmargin = 2,
                },
                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    halign = "left",
                    bgcolor = "clear",
                    children = rowPanels,
                },
            },
        }
    end

    -- Field row with consistent label + control width inside the card body.
    local function fieldRow(labelText, control)
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            bgcolor = "clear",
            vpad = 2,
            children = {
                gui.Label{
                    text = labelText,
                    color = COLORS.GOLD_DIM,
                    fontSize = 12,
                    width = 100,
                    height = "auto",
                    halign = "left",
                    valign = "center",
                },
                control,
            },
        }
    end

    local function buildRoleSlotRow(slot, casterToken)
        local subjectFilter = slot.isSubject and slot.defaultSubjectFilter or nil
        local control = buildTokenPickerButton(
            ability, casterToken, subjectFilter,
            state.roleSelections[slot.id],
            function(tokenId)
                state.roleSelections[slot.id] = tokenId
                refreshTest()
            end,
            "Choose " .. slot.name
        )
        return fieldRow(slot.name, control)
    end

    local function buildCasterSlotRow()
        local preferred, secondary = categoriseSceneTokens(ability, nil, nil)
        if #preferred == 0 and #secondary == 0 then return nil end
        local control = buildTokenPickerButton(
            ability, nil, nil,
            state.roleSelections.__caster,
            function(tokenId)
                state.roleSelections.__caster = tokenId
                refreshTest()
            end,
            "Choose Caster"
        )
        return fieldRow("Caster", control)
    end

    local function buildSymbolInputRow(sym)
        local v = state.symbolValues[sym.id]
        if v == nil then
            v = { raw = (sym.kind == "boolean" and false) or (sym.kind == "number" and 0) or "", kind = sym.kind }
            state.symbolValues[sym.id] = v
        end

        if sym.kind == "boolean" then
            local toggle = gui.Check{
                text = "",
                value = v.raw == true,
                width = 20,
                height = 20,
                change = function(element)
                    v.raw = element.value
                    refreshTest()
                end,
            }
            return fieldRow(sym.name, toggle)
        end

        if sym.kind == "unsupported" then
            return fieldRow(sym.name, gui.Label{
                text = "(" .. (sym.displayType or "complex") .. " input not yet supported in test panel)",
                color = COLORS.GRAY,
                italics = true,
                fontSize = 11,
                width = "100%-100",
                height = "auto",
                halign = "left",
                textWrap = true,
            })
        end

        -- Bounded-value dropdown: the trigger.symbols declaration carries a
        -- valueOptionsSource hint, so render a dropdown over the canonical
        -- table for that category instead of a free-text input. Uses
        -- hasSearch only when the option count justifies it (currently just
        -- nothing -- 33 conditions and 12 damage types and ~30 resources are
        -- all comfortable in a flat dropdown).
        if sym.kind == "text" and sym.valueOptionsSource and TEST_OPTION_BUILDERS[sym.valueOptionsSource] then
            local options = TEST_OPTION_BUILDERS[sym.valueOptionsSource]()
            local current = tostring(v.raw or "")
            local lowerCurrent = string.lower(current)
            local hasMatch = false
            local matchedId = nil
            -- Case-insensitive match: real-world formulas use both
            -- `Condition is "Grabbed"` and `Condition is "grabbed"` (and the
            -- runtime injection is case-insensitive at GoblinScript level).
            -- Normalise so the satisfying-value pre-fill latches onto the
            -- dropdown entry regardless of author casing.
            for _, opt in ipairs(options) do
                if string.lower(opt.id) == lowerCurrent then
                    hasMatch = true
                    matchedId = opt.id
                    break
                end
            end
            if hasMatch and matchedId ~= current then
                -- Sync stored raw to the canonical id so subsequent reads
                -- compare cleanly; preserves the user's eventual choice.
                v.raw = matchedId
                current = matchedId
            end
            -- Prepend a "(none)" sentinel so the user can clear the value;
            -- chosen explicitly because trigger.symbols rarely default to a
            -- specific category value, and the test panel must support an
            -- unset state for the "what if this symbol is missing" path.
            local items = { { id = "", text = "(none)" } }
            for _, opt in ipairs(options) do items[#items + 1] = opt end
            local dropdown = gui.Dropdown{
                classes = {"nae-field-input"},
                width = "100%-100",
                options = items,
                idChosen = hasMatch and current or "",
                change = function(element)
                    v.raw = element.idChosen or ""
                    refreshTest()
                end,
            }
            return fieldRow(sym.name, dropdown)
        end

        local placeholder = ""
        if sym.kind == "number" then placeholder = "0"
        elseif sym.kind == "set" then placeholder = "comma,separated,values"
        end

        local input = gui.Input{
            classes = {"nae-field-input"},
            text = tostring(v.raw or ""),
            placeholderText = placeholder,
            width = "100%-100",
            change = function(element)
                v.raw = element.text
                refreshTest()
            end,
        }
        return fieldRow(sym.name, input)
    end

    local function buildBehaviourPreview()
        local text = behaviorsFallbackText(ability)
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            halign = "left",
            bgcolor = "clear",
            tmargin = 8,
            children = {
                gui.Label{
                    text = "If it fires, then:",
                    color = COLORS.GOLD_DIM,
                    bold = true,
                    fontSize = 12,
                    width = "auto",
                    height = "auto",
                    bmargin = 2,
                },
                gui.Label{
                    text = text,
                    color = COLORS.CREAM_BRIGHT,
                    fontSize = 12,
                    italics = true,
                    width = "100%",
                    height = "auto",
                    wrap = true,
                    halign = "left",
                },
            },
        }
    end

    -- Expanded card body. Re-runs the test, captures last-run state, and
    -- assembles the full child list including the close button.
    local function buildExpanded()
        local inputs = discoverTestInputs(ability)
        local scenario = buildScenario(inputs)
        local result = runTriggerTest(ability, scenario)
        state.lastRun = result

        local children = {}

        -- Header row with title (kept in body so the close button has a
        -- consistent home; the strip view's title row is omitted when
        -- expanded since the card itself carries the visual weight).
        children[#children + 1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            bgcolor = "clear",
            bmargin = 6,
            children = {
                gui.Label{
                    text = "Test Trigger",
                    bold = true,
                    fontSize = 14,
                    color = COLORS.GOLD_BRIGHT,
                    width = "100%-70",
                    height = "auto",
                    halign = "left",
                },
                gui.Button{
                    text = "Close",
                    width = 60,
                    height = 24,
                    halign = "right",
                    fontSize = 11,
                    press = function()
                        state.expanded = false
                        refreshTest()
                    end,
                },
            },
        }

        if result.kind == "no-caster" then
            for _, line in ipairs(buildResultBlock(result)) do
                children[#children + 1] = line
            end
            return children
        end

        -- Caster slot only renders when there's something to choose between
        -- (more than one scene token); single-token scenes auto-fill silently.
        local casterRow = buildCasterSlotRow()
        if casterRow ~= nil and #(dmhub.allTokens or {}) > 1 then
            children[#children + 1] = casterRow
        end

        for _, slot in ipairs(inputs.roleSlots) do
            children[#children + 1] = buildRoleSlotRow(slot, scenario.casterToken)
        end

        if #inputs.symbolInputs > 0 then
            children[#children + 1] = gui.Panel{
                width = "100%", height = 1,
                bgimage = "panels/square.png", bgcolor = COLORS.GOLD,
                tmargin = 6, bmargin = 6,
            }
            for _, sym in ipairs(inputs.symbolInputs) do
                children[#children + 1] = buildSymbolInputRow(sym)
            end
        end

        children[#children + 1] = gui.Panel{
            width = "100%", height = 1,
            bgimage = "panels/square.png", bgcolor = COLORS.GOLD,
            tmargin = 8, bmargin = 8,
        }

        for _, line in ipairs(buildResultBlock(result)) do
            children[#children + 1] = line
        end

        local resolved = buildResolvedValues(scenario, inputs)
        if resolved ~= nil then children[#children + 1] = resolved end

        children[#children + 1] = buildBehaviourPreview()

        children[#children + 1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            bgcolor = "clear",
            tmargin = 8,
            children = {
                gui.Button{
                    text = "Run Test",
                    width = 100,
                    height = 28,
                    fontSize = 12,
                    halign = "left",
                    press = function()
                        refreshTest()
                    end,
                },
            },
        }

        return children
    end

    -- Fingerprint of the ability fields the card is sensitive to. Per-field
    -- text inputs (conditionFormula, subject, trigger) don't dispatch
    -- refreshAbility, so we poll and compare -- mirrors the previewSlot's
    -- thinkTime poll pattern. Only fires a refreshTest when a watched field
    -- actually changed, so the GoblinScript eval doesn't re-run every tick.
    local function fingerprint()
        local behaviors = ability:try_get("behaviors")
        local behaviorCount = behaviors and #behaviors or 0
        return string.format("%s|%s|%s|%d",
            ability:try_get("trigger") or "",
            ability:try_get("subject") or "",
            ability:try_get("conditionFormula") or "",
            behaviorCount)
    end
    local lastFingerprint = fingerprint()

    cardPanel = gui.Panel{
        id = "tsTestTriggerCard",
        width = CARD_WIDTH,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bgcolor = "clear",
        tmargin = 14,
        thinkTime = 0.25,
        think = function(element)
            local fp = fingerprint()
            if fp ~= lastFingerprint then
                lastFingerprint = fp
                element:FireEvent("refreshTest")
            end
        end,
        refreshTest = function(element)
            -- Sync the fingerprint here too so an upstream refreshAbility
            -- dispatch doesn't also trigger a redundant think-poll rebuild.
            lastFingerprint = fingerprint()
            if state.expanded then
                element.bgimage = "panels/square.png"
                element.bgcolor = COLORS.CARD_BG
                element.borderWidth = 2
                element.borderColor = COLORS.GOLD_DIM
                element.cornerRadius = 4
                element.vpad = 10
                element.hpad = 12
                element.borderBox = true
                element.children = buildExpanded()
            else
                element.bgimage = nil
                element.bgcolor = "clear"
                element.borderWidth = 0
                element.vpad = 0
                element.hpad = 0
                element.children = { buildStrip() }
            end
        end,
        -- Re-evaluate when any ability field changes upstream. Discovery of
        -- inputs (referenced symbols, role slots) needs to refresh as the
        -- author edits the trigger event / condition / behaviours.
        refreshAbility = function(element)
            element:FireEvent("refreshTest")
        end,
    }

    cardPanel:FireEvent("refreshTest")
    return cardPanel
end

-- Preview column + slot factory. Returns (colPanel, previewSlot). The slot
-- listens for refreshPreview and rebuilds its single child on demand.
-- `schedulePreviewRefresh` is called from the slot's think event so live
-- edits propagate into the preview without tight per-frame coupling.
local function makePreviewColumn(ability, schedulePreviewRefresh)
    local COLORS = getColors()
    -- Heading rows (subHeading below) need to match the cards' width so the
    -- right-aligned rollup chip aligns with the card's right border instead
    -- of bleeding into the scroll gutter.
    local CARD_WIDTH = LAYOUT.PREVIEW_WIDTH - 2 * LAYOUT.COL_HPAD - LAYOUT.SCROLL_GUTTER

    local previewSlot
    previewSlot = gui.Panel{
        id = "triggerPreviewSlot",
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "vertical",
        bgcolor = "clear",
        thinkTime = 0.25,
        think = function(element)
            if schedulePreviewRefresh ~= nil then
                schedulePreviewRefresh()
            end
        end,
        refreshPreview = function(element)
            local children = {}

            -- Sub-heading helper. Each preview pane gets a bold gold label
            -- above its card container so the column reads as a set of
            -- distinct sections. Optional trailing chip (right-aligned on
            -- the same row) lets the Mechanical View surface its rollup
            -- status without giving it its own row inside the card.
            local function subHeading(title, topMargin, rollup)
                local titleLabel = gui.Panel{
                    width = "50%-6",
                    height = "auto",
                    flow = "horizontal",
                    halign = "left",
                    valign = "center",
                    bgcolor = "clear",
                    children = {
                        gui.Label{
                            text = title,
                            bold = true,
                            fontSize = 16,
                            color = COLORS.GOLD_BRIGHT,
                            width = "auto",
                            height = "auto",
                            halign = "left",
                        },
                    },
                }
                local chipLabel
                if rollup ~= nil then
                    chipLabel = gui.Panel{
                        width = "50%-6",
                        height = "auto",
                        flow = "horizontal",
                        halign = "right",
                        valign = "center",
                        bgcolor = "clear",
                        children = {
                            gui.Label{
                                text = rollup.text,
                                bold = true,
                                fontSize = 12,
                                color = "white",
                                bgimage = "panels/square.png",
                                bgcolor = rollup.color,
                                width = "auto",
                                height = "auto",
                                hpad = 10,
                                vpad = 3,
                                halign = "right",
                                borderBox = true,
                            },
                        },
                    }
                end
                return gui.Panel{
                    width = CARD_WIDTH,
                    height = "auto",
                    flow = "horizontal",
                    halign = "left",
                    valign = "center",
                    bgcolor = "clear",
                    tmargin = topMargin or 0,
                    bmargin = 6,
                    children = chipLabel and { titleLabel, chipLabel } or { titleLabel },
                }
            end

            -- Trigger Preview
            children[#children + 1] = subHeading("Trigger Preview", 0, nil)
            local cardOk, cardOrErr = pcall(buildTriggerPreviewCard, ability)
            if cardOk and cardOrErr ~= nil then
                children[#children + 1] = cardOrErr
            else
                children[#children + 1] = gui.Label{
                    width = "100%",
                    height = "auto",
                    fontSize = 13,
                    italics = true,
                    color = COLORS.GRAY,
                    text = "(no preview available)",
                }
            end

            -- Mechanical View pane (labelled "How This Triggers" per the
            -- 2026-04-24 polish pass -- the diagnostic-style sub-title is
            -- self-explanatory, the earlier "will this trigger?" subtitle
            -- became redundant once the chip moved inline).
            local mechOk, mechRes, mechRollup = pcall(buildMechanicalView, ability)
            local mechPane, rollup
            if mechOk and mechRes ~= nil then
                mechPane, rollup = mechRes, mechRollup
            end
            children[#children + 1] = subHeading("How This Triggers", 14, rollup)
            if mechPane ~= nil then
                children[#children + 1] = mechPane
            end

            element.children = children
        end,
    }

    -- Test Trigger card lives outside previewSlot so its expanded/collapsed
    -- state and per-input values survive the previewSlot's frequent
    -- refreshPreview rebuilds. It listens for refreshAbility internally to
    -- re-discover referenced symbols when the trigger event or condition
    -- formula change.
    local testTriggerCard = buildTestTriggerCard(ability)

    local scrollArea = gui.Panel{
        classes = {"nae-preview-body"},
        id = "triggerPreviewScroll",
        vscroll = true,
        flow = "vertical",
        halign = "left",
        valign = "top",
        bgcolor = "clear",
        children = { previewSlot, testTriggerCard },
    }

    -- Column heading intentionally omitted: each pane carries its own
    -- sub-heading now ("Trigger Preview" / "Mechanical View" / Test
    -- Trigger in phase 6). A single "Preview" umbrella was a misfit --
    -- only the first pane is actually a preview.
    local colPanel = gui.Panel{
        classes = {"nae-preview-col"},
        id = "tsPreviewCol",
        width = LAYOUT.PREVIEW_WIDTH,
        height = "100%",
        flow = "vertical",
        valign = "top",
        hpad = LAYOUT.COL_HPAD,
        vpad = LAYOUT.COL_VPAD,
        borderBox = true,
        children = { scrollArea },
    }

    return colPanel, previewSlot
end

local function generateSectionedEditor(ability, options)
    local COLORS = getColors()

    local navButtons = {}
    local sectionContents = {}
    local rootPanel
    local detailScroll
    local effectsBottomBar
    local previewSlot

    -- Preview debounce state. Mirrors AbilityEditor's 0.15s coalescing
    -- pattern so rapid edits (keystrokes in a text field, slider drags)
    -- collapse into a single card rebuild per window. The slot's own
    -- think (thinkTime=0.25) is the polling fallback; fireChange uses
    -- this direct path for immediate invalidation on structural changes.
    local _previewDirty = false
    local _previewTimerActive = false
    local function schedulePreviewRefresh()
        _previewDirty = true
        if _previewTimerActive then return end
        _previewTimerActive = true
        dmhub.Schedule(0.15, function()
            if mod.unloaded then return end
            _previewTimerActive = false
            if not _previewDirty then return end
            _previewDirty = false
            if previewSlot ~= nil then
                previewSlot:FireEvent("refreshPreview")
            end
        end)
    end

    -- Structural-change dispatcher. Fires refreshAbility across the root
    -- subtree so: (a) the Effects behaviour-list panel's key-guarded
    -- rebuild picks up add/remove/reorder, (b) the paste button's
    -- visibility handler re-reads the clipboard, (c) the preview card
    -- rebuilds with the new field state via the debounced scheduler.
    -- Per-field edits inside a behaviour card use refreshBehavior instead
    -- and don't reach here; the preview still catches them via its
    -- thinkTime poll.
    local function fireChange()
        if rootPanel == nil then return end
        rootPanel:FireEventTree("refreshAbility")
        schedulePreviewRefresh()
    end

    local function pasteBehavior()
        local item = dmhub.GetInternalClipboard()
        if item == nil then return end
        local tn = item.typeName or ""
        if not (string.starts_with(tn, "ActivatedAbility") and string.ends_with(tn, "Behavior")) then
            return
        end
        local copy = DeepCopy(item)
        copy.guid = dmhub.GenerateGuid()
        ability.behaviors[#ability.behaviors + 1] = copy
        fireChange()
    end

    local function selectSection(sectionId)
        if rootPanel == nil then return end
        rootPanel.data.selectedSectionId = sectionId
        for _, btn in ipairs(navButtons) do
            btn:SetClass("selected", btn.data.sectionId == sectionId)
        end
        for _, content in ipairs(sectionContents) do
            content:SetClass("inactive", content.data.sectionId ~= sectionId)
        end
        -- Effects tab gets the fixed Add/Paste bottom bar (42px reserved);
        -- other tabs collapse the bar and reclaim the scroll height.
        if effectsBottomBar ~= nil and detailScroll ~= nil then
            local isEffects = (sectionId == "effects")
            effectsBottomBar:SetClass("collapsed", not isEffects)
            detailScroll.height = isEffects and "100%-42" or "100%"
        end
    end

    for _, sectionDef in ipairs(SECTIONS) do
        navButtons[#navButtons + 1] = makeNavButton(sectionDef, function(id)
            selectSection(id)
        end)
        sectionContents[#sectionContents + 1] = makeSectionContent(sectionDef, ability, fireChange)
    end

    -- Nav buttons sit inside an auto-sized inner container so the group can
    -- be vertically centered within the full-height nav column. A direct
    -- valign=center on a vertical-flow parent with multiple children doesn't
    -- reliably center the stack; wrapping in an auto-height inner panel does.
    local navCol = gui.Panel{
        classes = {"nae-nav-col"},
        id = "tsNavCol",
        width = LAYOUT.NAV_WIDTH,
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "center",
        hpad = LAYOUT.COL_HPAD,
        vpad = LAYOUT.COL_VPAD,
        borderBox = true,
        children = {
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                halign = "center",
                valign = "center",
                bgcolor = "clear",
                children = navButtons,
            },
        },
    }

    -- Scroll wrapper so the Add/Paste bottom bar can stay anchored outside
    -- the scrolling region. selectSection shrinks this to 100%-42 when the
    -- Effects tab is active and the bar is visible.
    detailScroll = gui.Panel{
        id = "tsDetailScroll",
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bgcolor = "clear",
        vscroll = true,
        hpad = LAYOUT.COL_HPAD,
        vpad = LAYOUT.COL_VPAD,
        borderBox = true,
        children = sectionContents,
    }

    -- Paste Behavior: visible only when the internal clipboard holds a
    -- behaviour. Listens to both refreshAbility (fired on our dispatch)
    -- and internalClipboardChanged (fired by the engine when the user
    -- copies a behaviour from elsewhere while this editor is open).
    local pasteButton = gui.Button{
        text = "Paste Behavior",
        width = 160,
        height = 34,
        halign = "center",
        classes = {cond(not clipboardHasBehavior(), "collapsed-anim")},
        press = function()
            pasteBehavior()
        end,
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", not clipboardHasBehavior())
        end,
        internalClipboardChanged = function(element)
            element:SetClass("collapsed-anim", not clipboardHasBehavior())
        end,
    }

    -- Inner auto-width container so the two buttons cluster in the center
    -- of the bar rather than spreading across its full 100% width.
    effectsBottomBar = gui.Panel{
        id = "tsEffectsBottomBar",
        classes = {"nae-effects-bottom-bar", "collapsed"},
        children = {
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                valign = "center",
                bgcolor = "clear",
                children = {
                    gui.Button{
                        text = "+ Add Behavior",
                        width = 160,
                        height = 34,
                        press = function()
                            AbilityEditor.OpenBehaviorPicker(ability, function(typeId)
                                local typeEntry = ability.TypesById[typeId]
                                if typeEntry and typeEntry.createBehavior then
                                    ability.behaviors[#ability.behaviors + 1] = typeEntry.createBehavior()
                                    AbilityEditor._trackRecentBehavior(typeId)
                                    fireChange()
                                end
                            end)
                        end,
                    },
                    pasteButton,
                },
            },
        },
    }

    -- Outer detail column: non-scrolling vertical container holding the
    -- scroll area and the effects bottom bar. Padding lives on detailScroll
    -- (not here) so the bottom bar can anchor flush to the column floor.
    local detailCol = gui.Panel{
        classes = {"nae-detail-col"},
        id = "tsDetailCol",
        width = string.format("100%%-%d", LAYOUT.NAV_WIDTH + LAYOUT.PREVIEW_WIDTH + 24),
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",
        borderBox = true,
        children = {detailScroll, effectsBottomBar},
    }

    -- Preview column (phase 5). Auto-derives the Trigger row through the
    -- GoblinScriptProse engine; other slots stay blank until phase 7's
    -- Display overrides land. Kept to the right of the detail column.
    local previewCol
    previewCol, previewSlot = makePreviewColumn(ability, schedulePreviewRefresh)

    rootPanel = gui.Panel{
        classes = {"nae-root"},
        id = "triggeredAbilityEditorRoot",
        styles = buildStyles(),
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "horizontal",
        borderBox = true,
        bgcolor = COLORS.BG,
        bgimage = "panels/square.png",
        borderWidth = 2,
        borderColor = COLORS.GOLD,
        cornerRadius = 6,
        data = {
            ability = ability,
            selectedSectionId = SECTIONS[1].id,
        },
        children = {navCol, detailCol, previewCol},
    }

    selectSection(SECTIONS[1].id)
    -- Fire an initial preview build so the card is populated immediately
    -- rather than waiting for the first thinkTime tick (0.25s).
    if previewSlot ~= nil then
        previewSlot:FireEvent("refreshPreview")
    end
    return rootPanel
end

--[[
    ============================================================================
    Dispatch
    ============================================================================
    Rules (in order):
      1. Aura-embed path (options.excludeTriggerCondition or
         options.excludeAppearance) -> classic editor. Keeps Aura.lua's
         embedded trigger editor working unchanged.
      2. User opt-out setting -> classic editor.
      3. Otherwise -> new sectioned editor.
]]
function TriggeredAbility:GenerateEditor(options)
    options = options or {}

    if options.excludeTriggerCondition or options.excludeAppearance then
        return classicGenerateEditor(self, options)
    end

    if dmhub.GetSettingValue("classicTriggeredAbilityEditor") == true then
        return classicGenerateEditor(self, options)
    end

    return generateSectionedEditor(self, options)
end
