local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local TopContainer = require("ui/widget/container/topcontainer")
local Device = require("device")
local Font = require("ui/font")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local LineWidget = require("ui/widget/linewidget")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local util = require("util")
local BD = require("ui/bidi")
local logger = require("logger")

local NavigationTabs = FocusManager:extend {
    modal = false,
    invisible = false,
    buttons = {
        {
            {
                text = "First row, left side"
            },
            {
                text = "First row, middle"
            },
            {
                text = "First row, right side"
            },
            {
                text = "+",
                width = 10,
                unselectable = true
            }
        },
    },
    margin = 15,
    callback = nil,
    width = nil,
    width_factor = nil,            -- number between 0 and 1, factor to the smallest of screen width and height
    shrink_unneeded_width = false, -- have 'width' meaning 'max_width'
    shrink_min_width = nil,        -- default to ButtonTable's default
    tap_close_callback = nil,
    alpha = nil,                   -- passed to MovableContainer
    -- If scrolling, prefers using this/these numbers of buttons rows per page
    -- (depending on what the screen height allows) to compute the height.
    rows_per_page = nil, -- number or array of numbers

    title = nil,
    title_align = "left",
    title_face = Font:getFace("x_smalltfont"),
    title_padding = Size.padding.large,
    title_margin = Size.margin.title,
    use_info_style = true, -- set to false to have bold font style of the title
    info_face = Font:getFace("infofont"),
    info_padding = Size.padding.default,
    info_margin = Size.margin.default,
}

function NavigationTabs:init()
    self.entry_by_id = {}

    for i = 1, #self.buttons do
        local row = self.buttons[i]
        for j = 1, #row do
            local button = row[j]

            if not button.id then
                button.id = i .. "-" .. j
            end

            self.entry_by_id[button.id] = button
        end
    end

    if not self.width then
        if not self.width_factor then
            --self.width_factor = 0.9 -- default if no width specified
            self.width_factor = 1
        end
        self.width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * self.width_factor)
    end

    self.buttontable = ButtonTable:new {
        buttons = self.buttons,
        width = self.width - 2 * Size.border.window - 2 * Size.padding.button,
        shrink_unneeded_width = self.shrink_unneeded_width,
        shrink_min_width = self.shrink_min_width,
        show_parent = self,
    }
    local buttontable_width = self.buttontable:getSize().w -- may be shrunk

    local title_widget, title_widget_height
    if self.title then
        local title_padding, title_margin, title_face
        if self.use_info_style then
            title_padding = self.info_padding
            title_margin  = self.info_margin
            title_face    = self.info_face
        else
            title_padding = self.title_padding
            title_margin  = self.title_margin
            title_face    = self.title_face
        end
        title_widget = FrameContainer:new {
            padding = title_padding,
            margin = title_margin,
            bordersize = 0,
            TextBoxWidget:new {
                text = self.title,
                width = buttontable_width - 2 * (title_padding + title_margin),
                face = title_face,
                alignment = self.title_align,
            },
        }
        title_widget_height = title_widget:getSize().h + Size.line.medium
    else
        title_widget = VerticalSpan:new {}
        title_widget_height = 0
    end
    self.top_to_content_offset = Size.padding.buttontable + Size.margin.default + title_widget_height

    -- If the ButtonTable ends up being taller than the screen, wrap it inside a ScrollableContainer.
    -- Ensure some small top and bottom padding, so the scrollbar stand out, and some outer margin
    -- so the this dialog does not take the full height and stand as a popup.
    local max_height = Screen:getHeight() - 2 * Size.padding.buttontable - 2 * Size.margin.default - title_widget_height
    local height = self.buttontable:getSize().h
    local scontainer, scrollbar_width
    if height > max_height then
        -- Adjust the ScrollableContainer to an integer multiple of the row height
        -- (assuming all rows get the same height), so when scrolling per page,
        -- we always end up seeing full rows.
        self.buttontable:setupGridScrollBehaviour()
        local step_scroll_grid = self.buttontable:getStepScrollGrid()
        local row_height = step_scroll_grid[1].bottom + 1 - step_scroll_grid[1].top
        local fit_rows = math.floor(max_height / row_height)
        if self.rows_per_page then
            if type(self.rows_per_page) == "number" then
                if fit_rows > self.rows_per_page then
                    fit_rows = self.rows_per_page
                end
            else
                for _, nb in ipairs(self.rows_per_page) do
                    if fit_rows >= nb then
                        fit_rows = nb
                        break
                    end
                end
            end
        end
        -- (Comment the next line to test ScrollableContainer behaviour when things do not fit)
        max_height = row_height * fit_rows
        scrollbar_width = ScrollableContainer:getScrollbarWidth()
        self.cropping_widget = ScrollableContainer:new {
            dimen = Geom:new {
                -- We'll be exceeding the provided width in this case (let's not bother
                -- ensuring it, we'd need to re-setup the ButtonTable...)
                w = buttontable_width + scrollbar_width,
                h = max_height,
            },
            show_parent = self,
            step_scroll_grid = step_scroll_grid,
            self.buttontable,
        }
        scontainer = VerticalGroup:new {
            VerticalSpan:new { width = Size.padding.buttontable },
            self.cropping_widget,
            VerticalSpan:new { width = Size.padding.buttontable },
        }
    end
    local separator
    if self.title then
        separator = LineWidget:new {
            background = Blitbuffer.COLOR_GRAY,
            dimen = Geom:new {
                w = buttontable_width + (scrollbar_width or 0),
                h = Size.line.medium,
            },
        }
    else
        separator = VerticalSpan:new {}
    end
    self.movable = MovableContainer:new {
        alpha = self.alpha,
        anchor = self.anchor,
        FrameContainer:new {
            background = Blitbuffer.COLOR_WHITE,
            bordersize = Size.border.window,
            radius = Size.radius.window,
            padding = Size.padding.button,
            -- No padding at top or bottom to make all buttons
            -- look the same size
            padding_top = 0,
            padding_bottom = 0,
            VerticalGroup:new {
                title_widget,
                separator,
                scontainer or self.buttontable,
            },
        }
    }

    -- No need to reinvent the wheel, ButtonTable's layout is perfect as-is
    self.layout = self.buttontable.layout
    -- But we'll want to control focus in its place, though
    self.buttontable.layout = nil

    self[1] = CenterContainer:new {
        ignore = "height",
        dimen = Screen:getSize(),
        self.movable,
    }
