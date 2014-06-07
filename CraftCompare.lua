local addonName, addon, _ = 'CraftCompare', {}
_G[addonName] = addon

--[[-- TODO --
* don't overwrite user tooltip positions
--]]

-- GLOBALS: _G, SMITHING, LINK_STYLE_DEFAULT, SI_FORMAT_BULLET_SPACING, SI_TOOLTIP_ITEM_NAME
-- GLOBALS: LibStub, PopupTooltip, ItemTooltip, ComparativeTooltip1, ComparativeTooltip2, ZO_PreHook, ZO_PreHookHandler, ZO_SavedVars
-- GLOBALS: GetItemLink, GetSmithingPatternResultLink, GetSmithingImprovedItemLink, GetComparisonEquipSlotsFromItemLink, GetWindowManager, GetString, GetItemLinkInfo, GetInterfaceColor, IsShiftKeyDown, ZO_PlayShowAnimationOnComparisonTooltip, ZO_Tooltips_SetupDynamicTooltipAnchors, ZO_ItemTooltip_SetEquippedInfo, ZO_Tooltip_AddDivider, ZO_Inventory_GetBagAndIndex, ZO_InventorySlot_GetItemListDialog, ZO_PopupTooltip_Hide
-- GLOBALS: unpack, type, moc, zo_strjoin, zo_callLater, zo_strformat

local SMITHING_MODE_EXTRACT     = 1
local SMITHING_MODE_CREATE      = 2
local SMITHING_MODE_IMPROVE     = 3
local SMITHING_MODE_DECONSTRUCT = 4
local SMITHING_MODE_RESEARCH    = 5

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
		if itemLink and itemLink ~= '' then
			return itemLink
		end
		materialQuantity = materialQuantity + 1
	end
end

local alternateSlot = {
	[_G.EQUIP_SLOT_MAIN_HAND]   = _G.EQUIP_SLOT_BACKUP_MAIN,
	[_G.EQUIP_SLOT_BACKUP_MAIN] = _G.EQUIP_SLOT_MAIN_HAND,
	[_G.EQUIP_SLOT_OFF_HAND]    = _G.EQUIP_SLOT_BACKUP_OFF,
	[_G.EQUIP_SLOT_BACKUP_OFF]  = _G.EQUIP_SLOT_OFF_HAND,
}
local function GetCompareSlots(itemLink)
	if not itemLink or itemLink == '' then return end

	local slot, otherSlot = GetComparisonEquipSlotsFromItemLink(itemLink)
	if IsShiftKeyDown() then
		local altSlot, altOtherSlot = alternateSlot[slot], alternateSlot[otherSlot]
		if altSlot or altOtherSlot then
			return altSlot, altOtherSlot
		end
	end
	return slot, otherSlot
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

local function UpdateTooltips(slot, otherSlot, tooltip, otherTooltip)
	-- handle primary tooltip
	local itemLink = slot and GetItemLink(_G.BAG_WORN, slot)
	tooltip = tooltip or PopupTooltip
	if itemLink and itemLink ~= '' then
		tooltip:ClearLines()
		tooltip:SetLink(itemLink)
		tooltip:SetHidden(false)
		ZO_PlayShowAnimationOnComparisonTooltip(tooltip)

		-- additional information
		AddCraftingItemInfo(tooltip, itemLink, slot)
	else
		-- ClearTooltip(tooltip)
		tooltip:SetHidden(true)
		tooltip = nil
	end

	-- handle secondary tooltip
	local otherLink = otherSlot and GetItemLink(_G.BAG_WORN, otherSlot)
	otherTooltip = otherTooltip or addon.tooltip
	if otherLink and otherLink ~= '' then
		otherTooltip:ClearLines()
		otherTooltip:SetLink(otherLink)
		otherTooltip:SetHidden(false)
		ZO_PlayShowAnimationOnComparisonTooltip(otherTooltip)

		-- additional information
		AddCraftingItemInfo(otherTooltip, otherLink, otherSlot)
	else
		-- ClearTooltip(otherTooltip)
		-- ZO_PlayHideAnimationOnComparisonTooltip(otherTooltip)
		otherTooltip:SetHidden(true)
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
		local slot, otherSlot = GetCompareSlots(itemLink)
		local tooltip, otherTooltip = ComparativeTooltip1, ComparativeTooltip2

		local tt1, tt2 = UpdateTooltips(slot, otherSlot, tooltip, otherTooltip)
		if tt1 or tt2 then
			-- AddCraftingItemInfo(ItemTooltip, itemLink)
			-- position things nicely
			ZO_Tooltips_SetupDynamicTooltipAnchors(ItemTooltip, button.tooltipAnchor or button, tooltip, otherTooltip)
		else
			ItemTooltip:HideComparativeTooltips()
		end
	end
