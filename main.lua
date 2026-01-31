local DateTimeWidget = require("ui/widget/datetimewidget")
local InfoMessage = require("ui/widget/infomessage")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local NavigationTabs = require("navigationtabs")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local TopContainer = require("ui/widget/container/topcontainer")
local EventListener = require("ui/widget/eventlistener")
local logger = require("logger")
local datetime = require("datetime")
local Event = require("ui/event")
local _ = require("gettext")
local T = require("ffi/util").template
local Size = require("ui/size")

local navigation_mat = {}
local tabs = 1
local selected_button = nil
local opening_book = nil

local ID_MENU = "menu"
local ID_ADD = "add"
local ID_BOOKMARK = "bookmark"

local TabbedReader = EventListener:extend {
    name = "tabbedreader",
    max_tabs = 10,
    button_width = 30,
}

function TabbedReader:new(o)
    o = self:extend(o)
    -- Both o._init and o.init are called on object creation.
    -- But o._init is used for base widget initialization (basic components used to build other widgets).
    -- While o.init is for higher level widgets, for example Menu.
    if o._init then o:_init() end
    if o.init then o:init() end
    return o
end

function TabbedReader:init()
    self.ui.menu:registerToMainMenu(self)
    self.readerReady = false
    self.current_page = 1
    self.current_chapter = nil
    self.current_book_file = nil
    self.current_book_title = nil
    logger.dbg("TabbedReader: loaded")
end

function TabbedReader:tabsToStr()
    local tabs_table = "\nPage | Chapter | Book Title | Book Path\n===============================\n"

    for k, v in pairs(navigation_mat) do
        tabs_table = tabs_table .. v.page .. " | " .. v.chapter .. " | " .. v.book_title .. " | " .. v.book_file .. "\n"
    end

    return tabs_table
end

-- Some comments:
-- switch to document using readerui.switchDocument
-- doc_settings.data.doc_path is the document path
-- doc_settings.data.doc_props.title is the document title

function TabbedReader:onReaderReady(doc_settings)
    if not doc_settings then
        return
    end
    self.current_book_file = doc_settings.data.doc_path
    self.current_book_title = doc_settings.data.doc_props.title
    logger.dbg("TabbedReader: ", "path", doc_settings.data.doc_path)
    logger.dbg("TabbedReader: ", "title", doc_settings.data.doc_props.title)

    logger.dbg("TabbedReader:onReaderReady", self:tabsToStr())

    local buttons = self:buildButtons()

    local nav_selected = navigation_mat[selected_button]

    if not nav_selected then
        nav_selected = {}
        nav_selected.page = self.current_page
        nav_selected.chapter = self.current_chapter
        nav_selected.book_file = self.current_book_file
        nav_selected.book_title = self.current_book_title
        navigation_mat[selected_button] = nav_selected
    end

    if nav_selected.page and nav_selected.page ~= self.current_page then
        self.ui:handleEvent(Event:new("GotoPage", nav_selected.page))
        logger.dbg("TabbedReader: ", "onReaderReady GotoPage", nav_selected.page)
    end

    if nav_selected.book_file and nav_selected.book_file ~= self.current_book_file then
        if opening_book then
            logger.dbg("TabbedReader: ", "ERROR - wrong book. Expected: ", nav_selected.book_file, "actual:",
                self.current_book_file)
        else
            --    Book opend from the file explorer
            nav_selected.page = self.current_page -- reset page info as it's a new book
            nav_selected.chapter = self.current_chapter
            nav_selected.book_file = self.current_book_file
            nav_selected.book_title = self.current_book_title
        end
    end

    opening_book = nil

    self.button_dialog = NavigationTabs:new {
        buttons = buttons,
        callback = function(button_id, ges)
            self:navigationCallback(button_id, ges)
        end,
    }
    self.ui.view:registerViewModule("button_dialog", self.button_dialog)
    self.button_dialog:initGesListener()
    self.button_dialog:setSelected(selected_button)
    self:refreshBookmark()
    logger.dbg("TabbedReader: ", "selected_button", selected_button, self.current_page, self.current_chapter)
    self.readerReady = true
end

function TabbedReader:getIdForButton(index)
    return "tab_" .. index
end

