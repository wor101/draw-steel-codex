local mod = dmhub.GetModLoading()

--- @class follower
--- @field follower.availableRolls number
--- @field follower.followerType string artisan|sage|retainer
follower = RegisterGameType("follower", "monster")

follower.availableRolls = 0

function follower.CreateNew(followerType)
    local result = follower.new{
		cr = 1,

        followerType = followerType or "artisan",
        availableRolls = 0,

		monster_type = 'Monster', --this is the specific type of monster. e.g. Adult Black Dragon
		monster_category = 'Monster', --this is the "Type" of monster. e.g. Dragon


		damage_taken = 0,
		max_hitpoints = 10,

		attributes = creature.CreateAttributes(),

		walkingSpeed = 5,

        equipment = {
            mainhand1 = "22ab52f5-955b-40c8-80c3-826f823e0a5b",
        },

		--map of skill id -> rating for that skill. 'true' means the monster is proficient and use proficiency bonus.
		skillRatings = {
		},

		--map of saving throw -> rating for that saving throw.
		savingThrowRatings = {
		},

		--list of innate attacks (type = AttackDefinition)
		innateAttacks = {
		},
	}

	return result
end

function creature:EnsureFollowers()
    return {}
end

--Create Follower table if it does not exist
---@return table[] table of followers as charid is true
function character:EnsureFollowers()
    local followers = self:try_get("followers")
    if not followers then
        self.followers = {}
    end
    return self.followers
end

---@param followerid string
function character:AddFollowerToMentor(followerid)
    local token = dmhub.LookupToken(self)
    token:ModifyProperties{
        description = "Assign Follower",
        execute = function()
            local followers = self:EnsureFollowers()
            followers[followerid] = true
        end,
    }
end

---@param mentorToken Token[]
---@param followerid string
function character:RemoveFollowerFromMentor(followerid)
    local token = dmhub.LookupToken(self)
    token:ModifyProperties{
        description = "Remove Follower",
        execute = function()
            local followers = self:EnsureFollowers()
            followers[followerid] = nil
        end,
    }
end