end

local anchors = {
	[SMITHING_MODE_CREATE]      = { _G.BOTTOMRIGHT, SMITHING.creationPanel.resultTooltip, _G.BOTTOMLEFT, -10, 0 },
	[SMITHING_MODE_IMPROVE]     = { _G.BOTTOMRIGHT, SMITHING.improvementPanel.resultTooltip, _G.BOTTOMLEFT, -10, 0 },
	[SMITHING_MODE_DECONSTRUCT] = { _G.BOTTOMRIGHT, SMITHING.deconstructionPanel.extractionSlot.control, _G.TOPLEFT, -190+4, -80 },
	[SMITHING_MODE_RESEARCH]    = { _G.BOTTOMRIGHT, GuiRoot, _G.CENTER, -240, 257 },
}
local function Update()
	local mode = SMITHING.mode
	if not mode or not GetSetting('compareMode'..mode) then return end

	if GetSetting('tooltipMode'..mode) == 'ComparativeTooltip' then
		UpdateComparativeTooltips()
	else
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
		elseif mode == SMITHING_MODE_RESEARCH then
			-- research traits
			local data = SMITHING.researchPanel:GetSelectedData()
			if data and not data.areAllTraitsKnown then
				itemLink = GetValidSmithingItemLink(data.researchLineIndex)
			end
		end

		-- show our tooltips
		local slot, otherSlot = GetCompareSlots(itemLink)
		local tooltip, otherTooltip = UpdateTooltips(slot, otherSlot)

		-- update tooltip positions
		if tooltip then
			if otherTooltip and otherTooltip:GetHeight() == 0 then
				-- in case the tooltip is unitialized, try again later
				tooltip:SetHidden(true)
				otherTooltip:SetHidden(true)
				zo_callLater(Update, 1)
				return
			end

			tooltip:ClearAnchors()
			tooltip:SetAnchor(unpack(anchors[mode] or {}))

			if otherTooltip then
				-- move tooltips so secondary (bottom one) aligns properly
				local isValidAnchor, point, relativeTo, relativePoint, offsetX, offsetY = tooltip:GetAnchor(0)
				if isValidAnchor then
					tooltip:ClearAnchors()
					tooltip:SetAnchor(point, relativeTo, relativePoint, offsetX, offsetY - otherTooltip:GetHeight() - 10)
				end
			end
		end
	end
end

