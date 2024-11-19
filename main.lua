local DateTimeWidget = require("ui/widget/datetimewidget")
local InfoMessage = require("ui/widget/infomessage")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local NavigationTabs = require("navigationtabs")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local TopContainer = require("ui/widget/container/topcontainer")
local logger = require("logger")
local datetime = require("datetime")
local Event = require("ui/event")
local _ = require("gettext")
local T = require("ffi/util").template
local Size = require("ui/size")

local navigation_mat = {}
local selected_button = nil
local opening_book = nil

local TabbedReader = WidgetContainer:extend {
    name = "tabbedreader",
    tabs = 3,
}

function TabbedReader:init()
    self.ui.menu:registerToMainMenu(self)
    self.readerReady = false
    self.navigation_mat = navigation_mat
    self.selected_button = selected_button
    self.current_page = 1
    self.current_chapter = nil
    self.current_book_file = nil
    self.current_book_title = nil
    print("TabbedReader loaded")
end

-- Some comments:
-- switch to document using readerui.switchDocument
-- doc_settings.data.doc_path is the document path
-- doc_settings.data.doc_props.title is the document title

function TabbedReader:onReaderReady(doc_settings)
    self.current_book_file = doc_settings.data.doc_path
    self.current_book_title = doc_settings.data.doc_props.title
    print("path", doc_settings.data.doc_path)
    print("title", doc_settings.data.doc_props.title)

    for k, v in pairs(self.navigation_mat) do
        print(k, v.page, v.chapter, v.book_file, v.book_title)
    end

    self.readerReady = true

    local buttons = {}

    for i = 1, self.tabs do
        local id = "tab_" .. i
        buttons[i] = {
            text_func = function()
                local nav_entry = self.navigation_mat[id]
                print("nav_entry", id, nav_entry, nav_entry and nav_entry.chapter)
                if nav_entry then
                    if nav_entry.book_title and nav_entry.chapter then
                        return nav_entry.book_title .. ": " .. nav_entry.chapter
                    end
                    return nav_entry.book_title or nav_entry.chapter or "Tab " .. i
                end
                return "Tab " .. i
            end,
            id = id
        }
        if not self.selected_button then
            self.selected_button = id
            selected_button = id
        end
    end

    local nav_selected = self.navigation_mat[self.selected_button]

    if not nav_selected then
        nav_selected = {}
        nav_selected.page = self.current_page
        nav_selected.chapter = self.current_chapter
        nav_selected.book_file = self.current_book_file
        nav_selected.book_title = self.current_book_title
        self.navigation_mat[self.selected_button] = nav_selected
    end

    if nav_selected.page and nav_selected.page ~= self.current_page then
        self.ui:handleEvent(Event:new("GotoPage", nav_selected.page))
    end

    if nav_selected.book_file and nav_selected.book_file ~= self.current_book_file then
        if opening_book then
            print("ERROR - wrong book", nav_selected.book_file)
        else
            --    Book opend from the file explorer
            nav_selected.book_file = self.current_book_file
            nav_selected.book_title = self.current_book_title
        end
    end
    opening_book = nil

    self.button_dialog = NavigationTabs:new {
        buttons = { buttons },
        callback = function(button_id)
            self:navigationCallback(button_id)
        end,
    }
    self.ui.view:registerViewModule("button_dialog", self.button_dialog)
    self.button_dialog:initGesListener()
    self.button_dialog:setSelected(self.selected_button)
    print("selected_button", self.selected_button, self.current_page, self.current_chapter)
end

function TabbedReader:navigationCallback(button_id)
    if button_id == "add" then
        print("Add pressed")
        return
    end

    if not self.navigation_mat[button_id] then
        print("navigationCallback", "id not found", self.current_book_file, self.current_book_title)
        local nav_entry = {}
        nav_entry.page = 1
        nav_entry.book_file = self.current_book_file
        nav_entry.book_title = self.current_book_title
        self.navigation_mat[button_id] = nav_entry
        self.button_dialog:refreshButton(self.selected_button)
    end

    print("navigationCallback", self.selected_button, button_id, self.navigation_mat[button_id].page)
    self.selected_button = button_id
    selected_button = self.selected_button

    local new_file = self.navigation_mat[button_id].book_file
    local new_page = self.navigation_mat[button_id].page

    if new_file ~= nil and new_file ~= self.current_book_file then
        opening_book = new_file
        self.ui:showReader(new_file, nil, true)
    else
        self.ui:handleEvent(Event:new("GotoPage", new_page))
    end
end

function TabbedReader:onCloseDocument()
end

function TabbedReader:onPageUpdate(page)
    print("Page update", page, self.ui.toc:getTocTitleOfCurrentPage())
    self.current_page = page
    self.current_chapter = self.ui.toc:getTocTitleOfCurrentPage()
    if self.selected_button then
        self.navigation_mat[self.selected_button].page = self.current_page
        self.navigation_mat[self.selected_button].chapter = self.current_chapter
        self.button_dialog:refreshButton(self.selected_button)
    end
end

function TabbedReader:onPosUpdate(pos)
    print("Pos update", pos)
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
    print("onSetDimensions main")
    if self.readerReady then
        self:onReaderReady()
    end
end

return TabbedReader