---@param followerInfo table 
---@param followerType string artisan, sage, premaderetainer, existing
---@param mentorToken Token[]
---@param pregenRetainerId string|nil optional data for creating a pre-made retainer
CreateFollowerMonster = function(followerInfo, followerType, mentorToken, pregenRetainerId)
    if followerType == "existing" then
        AddFollowerToMentor(mentorToken, followerInfo.followerToken)
        return
    end

    local locs = mentorToken.properties:AdjacentLocations()
    local loc = #locs and locs[1] or mentorToken.properties.locsOccupying[1]
    local newCharId

    dmhub.Coroutine(function()
        if pregenRetainerId then
            newMonster = game.SpawnTokenFromBestiaryLocally(pregenRetainerId, loc, {fitLocatoin = true})
            newCharId = newMonster.charid
            newMonster.ownerId = mentorToken.ownerId
            newMonster.partyId = mentorToken.partyId

            newMonster.name = followerInfo.name
            newMonster:UploadToken()
            game.UpdateCharacterTokens()
        else
            newCharId = game.CreateCharacter("follower")
            for i = 1, 100 do
                local newMonster = dmhub.GetCharacterById(newCharId)
                if newMonster ~= nil then
                    newMonster.properties = follower.CreateNew(followerInfo.type)
                    local monster = newMonster.properties

                    newMonster.name = followerInfo.name
                    monster.role = "Follower"
                    monster.followerType = followerInfo.type
                    monster.creatureTemplates = {}
                    monster.creatureTemplates[#monster.creatureTemplates + 1] = "25263715-cef4-4e25-b4bd-ddedc3a87dea"

                    if followerInfo.type ~= "retainer" then
                        monster.attributes["rea"].baseValue = 1
                        if monster.followerType == "sage" then
                            monster.attributes["inu"].baseValue = 1
                        elseif monster.followerType == "artisan" then
                            monster.attributes[followerInfo.characteristic].baseValue = 1
                        end
                    end

                    local ancestryTable = dmhub.GetTable(Race.tableName)
                    local ancestry = ancestryTable[followerInfo.ancestry]
                    local bandTable = dmhub.GetTable(MonsterGroup.tableName)
                    for id, band in pairs(bandTable) do
                        if string.lower(band.name) == string.lower(ancestry.name) then
                            monster.groupid = id
                            monster.keywords = {}
                            monster.keywords[band.name] = true
                        end
                    end

                    newMonster.ownerId = mentorToken.ownerId
                    newMonster.partyId = mentorToken.partyId
                    newMonster:UploadToken()
                    game.UpdateCharacterTokens()
                    newMonster:ChangeLocation(core.Loc{x = loc.x, y = loc.y})
                    break
                end
                coroutine.yield(0.1)
            end
        end
        local newMonster = dmhub.GetTokenById(newCharId)
        AddFollowerToMentor(mentorToken, newMonster.id)
        
        newMonster:ShowSheet()
    end)

end


function Follower.Create()
    return Follower.new{
        guid = dmhub.GenerateGuid(),
        ancestry = Race.DefaultRace(),
        skills = {},
        languages = {},
        assignedTo = {},
    }
end

function Follower.GetType(self)
    return self:try_get("type", "artisan")
end

function Follower:AddAssignedTo(tokenId, followerGuid)
    local assignedTo = self:get_or_add("assignedTo", {})
    assignedTo[tokenId] = followerGuid
    return self
end

function Follower:RemoveAssignedTo(tokenId)
    local assignedTo = self:get_or_add("assignedTo", {})
    assignedTo[tokenId] = nil
    return self
end

function Follower.Describe(self)

    local function ucFirst(s)
        return s:sub(1,1):upper() .. s:sub(2)
    end
    local function numToString(v)
        local n = tonumber(v)
        if n then
            return string.format("%d", math.floor(n))
        end
        return "?"
    end

    local type = self:GetType()
    local s = string.format("<b>%s Follower</b>", ucFirst(type))

    if self.type == "artisan" or self.type == "sage" then
        if self:try_get("ancestry") then
            s = s .. "\n<b>Ancestry:</b> "
            s = s .. dmhub.GetTable(Race.tableName)[self.ancestry].name
        end

        if self.skills and next(self.skills) then
            s = s .. "\n<b>Skills:</b> "
            local sList = ""
            local skills = dmhub.GetTable(Skill.tableName)
            for id, _ in pairs(self.skills) do
                if #sList > 0 then sList = sList .. ", " end
                sList = sList .. skills[id].name
            end
            s = s .. sList
        end

        if self.languages and next(self.languages) then
            s = s .. "\n<b>Languages:</b> "
            local sList = ""
            local langs = dmhub.GetTable(Language.tableName)
            for id, _ in pairs(self.languages) do
                if #sList > 0 then sList = sList .. ", " end
                sList = sList .. langs[id].name
            end
            s = s .. sList
        end
    else
        local id = self.followerToken or ""
        if id and #id > 0 then
            local node = assets:GetMonsterNode(id)
            if node and node.monster and node.monster.info then
                local t = node.monster.info
                s = string.format("%s\n%s", s, t.description)
                if t.properties then
                    local m = t.properties

                    local keywords = m:Keywords()
                    if keywords and next(keywords) then
                        local keys = {}
                        for key, value in pairs(keywords) do
                            if value then
                                keys[#keys + 1] = key
                            end
                        end
                        s = string.format("%s\n%s", s, table.concat(keys, ", "))
                    end

                    local level = numToString(m:Level())
                    local role = m:Role() or "Retainer"
                    s = string.format("%s\nLevel %s %s", s, level, ucFirst(role))

                    local stam = numToString(m.max_hitpoints)
                    local speed = numToString(m.walkingSpeed)
                    s = string.format("%s\n%s Stamina, %s Speed", s, stam, speed)
                end
            end
        end
    end

    local assignedTo = self:get_or_add("assignedTo", {})
    local atl = ""
    for tokenId,_ in pairs(assignedTo) do
        local t = dmhub.GetTokenById(tokenId)
        if t and t.name and #t.name > 0 then
            if #atl > 0 then 
                atl = atl ..  ", "
            else
                atl = "<b>Assigned To:</b> "
            end
            atl = atl .. t.name
        end
    end
    if #atl > 0 then
        s = string.format("%s\n\n%s", s, atl)
    end

    return s
end

function Follower.ToTable(self)
    local newFollower = {
        guid = dmhub.GenerateGuid(),
        type = self.type,
        name = self.name or "New Follower",
        characteristic = self.characteristic or "mgt",
        skills = self:try_get("skills", {}),
        ancestry = self.ancestry or "",
        portrait = self.portrait or "",
        languages = self:try_get("languages", {}),
        followerToken = self.followerToken or "",
        availableRolls = self.availableRolls or 0,
    }
    return newFollower
end

local function buildSkillLists()
    local skills = dmhub.GetTable(Skill.tableName) or {}
    local artisanSkills = {}
    local sageSkills = {}

    for id, skill in unhidden_pairs(skills) do
        if skill.category == "crafting" then
            artisanSkills[#artisanSkills + 1] = {
                id = id,
                text = skill.name,
            }
        elseif skill.category == "lore" then
            sageSkills[#sageSkills + 1] = {
                id = id,
                text = skill.name,
            }
        end
    end

    table.sort(artisanSkills, function(a,b)
        return string.lower(a.text) < string.lower(b.text)
    end)

    table.sort(sageSkills, function(a,b)
        return string.lower(a.text) < string.lower(b.text)
    end)

    return artisanSkills, sageSkills
end

local function buildLanguageList()
    return Language.GetDropdownList()
end

function buildRetainerList()
    local retainerTypes = { { id = "none", text = "Select retainer type...", }, }
    local retainerLookup = {}

    local function processNode(node)
        if node then
            if node.monster then
                local m = node.monster
                if m.info and m.info.properties and m.info.properties:IsRetainer() then
                    retainerTypes[#retainerTypes + 1] = {
                        id = node.id,
                        text = m.info.description
                    }
                    retainerLookup[node.id] = m.info.description
                end
            else
                for _,n in pairs(node.children) do
                    processNode(n)
                end
            end
        end
    end

    processNode(assets:GetMonsterNode(""))

    return retainerTypes, retainerLookup
end

local DialogStyles = {
    gui.Style{
        selectors = { "avatarPanel"},
        borderColor = Styles.textColor,
        borderWidth = 2,
        width = 90,
        height = 120,
        halign = "left",
        valign = "top",
        bgcolor = "white",
    },
    gui.Style{
        selectors = { "followerLabel"},
        height = 25,
        minWidth = 120,
        valign = "center",
        fontSize = 20,
        bold = true,
        fontFace = "Berling",
    },
    gui.Style{
        selectors = { "followersListLabel"},
        height = 20,
        width = 180,
        valign = "center",
        fontSize = 16,
        fontFace = "Berling",
    },
    gui.Style{
        selectors = { "followerDropdown"},
        width = 190,
        valign = "top",
        fontFace = "Berling",
    },
    gui.Style{
        selectors = { "followerMultiselect" },
        valign ="top",
        fontFace = "Berling",
    },
    gui.Style{
        selectors = { "followerNameLabel"},
        width = "50%",
        height = 25,
        fontSize = 32,
        bold = true,
        color = Styles.textColor,
        fontFace = "Berling",
    },
    gui.Style{
        selectors = {"saveButton"},
        fontSize = 22,
        textAlignment = "center",
        bold = true,
        height = 35,
    }
}

function Follower:CreateEditorDialog(options)
    local types = {
        {id = "artisan", text = "Artisan"},
        {id = "retainer", text = "Retainer"},
        {id = "sage", text = "Sage"},
    }
    local chars = {
        {id = "mgt", text = "Might"},
        {id = "agl", text = "Agility"},
    }
    local artisanSkills, sageSkills = buildSkillLists()
    local languages = buildLanguageList()
    local retainerTypes, retainerLookup = buildRetainerList()

    local editorPanel

    local namePanel = gui.Label {
        classes = {"followerNameLabel"},
        halign = "left",
        text = self.name or "Unnamed",
        editable = true,
        edit = function(element)
            element:FireEvent("change")
        end,
        change = function(element)
            self.name = element.text
        end,
        refreshAll = function(element)
            element.text = self.name or "Unnamed"
        end
    }

    local typePanel = gui.Panel {
        flow = "horizontal",
        width = "auto",
        height = 30,
        margin = 3,
        halign = "left",
        valign = "top",
        children = {
            gui.Label {
                classes = {"followerLabel"},
                width = 80,
                height = "auto",
                text = "Type:",
                halign = "left",
                valign = "top",
                fontSize = 20,
            },
            gui.Dropdown {
                halign = "left",
                valign = "top",
                options = types,
                idChosen = self.type,
                change = function(element)
                    if self.type ~= element.idChosen then
                        self.skills = {}
                        self.type = element.idChosen
                        editorPanel:FireEventTree("refreshAll")
                    end
                end,
            }
        }
    }

    local avatarPanel = gui.Panel {
        halign = "left",
        valign = "top",
        flow = "vertical",
        height = "auto",
        width = "auto",
        children = {
            gui.IconEditor {
                classes = { "avatarPanel" },
                library = "Avatar",
                restrictImageType = "Avatar",
                allowPaste = true,
                value = self.portrait or false,
                refreshAll = function(element)
                    if self:try_get("followerToken") then
                        local node = assets:GetMonsterNode(self.followerToken)
                        if node and node.monster then
                            self.portrait = node.monster.info.portrait
                            element.value = self.portrait
                        end
                    else
                        element.value = self.portrait or false
                    end
                end,
                change = function(element)
                    self.portrait = element.value
                end
            },
        },
    }

    local ancestryPanel = gui.Panel {
        classes = {cond(self.type == "retainer", "collapsed-anim")},
        flow = "horizontal",
        width = "auto",
        height = 30,
        margin = 3,
        halign = "left",
        valign = "top",
        refreshAll = function(element)
            element:SetClass("collapsed-anim", self.type == "retainer")
        end,
        children = {
            gui.Label {
                classes = {"followerLabel"},
                width = "auto",
                height = 30,
                text = "Ancestry:",
                halign = "left",
                valign = "top",
                fontSize = 20,
            },
            gui.Dropdown {
                options = Race.GetDropdownList(),
                idChosen = self:try_get("ancestry"),
                textDefault = "Select an ancestry...",
                change = function(element)
                    self.ancestry = element.idChosen
                end,
            }
        }
    }

    local characteristicPanel = gui.Panel {
        classes = {cond(self.type ~= "artisan", "collapsed-anim")},
        flow = "horizontal",
        width = "auto",
        height = 30,
        margin = 3,
        halign = "left",
        valign = "top",
        refreshAll = function(element)
            element:SetClass("collapsed-anim", self.type ~= "artisan")
        end,
        children = {
            gui.Label {
                classes = {"followerLabel"},
                width = "auto",
                height = 30,
                text = "Characteristic:",
                halign = "left",
                valign = "top",
                fontSize = 20,
            },
            gui.Dropdown {
                options = chars,
                idChosen = self:try_get("characteristic"),
                textDefault = "Select a characteristic...",
                change = function(element)
                    self.characteristic = element.idChosen
                end,
            }
        }
    }

    local skillsPanel = gui.Panel {
        classes = {cond(self.type == "retainer", "collapsed-anim")},
        flow = "vertical",
        width = "100%-100",
        height = "auto",
        margin = 3,
        halign = "left",
        valign = "top",
        refreshAll = function(element)
            element:SetClass("collapsed-anim", self.type == "retainer")
        end,
        children = {
            gui.Multiselect {
                id = "skillSelector",
                options = self.type == "sage" and sageSkills or artisanSkills,
                width = "100%",
                valign = "top",
                halign = "left",
                vmargin = 4,
                textDefault = "Select 4 skills...",
                sort = true,
                flow = "horizontal",
                chipPos = "right",
                dropdown = {
                    classes = {"followerMultiselect"},
                    width = 160,
                },
                chipPanel = {
                    width = "100%-160",
                    halign = "left",
                },
                chips = {
                    halign = "left",
                },
                create = function(element)
                    element:FireEvent("refreshAll")
                end,
                change = function(element)
                    self.skills = element.value
                end,
                refreshAll = function(element)
                    local opts = self.type == "sage" and sageSkills or artisanSkills
                    local selected = self:try_get("skills", {}) 
                    element:FireEvent("refreshSet", opts, selected)
                    element.value = selected
                end,
            },
        }
    }

    local languagesPanel = gui.Panel {
        classes = {cond(self.type == "retainer", "collapsed-anim")},
        flow = "vertical",
        width = "100%-100",
        height = "auto",
        margin = 3,
        halign = "left",
        valign = "top",
        refreshAll = function(element, info)
            element:SetClass("collapsed-anim", self.type == "retainer")
        end,
        children = {
            gui.Multiselect {
                options = languages,
                width = "100%",
                valign = "top",
                halign = "left",
                vmargin = 4,
                textDefault = "Select 2 languages...",
                sort = true,
                flow = "horizontal",
                chipPos = "right",
                dropdown = {
                    classes = {"followerMultiselect"},
                    width = 160,
                },
                chipPanel = {
                    width = "100%-160",
                    halign = "left",
                },
                chips = {
                    halign = "left",
                },
                create = function(element)
                    element.value = self:try_get("languages", {})
                end,
                change = function(element)
                    self.languages = element.value
                end,
                refreshAll = function(element, info)
                    element.value = self:try_get("languages", {})
                end,
            }
        }
    }

    local retainersPanel = gui.Panel {
        classes = {cond(self.type ~= "retainer", "collapsed-anim")},
        flow = "vertical",
        width = "auto",
        height = "auto",
        margin = 3,
        halign = "left",
        valign = "top",
        refreshAll = function(element)
            element:SetClass("collapsed-anim", self.type ~= "retainer")
        end,
        children = {
            gui.Label {
                classes = {"followerLabel"},
                width = "auto",
                height = 30,
                text = "Retainer:",
                halign = "left",
                valign = "top",
                fontSize = 20,
            },
            gui.Dropdown {
                options = retainerTypes,
                idChosen = self:try_get("followerToken", "none"),
                change = function(element)
                    self.followerToken = element.idChosen
                    editorPanel:FireEventTree("refreshAll")
                end
            }
        }
    }

    local headerPanel = gui.Panel {
        halign = "left",
        valign = "top",
        width = "100%",
        height = "auto",
        children = {
            namePanel,
            gui.CloseButton {
                halign = "right",
                valign = "top",
                press = function()
                    editorPanel:DestroySelf()
                end
            },
        }
    }

    editorPanel = gui.Panel {
        styles = DialogStyles,
        classes = {"editorPanel"},

        halign = "center",
        valign = "center",
        width = 680,
        height = 320,
        hmargin = 12,
        vmargin = 12,
        flow = "vertical",

        children = {
            gui.Panel {
                classes = {"framedPanel"},
                styles = { Styles.Default, Styles.Panel },
                halign = "center",
                width = "100%",
                height = "100%",
                hpad = 20,
                flow = "vertical",

                children = {

                    headerPanel,

                    gui.Panel {
                        valign = "top",
                        halign = "left",
                        flow = "horizontal",
                        width = "100%",
                        height = "auto",
                        margin = 4,
                        children = {
                            avatarPanel,
                            gui.Panel {
                                flow = "vertical",
                                width = "auto",
                                height = "auto",
                                halign = "left",
                                valign = "top",
                                hpad = 20,
                                children = {
                                    typePanel,
                                    ancestryPanel,
                                    characteristicPanel,
                                    retainersPanel,
                                    gui.Panel {
                                        flow = "vertical",
                                        width = "auto",
                                        height = "auto",
                                        valign = "top",
                                        halign = "left",
                                        children = {
                                            skillsPanel,
                                            languagesPanel
                                        }
                                    }
                                }
                            }
                        }
                    },

                    gui.Button {
                        classes = {"saveButton"},
                        text = "Save",
                        halign = "Center",
                        valign = "Bottom",
                        press = function(element)
                            if options.save and type(options.save) == "function" then
                                options.save()
                            end
                            element:FindParentWithClass("editorPanel"):DestroySelf()
                        end,
                    }

                }
            }
        }
    }

    GameHud.instance.documentsPanel:AddChild(editorPanel)
end