function TabbedReader:buildButtons()
    local buttons = {}

    buttons[1] = {
        icon = "appbar.menu",
        icon_width = self.button_width * 0.9,
        icon_height = self.button_width * 0.9,
        id = ID_MENU,
        width = self.button_width,
        unselectable = true
    }

    for i = 1, tabs do
        local id = self:getIdForButton(i)
        buttons[i + 1] = {
            text_func = function()
                local nav_entry = navigation_mat[id]
                logger.dbg("TabbedReader: ", "nav_entry", id, nav_entry, nav_entry and nav_entry.chapter)
                if nav_entry then
                    if nav_entry.book_title and nav_entry.chapter then
                        return nav_entry.book_title .. ": " .. nav_entry.chapter
                    end
                    return nav_entry.book_title or nav_entry.chapter or "Tab " .. i
                end
                return "Tab " .. i
            end,
            id = id,
        }
        if not selected_button then
            selected_button = id
        end
    end

    local index = tabs + 2

    if tabs < self.max_tabs then
        buttons[index] = {
            text = "+",
            id = ID_ADD,
            width = self.button_width,
            unselectable = true,
        }
        index = index + 1
    end

    buttons[index] = {
        icon = "bookmark",
        icon_width = self.button_width * 0.9,
        icon_height = self.button_width * 0.9,
        id = ID_BOOKMARK,
        width = self.button_width,
        unselectable = true,
    }
    index = index + 1

    return { buttons }
end

function TabbedReader:reloadLayout()
    local buttons = self:buildButtons()
    self.button_dialog:reloadButtons(buttons)
    self.button_dialog:initGesListener()
    self.button_dialog:setSelected(selected_button)
    self:refreshBookmark()
end

function TabbedReader:refreshBookmark()
    local button = self.button_dialog:getButtonById(ID_BOOKMARK)
    button.frame.invert = self.ui.bookmark:isPageBookmarked()
    button:refresh()
end

function TabbedReader:navigationTapCallback(button_id)
    if not navigation_mat[button_id] then
        logger.dbg("TabbedReader: ", "navigationCallback", "id not found", self.current_book_file,
            self.current_book_title)
        local nav_entry = {}
        nav_entry.page = 1
        nav_entry.book_file = self.current_book_file
        nav_entry.book_title = self.current_book_title
        navigation_mat[button_id] = nav_entry
        self.button_dialog:refreshButton(selected_button)
    end

    logger.dbg("TabbedReader: ", "navigationCallback", selected_button, button_id, navigation_mat[button_id].page)
    selected_button = button_id

    local new_file = navigation_mat[button_id].book_file
    local new_page = navigation_mat[button_id].page

    if new_file ~= nil and new_file ~= self.current_book_file then
        opening_book = new_file
        self.ui:showReader(new_file, nil, true)
    else
        self.ui:handleEvent(Event:new("GotoPage", new_page))
        logger.dbg("TabbedReader: ", "GotoPage", new_page)
    end

    self.button_dialog:setSelected(selected_button)
end

function TabbedReader:navigationHoldCallback(button_id)

end

function TabbedReader:navigationCallback(button_id, ges)
    if button_id == ID_MENU then
        logger.dbg("TabbedReader: ", "Menu pressed")
        return
    end

    if button_id == ID_ADD then
        logger.dbg("TabbedReader: ", "Add pressed")
        if tabs >= self.max_tabs then
            logger.dbg("TabbedReader: ", "Max tabs reached")
            return
        end
        tabs = tabs + 1
        self:reloadLayout()
        self:navigationTapCallback(self:getIdForButton(tabs))
        return
    end

    if button_id == ID_BOOKMARK then
        logger.dbg("TabbedReader: ", "Bookmark pressed")
        self.ui.bookmark:onToggleBookmark()
        self:refreshBookmark()
        return
    end

    if ges.ges == "tap" then
        self:navigationTapCallback(button_id)
        return
    end

    if ges.ges == "hold" then
        self:navigationHoldCallback(button_id)
        return
    end
end


function TabbedReader:onAnnotationsModified(item)
    self:refreshBookmark()
end

function TabbedReader:onCloseDocument()
end

function TabbedReader:onPageUpdate(page)
    logger.dbg("TabbedReader: ", "Page update", self.current_page, "=>", page, self.ui.toc:getTocTitleOfCurrentPage())
    self.current_page = page
    self.current_chapter = self.ui.toc:getTocTitleOfCurrentPage()

    if selected_button then
        navigation_mat[selected_button].page = self.current_page
        navigation_mat[selected_button].chapter = self.current_chapter
        if self.readerReady then
            self.button_dialog:refreshButton(selected_button)
        end
    end
end

function TabbedReader:onPosUpdate(pos)
    logger.dbg("Pos update", pos)
end

function TabbedReader:addToMainMenu(menu_items)
    menu_items.twenty_twenty = {
        text_func = function()
            return _("Tabbed Reader")
        end,
        sorting_hint = "more_tools",
        sub_item_table = {
        },
    }
end

function TabbedReader:onResume()

end

function TabbedReader:onSetDimensions(dimen)
    logger.dbg("TabbedReader: ", "onSetDimensions main")
    if self.readerReady then
        self:onReaderReady()
    end
end

return TabbedReader
