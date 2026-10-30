-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)
local Book = addon.SpellbookModule
local tr = addon.L

local floor, max, min, pairs, ipairs = math.floor, math.max, math.min, pairs, ipairs
local tip = GameTooltip

local TAB_PREFIX = "DragonUI_SpellbookFrameTab"
local STATE_SETTERS = { "SetNormalTexture", "SetPushedTexture", "SetDisabledTexture", "SetHighlightTexture" }
local TAB_LEFT, TAB_BOTTOM = 70, -83
-- Tabs never start left of this: the class portrait stays at scale 1 over the top-left corner.
local TAB_MIN_LEFT = 60
local SEARCH_W, SEARCH_MIN = 220, 90
local CORNER_SPEED = 32

-- Left to right on screen; the category ids behind them (and the secure data) keep their numbers.
local TAB_ORDER = { Book.GENERAL, Book.CLASS, Book.PET }
local TAB_BINDINGS = { [Book.CLASS] = "TOGGLESPELLBOOK", [Book.GENERAL] = "TOGGLESPELLBOOK",
    [Book.PET] = "TOGGLEPETBOOK" }

local tabs, flagged = {}, {}
local drawn = {}
local pager, pageText, emptyText, gear, modeButton
local laying, menuHooked, gearRight
local cornerAt = 1
local flashClock = 0

-- Redraw from the secure state ------------------------------------------------------------------

local function emptyMessage(model)
    if not model or model.total > 0 or not Book.query then return "" end
    return tr["No spells match your search"]
end

