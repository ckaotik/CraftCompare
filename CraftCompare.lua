local addonName, addon, _ = 'CraftCompare', {}
_G[addonName] = addon
addon.name = addonName

--[[-- TODO --
* Deconstruction should show item tooltip + comparison popup
* don't overwrite user tooltip positions
--]]

-- GLOBALS: _G, SMITHING, LINK_STYLE_DEFAULT, SI_FORMAT_BULLET_SPACING, SI_TOOLTIP_ITEM_NAME
-- GLOBALS: LibStub, PopupTooltip, ItemTooltip, ItemTooltipTopLevel, ComparativeTooltip1, ComparativeTooltip2, ZO_PreHook, ZO_PreHookHandler, ZO_SavedVars, ZO_SmithingTopLevel, ZO_ListDialog1
-- GLOBALS: GetItemLink, GetSmithingPatternResultLink, GetSmithingImprovedItemLink, GetComparisonEquipSlotsFromItemLink, GetWindowManager, GetString, GetItemLinkInfo, GetInterfaceColor, IsShiftKeyDown, ZO_PlayShowAnimationOnComparisonTooltip, ZO_Tooltips_SetupDynamicTooltipAnchors, ZO_ItemTooltip_SetEquippedInfo, ZO_Tooltip_AddDivider, ZO_Inventory_GetBagAndIndex, LocalizeString
-- GLOBALS: unpack, type, moc, zo_strjoin, zo_callLater

local SMITHING_MODE_EXTRACT = 1
local SMITHING_MODE_CREATE = 2
local SMITHING_MODE_IMPROVE = 3
local SMITHING_MODE_DECONSTRUCT = 4
local SMITHING_MODE_RESEARCH = 5

local function L(text)
	if type(text) == 'number' then
		-- get the string from this constant
		text = GetString(text)
	end
	return zo_strformat(SI_TOOLTIP_ITEM_NAME, text)
end

-- ========================================================
--  Settings
-- ========================================================
local function GetSetting(setting)
	return addon.db and addon.db[setting]
end
local function SetSetting(setting, value)
	if addon.db then
		addon.db[setting] = value
	end
end

local function CreateSettings()
	local LAM = LibStub:GetLibrary('LibAddonMenu-1.0')
	local panel = LAM:CreateControlPanel(addonName..'Settings', addonName)

	-- modes to display tooltips for
	LAM:AddHeader(panel, addonName..'HeaderModes', 'Compare in crafting mode')
	LAM:AddCheckbox(panel, addonName..'ToggleCreate',
		'Creation', 'Enable item comparison when in "Creation" mode',
		function() return GetSetting('compareMode'..SMITHING_MODE_CREATE) end, function(value) SetSetting('compareMode'..SMITHING_MODE_CREATE, value) end)
	LAM:AddCheckbox(panel, addonName..'ToggleImprove',
		'Improvement', 'Enable item comparison when in "Improvement" mode',
		function() return GetSetting('compareMode'..SMITHING_MODE_IMPROVE) end, function(value) SetSetting('compareMode'..SMITHING_MODE_IMPROVE, value) end)
	LAM:AddCheckbox(panel, addonName..'ToggleDeconstruct',
		'Deconstruction', 'Enable item comparison when in "Deconstruction" mode',
		function() return GetSetting('compareMode'..SMITHING_MODE_DECONSTRUCT) end, function(value) SetSetting('compareMode'..SMITHING_MODE_DECONSTRUCT, value) end)
	LAM:AddCheckbox(panel, addonName..'ToggleResearch',
		'Research', 'Enable item comparison when in "Research" mode',
		function() return GetSetting('compareMode'..SMITHING_MODE_RESEARCH) end, function(value) SetSetting('compareMode'..SMITHING_MODE_RESEARCH, value) end)
	LAM:AddDescription(panel, addonName..'CompareHint',
		'|cFFFFB0'..'Hold down SHIFT to compare to your alternate weapon set.'..'|r', '|cFFFFB0'..'Hint'..'|r')

	-- tooltip mode
	LAM:AddHeader(panel, addonName..'HeaderTTStyle', 'Tooltip Style')
	LAM:AddCheckbox(panel, addonName..'ToggleInfo',
		'Item Details', 'Enable display of item details such as item style',
		function() return GetSetting('showInfo') end, function(value) SetSetting('showInfo', value) end)
	LAM:AddDropdown(panel, addonName..'TTStyleDeconstruct',
		'Deconstruct', nil,
		{'PopupTooltip', 'ComparativeTooltip'},
		function(...) return GetSetting('tooltipMode'..SMITHING_MODE_DECONSTRUCT) end, function(value) SetSetting('tooltipMode'..SMITHING_MODE_DECONSTRUCT, value) end)
	LAM:AddDropdown(panel, addonName..'TTStyleResearch',
		'Research', nil,
		{'PopupTooltip', 'ComparativeTooltip'},
		function(...) return GetSetting('tooltipMode'..SMITHING_MODE_RESEARCH) end, function(value) SetSetting('tooltipMode'..SMITHING_MODE_RESEARCH, value) end)
	LAM:AddDescription(panel, addonName..'Description', 'PopupTooltip can be moved and closed.\nComparativeTooltip is attached to the normal item tooltip.', nil)