end

function NavigationTabs:getContentSize()
    return self.movable.dimen
end

function NavigationTabs:getButtonById(id)
    return self.buttontable:getButtonById(id)
end

function NavigationTabs:getScrolledOffset()
    if self.cropping_widget then
        return self.cropping_widget:getScrolledOffset()
    end
end

function NavigationTabs:setScrolledOffset(offset_point)
    if offset_point and self.cropping_widget then
        return self.cropping_widget:setScrolledOffset(offset_point)
    end
end

function NavigationTabs:setTitle(title)
    self.title = title
    self:free()
    self:init()
    UIManager:setDirty("all", "ui")
end

function NavigationTabs:reloadButtons(new_buttons)
    if new_buttons then
        self.buttons = new_buttons
        self.selected_button = nil -- clear selected button
    end
    self:free()
    self:init()
    UIManager:setDirty("all", "ui")
    logger.dbg("NavigationTabs: reloadButtons")
end

function NavigationTabs:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.movable.dimen
    end)
end

function NavigationTabs:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "flashui", self.movable.dimen
    end)
end

function NavigationTabs:onClose()
    if self.tap_close_callback then
        self.tap_close_callback()
    end
    UIManager:close(self)
    return true
end

function NavigationTabs:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.movable.dimen) then
        self:onClose()
    end
    return true
end

function NavigationTabs:paintTo(bb, x, y)
    FocusManager.paintTo(self, bb, x, y)
    self.dimen = self.movable.dimen
end

function NavigationTabs:onFocusMove(args)
    local ret = FocusManager.onFocusMove(self, args)

    -- If we're using a ScrollableContainer, ask it to scroll to the focused item
    if self.cropping_widget then
        local focus = self:getFocusItem()
        if self.dimen and focus and focus.dimen then
            local button_y_offset = focus.dimen.y - self.dimen.y - self.top_to_content_offset
            -- NOTE: The final argument ensures we'll always keep the neighboring item visible.
            --       (i.e., the top/bottom of the scrolled view is actually the previous/next item).
            self.cropping_widget:_scrollBy(0, button_y_offset, true)
        end
    end

    return ret
