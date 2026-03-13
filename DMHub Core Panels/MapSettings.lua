local mod = dmhub.GetModLoading()

setting{
	id = "truediagonals",
	classes = {"dmonly"},
	description = "True Diagonals",
	help = "Count diagonals as 1.5 spaces",
	storage = "game", 
	section = "game",

	editor = "check",
	default = true, 
}

setting{
	id = "maxlookup",
	description = "Max Look Up",
	help = "The maximum number of floors a creature can look up on this map",
	storage = "map",
	editor = "dropdown",
	default = -1,
	enum = {
		{ value = 0, text = "None" },
		{ value = 1, text = "One floor" },
		{ value = 2, text = "Two floors" },
		{ value = 3, text = "Three floors" },
		{ value = 4, text = "Four floors" },
		{ value = 5, text = "Five floors" },
		{ value = -1, text = "Unlimited floors" },
	},
}

local CreateMapSettings
local CreateEditorSettings

DockablePanel.Register{
	name = "Map Settings",
	icon = "icons/standard/Icon_App_MapSettings.png",
	vscroll = true,
    dmonly = true,
	minHeight = 100,
	content = function()
		return CreateMapSettings()
	end,
}

DockablePanel.Register{
	name = "Editor Settings",
	folder = "Map Editing",
	icon = mod.images.editorSettingsIcon,
	vscroll = true,
    dmonly = true,
	minHeight = 100,
	content = function()
		return CreateEditorSettings()
	end,
}



local SettingsPanelHeight = 30

CreateMapSettings = function()

	local contentPanel = gui.Panel{
		id = "mapSettingsPanel",
		flow = "vertical",
		style = {
			pivot = { x = 0, y = 1 },
			width = '100%',
			height = 'auto',
		},
        styles = {
            {
                selectors = {"dropdown"},
                priority = 5,
                width = 200,
            }
        },
		children = {
			CreateSettingsEditor('gridcolor'),
			CreateSettingsEditorsForSection('vision'),

			CreateSettingsEditor("maplayout:tiletype"),
			CreateSettingsEditor("maplayout:stagger"),
			CreateSettingsEditor("maplayout:tilewidth"),
			CreateSettingsEditor("maplayout:tileheight"),
			CreateSettingsEditor("maplayout:hexslant"),

			CreateSettingsEditor("editor:showpathfinding"),
			CreateSettingsEditor("maxlookup"),
		},
	}

	return contentPanel

end

CreateEditorSettings = function()

	local contentPanel = gui.Panel{
		flow = "vertical",
		style = {
			pivot = { x = 0, y = 1 },
			width = '100%',
			height = 'auto',
		},
		children = {
			CreateSettingsEditorsForSection('editor'),
			CreateSettingsEditor('dm:showinvisibletokens'),
			CreateSettingsEditor('arrowcolor'),

		},
	}

	return contentPanel
end
