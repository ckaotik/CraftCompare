local addonName, addon, _ = 'CraftCompare', {}
_G[addonName] = addon
addon.name = addonName

--[[-- TODO --
* Deconstruction should show item tooltip + comparison popup
* fix ComparativeTooltip1 hiding when hovering things while crafting
--]]

-- GLOBALS: _G, SMITHING, TOPLEFT, BOTTOMLEFT, BOTTOMRIGHT, BAG_WORN, LINK_STYLE_DEFAULT, CT_TEXTURE
-- GLOBALS: LibStub, PopupTooltip, ItemTooltip, ItemTooltipTopLevel, ComparativeTooltip1, ZO_PreHook, ZO_SavedVars, ZO_SmithingTopLevel, ZO_ListDialog1
-- GLOBALS: GetItemLink, GetSmithingPatternResultLink, GetSmithingImprovedItemLink, GetComparisonEquipSlotsFromItemLink, GetWindowManager, GetString, GetItemLinkInfo, GetInterfaceColor
-- GLOBALS: unpack, type

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

local function ShowCraftingComparisons(slot, otherSlot)
	local itemLink = slot and GetItemLink(BAG_WORN, slot, LINK_STYLE_DEFAULT)
	local mode = SMITHING.mode
	if not mode or not itemLink or itemLink == '' then return end

	-- fill tooltip
	local tooltip = PopupTooltip
	tooltip:ClearLines()
	tooltip:SetHidden(false)
	tooltip:SetBagItem(BAG_WORN, slot)

	local font = 'ZoFontWinT2'
	local r, g, b, a = GetInterfaceColor(_G.INTERFACE_COLOR_TYPE_ATTRIBUTE_TOOLTIP)
	local equipped = '('..GetString(_G.SI_ITEM_FORMAT_STR_EQUIPPED)..')'

	-- show style in tooltip
	local _, _, _, _, itemStyle = GetItemLinkInfo(itemLink)
	tooltip:AddHeaderLine(GetString(_G['SI_ITEMSTYLE'..itemStyle]), font, 0, _G.TOOLTIP_HEADER_SIDE_RIGHT, r, g, b, a)
	tooltip:AddHeaderLine(equipped, font, 1, _G.TOOLTIP_HEADER_SIDE_RIGHT, r, g, b, a)

	local otherLink = otherSlot and GetItemLink(BAG_WORN, otherSlot, LINK_STYLE_DEFAULT)
	if otherLink and otherLink ~= '' then
		local otherTooltip = addon.tooltip
		otherTooltip:ClearLines()
		otherTooltip:SetHidden(false)
		otherTooltip:SetBagItem(BAG_WORN, otherSlot)

		-- show style in tooltip & update icon
		local icon, sellPrice, canUse, equipType, itemStyle = GetItemLinkInfo(otherLink)
		otherTooltip.icon:SetTexture(icon)
		otherTooltip:AddHeaderLine(GetString(_G['SI_ITEMSTYLE'..itemStyle]), font, 0, _G.TOOLTIP_HEADER_SIDE_RIGHT, r, g, b, a)
		otherTooltip:AddHeaderLine(equipped, font, 1, _G.TOOLTIP_HEADER_SIDE_RIGHT, r, g, b, a)

		-- move tooltips so secondary (bottom one) aligns properly
		local isValidAnchor, point, relativeTo, relativePoint, offsetX, offsetY = tooltip:GetAnchor(0)
		tooltip:ClearAnchors()
		tooltip:SetAnchor(point, relativeTo, relativePoint, offsetX, offsetY - otherTooltip:GetHeight() - 10)
	end
end