end

function NavigationTabs:_onPageScrollToRow(row)
    -- ScrollableContainer will pass us the row number of the top widget at the current scroll offset
    self:moveFocusTo(1, row)
end

function NavigationTabs:onSetDimensions(dimen)
    logger.dbg("NavigationTabs: onSetDimensions")
end

function NavigationTabs:setSelected(selected)
    if self.entry_by_id[selected] and self.entry_by_id[selected].unselectable then
        return
    end

    if self.selected_button then
        local selected_button = self.buttontable:getButtonById(self.selected_button)
        selected_button:onUnfocus()
        selected_button:refresh()
    end
    logger.dbg("NavigationTabs: focusing", selected)

    local button = self.buttontable:getButtonById(selected)
    button:onFocus()
    self.selected_button = selected

    button:refresh()
end

function NavigationTabs:setFocus(id, focused)
    local button = self.buttontable:getButtonById(id)
    if button then
        if focused then
            button:onFocus()
        else
            button:onUnfocus()
        end
        button:refresh()
    end
end

function NavigationTabs:tapHandler(button, ges)
    logger.dbg("NavigationTabs", "tapHandler", button, ges)

    if self.callback then
        self.callback(button, ges)
    end
end

function NavigationTabs:initGesListener()
    logger.dbg("NavigationTabs: initGesListener")
    local is_rtl = BD.mirroredUILayout()

    self:unRegisterGesListener()

    self.touch_zone_mat = {}
    local index = 1
    local x = 0
    local y = 0

    for i = 1, #(self.buttontable.buttons_layout) do
        local row = self.buttontable.buttons_layout[i]
        local h = 0
        for j = 1, #row do
            local button = row[j]
            button.no_focus = false

            local w = button.dimen.w / Screen:getWidth()
            h = button.dimen.h / Screen:getHeight()
            local id = self.buttons[i][j].id
            local actual_x
            if is_rtl then
                actual_x = 1 - x - w
            else
                actual_x = x
            end

            local screen_zone = { ratio_x = actual_x, ratio_y = y, ratio_w = w, ratio_h = h }

            local val = {
                id = "navigationtab_" .. id,
                ges = "tap",
                screen_zone = screen_zone,
                overrides = {
                    "readerhighlight_tap",
                    "readermenu_ext_tap",
                    "tap_top_left_corner",
                    "tap_top_right_corner",
                },
                handler = function(ges)
                    self:tapHandler(id, ges)
                    return true
                end,
            }
            self.touch_zone_mat[index] = val
            index = index + 1

            val = {
                id = "navigationtab_hold_" .. id,
                ges = "hold",
                screen_zone = screen_zone,
                overrides = {
                    "readerhighlight_hold",
                },
                handler = function(ges)
                    self:tapHandler(id, ges)
                    return true
                end,
            }
            self.touch_zone_mat[index] = val
            index = index + 1

            logger.dbg("NavigationTabs:", val.id, val.ges,
                val.screen_zone.ratio_x, val.screen_zone.ratio_y,
                val.screen_zone.ratio_w, val.screen_zone.ratio_h)
            x = x + w
        end
        y = y + h
    end
    self.ui:registerTouchZones(self.touch_zone_mat)

    self:setSelected(self.buttons[1][1].id)
end

function NavigationTabs:unRegisterGesListener()
    if not self.touch_zone_mat then
        return
    end

    logger.dbg("NavigationTabs: unRegisterGesListener")
    self.ui:unRegisterTouchZones(self.touch_zone_mat)
end

function NavigationTabs:getSelected()
    return self.selected_button
end

function NavigationTabs:refreshButton(button_id)
    local button = self.buttontable:getButtonById(button_id)
    local focused = button.frame.invert
    button:setText(button.text_func(), button.width)
    if focused then
        button:onFocus()
    end
    button:refresh()
end

return NavigationTabs
