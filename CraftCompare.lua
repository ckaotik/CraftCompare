local addonName, addon, _ = 'CraftCompare', {}

--[[-- TODO --
* Deconstruction should show item tooltip + comparison popup
* fix ComparativeTooltip1 hiding when hovering things while crafting
--]]

-- GLOBALS: _G, SMITHING, TOPLEFT, BOTTOMLEFT, BOTTOMRIGHT, BAG_WORN, LINK_STYLE_DEFAULT
-- GLOBALS: LibStub, PopupTooltip, ItemTooltip, ComparativeTooltip1, ZO_PreHook, ZO_SavedVars, ZO_Smithing, ZO_SmithingTopLevel, ZO_SmithingCreation, ZO_SmithingImprovement, ZO_SmithingExtraction
-- GLOBALS: GetItemLink, GetSmithingPatternResultLink, GetSmithingImprovedItemLink, GetComparisonEquipSlotsFromItemLink
-- GLOBALS: unpack

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
		function() return GetSetting('create') end, function(value) SetSetting('create', value) end)
	LAM:AddCheckbox(panel, addonName..'ToggleImprove',
		'Improvement', 'Enable item comparison when in "Improvement" mode',
		function() return GetSetting('improve') end, function(value) SetSetting('improve', value) end)
	LAM:AddCheckbox(panel, addonName..'ToggleExtract',
		'Extraction', 'Enable item comparison when in "Extraction" mode',
		function() return GetSetting('extract') end, function(value) SetSetting('extract', value) end)
	LAM:AddCheckbox(panel, addonName..'ToggleResearch',
		'Research', 'Enable item comparison when in "Research" mode',
		function() return GetSetting('research') end, function(value) SetSetting('research', value) end)

	-- tooltip mode
	LAM:AddHeader(panel, addonName..'HeaderTTStyle', 'Tooltip Style')
	LAM:AddDropdown(panel, addonName..'DropdownTTStyle',
		'Extraction / Research', 'PopupTooltip can be moved and closed.\nComparativeTooltip is attached to the normal item tooltip.',
		{'PopupTooltip', 'ComparativeTooltip'},
		function(...) return GetSetting('tooltipStyle') end, function(value) SetSetting('tooltipStyle', value) end,
		true, 'Requires UI reload')
	LAM:AddDescription(panel, addonName..'Description', 'You may change the way item comparisons are presented to you.\nPopupTooltip does not yet support "Research" mode.', nil)
end

-- ========================================================
--  Functionality
-- ========================================================
local anchors = {
	[2] = { BOTTOMRIGHT, BOTTOMLEFT, -10, 0 },
	[3] = { BOTTOMRIGHT, BOTTOMLEFT, -10, 0 },
	[4] = { BOTTOMRIGHT, TOPLEFT, -190+4, -80 },
	-- [4] = { BOTTOM, TOP, 0, -80 },
}
local function ShowCraftingComparisons(slot, otherSlot)
	local itemLink = slot and GetItemLink(BAG_WORN, slot, LINK_STYLE_DEFAULT)
	if not SMITHING.mode or not itemLink or itemLink == '' then return end

	-- positioning
	local tooltip = PopupTooltip
	tooltip:ClearAnchors()
	local from, to, dx, dy = unpack(anchors[SMITHING.mode or 1] or {})
	local anchor = SMITHING.mode == 2 and SMITHING.creationPanel.resultTooltip
		or SMITHING.mode == 3 and SMITHING.improvementPanel.resultTooltip
		or SMITHING.mode == 4 and SMITHING.deconstructionPanel.extractionSlot.control
	tooltip:SetAnchor(from, anchor, to, dx, dy)

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