-- ========================================================
--  Setup
-- ========================================================
local em = GetEventManager()
local function Initialize(eventID, arg1, ...)
	if arg1 ~= addonName then return end
	em:UnregisterForEvent(addonName, _G.EVENT_ADD_ON_LOADED)

	addon.db = ZO_SavedVars:NewAccountWide(addonName..'DB', 2, nil, {
		['tooltipMode'..SMITHING_MODE_DECONSTRUCT] = 'PopupTooltip',
		['tooltipMode'..SMITHING_MODE_RESEARCH] = 'PopupTooltip',
		['compareMode'..SMITHING_MODE_CREATE] = true,
		['compareMode'..SMITHING_MODE_IMPROVE] = true,
		['compareMode'..SMITHING_MODE_DECONSTRUCT] = true,
		['compareMode'..SMITHING_MODE_RESEARCH] = true,
		showInfo = true,
	})

	local wm = GetWindowManager()
	local compareTooltip = wm:CreateControlFromVirtual(addonName..'Tooltip', PopupTooltip, 'ZO_ItemIconTooltip')
	      compareTooltip:ClearAnchors()
	      compareTooltip:SetAnchor(_G.TOP, PopupTooltip, _G.BOTTOM, 0, 10)
	      compareTooltip:SetHidden(true)
	      compareTooltip:SetClampedToScreen(true)
	      compareTooltip:SetMouseEnabled(true)
	      compareTooltip:SetMovable(true)
	      compareTooltip:SetExcludeFromResizeToFitExtents(true)
	addon.tooltip = compareTooltip

	local resultTooltip = wm:CreateControlFromVirtual(addonName..'DeconstructTooltip', SMITHING.control, 'ZO_ItemIconTooltip')
	      resultTooltip:ClearAnchors()
	      resultTooltip:SetAnchor(_G.BOTTOM, SMITHING.deconstructionPanel.extractionSlot.control, _G.TOP, 0, -80)
	      resultTooltip:SetHidden(true)
	      resultTooltip:SetClampedToScreen(true)
	addon.resultTooltip = resultTooltip

	-- compare to alternate set
	-- ----------------------------------------------------
	local isSHIFTCompared, lastSHIFTCheck = nil, 0
	ZO_PreHookHandler(SMITHING.control, 'OnUpdate', function(self, elapsed)
		if elapsed <= lastSHIFTCheck + 0.25 then return end
		lastSHIFTCheck = elapsed

		local shift = IsShiftKeyDown()
		if isSHIFTCompared ~= shift then
			isSHIFTCompared = shift

			local mode = SMITHING.mode
			-- only show research PopupTooltip when dialog is actually open
			local prevent = mode == SMITHING_MODE_RESEARCH
				and GetSetting('tooltipMode'..mode) == 'PopupTooltip'
				and ZO_InventorySlot_GetItemListDialog():GetControl():IsHidden()

			if GetSetting('compareMode'..mode) and not prevent then
				Update()
			end
		end
	end)

	-- hooks
	-- ----------------------------------------------------
	em:RegisterForEvent(addonName, _G.EVENT_END_CRAFTING_STATION_INTERACT, ZO_PopupTooltip_Hide)

	ZO_PreHook(SMITHING, 'SetMode', function(self, mode)
		-- hide comparisons when switching modes
		PopupTooltip:SetHidden(true)
		addon.resultTooltip:SetHidden(true)

		if GetSetting('compareMode'..mode) and mode ~= SMITHING_MODE_RESEARCH then
			-- delay 1ms so original SetMode has completed
			zo_callLater(Update, 1)
		end
	end)

	ZO_PreHook(SMITHING, 'OnSelectedPatternChanged', Update) -- crafting
	ZO_PreHook(SMITHING, 'OnImprovementSlotChanged', Update) -- improvement
	ZO_PreHook(SMITHING, 'OnExtractionSlotChanged',  function(self, ...) -- extraction / deconstruction
		Update(self, ...)

		if not self.deconstructionPanel:IsExtractable() then
			addon.resultTooltip:SetHidden(true)
		end
	end)

	ZO_PreHook(SMITHING.researchPanel, 'Research',   Update) -- research
	local dialog = ZO_InventorySlot_GetItemListDialog():GetControl()
	ZO_PreHook(dialog, 'SetHidden', function(self, hidden)
		if hidden and not SMITHING.control:IsHidden() and not PopupTooltip:IsHidden() then
			ZO_PopupTooltip_Hide()
		end
	end)

	-- update our custom deconstruct tooltip
	ZO_PreHook(SMITHING.deconstructionPanel, 'SetExtractionSlotItem', function(extractionSlot, bag, slot)
		if GetSetting('tooltipMode'..SMITHING_MODE_DECONSTRUCT) ~= 'PopupTooltip' then return end

		local tooltip = addon.resultTooltip
		if bag and slot then
			local itemLink = GetItemLink(bag, slot)

			-- update our custom deconstruct tooltip
			tooltip:ClearLines()
			tooltip:SetLink(itemLink)
			tooltip:SetHidden(false)

			AddCraftingItemInfo(tooltip, itemLink)
		else
			tooltip:SetHidden(true)
		end
	end)

	-- ComparativeTooltips
	local orig = ItemTooltip.SetBagItem
	ItemTooltip.SetBagItem = function(self, bag, slot)
		orig(self, bag, slot)

		if not SMITHING.control:IsHidden()
			and GetSetting('compareMode'..SMITHING.mode)
			and GetSetting('tooltipMode'..SMITHING.mode) == 'ComparativeTooltip' then
			UpdateComparativeTooltips()
		end
	end

	CreateSettings()
end
em:RegisterForEvent(addonName, _G.EVENT_ADD_ON_LOADED, Initialize)