end

-- ========================================================
--  Functionality
-- ========================================================
local function GetValidSmithingItemLink(patternIndex)
	local materialIndex, styleIndex, traitIndex = 1, 1, 1
	local materialQuantity = 1
	if not patternIndex then
		-- this is a crafting process
		patternIndex, materialIndex, materialQuantity, styleIndex, traitIndex = SMITHING.creationPanel:GetAllCraftingParameters()
	end

	-- for some obscure reason, API tries using too few mats sometimes
	while materialQuantity <= 100 do
		-- assumption: crafting and research share the same indices for the same slots
		local itemLink = GetSmithingPatternResultLink(patternIndex, materialIndex, materialQuantity, styleIndex, traitIndex, LINK_STYLE_DEFAULT)
		materialQuantity = materialQuantity + 1
		if itemLink and itemLink ~= '' then
			return itemLink
		end
	end
end

local function AddCraftingItemInfo(tooltip, itemLink, slot)
	local font = 'ZoFontWinT2'
	local r, g, b, a = GetInterfaceColor(_G.INTERFACE_COLOR_TYPE_ATTRIBUTE_TOOLTIP)
	local separator = ' '..GetString(SI_FORMAT_BULLET_SPACING)

	local texture, sellPrice, canUse, equipType, itemStyle = GetItemLinkInfo(itemLink)

	-- update item icon
	local icon = tooltip:GetNamedChild('Icon')
	if icon then
		local hidden = not texture
		tooltip:GetNamedChild('FadeLeft'):SetHidden(hidden)
    	tooltip:GetNamedChild('FadeRight'):SetHidden(hidden)

		icon:SetHidden(hidden)
		if not hidden then
			icon:SetTexture(texture)
		end
	end

	-- update equipped info
	if slot then
		ZO_ItemTooltip_SetEquippedInfo(tooltip, slot)
	end

	if not GetSetting('showInfo') then return end

	-- show item style
	ZO_Tooltip_AddDivider(tooltip)
	tooltip:AddLine(zo_strjoin(separator, L(_G['SI_ITEMSTYLE'..itemStyle])), font, r, g, b)
	-- tooltip:AddHeaderLine(GetString(_G['SI_ITEMSTYLE'..itemStyle]), 'ZoFontWinT2', 1, _G.TOOLTIP_HEADER_SIDE_RIGHT, GetInterfaceColor(_G.INTERFACE_COLOR_TYPE_ATTRIBUTE_TOOLTIP))
end

local alternateSlot = {
	[_G.EQUIP_SLOT_MAIN_HAND]   = _G.EQUIP_SLOT_BACKUP_MAIN,
	[_G.EQUIP_SLOT_BACKUP_MAIN] = _G.EQUIP_SLOT_MAIN_HAND,
	[_G.EQUIP_SLOT_OFF_HAND]    = _G.EQUIP_SLOT_BACKUP_OFF,
	[_G.EQUIP_SLOT_BACKUP_OFF]  = _G.EQUIP_SLOT_OFF_HAND,
}
local function ShowCraftingComparisons(slot, otherSlot, tooltip, otherTooltip)
	if IsShiftKeyDown() then
		slot = alternateSlot[slot]
		otherSlot = alternateSlot[otherSlot]
	end

	local itemLink = slot and GetItemLink(_G.BAG_WORN, slot, LINK_STYLE_DEFAULT)
	if not itemLink or itemLink == '' then return end

	-- handle primary tooltip
	tooltip = tooltip or PopupTooltip
	tooltip:ClearLines()
	tooltip:SetHidden(false)
	tooltip:SetLink(itemLink)

	-- additional information
	AddCraftingItemInfo(tooltip, itemLink, slot)

	-- handle secondary tooltip
	local otherLink = otherSlot and GetItemLink(_G.BAG_WORN, otherSlot, LINK_STYLE_DEFAULT)
	if otherLink and otherLink ~= '' then
		otherTooltip = otherTooltip or addon.tooltip
		otherTooltip:ClearLines()
		otherTooltip:SetHidden(false)
		otherTooltip:SetLink(otherLink)

		-- additional information
		AddCraftingItemInfo(otherTooltip, otherLink, otherSlot)
	else
		-- unset so return values have meaning
		otherTooltip = nil
	end

	return tooltip, otherTooltip
end

