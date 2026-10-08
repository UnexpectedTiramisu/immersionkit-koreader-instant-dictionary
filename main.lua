-- instantdictionary.koplugin/main.lua
--
-- Single tap on text behaves like KOReader's long-press word lookup.
-- This version deliberately routes through ReaderHighlight:onHold(),
-- so Japanese Support / languagesupport word expansion is preserved.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Device = require("device")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local util = require("util")

local Screen = Device.screen

local InstantDictionary = WidgetContainer:extend{
    name = "instantdictionary",
    is_doc_only = true,
}

local MAX_LOOKUP_DISTANCE = 36

-- Checks whether a given character should be ignored.
--   This is supposed to fix an annoyance I've had where characters such as 
--  【】（）were highlighted by themselves if I pressed near the end of a quotation, for example.
local function isNonLookupChar(char)
    if char:match("^%s$") or char:match("^%p$") then
        return true
    end

    local code = ffiUtil.utf8charcode(char)
    if not code then
        return false
    end

    return code == 0x00A0 -- no-break space
        or (code >= 0x2000 and code <= 0x206F) -- General Punctuation
        or (code >= 0x2E00 and code <= 0x2E7F) -- Supplemental Punctuation
        or (code >= 0x3001 and code <= 0x3003) -- CJK punctuation
        or (code >= 0x3008 and code <= 0x3011) -- CJK brackets
        or (code >= 0x3014 and code <= 0x301F) -- CJK brackets and marks
        or code == 0x3030 -- wavy dash
        or code == 0x303D -- part alternation mark
        or (code >= 0xFE10 and code <= 0xFE1F) -- Vertical Forms
        or (code >= 0xFE30 and code <= 0xFE4F) -- CJK Compatibility Forms
        or (code >= 0xFF01 and code <= 0xFF0F) -- fullwidth ASCII punctuation
        or (code >= 0xFF1A and code <= 0xFF20)
        or (code >= 0xFF3B and code <= 0xFF40)
        or (code >= 0xFF5B and code <= 0xFF65)
end

local function hasLookupText(text)
    text = util.cleanupSelectedText(text or "")
    for char in text:gmatch(util.UTF8_CHAR_PATTERN) do
        if not isNonLookupChar(char) then
            return true
        end
    end
    return false
end

local function pointInFooterContent(ui, pos)
    local footer = ui and ui.footer
    if not footer or not pos then
        return false
    end

    if footer.view and footer.view.flipping_visible
            and footer.progress_bar and footer.progress_bar.dimen then
        return footer.progress_bar.dimen:contains(pos)
    end

    if footer.view and not footer.view.footer_visible then
        return false
    end

    local dimen = footer.footer_content and footer.footer_content.dimen
    return dimen and dimen:contains(pos)
end

local function pointInRegisteredTouchZone(ui, zone_id, pos)
    local zone = ui and ui._zones and ui._zones[zone_id]
    local range = zone and zone.gs_range and zone.gs_range.range
    return range and range:contains(pos)
end

-- Checks how far a given position is away from a (word) box.
--   By default, long-press highlights can select word boxes that are very far away.
--   Combined with instant highlights, this would lead to constant accidental selections of far away text.
local function distanceFromBox(box, pos)
    local dx = 0
    if pos.x < box.x then
        dx = box.x - pos.x
    elseif pos.x > box.x + box.w then
        dx = pos.x - (box.x + box.w)
    end

    local dy = 0
    if pos.y < box.y then
        dy = box.y - pos.y
    elseif pos.y > box.y + box.h then
        dy = pos.y - (box.y + box.h)
    end

    return math.sqrt(dx * dx + dy * dy)
end

function InstantDictionary:isTapCloseToSelection(ges)
    local selected_text = self.ui.highlight and self.ui.highlight.selected_text
    local boxes = selected_text and (selected_text.sboxes or selected_text.pboxes)
    if not ges.pos or not selected_text or not boxes or not boxes[1] then
        return false
    end

    local max_distance = Screen:scaleBySize(MAX_LOOKUP_DISTANCE)
    local page = selected_text.pos0 and selected_text.pos0.page
    for _, box in ipairs(boxes) do
        local screen_box = box
        if page and self.ui.view and self.ui.view.pageToScreenTransform then
            screen_box = self.ui.view:pageToScreenTransform(page, box)
        end
        if screen_box and distanceFromBox(screen_box, ges.pos) <= max_distance then
            return true
        end
    end

    return false
