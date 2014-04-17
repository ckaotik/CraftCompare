local addonName, addon, _ = 'CraftCompare', {}

--[[-- TODO --
? PopupTooltip does not hide when leaving crafting dialog
* Comparison does not show sometimes when researching
* Deconstruction should show item tooltip + comparison popup
* Deconstruction shows wrong item or none at all
--]]

-- GLOBALS: _G, TOPLEFT, BOTTOMLEFT, BOTTOMRIGHT, BAG_WORN, LINK_STYLE_DEFAULT
-- GLOBALS: LibStub, PopupTooltip, ItemTooltip, ComparativeTooltip1, ZO_PreHook, ZO_SavedVars, ZO_Smithing, ZO_SmithingTopLevel, ZO_SmithingCreation, ZO_SmithingImprovement, ZO_SmithingExtraction
-- GLOBALS: GetItemLink, GetSmithingPatternResultLink, GetSmithingImprovedItemLink, GetComparisonEquipSlotsFromItemLink
-- GLOBALS: unpack

local anchors = {
	[2] = { BOTTOMRIGHT, BOTTOMLEFT, -10, 0 },
	[3] = { BOTTOMRIGHT, BOTTOMLEFT, -10, 0 },
	[4] = { BOTTOM, TOP, 0, -80 },
}
local function ShowCraftingComparisons(owner, slot, otherSlot)
	owner = owner or addon.object
	local tooltip = PopupTooltip
	      tooltip:SetHidden(true)
	local otherTooltip = ComparativeTooltip1
	      otherTooltip:SetHidden(true)

	local itemLink = slot and GetItemLink(BAG_WORN, slot, LINK_STYLE_DEFAULT)
	if not itemLink or itemLink == '' or not owner then return end

	-- positioning
	tooltip:ClearAnchors()
	local from, to, dx, dy = unpack(anchors[owner.mode] or {})
	local anchor = owner.mode == 2 and owner.creationPanel.resultTooltip
		or owner.mode == 3 and owner.improvementPanel.resultTooltip
		or owner.mode == 4 and owner.deconstructionPanel.extractionSlot.control
	tooltip:SetAnchor(from, anchor, to, dx, dy)

	-- fill tooltip
	tooltip:ClearLines()
	tooltip:SetBagItem(BAG_WORN, slot)
	tooltip:SetHidden(false)

	local otherLink = otherSlot and GetItemLink(BAG_WORN, otherSlot, LINK_STYLE_DEFAULT)
	if otherLink and otherLink ~= '' then
		otherTooltip:ClearAnchors()
		otherTooltip:SetAnchor(BOTTOMLEFT, tooltip, TOPLEFT, 0, -20)

		otherTooltip:ClearLines()
		otherTooltip:SetBagItem(BAG_WORN, otherSlot)
		otherTooltip:SetHidden(false)
	end
end

local object
local function UpdateCraftingComparison(obj)
	-- store object for later access
	if not object and obj then object = obj.owner; addon.object = object end
	if not object then return end

	-- create item link to get slot info
	local itemLink
	if object.mode == 2 and addon.db.create then
		-- create items
		local patternIndex, materialIndex, materialQuantity, styleIndex, traitIndex = object.creationPanel:GetAllCraftingParameters()
		-- for some obscure reason, API tries using too few mats sometimes
		while (not itemLink or itemLink == '') and materialQuantity <= 100 do
			itemLink = GetSmithingPatternResultLink(patternIndex, materialIndex, materialQuantity, styleIndex, traitIndex, LINK_STYLE_DEFAULT)
			materialQuantity = materialQuantity + 1
		end
	elseif object.mode == 3 and addon.db.improve then
		-- improve items
		local bag, slot, quantity = object.improvementPanel:GetCurrentImprovementParams()
		itemLink = GetSmithingImprovedItemLink(bag, slot, quantity)
	elseif object.mode == 4 and addon.db.extract and object.deconstructionPanel:HasSelections()then
		-- extract items / deconstruction
		local itemSlot = object.deconstructionPanel.extractionSlot
		itemLink = GetItemLink(itemSlot.bagId, itemSlot.slotIndex, LINK_STYLE_DEFAULT)
	end

	-- show comparison
	local slot, otherSlot = GetComparisonEquipSlotsFromItemLink(itemLink or '')
	ShowCraftingComparisons(object, slot, otherSlot)
end