local anchors = {
	[SMITHING_MODE_CREATE]      = { BOTTOMRIGHT, SMITHING.creationPanel.resultTooltip, BOTTOMLEFT, -10, 0 },
	[SMITHING_MODE_IMPROVE]     = { BOTTOMRIGHT, SMITHING.improvementPanel.resultTooltip, BOTTOMLEFT, -10, 0 },
	[SMITHING_MODE_DECONSTRUCT] = { BOTTOMRIGHT, SMITHING.deconstructionPanel.extractionSlot.control, TOPLEFT, -190+4, -80 },
	[SMITHING_MODE_RESEARCH]    = { BOTTOMRIGHT, GuiRoot, CENTER, -240, 257 },
}
local function UpdateCraftingComparison(self, setMode)
	PopupTooltip:HideComparativeTooltips()
	PopupTooltip:SetHidden(true)
	addon.resultTooltip:SetHidden(true)

	local mode = type(setMode) == 'number' and setMode or SMITHING.mode
	if not mode or not GetSetting('compareMode'..mode) then return end

	-- avoid showing both PopupTooltip -and- ComparativeTooltip simultaneously
	if GetSetting('tooltipMode'..mode) == 'ComparativeTooltip' then
		ItemTooltip:ShowComparativeTooltips()
		return
	else
		local tooltip = PopupTooltip
		tooltip:ClearAnchors()
		tooltip:SetAnchor(unpack(anchors[mode or 1] or {}))
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
			local tooltip = addon.resultTooltip
			tooltip:ClearLines()
			tooltip:SetHidden(false)
			tooltip:SetLink(itemLink)

			local icon, _, _, _, itemStyle = GetItemLinkInfo(itemLink)
			tooltip.icon:SetTexture(icon)
			tooltip:AddHeaderLine(GetString(_G['SI_ITEMSTYLE'..itemStyle]), 'ZoFontWinT2', 1, _G.TOOLTIP_HEADER_SIDE_RIGHT, GetInterfaceColor(_G.INTERFACE_COLOR_TYPE_ATTRIBUTE_TOOLTIP))
		end
	elseif mode == SMITHING_MODE_RESEARCH and setMode ~= SMITHING_MODE_RESEARCH then
		-- research traits; we don't want tooltips just for switching panels
		local data = SMITHING.researchPanel:GetSelectedData()
		if data and not data.areAllTraitsKnown then
			itemLink = GetValidSmithingItemLink(data.researchLineIndex)
		end
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

	local wm = GetWindowManager()
	local compareTooltip = wm:CreateControlFromVirtual(addonName..'Tooltip', ItemTooltipTopLevel, 'ItemTooltipBase')
	compareTooltip:ClearAnchors()
	compareTooltip:SetAnchor(_G.TOP, PopupTooltip, _G.BOTTOM, 0, 10)
	compareTooltip:SetHidden(true)
	compareTooltip:SetClampedToScreen(true)
	compareTooltip:SetMouseEnabled(true)
	compareTooltip:SetMovable(true)
	addon.tooltip = compareTooltip

	-- set any item so the sizing fits later on :P
	compareTooltip:SetLink("|H3A92FF:item:43529:4:6:5365:4:6:0:0:0:0:0:0:0:0:0:4:0:0:45:0|h[Eisenaxt des Frosts]|h")

	local icon = wm:CreateControl(addonName..'TooltipIcon', compareTooltip, CT_TEXTURE)
	icon:SetWidth(64)
	icon:SetHeight(64)
	icon:SetAnchor(_G.CENTER, compareTooltip, _G.TOP, 0, 20)
	icon:SetHidden(false)
	icon:SetExcludeFromResizeToFitExtents(true)
	compareTooltip.icon = icon

	local resultTooltip = wm:CreateControlFromVirtual(addonName..'DeconstructTooltip', ZO_SmithingTopLevel, 'ItemTooltipBase')
	resultTooltip:ClearAnchors()
	resultTooltip:SetAnchor(_G.BOTTOM, SMITHING.deconstructionPanel.extractionSlot.control, _G.TOP, 0, -80)
	resultTooltip:SetHidden(true)
	resultTooltip:SetClampedToScreen(true)
	resultTooltip:SetMouseEnabled(true)
	addon.resultTooltip = resultTooltip

	local resultIcon = wm:CreateControl(addonName..'DeconstructTooltipIcon', resultTooltip, CT_TEXTURE)
	resultIcon:SetWidth(64)
	resultIcon:SetHeight(64)
	resultIcon:SetAnchor(_G.CENTER, resultTooltip, _G.TOP, 0, 0)
	resultIcon:SetHidden(false)
	resultIcon:SetExcludeFromResizeToFitExtents(true)
	resultTooltip.icon = resultIcon

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