local function UpdateComparativeTooltips()
	local button = moc() and moc():GetNamedChild('Button')
	if button then
		local bag, slot = ZO_Inventory_GetBagAndIndex(button)
		if not bag or not slot then return end
		local itemLink = GetItemLink(bag, slot)
		local slot, otherSlot = GetComparisonEquipSlotsFromItemLink(itemLink or '')

		local tooltip, otherTooltip = ComparativeTooltip1, ComparativeTooltip2
		local tt1, tt2 = ShowCraftingComparisons(slot, otherSlot, tooltip, otherTooltip)
		if tt1 then
			ZO_PlayShowAnimationOnComparisonTooltip(tt1)
		else
			ItemTooltip:HideComparativeTooltips()
		end
		if tt2 then
			ZO_PlayShowAnimationOnComparisonTooltip(tt2)
		else
			otherTooltip:SetHidden(true)
		end
		-- position things nicely
		ZO_Tooltips_SetupDynamicTooltipAnchors(ItemTooltip, button.tooltipAnchor or button, tooltip, otherTooltip)
	end
end

local anchors = {
	[SMITHING_MODE_CREATE]      = { _G.BOTTOMRIGHT, SMITHING.creationPanel.resultTooltip, _G.BOTTOMLEFT, -10, 0 },
	[SMITHING_MODE_IMPROVE]     = { _G.BOTTOMRIGHT, SMITHING.improvementPanel.resultTooltip, _G.BOTTOMLEFT, -10, 0 },
	[SMITHING_MODE_DECONSTRUCT] = { _G.BOTTOMRIGHT, SMITHING.deconstructionPanel.extractionSlot.control, _G.TOPLEFT, -190+4, -80 },
	[SMITHING_MODE_RESEARCH]    = { _G.BOTTOMRIGHT, GuiRoot, _G.CENTER, -240, 257 },
}
local function UpdateCraftingComparison(self, setMode)
	local wasHidden = PopupTooltip:IsHidden()
	PopupTooltip:SetHidden(true)
	addon.resultTooltip:SetHidden(true)

	local mode = type(setMode) == 'number' and setMode or SMITHING.mode
	if not mode or not GetSetting('compareMode'..mode) then return end

	-- avoid showing both PopupTooltip -and- ComparativeTooltip simultaneously
	if GetSetting('tooltipMode'..mode) == 'ComparativeTooltip' then
		UpdateComparativeTooltips()
		return
	end

	-- create item link to get slot info
	local itemLink
	if mode == SMITHING_MODE_CREATE then
		-- create items
		itemLink = GetValidSmithingItemLink()
	elseif mode == SMITHING_MODE_IMPROVE then
		-- improve items
		local bag, slot, quantity = SMITHING.improvementPanel:GetCurrentImprovementParams()
		itemLink = GetSmithingImprovedItemLink(bag, slot, quantity)
	elseif mode == SMITHING_MODE_DECONSTRUCT and SMITHING.deconstructionPanel:HasSelections() then
		-- deconstruct items; only when item is already selected
		local itemSlot = SMITHING.deconstructionPanel.extractionSlot
		itemLink = GetItemLink(itemSlot.bagId, itemSlot.slotIndex, LINK_STYLE_DEFAULT)

		if itemLink ~= '' then
			-- update our custom deconstruct tooltip
			local tooltip = addon.resultTooltip
			tooltip:ClearLines()
			tooltip:SetHidden(false)
			tooltip:SetLink(itemLink)

			AddCraftingItemInfo(tooltip, itemLink)
		end
	elseif mode == SMITHING_MODE_RESEARCH and setMode ~= SMITHING_MODE_RESEARCH then
		-- research traits; we don't want tooltips just for switching panels
		local data = SMITHING.researchPanel:GetSelectedData()
		if data and not data.areAllTraitsKnown then
			itemLink = GetValidSmithingItemLink(data.researchLineIndex)
		end
	end

	-- show our tooltips
	local slot, otherSlot = GetComparisonEquipSlotsFromItemLink(itemLink or '')

	-- update tooltip positions
	local tooltip, otherTooltip = ShowCraftingComparisons(slot, otherSlot)
	if tooltip then
		if otherTooltip and otherTooltip:GetHeight() == 0 then
			tooltip:SetHidden(true)
			otherTooltip:SetHidden(true)
			zo_callLater(UpdateCraftingComparison, 1)
			return
		end

		ZO_PlayShowAnimationOnComparisonTooltip(tooltip)

		tooltip:ClearAnchors()
		tooltip:SetAnchor(unpack(anchors[mode] or {}))

		if otherTooltip then
			ZO_PlayShowAnimationOnComparisonTooltip(otherTooltip)

			-- move tooltips so secondary (bottom one) aligns properly
			local isValidAnchor, point, relativeTo, relativePoint, offsetX, offsetY = tooltip:GetAnchor(0)
			if isValidAnchor then
				tooltip:ClearAnchors()
				tooltip:SetAnchor(point, relativeTo, relativePoint, offsetX, offsetY - otherTooltip:GetHeight() - 10)
			end
		end
	end
