local mod = dmhub.GetModLoading()
--- @class CharacterDescription
--- @field weight string
--- @field height string
--- @field hair string
--- @field eyes string
--- @field skinTone string
--- @field build string
--- @field genderPresentation string
--- @field pronouns string
--- @field physicalFeatures string
CharacterDescription = RegisterGameType("CharacterDescription")
CharacterDescription.__index = CharacterDescription

CharacterDescription.CHARACTER_KEY = "characterDescription"

function CharacterDescription:new()
    local instance = setmetatable({}, self)

    instance.weight = ""
    instance.height = ""
    instance.hair = ""
    instance.eyes = ""
    instance.skinTone = ""
    instance.build = ""
    instance.genderPresentation = ""
    instance.pronouns = ""
    instance.physicalFeatures = ""

    return instance
end

function CharacterDescription:SetWeight(weight)
    self.weight = weight
    return self
end

function CharacterDescription:GetWeight()
    return self:try_get("weight")
end

function CharacterDescription:SetHeight(height)
    self.height = height
    return self
end

function CharacterDescription:GetHeight()
    return self:try_get("height")
end

function CharacterDescription:SetHair(hair)
    self.hair = hair
    return self
end

function CharacterDescription:GetHair()
    return self:try_get("hair")
end

function CharacterDescription:SetEyes(eyes)
    self.eyes = eyes
    return self
end

function CharacterDescription:GetEyes()
    return self:try_get("eyes")
end

function CharacterDescription:SetSkinTone(skinTone)
    self.skinTone = skinTone
    return self
end

function CharacterDescription:GetSkinTone()
    return self:try_get("skinTone")
end

function CharacterDescription:SetBuild(build)
    self.build = build
    return self
end

function CharacterDescription:GetBuild()
    return self:try_get("build")
end

function CharacterDescription:SetGenderPresentation(genderPresentation)
    self.genderPresentation = genderPresentation
    return self
end

function CharacterDescription:GetGenderPresentation()
    return self:try_get("genderPresentation")
end

function CharacterDescription:SetPronouns(pronouns)
    self.pronouns = pronouns
    return self
end

function CharacterDescription:GetPronouns()
    return self:try_get("pronouns")
end

function CharacterDescription:SetPhysicalFeatures(physicalFeatures)
    self.physicalFeatures = physicalFeatures
    return self
end

function CharacterDescription:GetPhysicalFeatures()
    return self:try_get("physicalFeatures")
end

character.Description = function(self)
    local desc = self:get_or_add(CharacterDescription.CHARACTER_KEY, CharacterDescription:new())
    return desc
end