function Book.Sync(withSound)
    if not Book.IsOpen() then return end
    Book.CloseRanks()
    local root = Book.root
    local cat = root:GetAttribute("cat")
    local page = root:GetAttribute("page-" .. cat) or 1
    if withSound and drawn.cat then
        if cat ~= drawn.cat then
            PlaySound("igCharacterInfoTab")
        elseif page ~= drawn.page then
            PlaySound("igAbiliityPageTurn")
        end
    end
    drawn.cat, drawn.page = cat, page
    Book.DrawSpread(cat, page)
    local model = Book.models[cat]
    pageText:SetFormattedText(tr["Page %d/%d"], page, model and #model.spreads or 1)
    emptyText:SetText(emptyMessage(model))
    Book.PaintTabs(cat)
    Book.RefreshHoverTooltip()
    -- A page turn can enable or disable the arrow under a pointer that never moved.
    Book.Animate("corner", Book.CornerStep)
end

-- CallMethod targets: controls redraw with sounds, plain-code layout passes redraw silently.
local function syncing(withSound)
    return function() Book.Sync(withSound) end
end
Book.SyncLoud, Book.SyncQuiet = syncing(true), syncing(false)

-- Page corner -------------------------------------------------------------------------------------

-- One of the flipbook's eight frames on a corner from Book.CreatePageCorner; 1 is the corner at rest.
function Book.PaintCorner(corner, frame)
    local atlas = addon.atlasinfo["spellbook-corner-flipbook-evergreen"]
    local width, height = (atlas[5] - atlas[4]) / 4, (atlas[7] - atlas[6]) / 2
    local column, row = (frame - 1) % 4, floor((frame - 1) / 4)
    corner:SetTexCoord(atlas[4] + column * width, atlas[4] + (column + 1) * width,
        atlas[6] + row * height, atlas[6] + (row + 1) * height)
end

local function showCorner(frame)
    Book.PaintCorner(Book.corner, frame)
end

-- Disabled arrows send no OnLeave, so while tracking the step itself asks where the pointer is.
function Book.CornerStep(elapsed)
    local over = pager:IsMouseOver()
    local goal = over and 8 or 1
    if cornerAt < goal then
        cornerAt = min(goal, cornerAt + elapsed * CORNER_SPEED)
    elseif cornerAt > goal then
        cornerAt = max(goal, cornerAt - elapsed * CORNER_SPEED)
    end
    showCorner(floor(cornerAt + 0.5))
    return over or cornerAt > 1
end

function Book.PagerEnter()
    Book.Animate("corner", Book.CornerStep)
end

function Book.FlattenCorner()
    Book.Animate("corner", nil)
    cornerAt = 1
    showCorner(1)
end

function Book.ForgetDrawn()
    drawn.cat, drawn.page = nil, nil
    Book.FlattenCorner()
end

-- Category tabs -----------------------------------------------------------------------------------

-- Selecting re-levels a tab above its neighbours; the flash is a child and must stay on top of it.
local function liftFlashes()
    for index = 1, Book.CATEGORIES do
        local tab = tabs[index]
        tab.flash:SetFrameLevel(tab:GetFrameLevel() + 1)
    end
end

-- The scale-1 search box narrows when small content scales bring the tabs close, down to a floor.
local function fitSearch(tabsRight)
    if not gearRight then return end
    local searchRight = Book.root:GetWidth() + gearRight - gear:GetWidth() - 6
    Book.search:SetWidth(max(SEARCH_MIN, min(SEARCH_W, searchRight - tabsRight - 12)))
end

-- Skins labelled tabs (CharacterFrameTabButtonTemplate) and hangs them left to right from the wood
-- strip of a book at this content scale; place(index, x, y) can put more at each tab. Returns the
-- right edge of the last tab. Also for integrations that draw another character's book.
function Book.PlaceTabs(root, faces, scale, place)
    local CP = addon.CharacterPanel
    local x, y = Book.OnBook("TOPLEFT", TAB_LEFT, TAB_BOTTOM, scale)
    x = max(x, TAB_MIN_LEFT)
    if not faces[1] then return x end
    -- Below ~0.56 the wood strip is shorter than a tab; the tab then keeps its top under the title.
    y = min(y, -Book.BAND - faces[1]:GetHeight())
    for index, face in ipairs(faces) do
        if CP and CP.ReskinTab then
            CP.ReskinTab(face, true)
        else
            PanelTemplates_TabResize(face, 0)
        end
        face:ClearAllPoints()
        face:SetPoint("BOTTOMLEFT", root, "TOPLEFT", x, y)
        if place then place(index, x, y) end
        x = x + face:GetWidth() + 1
    end
    return x
end

function Book.LayoutTabs()
    if laying then return end
    laying = true
    local root = Book.root
    local locked = Book.Locked()
    local faces, cats = {}, {}
    for _, cat in ipairs(TAB_ORDER) do
        local face, label = tabs[cat], Book.labels[cat]
        face:SetShownCompat(label ~= nil)
        -- The catcher is protected; tabs never change in combat, so it keeps its last place.
        if not locked then Book.tabCatchers[cat]:SetShownCompat(label ~= nil) end
        if label then
            face:SetText(label)
            faces[#faces + 1], cats[#cats + 1] = face, cat
        end
    end
    fitSearch(Book.PlaceTabs(root, faces, Book.contentScale, function(index, x, y)
        if locked then return end
        local face, catcher = faces[index], Book.tabCatchers[cats[index]]
        catcher:ClearAllPoints()
        catcher:SetPoint("BOTTOMLEFT", root, "TOPLEFT", x, y)
        catcher:SetSize(face:GetWidth(), face:GetHeight())
    end))
    liftFlashes()
    laying = false
end

-- The scale-1 controls on a book at this content scale, each optional: `top` right-aligned below the
-- frame's top-right corner (this book's gear), the pager, its page corner and the page arrows from
-- Book.DressPageArrow. Also for integrations that draw another character's book.
function Book.PlaceControlsOn(root, scale, controls)
    local top = controls.top
    if top then
        top:ClearAllPoints()
        top:SetPoint("RIGHT", root, "TOPRIGHT", Book.OnBook("TOPRIGHT", -14, -55, scale))
    end
    local x, y = Book.OnBook("BOTTOMRIGHT", -75, 40, scale)
    if controls.pager then
        controls.pager:ClearAllPoints()
        controls.pager:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", x, y)
    end
    for _, arrow in ipairs(controls.arrows or {}) do
        arrow:ClearAllPoints()
        arrow:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", x + arrow.offset, y)
    end
    if controls.corner then
        controls.corner:ClearAllPoints()
        controls.corner:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", Book.OnBook("BOTTOMRIGHT", -15, 6, scale))
    end
end

-- Out of combat only (the page arrows are secure); after every content-scale change.
function Book.PlaceControls()
    local root, scale = Book.root, Book.contentScale
    gearRight = Book.OnBook("TOPRIGHT", -14, -55, scale)
    Book.PlaceControlsOn(root, scale, { top = gear, pager = pager, corner = Book.corner })
    Book.PlaceArrows()
    if Book.tabCatchers then Book.LayoutTabs() end
end

function Book.PaintTabs(cat)
    for index = 1, Book.CATEGORIES do
        local tab = tabs[index]
        if tab:IsShown() then
            if index == cat then
                PanelTemplates_SelectTab(tab)
            else
                PanelTemplates_DeselectTab(tab)
            end
        end
    end
    liftFlashes()
end

function Book.TabEnter(catcher)
    local cat = catcher:GetID()
    tabs[cat]:LockHighlight()
    local label = Book.labels[cat]
    if not label then return end
    local binding = TAB_BINDINGS[cat]
    tip:SetOwner(catcher, "ANCHOR_RIGHT")
    tip:SetText(binding and MicroButtonTooltipText(label, binding) or label, 1, 1, 1)
    tip:Show()
end

function Book.TabLeave(catcher)
    tabs[catcher:GetID()]:UnlockHighlight()
    if tip:IsOwned(catcher) then tip:Hide() end
end

local function flashStep(elapsed)
    flashClock = (flashClock + elapsed) % 1
    local alpha = flashClock < 0.5 and flashClock / 0.5 or (1 - flashClock) / 0.5
    local any = false
    for cat in pairs(flagged) do
        tabs[cat].flash:SetAlpha(alpha)
        any = true
    end
    return any
end

function Book.FlagTab(skillTab)
    if Book.root:GetAttribute("cat") == Book.PET then return end
    flagged[skillTab == 1 and Book.GENERAL or Book.CLASS] = true
    if Book.IsOpen() then Book.StartFlashes() end
end

function Book.StartFlashes()
    for cat in pairs(flagged) do
        tabs[cat].flash:Show()
    end
    if next(flagged) then Book.Animate("flash", flashStep) end
end

function Book.StopFlashes()
    for cat in pairs(flagged) do
        tabs[cat].flash:Hide()
        flagged[cat] = nil
    end
end

function Book.TabClicked(catcher)
    local cat = catcher:GetID()
    flagged[cat] = nil
    tabs[cat].flash:Hide()
end

local function buildTabs(deck)
    local holder = CreateFrame("Frame", nil, deck)
    holder:SetAllPoints(deck)
    holder:SetFrameLevel(Book.Level("content"))
    for cat = 1, Book.CATEGORIES do
        local tab = CreateFrame("Button", TAB_PREFIX .. cat, holder, "CharacterFrameTabButtonTemplate")
        tab:Hide()
        -- The secure catcher on top takes every click; the template's own handler targets CharacterFrame.
        tab:SetScript("OnClick", nil)
        tab:EnableMouse(false)
        tab._duiRelayout = Book.LayoutTabs
        local flash = CreateFrame("Frame", nil, tab)
        flash:SetAllPoints(tab)
        flash:Hide()
        local shimmer = flash:CreateTexture(nil, "ARTWORK")
        shimmer:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
        shimmer:SetTexCoord(0, 1, 1, 0)
        shimmer:SetBlendMode("ADD")
        shimmer:SetAllPoints(flash)
        tab.flash = flash
        tabs[cat] = tab
    end
end

-- Search box --------------------------------------------------------------------------------------

-- The search box, unplaced. onQuery receives every change as Book.NormalizeQuery's query; refuse,
-- when given, can keep focus and the clear button away. Also for integrations that draw another
-- character's book.
function Book.CreateSearchBox(parent, onQuery, refuse)
    local finder = CreateFrame("EditBox", nil, parent)
    finder:SetSize(SEARCH_W, 22)
    finder:SetAutoFocus(false)
    finder:EnableMouse(true)
    finder:SetFontObject(ChatFontNormal)
    finder:SetTextInsets(18, 20, 0, 0)
    -- Swallows the wheel so scrolling over the search box never turns the page underneath.
    finder:EnableMouseWheel(true)
    finder:SetScript("OnMouseWheel", addon._noop)

    local border = "Interface\\Common\\Common-Input-Border"
    local capLeft = finder:CreateTexture(nil, "BACKGROUND")
    capLeft:SetTexture(border)
    capLeft:SetTexCoord(0, 0.0625, 0, 0.625)
    capLeft:SetSize(8, 20)
    capLeft:SetPoint("LEFT", finder, "LEFT", -5, 0)
    local capRight = finder:CreateTexture(nil, "BACKGROUND")
    capRight:SetTexture(border)
    capRight:SetTexCoord(0.9375, 1, 0, 0.625)
    capRight:SetSize(8, 20)
    capRight:SetPoint("RIGHT", finder, "RIGHT", 0, 0)
    local span = finder:CreateTexture(nil, "BACKGROUND")
    span:SetTexture(border)
    span:SetTexCoord(0.0625, 0.9375, 0, 0.625)
    span:SetHeight(20)
    span:SetPoint("TOPLEFT", capLeft, "TOPRIGHT", 0, 0)
    span:SetPoint("BOTTOMRIGHT", capRight, "BOTTOMLEFT", 0, 0)

    local glass = finder:CreateTexture(nil, "OVERLAY")
    glass:SetTexture(addon._dir .. "Collections\\UI-Searchbox-Icon")
    glass:SetSize(14, 14)
    glass:SetPoint("LEFT", finder, "LEFT", 2, -1.5)

    local hint = finder:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", finder, "LEFT", 20, 0)
    hint:SetText(SEARCH)

    local clear = CreateFrame("Button", nil, finder)
    clear:SetSize(16, 16)
    clear:SetPoint("RIGHT", finder, "RIGHT", -3, 0)
    clear:Hide()
    local cross = clear:CreateTexture(nil, "ARTWORK")
    cross:SetTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    cross:SetAllPoints(clear)
    cross:SetAlpha(0.6)
    clear:SetScript("OnEnter", function() cross:SetAlpha(1) end)
    clear:SetScript("OnLeave", function() cross:SetAlpha(0.6) end)
    clear:SetScript("OnClick", function()
        if refuse and refuse() then return end
        finder:SetText("")
        finder:ClearFocus()
    end)

    local function syncHints()
        local text = finder:GetText()
        clear:SetShownCompat(text ~= "")
        hint:SetShownCompat(text == "" and not finder.focused)
    end

    finder:SetScript("OnEditFocusGained", function()
        if refuse and refuse() then return finder:ClearFocus() end
        finder.focused = true
        syncHints()
    end)
    finder:SetScript("OnEditFocusLost", function()
        finder.focused = false
        syncHints()
    end)
    -- The first Esc only empties the box and drops focus; the next one reaches the window.
    finder:SetScript("OnEscapePressed", function()
        if finder:GetText() ~= "" then finder:SetText("") end
        finder:ClearFocus()
    end)
    finder:SetScript("OnEnterPressed", finder.ClearFocus)
    finder:SetScript("OnTextChanged", function(self)
        syncHints()
        onQuery(Book.NormalizeQuery(self:GetText()))
    end)
    return finder
end

local function buildSearch(bar)
    Book.search = Book.CreateSearchBox(bar, function(query)
        if query == Book.query or Book.Locked() then return end
        Book.query = query
        Book.RestartFromFirstPage()
    end, Book.RefuseInCombat)
    Book.search:SetPoint("RIGHT", gear, "LEFT", -6, 0)
end

-- Settings menu -----------------------------------------------------------------------------------

local function flipOption(flip)
    if Book.RefuseInCombat() then return end
    flip(Book.Config())
    Book.RestartFromFirstPage()
end

local function checkItem(label, isOn, flip)
    return { text = label, keepShown = true, checked = isOn, func = function() flipOption(flip) end }
end

-- Ranks follow the client setting behind Blizzard's own checkbox, so both books agree.
local function allRanksOn()
    return GetCVarBool("ShowAllSpellRanks") and true or false
end

local function styleItem(label, style)
    return {
        text = label,
        keepShown = true,
        indent = 12,
        checked = function() return Book.RankStyle() == style end,
        func = function()
            if Book.RefuseInCombat() then return end
            addon.RefreshSpellbookRankSelector(style)
        end,
    }
end

local MENU, fillMenu = {}, nil

local BASE = {
    { text = tr["Spellbook settings"], isTitle = true },
    checkItem(tr["Show All Ranks"], allRanksOn, function()
        SetCVar("ShowAllSpellRanks", allRanksOn() and "0" or "1")
    end),
    checkItem(tr["Hide Passives"], function() return Book.Config().hidePassives end, function(profile)
        profile.hidePassives = not profile.hidePassives
    end),
    checkItem(tr["Hide Unlearned Spells"], function() return Book.Config().hideUnlearned end, function(profile)
        profile.hideUnlearned = not profile.hideUnlearned
    end),
    checkItem(tr["Highlight spells missing from action bars"], function() return Book.Config().highlightUnbound end,
        function(profile) profile.highlightUnbound = not profile.highlightUnbound end),
    {
        text = tr["Show Lower Rank Selector"],
        keepShown = true,
        checked = function() return Book.Config().rankSelectorShown ~= false end,
        func = function()
            if Book.RefuseInCombat() then return end
            local profile = Book.Config()
            profile.rankSelectorShown = profile.rankSelectorShown == false
            fillMenu()
            addon.RefreshSpellbookRankSelector()
        end,
    },
}

local STYLE_CHOICES = {
    styleItem(tr["Menu under the icon"], "dropdown"),
    styleItem(tr["Side flyout"], "flyout"),
}

-- Filled in place: the open menu redraws from this same table, so the style choices come and go live.
fillMenu = function()
    for index = #MENU, 1, -1 do
        MENU[index] = nil
    end
    for _, entry in ipairs(BASE) do
        MENU[#MENU + 1] = entry
    end
    if Book.Config().rankSelectorShown == false then return end
    for _, entry in ipairs(STYLE_CHOICES) do
        MENU[#MENU + 1] = entry
    end
end

function Book.MenuClosed()
    if Book.Locked() or addon.Menu.IsOpenFor(gear) then return end
    Book.root:SetAttribute("wheel-off", nil)
end

function Book.CloseMenu()
    if addon.Menu.IsOpenFor(gear) then addon.Menu.Close() end
end

-- The menu floats over the window; while it is open the wheel must not page the book below it.
local function openMenu()
    if Book.RefuseInCombat() then return end
    fillMenu()
    addon.Menu.Open(gear, MENU)
    if not addon.Menu.IsOpenFor(gear) then return end
    Book.root:SetAttribute("wheel-off", true)
    if not menuHooked then
        menuHooked = true
        _G.DragonUIMenu:HookScript("OnHide", Book.MenuClosed)
    end
end

local function cogLayer(layer)
    local art = gear:CreateTexture(nil, layer)
    art:SetAtlasTexture("questlog-icon-setting", true)
    art:SetPoint("CENTER", gear, "CENTER", 0, 0)
    return art
end

local function buildGear(bar)
    gear = CreateFrame("Button", nil, bar)
    gear:SetSize(15, 16)
    cogLayer("ARTWORK")
    local lit = cogLayer("HIGHLIGHT")
    lit:SetBlendMode("ADD")
    lit:SetAlpha(0.4)
    gear:SetScript("OnEnter", function()
        tip:SetOwner(gear, "ANCHOR_LEFT")
        tip:SetText(tr["Spellbook settings"])
        tip:Show()
    end)
    gear:SetScript("OnLeave", GameTooltip_Hide)
    gear:SetScript("OnClick", openMenu)
end

-- One or two pages button -------------------------------------------------------------------------

local function modeTooltip(button)
    tip:SetOwner(button, "ANCHOR_LEFT")
    tip:SetText(button.isWide() and tr["Show single page"] or tr["Show second page"])
    tip:Show()
end

-- Shows which way a button from Book.CreateModeButton switches; this book's own by default.
function Book.PaintModeButton(button)
    button = button or modeButton
    local atlas = button.isWide() and "redbutton-condense" or "redbutton-expand"
    button:GetNormalTexture():SetAtlasTexture(atlas)
    button:GetPushedTexture():SetAtlasTexture(atlas .. "-pressed")
    button:GetDisabledTexture():SetAtlasTexture(atlas .. "-disabled")
    if tip:IsOwned(button) then modeTooltip(button) end
end

-- The red one-or-two-pages button; isWide() tells whether two pages show. Also for integrations
-- that draw another character's book.
function Book.CreateModeButton(root, level, isWide, onClick)
    local button = CreateFrame("Button", nil, root)
    button:SetSize(24, 24)
    button:SetPoint("TOPRIGHT", root, "TOPRIGHT", -24, 0)
    button:SetFrameLevel(level)
    button.isWide = isWide
    -- Every state needs a texture object before SetAtlasTexture can dress it.
    local sheet = addon.atlasinfo["redbutton-highlight"][1]
    for _, setter in ipairs(STATE_SETTERS) do
        button[setter](button, sheet)
    end
    button:GetHighlightTexture():SetAtlasTexture("redbutton-highlight")
    button:GetHighlightTexture():SetBlendMode("ADD")
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", modeTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

local function buildModeButton(root)
    modeButton = Book.CreateModeButton(root, Book.Level("buttons"), Book.Wide,
        function() Book.SetMinimized(Book.Wide()) end)
end

-- Pager and empty line ----------------------------------------------------------------------------

-- The pager block and its page line, unplaced; Book.PlaceControlsOn puts them on the page. Also for
-- integrations that draw another character's book.
function Book.CreatePager(parent)
    local block = CreateFrame("Frame", nil, parent)
    block:SetSize(146, 32)
    local line = block:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    -- Ends just left of the back arrow (see PlaceArrows), so longer translations grow leftwards.
    line:SetPoint("RIGHT", block, "RIGHT", -76, 0)
    line:SetJustifyH("RIGHT")
    line:SetTextColor(0, 0, 0)
    line:SetShadowOffset(0, 0)
    return block, line
end

-- A page arrow's art ("Next" or "Prev") and its offset from the pager's spot.
function Book.DressPageArrow(turner, direction)
    turner:SetSize(32, 32)
    turner.offset = direction == "Prev" and -32 - 8 or 0
    local art = "Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-"
    turner:SetNormalTexture(art .. "Up")
    turner:SetPushedTexture(art .. "Down")
    turner:SetDisabledTexture(art .. "Disabled")
    turner:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
end

-- The line a filtered page shows when nothing matches, centred on the first page of the stage.
function Book.CreateEmptyLine(parent, stage)
    local grid = Book.GRID
    local line = Book.InkLabel(parent, "ARTWORK", "GameFontHighlightLarge", 16)
    line:SetJustifyH("CENTER")
    line:SetPoint("CENTER", stage, "TOPLEFT", Book.PageLeft(1) + grid.viewW / 2, grid.viewTop - grid.viewH / 2)
    return line
end

local function buildPager(bar)
    pager, pageText = Book.CreatePager(bar)
    pager:EnableMouse(true)
    pager:SetScript("OnEnter", Book.PagerEnter)
end

local function buildEmptyLine(bar)
    emptyText = Book.CreateEmptyLine(bar, Book.stage)
end

function Book.BuildControls()
    local root, stage = Book.root, Book.stage
    -- Tabs, search, gear and pager stay at scale 1 like the frame; PlaceControls puts them on the book.
    local deck = CreateFrame("Frame", nil, root)
    deck:SetAllPoints(root)
    deck:SetFrameLevel(Book.Level("content"))
    buildTabs(deck)
    buildGear(deck)
    buildSearch(deck)
    buildPager(deck)
    local page = CreateFrame("Frame", nil, stage)
    page:SetAllPoints(stage)
    page:SetFrameLevel(Book.Level("content"))
    buildEmptyLine(page)
    buildModeButton(root)
    Book.LayoutMode()
    Book.ApplyScale()
    showCorner(1)
end