-- ========================================================
--  UI / Saved Vars management
-- ========================================================
local function GetSetting(setting)
	return addon.db and addon.db[setting]
end
local function SetSetting(setting, value)
	if addon.db then
		addon.db[setting] = value
	end
end

local function Initialize(eventCode, arg1, ...)
	if arg1 ~= addonName then return end

	-- addon.db = ZO_SavedVars:New(addonName..'DB', 1, nil, {
	addon.db = ZO_SavedVars:NewAccountWide(addonName..'DB', 1, nil, {
		tooltipStyle = 'PopupTooltip',
		create = true,
		improve = true,
		extract = false,
		research = false,
	})

	-- hooks
	-- ----------------------------------------------------
	ZO_PreHook(ZO_SmithingCreation, 'OnSelectedPatternChanged', UpdateCraftingComparison)
	ZO_PreHook(ZO_SmithingImprovement, 'OnSlotChanged', UpdateCraftingComparison)

	if GetSetting('tooltipStyle') == 'PopupTooltip' then
		ZO_PreHook(ZO_SmithingExtraction, 'OnSlotChanged', UpdateCraftingComparison)
	elseif GetSetting('tooltipStyle') == 'ComparativeTooltip' then
		local orig = ItemTooltip.SetBagItem
		ItemTooltip.SetBagItem = function(self, bag, slot)
			orig(self, bag, slot)

			--if IsShiftKeyDown() then
			--	self:ShowComparativeTooltips()
			if not ZO_SmithingTopLevel:IsHidden() and addon.object and (
				(addon.object.mode == 4 and GetSetting('extract')) or
				(addon.object.mode == 5 and GetSetting('research')) ) then
				d('showing comparative tooltips')
				self:ShowComparativeTooltips()
			end
		end
		d('hooked ItemTooltip.SetBagItem')
	end

	-- show/hide tooltip when changing crafting modes
	local orig = ZO_Smithing.SetMode
	ZO_Smithing.SetMode = function(...)
		orig(...)
		UpdateCraftingComparison()
	end

	-- settings menu
	-- ----------------------------------------------------
	local LAM = LibStub('LibAddonMenu-1.0')
	local panelID = LAM:CreateControlPanel(addonName, addonName)

	-- modes to display tooltips for
	LAM:AddHeader(panelID, addonName..'HeaderModes', 'Compare in modes')
	LAM:AddCheckbox(panelID, addonName..'ToggleCreate',
		'Creation', 'Enable item comparison when in "Creation" mode',
		function() return GetSetting('create') end, function(value) SetSetting('create', value) end)
	LAM:AddCheckbox(panelID, addonName..'ToggleImprove',
		'Improvement', 'Enable item comparison when in "Improvement" mode',
		function() return GetSetting('improve') end, function(value) SetSetting('improve', value) end)
	LAM:AddCheckbox(panelID, addonName..'ToggleExtract',
		'Extraction', 'Enable item comparison when in "Extraction" mode',
		function() return GetSetting('extract') end, function(value) SetSetting('extract', value) end)
	LAM:AddCheckbox(panelID, addonName..'ToggleResearch',
		'Research', 'Enable item comparison when in "Research" mode',
		function() return GetSetting('research') end, function(value) SetSetting('research', value) end)

	-- tooltip mode
	LAM:AddHeader(panelID, addonName..'HeaderTTStyle', 'Tooltip Style')
	LAM:AddDropdown(panelID, addonName..'DropdownTTStyle',
		'Extraction / Research', 'PopupTooltip can be moved and closed.\nComparativeTooltip is attached to the normal item tooltip.',
		{'PopupTooltip', 'ComparativeTooltip'},
		function(...) return GetSetting('tooltipStyle') end, function(value) SetSetting('tooltipStyle', value) end,
		true, 'Requires UI reload')
	LAM:AddDescription(panelID, addonName..'Description', 'You may change the way item comparisons are presented to you.\nPopupTooltip does not yet support "Research" mode.', nil)

	-- addon exposure
	-- ----------------------------------------------------
	addon.name = addonName
	_G[addonName] = addon
end

local em = GetEventManager()
em:RegisterForEvent('CraftCompare_Loaded', EVENT_ADD_ON_LOADED, Initialize)
em:RegisterForEvent('CraftCompare_CraftClose', EVENT_END_CRAFTING_STATION_INTERACT, ShowCraftingComparisons)
