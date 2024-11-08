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

local TabbedReader = WidgetContainer:extend {
    name = "tabbedreader",
    tabs = 3,
}

function TabbedReader:init()
    self.ui.menu:registerToMainMenu(self)
    self.readerReady = false
    self.navigation_mat = {}
    self.selected_button = nil
    self.current_page = 1
    self.current_chapter = nil
end

function TabbedReader:onReaderReady()
    self.readerReady = true

    local buttons = {}

    for i = 1, self.tabs do
        local id = "tab_"..i
        buttons[i] = {
            text_func = function ()
                local nav_entry = self.navigation_mat[id]
                print("nav_entry", id, nav_entry, nav_entry and nav_entry.chapter)
                if nav_entry then
                    if nav_entry.chapter then
                        return i..": "..nav_entry.chapter
                    end
                end
                return "Tab "..i
            end,
            id = id
        }
        self.navigation_mat[id] = {
            page = 1,
            chapter = nil,
        }
    end

    self.button_dialog = NavigationTabs:new {
        buttons = { buttons },
        callback = function(button_id)
            self:navigationCallback(button_id)
        end,
    }
    self.ui.view:registerViewModule("button_dialog", self.button_dialog)
    self.button_dialog:initGesListener()
    self.selected_button = self.button_dialog:getSelected()
    print("selected_button", self.selected_button, self.current_page, self.current_chapter)
    self.navigation_mat[self.selected_button].page = self.current_page
    self.navigation_mat[self.selected_button].chapter = self.current_chapter
end

function TabbedReader:navigationCallback(button_id)
    if not self.navigation_mat[button_id] then
        print("navigationCallback", "id not found")
        self.navigation_mat[button_id] = { page = 1}
    end

    print("navigationCallback", self.selected_button, button_id, self.navigation_mat[button_id].page)
    self.selected_button = button_id

    self.ui:handleEvent(Event:new("GotoPage", self.navigation_mat[button_id].page))
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