end

-- Checks if the user's touch position is within a word selection box.
function InstantDictionary:isTapInsideSelection(ges)
    local selected_text = self.ui.highlight and self.ui.highlight.selected_text
    local boxes = selected_text and (selected_text.sboxes or selected_text.pboxes)
    if not ges.pos or not selected_text or not boxes or not boxes[1] then
        return false
    end

    local page = selected_text.pos0 and selected_text.pos0.page
    for _, box in ipairs(boxes) do
        local screen_box = box
        if page and self.ui.view and self.ui.view.pageToScreenTransform then
            screen_box = self.ui.view:pageToScreenTransform(page, box)
        end
        if screen_box and screen_box:contains(ges.pos) then
            return true
        end
    end

    return false
end

function InstantDictionary:init()
    if not Device:isTouchDevice() then
        return
    end

    self.ui:registerPostReaderReadyCallback(function()
        self:registerDictionaryTapZone()
    end)
end

function InstantDictionary:registerDictionaryTapZone()
    self.ui:registerTouchZones({
        {
            id = "instantdictionary_tap_word",
            ges = "tap",
            screen_zone = {
                ratio_x = 0,
                ratio_y = 0,
                ratio_w = 1,
                ratio_h = 1,
            },

            -- Take priority over page-turn taps and the normal highlight tap.
            -- Do not override tap_link, so links/footnotes should still work.
            overrides = {
                "readerhighlight_tap",
                "tap_forward",
                "tap_backward",
            },

            handler = function(ges)
                return self:onTapAsDictionaryHold(ges)
            end,
        },
    })

    logger.info("InstantDictionary: tap-to-dictionary touch zone registered")
end

function InstantDictionary:onTapAsDictionaryHold(ges)
    if pointInFooterContent(self.ui, ges.pos) then
        return false
    end

    local highlight = self.ui and self.ui.highlight
    if not highlight or not highlight.onHold or not highlight.onHoldRelease then
        return false
    end

    local old_single_word = G_reader_settings:readSetting("highlight_action_on_single_word")
    local old_default_action = G_reader_settings:readSetting("default_highlight_action")

    -- Force KOReader's normal long-press release path to choose dictionary.
    G_reader_settings:saveSetting("highlight_action_on_single_word", true)
    G_reader_settings:saveSetting("default_highlight_action", "dictionary")

    -- Executes onHold, then checks whether the highlight action is allowed.
    --  Highlight will be ignored if the touch position is too far away from a word,
    --  within the footer (statusbar), or the lookup consists of ignored characters.
    local ok, handled_or_err = pcall(function()
        local handled = highlight:onHold(nil, ges)

        if handled then
            if not (highlight.selected_text and hasLookupText(highlight.selected_text.text)) then
                highlight:onClose()
                return false
            end

            if pointInRegisteredTouchZone(self.ui, "readerfooter_tap", ges.pos)
                    and not self:isTapInsideSelection(ges) then
                highlight:onClose()
                return false
            end

            if not self:isTapCloseToSelection(ges) then
                highlight:onClose()
                return false
            end

            return highlight:onHoldRelease()
        end

        return false
    end)

    if old_single_word == nil then
        G_reader_settings:delSetting("highlight_action_on_single_word")
    else
        G_reader_settings:saveSetting("highlight_action_on_single_word", old_single_word)
    end

    if old_default_action == nil then
        G_reader_settings:delSetting("default_highlight_action")
    else
        G_reader_settings:saveSetting("default_highlight_action", old_default_action)
    end

    if not ok then
        logger.warn("InstantDictionary: synthetic hold/release failed:", handled_or_err)
        return false
    end

    return handled_or_err and true or false
end

return InstantDictionary
