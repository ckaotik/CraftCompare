local addonName, addon, _ = 'CraftCompare', {}
_G[addonName] = addon
addon.name = addonName

--[[-- TODO --
* Deconstruction should show item tooltip + comparison popup
* fix ComparativeTooltip1 hiding when hovering things while crafting
* fix SMITHING_MODE_RESEARCH guessing itemlink when no such item is equipped
--]]

-- GLOBALS: _G, SMITHING, TOPLEFT, BOTTOMLEFT, BOTTOMRIGHT, BAG_WORN, LINK_STYLE_DEFAULT
-- GLOBALS: LibStub, PopupTooltip, ItemTooltip, ComparativeTooltip1, ZO_PreHook, ZO_SavedVars, ZO_SmithingTopLevel
-- GLOBALS: GetItemLink, GetSmithingPatternResultLink, GetSmithingImprovedItemLink, GetComparisonEquipSlotsFromItemLink
-- GLOBALS: unpack

local SMITHING_MODE_EXTRACT = 1
local SMITHING_MODE_CREATE = 2
local SMITHING_MODE_IMPROVE = 3
local SMITHING_MODE_DECONSTRUCT = 4
local SMITHING_MODE_RESEARCH = 5

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

	-- tooltip mode
	LAM:AddHeader(panel, addonName..'HeaderTTStyle', 'Tooltip Style')
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

local anchors = {
	[SMITHING_MODE_CREATE]      = { BOTTOMRIGHT, SMITHING.creationPanel.resultTooltip, BOTTOMLEFT, -10, 0 },
	[SMITHING_MODE_IMPROVE]     = { BOTTOMRIGHT, SMITHING.improvementPanel.resultTooltip, BOTTOMLEFT, -10, 0 },
	[SMITHING_MODE_DECONSTRUCT] = { BOTTOMRIGHT, SMITHING.deconstructionPanel.extractionSlot.control, TOPLEFT, -190+4, -80 },
	[SMITHING_MODE_RESEARCH]    = { BOTTOMRIGHT, GuiRoot, CENTER, -240, 257 },
}
local function ShowCraftingComparisons(slot, otherSlot)
	local itemLink = slot and GetItemLink(BAG_WORN, slot, LINK_STYLE_DEFAULT)
	local mode = SMITHING.mode
	if not mode or not itemLink or itemLink == '' then return end

	-- positioning
	local tooltip = PopupTooltip
	tooltip:ClearAnchors()
	tooltip:SetAnchor(unpack(anchors[mode or 1] or {}))

	-- fill tooltip
	tooltip:ClearLines()
	tooltip:SetBagItem(BAG_WORN, slot)
	tooltip:SetHidden(false)

	local otherLink = otherSlot and GetItemLink(BAG_WORN, otherSlot, LINK_STYLE_DEFAULT)
	if otherLink and otherLink ~= '' then
		local otherTooltip = ComparativeTooltip1
		otherTooltip:ClearAnchors()
		otherTooltip:SetAnchor(BOTTOMLEFT, tooltip, TOPLEFT, 0, -20)

		otherTooltip:ClearLines()
		otherTooltip:SetBagItem(BAG_WORN, otherSlot)
		otherTooltip:SetHidden(false)
		-- show animation
		if otherTooltip:GetAlpha() == 0 then
			otherTooltip.showAnimation:PlayFromStart()
		end
	end
end

local function UpdateCraftingComparison(self, mode)
	local mode = mode or SMITHING.mode
	if not GetSetting('compareMode'..mode) then return end

	PopupTooltip:HideComparativeTooltips()
	PopupTooltip:SetHidden(true)

	-- avoid showing both PopupTooltip -and- ComparativeTooltip simultaneously
	if GetSetting('tooltipMode'..mode) == 'ComparativeTooltip' then
		ItemTooltip:ShowComparativeTooltips()
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
		-- deconstruct items
		local itemSlot = SMITHING.deconstructionPanel.extractionSlot
		itemLink = GetItemLink(itemSlot.bagId, itemSlot.slotIndex, LINK_STYLE_DEFAULT)
	elseif mode == SMITHING_MODE_RESEARCH then
		-- research traits
		local data = SMITHING.researchPanel:GetSelectedData()
		itemLink = data and GetValidSmithingItemLink(data.researchLineIndex)
	end

	-- show comparison
	local slot, otherSlot = GetComparisonEquipSlotsFromItemLink(itemLink or '')
	ShowCraftingComparisons(slot, otherSlot)
end

-- ========================================================
--  Setup
-- ========================================================
local function Initialize(eventCode, arg1, ...)
	if arg1 ~= addonName then return end

	addon.db = ZO_SavedVars:NewAccountWide(addonName..'DB', 2, nil, {
		['tooltipMode'..SMITHING_MODE_DECONSTRUCT] = 'PopupTooltip',
		['tooltipMode'..SMITHING_MODE_RESEARCH] = 'PopupTooltip',
		['compareMode'..SMITHING_MODE_CREATE] = true,
		['compareMode'..SMITHING_MODE_IMPROVE] = true,
		['compareMode'..SMITHING_MODE_DECONSTRUCT] = true,
		['compareMode'..SMITHING_MODE_RESEARCH] = true,
	})

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
		-- hide ComparativeTooltip1 when hiding PopupTooltip
		if not ZO_SmithingTopLevel:IsHidden() and ComparativeTooltip1 then
			ComparativeTooltip1:SetHidden(true)
		end
	end)

	local orig = ItemTooltip.SetBagItem
	ItemTooltip.SetBagItem = function(self, bag, slot)
		orig(self, bag, slot)

		if ZO_SmithingTopLevel:IsHidden() or not GetSetting('compareMode'..SMITHING.mode)
			or GetSetting('tooltipMode'..SMITHING.mode) ~= 'ComparativeTooltip' then return end

		-- we want to show comparative tooltips
		self:ShowComparativeTooltips()
		for i = 1, 2 do
			local tooltip = _G['ComparativeTooltip'..i]
			if not tooltip:IsHidden() and tooltip.showAnimation then
				tooltip.showAnimation:PlayFromStart()
			end
		end
	end

	CreateSettings()
end

local em = GetEventManager()
em:RegisterForEvent('CraftCompare_Loaded', EVENT_ADD_ON_LOADED, Initialize)
em:RegisterForEvent('CraftCompare_CraftClose', EVENT_END_CRAFTING_STATION_INTERACT, UpdateCraftingComparison)
