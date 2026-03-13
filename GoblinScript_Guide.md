# GoblinScript Reference Guide

A complete reference for the GoblinScript formula language used in the Draw Steel Codex.

---

## Table of Contents

1. [What is GoblinScript?](#what-is-goblinscript)
2. [The Formula Editor](#the-formula-editor)
3. [Basic Syntax](#basic-syntax)
4. [Conditional Expressions](#conditional-expressions)
5. [Subjects: Who and What You Can Reference](#subjects)
6. [Creature Fields](#creature-fields)
7. [Custom Attribute Symbols](#custom-attribute-symbols)
8. [Ability Fields](#ability-fields)
9. [Cast Fields](#cast-fields)
10. [Path Fields](#path-fields)
11. [Aura and Ongoing Effect Fields](#aura-and-ongoing-effect-fields)
12. [Global Functions](#global-functions)
13. [Dice Notation in Roll Fields](#dice-notation)
14. [Special Syntax](#special-syntax)
15. [Where GoblinScript Can Be Used](#where-goblinscript-can-be-used)
16. [Real Examples from the Compendium](#real-examples)

---

## What is GoblinScript?

GoblinScript is the formula language used throughout the Draw Steel Codex. It lets you write
expressions that the app evaluates automatically at runtime -- pulling in live values from
the game state to produce a number, a yes/no (boolean), or a piece of text.

You do not need a programming background to use GoblinScript. It reads much like plain English.
For example:

```
Stamina <= Maximum Stamina / 2
```

That expression is true when a creature's current stamina is at or below half its maximum --
in other words, when it is winded.

GoblinScript appears wherever there is a formula field in the Codex. The field might control
damage, determine who can be targeted, decide whether a modifier is active, or embed a
calculated value in an ability description. Any field where you see the goblin head icon
accepts GoblinScript.

---

## The Formula Editor

Click the **goblin head icon** next to any formula field to open the formula editor.

The editor has two modes:

### Expression Mode

Write a formula directly. This is the primary mode and is covered throughout this guide.

### Table Mode

An alternative to writing conditional expressions for level-based scaling. Instead of writing:

```
(1d3 + 1) when Level >= 7 else (1d3)
```

you can add table rows that map level ranges to values:

| Level | Value |
|---|---|
| 1 | 1d3 |
| 7 | 1d3 + 1 |

The app generates the equivalent conditional expression automatically. Table mode is easier
when you are implementing a feature that changes value at specific levels.

### In-App Documentation Panel

Inside the formula editor, the documentation panel lists all subjects and fields available for
the specific field you are editing. The available subjects depend on context -- for example, a
targeting filter field will show `Target` as a subject, while an ability-level formula will
show `Ability`. When in doubt, open the documentation panel to see exactly what is available.

---

## Basic Syntax

### Numbers and Arithmetic

```
2 + 3          -- addition
10 - 4         -- subtraction
Might * 2      -- multiplication
Stamina / 2    -- division
```

Dice rolls use standard notation:

```
2d10 + Might
1d6
```

### Comparisons

| Operator | Meaning |
|---|---|
| `=` | equals |
| `~=` or `!=` | not equals |
| `>` | greater than |
| `<` | less than |
| `>=` | greater than or equal |
| `<=` | less than or equal |

Examples:

```
Stamina <= 10
Level >= 4
Role = "Artillery"
```

### Logic

```
condition1 and condition2
condition1 or condition2
not condition
```

Example:

```
not Friends(Target, Caster) and Target.Stamina > 0
```

### Text Comparisons

Use `=` to check if a text field matches a value exactly, and `has` to check if a text field
contains a word. The value being compared must always be wrapped in double quotes.

```
Role = "Artillery"
Movement Type = "Fly"
Keywords has "Strike"
Conditions has "Grabbed"
```

### Math Functions

```
min(a, b)        -- returns the smaller of two values
max(a, b)        -- returns the larger of two values
floor(x)         -- rounds down to the nearest whole number
ceiling(x)       -- rounds up to the nearest whole number
```

---

## Conditional Expressions

### Basic Conditional

Returns the value only when the condition is true. Returns 0 otherwise.

```
value when condition
```

Example: "5, but only when the target is flanked":

```
5 when Target.Flanked
```

### Conditional with Fallback

Returns one value when the condition is true, another when false.

```
value when condition else fallback
```

Example: "1d3 + 1 at level 7 or higher, otherwise 1d3":

```
(1d3 + 1) when Level >= 7 else (1d3)
```

### Additive Chaining for Level Scaling

Add multiple `when` expressions together to build values that grow at specific levels.
Each `when` expression adds to the total independently.

```
base + (bonus when Level >= 4) + (bonus when Level >= 7)
```

Example from the Shadow class: "1 slot, plus 1 more at level 4":

```
1 + (1 when Level >= 4)
```

This pattern is common for features that improve at multiple level milestones.

---

## Subjects

A **subject** is a handle to a specific creature or game object that GoblinScript can reference.
You access a subject's fields using dot notation: `Subject.Fieldname`.

Which subjects are available depends on the formula field. The in-app documentation panel shows
you exactly which subjects are available in the field you are editing.

| Subject | Type | When available |
|---|---|---|
| `Self` | Creature | Always -- the creature that owns the ability, modifier, or aura |
| `Caster` | Creature | Always -- the creature currently using the ability |
| `Target` | Creature | Targeting and effect formulas |
| `Attacker` | Creature | Defensive trigger contexts (e.g. "when you are attacked") |
| `Moving Creature` | Creature | Movement trigger contexts only (e.g. "when a creature moves away") |
| `Ability` | Ability | Formula fields on activated abilities |
| `UsedAbility` | Ability | Event trigger contexts ("when you use a maneuver...") -- same fields as Ability |
| `Cast` | Cast | During ability resolution (damage dealt, roll results, targets hit) |
| `Aura` | Aura | Inside aura effect formulas |
| `Path` | Path | Movement formula fields |

**Self vs Caster**: `Self` is the creature that *owns* the ability or modifier (e.g. a monster
with a passive aura). `Caster` is the creature actively *using* an ability right now. In most
ability formulas these are the same creature, but in shared or triggered contexts they can differ.

All creature-typed subjects (Self, Target, Caster, Attacker, Moving Creature) share the same
pool of creature fields described in the next section.

---

## Creature Fields

The following fields are available on any creature subject: `Self`, `Target`, `Caster`,
`Attacker`, and `Moving Creature`.

### Identity and Role

| Field | Type | Description |
|---|---|---|
| Name | Text | The monster type (e.g. Bandit, Goblin). For monsters only; not characters. |
| ID | Text | A unique internal identifier for this creature. Not human-readable. |
| Type | Text | The creature's type (e.g. Goblin, Demon for monsters; Elf, Human for characters) |
| Subtype | Text | The creature's subtype (e.g. Goblinoid, High Elf). Empty if no subtype. |
| Level | Number | The creature's level |
| Role | Text | Creature role (e.g. "Artillery", "Brute", "Leader") |
| Keywords | Text | Creature keywords (use `has` to check: `Keywords has "Undead"`) |
| Subclasses | Set | Subclasses this character has taken. None for monsters. |
| Minion | Boolean | True if the creature is a minion |
| Captain | Boolean | True if the creature is a captain |
| Solo | Boolean | True if the creature is a solo |
| Leader | Boolean | True if the creature is a leader |
| HasCaptain | Boolean | True if the creature has a captain nearby |
| SquadCaptain | Boolean | True if the creature is the captain of a squad |
| Hero | Boolean | True if the creature is a hero (player character) |
| Object | Boolean | True if the creature is an object |
| PlayerAllied | Boolean | True if the creature is allied with the players |
| Retainer | Boolean | True if the creature is a retainer |
| Mentor | Boolean | True if the creature is a mentor |

### Health and Resources

| Field | Type | Description |
|---|---|---|
| Stamina | Number | Current stamina |
| Maximum Stamina | Number | Maximum stamina |
| Temporary Stamina | Number | Current temporary stamina |
| Recovery Value | Number | The creature's recovery value |
| Recoveries Available to Spend | Number | How many recoveries the creature has left |
| Heroic Resources Available to Spend | Number | Total heroic resources available to spend |
| Heroic Resources This Turn | Number | Heroic resources gained this turn |
| Malice | Number | Current malice (Director-facing resource) |
| Power Roll Bonus | Number | Bonus applied to power rolls |
| Dying | Boolean | True if the creature is dying |
| Dead | Boolean | True if the creature is dead |
| Resources | Resources | The resource pools this creature has available |

### Combat Status

| Field | Type | Description |
|---|---|---|
| Flanked | Boolean | True if the creature is flanked |
| FlankedBy | Text | ID of the creature providing flanking |
| InWater | Boolean | True if the creature is in water |
| Concealed | Boolean | True if the creature is concealed |
| TakeTurn | Boolean | True if the creature has already taken its turn this round |
| TurnBeingChosen | Boolean | True if it is currently this creature's turn to be chosen |
| End Turn Timestamp | Number | Timestamp of the creature's last end of turn |
| Last Damaged By | Text | ID of the creature that last dealt damage to this creature |
| Your Turn | Boolean | True if it is currently this creature's turn in combat |
| Combat Round | Number | Current combat round number (0 if not in combat) |
| Hidden This Turn | Boolean | True if this creature has been hidden this turn |

### Characteristics and Potency

Draw Steel uses three potency tiers (Weak, Average, Strong) to determine whether abilities
overcome resistances.

| Field | Type | Description |
|---|---|---|
| Weak | Number | The creature's Weak characteristic score |
| Average | Number | The creature's Average characteristic score |
| Strong | Number | The creature's Strong characteristic score |
| Highest Characteristic | Number | The creature's highest characteristic score |
| Passes Potency | Function | Returns true if this creature passes potency: `Passes Potency(target, characteristic, potency)` |

### Size and Movement

Movement speed fields are generated dynamically for each movement type a creature has.

| Field | Type | Description |
|---|---|---|
| Size | Number | Creature size (1=Tiny, 2=Small, 3=Medium, 4=Large, 5=2, 6=3, 7=4, 8=5) |
| Tile Size | Number | Size in tiles occupied on the map |
| Height | Number | The creature's stature in tiles tall |
| Altitude | Number | Vertical position in tiles above map ground level |
| AltitudeInDeciTiles | Number | Vertical position in tenths of a tile (for precise height checks) |
| SizeWhenForceMoved | Number | The effective size used when the creature is force moved |
| Reach | Number | The creature's reach in squares |
| Walking Speed | Number | The creature's walking speed in squares |
| Flying Speed | Number | The creature's flying speed (0 if it cannot fly) |
| Burrowing Speed | Number | The creature's burrowing speed (0 if it cannot burrow) |
| Movement Speed | Number | Total movement available per round in squares |
| Moved This Turn | Number | Distance moved so far this turn in squares |
| Charge Distance | Number | Straight-line distance moved this turn (used for charging checks) |
| Movement Type | Text | Current movement type: "Walk", "Swim", "Fly", etc. |
| Movement Multiplier | Number | Multiplier applied to movement distance this round |
| Mounted | Boolean | True if this creature is currently mounted |
| Mount | Creature | The creature being ridden (access its fields via `Mount.Fieldname`) |
| Number of Creatures Grabbed | Number | Count of creatures currently grabbed by this creature |

Additional movement types (Climbing, Swimming, Teleport, etc.) also generate speed fields
using the same naming pattern.

### Auras

| Field | Type | Description |
|---|---|---|
| Auras Affecting | Text set | Names of auras currently affecting this creature (use `has` to check) |
| AurasCaster | Function | Returns the creature projecting a named aura: `AurasCaster("Aura of Courage")` |

### Conditions and Effects

| Field | Type | Description |
|---|---|---|
| Conditions | Set | Names of conditions on this creature. Use `has` to check: `Conditions has "Grabbed"` |
| Ongoing Effects | Set | Names of ongoing effects on this creature. Use `has` to check. |
| Save Ends Effects | Number | Number of active save-ends effects on the creature |
| Condition Stacks | Number | Total condition stacks on this creature |
| Condition Count | Number | Number of distinct conditions on this creature |
| Stacks | Function | Returns the stack count of a named effect: `Stacks("Condition Name")` |
| Condition Immunities | Set | Conditions this creature is immune to |
| Effect Caster | Text | ID of the creature that applied the current condition or ongoing effect |
| ConditionCaster | Function | Returns the creature that applied a named condition: `ConditionCaster("Grabbed")` |
| CasterSet | Function | Returns the set of creatures that applied a named ongoing effect |
| Last Caster | Creature | The creature that last triggered a saving throw on this creature |

### Squad and Summoning

| Field | Type | Description |
|---|---|---|
| Bound Creatures | Number | Number of creatures bound to this creature |
| Bound Ongoing Effect | Text | ID of the ongoing effect that binds this creature |
| Complications | Number | Number of complications on this creature |
| AdjacentAlliesWithFeature | Function | Count of adjacent allies with a named feature |
| Summoned | Boolean | True if this creature was summoned by another creature |
| Summoner | Creature | The creature that summoned this creature |
| SquadCaster | Function | Returns the squad that applied a named ongoing effect |
| SquadLiveMembers | Function | Returns the count of living members in a named squad |

### Monster-Only Fields

| Field | Type | Description |
|---|---|---|
| Free Strike Damage | Number | The monster's free strike damage value |
| Free Strike Range | Number | The monster's free strike range |
| EV | Number | The monster's encounter value |

### Other

| Field | Type | Description |
|---|---|---|
| Victories | Number | The party's current victory count |
| Kit | Text | The hero's equipped kit name |
| Game Mode | Text | Current game mode (e.g. "Combat", "Respite") |
| Routine Distance | Number | Distance used by monster routine calculations |
| Num Dead Languages | Number | Number of dead languages the creature knows |
| Dead Languages | Text | The dead languages the creature knows |
| Languages | Set | Languages this creature knows |

### Creature Functions

These symbols are functions that take arguments and return calculated values. Call them with
parentheses and the required arguments.

| Field | Type | Description |
|---|---|---|
| Distance | Function | Distance in squares to another creature: `Distance(Target)` |
| Count Nearby Enemies | Function | Count of live enemies within a range in squares: `Count Nearby Enemies(5)`. Accepts group names, feature names, or creatures to exclude as additional arguments. |
| Count Nearby Friends | Function | Count of live allies within a range in squares: `Count Nearby Friends(5)`. Same filter options as Count Nearby Enemies. |
| Count Nearby Creatures | Function | Count of all live creatures within a range: `Count Nearby Creatures(5)`. Accepts `"ally"`, `"enemy"`, group names, feature names, or creatures to exclude. |
| Count Riders | Function | Count of riders matching filter criteria: `Count Riders("goblin")` |

---

## Custom Attribute Symbols

Every custom attribute defined in the compendium automatically becomes a GoblinScript symbol
available on all creatures. You use the attribute name directly in a formula -- the app
handles the lookup for you.

For example, `Critical Threshold` is a custom attribute with a default value of 19. You can
write it in any formula that has access to a creature subject:

```
Cast.Natural Roll >= Caster.Critical Threshold
```

Below are commonly used custom attribute symbols. For the full list, open the **Custom
Attributes** table in the compendium, or click the goblin head icon on any creature formula
field and check the documentation panel.

| Symbol | Type | Description | Default |
|---|---|---|---|
| Winded | Boolean | True when stamina is at or below half maximum stamina | Calculated |
| Charging | Boolean | True when the creature is in a charging state during ability use | 0 (false) |
| Has Cover | Boolean | True when the creature has cover | 0 (false) |
| Can Fly | Number | Non-zero if the creature can fly (same as `Flying Speed > 0`) | 0 |
| Can Burrow | Number | Non-zero if the creature can burrow | 0 |
| Grab Characteristic | Value | The characteristic score used for grab checks | Might |
| Critical Threshold | Number | Minimum natural power roll result to score a critical hit | 19 |
| SummonerRange | Number | Maximum distance for summoner abilities | 5 + Reason |
| MaximumMinions | Number | Maximum number of minions the creature can have active | 8 |
| Ignore Concealment Within Range | Number | Concealment is ignored for attacks within this distance | 0 |

Custom attributes added by a class or homebrew content also become symbols automatically.
If you add a new custom attribute to the compendium, it will appear in the documentation
panel the next time you open the formula editor.

---

## Ability Fields

These fields are available on the `Ability` subject and on `UsedAbility` (which appears in
event trigger contexts such as "when you use a maneuver..."). Both subjects share the same
fields.

### Identity

| Field | Type | Description |
|---|---|---|
| Name | Text | The ability's name |
| Keywords | Text | The ability's keywords (use `has` to check: `Ability.Keywords has "Strike"`) |
| Range | Number | The ability's range in squares |
| Level | Number | The level at which the ability is acquired |
| Categorization | Text | The ability's categorization (e.g. "Signature Ability", "Heroic Ability") |
| Allegiance | Text | Who the ability targets: `"ally"`, `"enemy"`, `"dead"`, or `"all"` |

### Action Economy

| Field | Type | Description |
|---|---|---|
| Action | Boolean | True if the ability consumes an Action |
| Maneuver | Boolean | True if the ability consumes a Maneuver |
| Main Action | Boolean | True if the ability is a main action |
| Heroic | Boolean | True if the ability is a Heroic Ability |
| Trigger | Boolean | True if the ability has a trigger |
| Heroic Resource Cost | Number | The heroic resource cost (0 if not a heroic ability) |
| Malice Cost | Number | The malice cost (0 if not a malice ability) |

### Behavior Flags

| Field | Type | Description |
|---|---|---|
| Has Attack | Boolean | True if the ability includes a power roll attack |
| Has Heal | Boolean | True if the ability includes healing |
| Does Damage | Boolean | True if the ability deals damage |
| Has Forced Movement | Boolean | True if the ability includes forced movement |
| Has Potency | Boolean | True if the ability has potency (uses the `<` notation in tiers) |
| Spell | Boolean | True if the ability is a spell |
| Free Strike | Boolean | True if the ability is a free strike |
| Usable As Free Strike | Boolean | True if the ability can be used as a free strike |
| Usable As Signature Ability | Boolean | True if the ability can be used as a signature ability |
| Damage Types | Text | Damage types the ability deals |
| Inflicts | Text | Conditions or effects the ability inflicts |
| Number Of Targets | Number | Maximum number of targets |
| Weapon Attack | Boolean | True if the ability uses a weapon attack |

---

## Cast Fields

The `Cast` subject is available during ability resolution -- after the power roll is made
but while effects are being applied. It holds information about what happened in the current
roll and its results.

| Field | Type | Description |
|---|---|---|
| High Roll | Number | The higher of the two d10 results in the power roll |
| Low Roll | Number | The lower of the two d10 results |
| Natural Roll | Number | The raw total of both d10 results before any bonuses |
| Roll | Number | The final power roll result including all bonuses |
| Tier | Number | The power roll tier (1, 2, or 3) |
| Tier For Target | Number | The tier result for a specific target |
| Target Count | Number | Number of creatures targeted by this cast |
| Spaces Moved | Number | Squares moved during this ability (for movement-based effects) |
| Damage Dealt | Number | Total damage dealt in this cast |
| Damage Raw | Number | Damage before resistances and reductions |
| Healing | Number | Total healing done in this cast |
| Heal Roll | Number | The raw healing roll result |
| First Target | Creature | The first creature targeted |
| Primary Target | Creature | The primary target |
| Has Primary Target | Boolean | True if a primary target has been selected |
| Has Target | Boolean | True if at least one target was hit |
| Ability | Ability | The ability being cast (provides access to Ability fields) |
| Memory | Text | Arbitrary value stored during multi-step ability execution |
| Mode | Text | Cast mode identifier |
| Inflicted Conditions | Text | Conditions inflicted during this cast |
| Purged Conditions | Text | Conditions removed during this cast |
| Forced Movement Distance | Number | Total forced movement distance applied |
| Forced Movement Collision | Boolean | True if a forced movement collision occurred |
| Opportunity Attacks Triggered | Boolean | True if an opportunity attack was triggered |
| Heroic Resources Gained | Number | Heroic resources gained as a result of this cast |
| Number Of Added Creatures | Number | Creatures added to the encounter during this cast |
| Creature List Size | Number | Size of the creature list at this stage |
| Passes Potency | Function | Returns true if the cast passes potency: `Passes Potency(target, characteristic, potency)` |

---

## Path Fields

The `Path` subject is available in movement formula fields and movement trigger contexts.

| Field | Type | Description |
|---|---|---|
| Squares | Number | Number of squares moved |
| Shift | Boolean | True if the movement is a shift |
| Forced | Boolean | True if the movement is forced movement |
| Vertical Only | Boolean | True if the movement is vertical only |
| Distance To Creature | Function | Distance from the path to a given creature |

---

## Aura and Ongoing Effect Fields

The `Aura` subject (available in aura effect formulas) and ongoing effect context both expose
a single field:

| Field | Type | Description |
|---|---|---|
| Caster | Creature | The creature that created the aura or applied the ongoing effect |

This lets you access any creature field on the aura's creator. For example:

```
Aura.Caster.Level
```

---

## Global Functions

These functions are provided by the engine and can be used in targeting and filtering contexts.

### Friends(creatureA, creatureB)

Returns true if the two creatures are on the same side (both heroes, or both enemies).
Returns false if they are on opposing sides.

```
Friends(Target, Caster)
not Friends(Target, Caster)
```

Use this in a target filter to restrict an ability behavior to allies or enemies:

```
Friends(Target, Caster)        -- allies only
not Friends(Target, Caster)    -- enemies only
```

### Line of Sight(creatureA, creatureB)

Returns true if the two creatures have line of sight to each other. Uses token position data
from the map.

```
Line of Sight(Target, Caster)
```

---

## Dice Notation in Roll Fields

Roll fields such as damage rolls, power rolls, and resource quantities accept standard dice
notation in addition to GoblinScript expressions. Dice notation and GoblinScript can be
combined freely in the same formula -- for example, `2d10 + Might` is a valid roll field.

### Basic Notation

Write the number of dice, the letter `d`, and the number of faces: `2d10`, `3d6`, `1d8`.
Add a flat modifier with `+` or `-`: `2d10 + 4`, `3d6 - 1`.
Multiple dice pools can be combined: `2d6 + 1d4 + 3`.

### Keep and Drop

Control which dice count toward the total:

| Syntax | Effect |
|---|---|
| `4d6 keep 3` | Roll 4 dice, count only the highest 3 |
| `4d6 drop 1` | Roll 4 dice, discard the lowest 1 |
| `4d6 keep low 3` | Roll 4 dice, count only the lowest 3 |

Abbreviated forms are also accepted: `4d6k3` (keep highest 3), `4d6kl3` (keep lowest 3).

### Reroll

`reroll N` rerolls any die whose result is equal to or less than N. Each die rerolls at most
once.

```
3d6 reroll 2    -- reroll any die showing 1 or 2
2d10 reroll 1   -- reroll any die showing a 1
```

### Minimum Roll (Minroll)

`minroll N` sets a floor on individual die results -- no single die can count as less than N.
The minimum applies to the raw die value before adding flat modifiers.

```
2d10 minroll 4          -- each die counts as at least 4
2d10 + 4 minroll 4      -- each die counts as at least 4; minimum total result is 12
```

### Extra Dice

`extradie` adds one additional die matching the highest-face die already in the roll.

```
2d8 extradie    -- rolls 3d8 instead of 2d8
2d8 + 1d4 extradie    -- rolls 3d8 + 1d4
```

This is useful for abilities that grant a bonus die on a hit.

### Dice Count

`dicecount` evaluates to the number of dice in the roll as a plain number. This lets you
scale a modifier with the size of the roll.

```
3d8 + dicecount    -- 3d8 + 3
```

### Exploding Dice

`exploding` causes any die that shows its maximum value to roll again, adding the new
result. The extra die can itself explode.

```
2d6 exploding
```

### Alter

`alter` applies a GoblinScript expression to transform the dice pool itself. The expression
has access to four special variables:

| Variable | Meaning |
|---|---|
| `count` | Number of dice |
| `faces` | Number of faces per die |
| `modifier` | The flat modifier on the roll |
| `index` | The index of the current die (for per-die transforms) |

```
2d6 + 4 alter "(count*2) d faces + modifier"
-- Equivalent to rolling 4d6 + 4
```

`alter` is an advanced feature. Most abilities do not need it.

---

## Special Syntax

### Inline Text Substitution: `{expression}`

Wrap any GoblinScript expression in curly braces inside a text field (such as a description
or effect) to show its calculated value in-game. The braces and formula are replaced with the
evaluated result when displayed.

Basic usage:

```
The ability deals {2 * Reason} additional damage.
```

With a fallback value for when the expression cannot be evaluated:

```
The target can shift {Reason|a number of squares equal to your Reason score}.
```

If `Reason` is available, the displayed text shows the number. If not (for example in a
context where the Reason characteristic is undefined), the fallback text is shown instead:

```
The target can shift a number of squares equal to your Reason score.
```

Another example combining both in one line:

```
The ability deals {2 * Reason|double your Reason score in} additional damage.
```

### Parameter Pipe: `<<expression>>`

Used in **Standard Abilities** and **Invoke Ability** behaviors to pass a dynamic value as
a parameter.

**In a Standard Ability definition**, `<<parametername>>` marks a slot that must be filled
when the ability is invoked. For example, the Shift standard ability defines its range and
target filter as parameters:

```
range: "<<distance>>"
targetFilter: "<<targetfilter>>"
```

**In an Invoke Ability behavior**, you supply values for those parameters. You can pass a
fixed value or a GoblinScript expression:

```
distance: "3"
targetid: "<<Cast.Primary Target.ID>>"
```

This lets a multi-step ability pass runtime results (such as which creature was the primary
target, or how many squares were moved) into a follow-up step.

### Variable Binding: `where`

Defines a local alias for a sub-expression, which can make complex formulas more readable.

```
Stamina + x where x = 7
```

This is equivalent to `Stamina + 7`. The `where` clause is evaluated first and the alias
substituted throughout the expression.

---

## Where GoblinScript Can Be Used

The following field categories accept GoblinScript. These are the names of the formula fields
as they appear in the Codex editor.

### Filter and Condition Fields (return true or false)

| Field | What it controls |
|---|---|
| Target Filter | Which targets are valid for the ability overall |
| Filter Target | Which targets a specific behavior within an ability applies to |
| Activation Condition | When a modifier or trait is active |
| Display Condition | When a UI element or feature is shown |
| Filter Condition | Which resources or effects meet a filter |
| Filter Ability | Which abilities match a filter (e.g. for a modifier that applies to strikes) |
| Prerequisite | Whether an ability or option is available to the creature |
| Sustain Formula | Whether an ongoing effect continues at the start of the creature's turn |
| Condition Formula | A complex condition for trigger evaluation |

### Value and Calculation Fields (return a number)

| Field | What it controls |
|---|---|
| Value | A damage amount, healing amount, or stat modifier |
| Num | A count, duration, or quantity |
| Roll | A damage or healing roll formula (supports dice notation) |
| Stacks | How many stacks of a condition or effect to apply |
| Calculation | A generic calculated value |
| Formula | A generic formula result |
| Quantity | A quantity (used in resource and ability cost fields) |
| Damage Modifier | A bonus or penalty to damage |
| Potency Mod | A modifier to the potency of an effect |

### Text Fields with Embedded Formulas

Any of the following text fields can use `{expression}` substitution to show calculated
values inline:

`Description`, `Effect`, `Rule`, `Trigger Prompt`, `Prompt Text`, `Add Text`, `Replace Text`

---

## Real Examples from the Compendium

The following are real examples taken from the Draw Steel Codex compendium.

---

### Example 1: Targeting Filters Using Friends()

**Source:** Angulotl Slink (bestiary)

An ability that damages enemies but helps allies uses opposite target filters on two behaviors:

```yaml
behaviors:
  - __typeName: ActivatedAbilityPowerRollBehavior
    filterTarget: not Friends(Target, Caster)   # applies to enemies
    roll: 2d10 + Might or Agility
    tiers:
      - 3 damage; pull 3
      - 5 damage; pull 5
      - 7 damage; pull 6

  - __typeName: ActivatedAbilityDrawSteelCommandBehavior
    filterTarget: Friends(Target, Caster)        # applies to allies
    rule: Pull 6
```

`not Friends(Target, Caster)` targets enemies. `Friends(Target, Caster)` targets allies.
This is the standard pattern for abilities that affect multiple groups differently.

---

### Example 2: Level-Scaled Value

**Source:** Conduit class

A resource that changes at level 7:

```yaml
quantity: (1d3 + 1) when Level >= 7 else (1d3)
```

**Source:** Shadow class

A slot count that grows at level 4:

```yaml
quantity: 1 + (1 when Level >= 4)
```

At level 1-3 this returns 1. At level 4+ it returns 2. The additive `when` pattern is useful
when a value increases at several level thresholds -- each threshold adds its own bonus
independently. The table mode in the formula editor produces the same result and may be
easier to manage for features with many level milestones.

---

### Example 3: Cast Fields in Action

**Source:** Bugbear Roughneck (bestiary)

An ability that deals damage equal to twice the squares moved during the ability:

```yaml
- __typeName: ActivatedAbilityDamageBehavior
  roll: Cast.Spaces Moved * 2
```

The same ability uses the parameter pipe to pass the primary target and spaces moved to
follow-up steps via an Invoke Ability behavior:

```yaml
- __typeName: ActivatedAbilityInvokeAbilityBehavior
  targetid: "<<Cast.Primary Target.ID>>"

- __typeName: ActivatedAbilityInvokeAbilityBehavior
  spacesmoved: "<<Cast.Spaces Moved>>"
```

---

### Example 4: Inline Text Substitution with Fallback

**Source:** Tactician class

An effect description that embeds a calculated value with a fallback:

```yaml
effect: The target can shift {Reason|a number of squares equal to your Reason score}.
```

When displayed for a character with Reason 3, this reads: `The target can shift 3.`
If the Reason score is unavailable in the current context, the fallback reads:
`The target can shift a number of squares equal to your Reason score.`

---

### Example 5: Activation Condition Using a Custom Attribute

**Source:** Demon Bendrak (bestiary)

A modifier that activates only while the creature is winded:

```yaml
name: Lethe
description: While winded, the bendrak has an edge on strikes, and strikes have an edge against them.
activationCondition: Self.Winded = 1
```

`Winded` is a custom attribute whose default value calculates `Stamina <= Maximum Stamina / 2`.
The same modifier also appears with `Target.Winded = 1` to apply an edge when attacking a
winded creature -- the subject changes, but the field is the same.

---

*This guide covers the GoblinScript symbols and syntax confirmed in the Draw Steel Codex as
of the current compendium version. For the full list of custom attribute symbols, open the
Custom Attributes table in the compendium or use the in-app formula documentation panel.*