end

-- ========================================================
--  Setup
-- ========================================================
local function Initialize(eventID, arg1, ...)
	if arg1 ~= addonName then return end
	EVENT_MANAGER:UnregisterForEvent(addonName, EVENT_ADD_ON_LOADED)

	addon.db = ZO_SavedVars:NewAccountWide(addonName..'DB', 2, nil, {
		['tooltipMode'..SMITHING_MODE_DECONSTRUCT] = 'PopupTooltip',
		['tooltipMode'..SMITHING_MODE_RESEARCH] = 'PopupTooltip',
		['compareMode'..SMITHING_MODE_CREATE] = true,
		['compareMode'..SMITHING_MODE_IMPROVE] = true,
		['compareMode'..SMITHING_MODE_DECONSTRUCT] = true,
		['compareMode'..SMITHING_MODE_RESEARCH] = true,
		showInfo = true,
	})

	local wm = GetWindowManager() -- ItemTooltipTopLevel PopupTooltip
	local compareTooltip = wm:CreateControlFromVirtual(addonName..'Tooltip', ItemTooltipTopLevel, 'ZO_ItemIconTooltip')
	compareTooltip:ClearAnchors()
	compareTooltip:SetAnchor(_G.TOP, PopupTooltip, _G.BOTTOM, 0, 10)
	compareTooltip:SetHidden(true)
	compareTooltip:SetClampedToScreen(true)
	compareTooltip:SetMouseEnabled(true)
	compareTooltip:SetMovable(true)
	compareTooltip:SetExcludeFromResizeToFitExtents(true)
	addon.tooltip = compareTooltip

	local resultTooltip = wm:CreateControlFromVirtual(addonName..'DeconstructTooltip', ZO_SmithingTopLevel, 'ZO_ItemIconTooltip')
	resultTooltip:ClearAnchors()
	resultTooltip:SetAnchor(_G.BOTTOM, SMITHING.deconstructionPanel.extractionSlot.control, _G.TOP, 0, -80)
	resultTooltip:SetHidden(true)
	resultTooltip:SetClampedToScreen(true)
	addon.resultTooltip = resultTooltip

	-- compare to off-weapon set
	-- ----------------------------------------------------
	local isSHIFTCompared, lastSHIFTCheck = nil, 0
	ZO_PreHookHandler(SMITHING.control, 'OnUpdate', function(self, elapsed)
		-- check with delay
		if elapsed <= lastSHIFTCheck + 0.25 then return end
		lastSHIFTCheck = elapsed

		local shift = IsShiftKeyDown()
		if shift ~= isSHIFTCompared then
			isSHIFTCompared = shift
			UpdateCraftingComparison()
		end
	end)

	-- hooks
	-- ----------------------------------------------------
	ZO_PreHook(SMITHING, 'SetMode', UpdateCraftingComparison)
	ZO_PreHook(SMITHING, 'OnSelectedPatternChanged', UpdateCraftingComparison) -- crafting
	ZO_PreHook(SMITHING, 'OnExtractionSlotChanged',  UpdateCraftingComparison) -- extraction / deconstruction
	ZO_PreHook(SMITHING, 'OnImprovementSlotChanged', UpdateCraftingComparison) -- improvement
	ZO_PreHook(SMITHING.researchPanel, 'Research',   UpdateCraftingComparison) -- research

	ZO_PreHook(ZO_ListDialog1, 'SetHidden', function(self, hidden)
		-- hide tooltip when cancelling research
		if hidden and not ZO_SmithingTopLevel:IsHidden() and not PopupTooltip:IsHidden() then
			PopupTooltip:SetHidden(true)
		end
	end)
	ZO_PreHook(PopupTooltip, 'SetHidden', function(self, hidden)
		if hidden then
			addon.tooltip:SetHidden(true)
		end
	end)

	local orig = ItemTooltip.SetBagItem
	ItemTooltip.SetBagItem = function(self, bag, slot)
		orig(self, bag, slot)

		if ZO_SmithingTopLevel:IsHidden() or not GetSetting('compareMode'..SMITHING.mode)
			or GetSetting('tooltipMode'..SMITHING.mode) ~= 'ComparativeTooltip' then return end

		-- we want to show comparative tooltips
		UpdateCraftingComparison()
	end

	CreateSettings()
end

local em = GetEventManager()
em:RegisterForEvent(addonName, EVENT_ADD_ON_LOADED, Initialize)
em:RegisterForEvent(addonName, EVENT_END_CRAFTING_STATION_INTERACT, function()
	PopupTooltip:SetHidden(true)
end)