local function UpdateCraftingComparison()
	if not SMITHING then return end
	PopupTooltip:HideComparativeTooltips()
	PopupTooltip:SetHidden(true)

	-- avoid showing both PopupTooltip -and- ComparativeTooltip simultaneously
	local isComparative = GetSetting('tooltipStyle') == 'ComparativeTooltip'
	if isComparative and (SMITHING.mode == 4 or SMITHING.mode == 5) then
		ItemTooltip:ShowComparativeTooltips()
		return
	end

	-- create item link to get slot info
	local itemLink
	if SMITHING.mode == 2 and addon.db.create then
		-- create items
		local patternIndex, materialIndex, materialQuantity, styleIndex, traitIndex = SMITHING.creationPanel:GetAllCraftingParameters()
		-- for some obscure reason, API tries using too few mats sometimes
		while (not itemLink or itemLink == '') and materialQuantity <= 100 do
			itemLink = GetSmithingPatternResultLink(patternIndex, materialIndex, materialQuantity, styleIndex, traitIndex, LINK_STYLE_DEFAULT)
			materialQuantity = materialQuantity + 1
		end
	elseif SMITHING.mode == 3 and addon.db.improve then
		-- improve items
		local bag, slot, quantity = SMITHING.improvementPanel:GetCurrentImprovementParams()
		itemLink = GetSmithingImprovedItemLink(bag, slot, quantity)
	elseif SMITHING.mode == 4 and addon.db.extract and SMITHING.deconstructionPanel:HasSelections() then
		-- extract items / deconstruction
		local itemSlot = SMITHING.deconstructionPanel.extractionSlot
		itemLink = GetItemLink(itemSlot.bagId, itemSlot.slotIndex, LINK_STYLE_DEFAULT)
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

	addon.db = ZO_SavedVars:NewAccountWide(addonName..'DB', 1, nil, {
		tooltipStyle = 'PopupTooltip',
		create = true,
		improve = true,
		extract = false,
		research = false,
	})

	-- addon exposure
	-- ----------------------------------------------------
	addon.name = addonName
	_G[addonName] = addon

	-- hooks
	-- ----------------------------------------------------
	ZO_PreHook(ZO_SmithingCreation, 'OnSelectedPatternChanged', UpdateCraftingComparison)
	ZO_PreHook(ZO_SmithingImprovement, 'OnSlotChanged', UpdateCraftingComparison)
	ZO_PreHook(ZO_SmithingExtraction,  'OnSlotChanged', UpdateCraftingComparison)

	ZO_PreHook(PopupTooltip, 'SetHidden', function(self, hidden)
		if not ZO_SmithingTopLevel:IsHidden() and ComparativeTooltip1 then
			-- hide ComparativeTooltip1 when hiding PopupTooltip
			ComparativeTooltip1:SetHidden(true)
		end
	end)

	if GetSetting('tooltipStyle') == 'ComparativeTooltip' then
		local orig = ItemTooltip.SetBagItem
		ItemTooltip.SetBagItem = function(self, bag, slot)
			orig(self, bag, slot)

			if not ZO_SmithingTopLevel:IsHidden() and SMITHING and (
				(SMITHING.mode == 4 and GetSetting('extract')) or
				(SMITHING.mode == 5 and GetSetting('research')) ) then
				-- we want to show comparative tooltips
				self:ShowComparativeTooltips()
				for i = 1, 2 do
					local tooltip = _G['ComparativeTooltip'..i]
					if not tooltip:IsHidden() and tooltip.showAnimation then
						tooltip.showAnimation:PlayFromStart()
					end
				end
			end
		end
	end

	-- show/hide tooltip when changing crafting modes
	local orig = ZO_Smithing.SetMode
	ZO_Smithing.SetMode = function(...)
		orig(...)
		UpdateCraftingComparison()
	end

	CreateSettings()
end

local em = GetEventManager()
em:RegisterForEvent('CraftCompare_Loaded', EVENT_ADD_ON_LOADED, Initialize)
em:RegisterForEvent('CraftCompare_CraftClose', EVENT_END_CRAFTING_STATION_INTERACT, UpdateCraftingComparison)
