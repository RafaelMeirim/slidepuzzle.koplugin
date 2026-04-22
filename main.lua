--[[
    slidepuzzle.koplugin/main.lua
    Plugin entry point: registers the menu item, owns per-size
    persistence (current state, best results) and hands out Game
    instances to the screen.
--]]

local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Game = require("slidepuzzle_game")
local Screen = require("slidepuzzle_screen")

local SlidePuzzle = WidgetContainer:extend{
    name = "slidepuzzle",
    is_doc_only = false,
}

-- Init --------------------------------------------------------------------

function SlidePuzzle:init()
    self.settings_file = DataStorage:getSettingsDir() .. "/slidepuzzle.lua"
    self.settings = LuaSettings:open(self.settings_file)
    self.active_size = tonumber(self.settings:readSetting("active_size")) or Game.getMinSize()
    if self.active_size < Game.getMinSize() or self.active_size > Game.getMaxSize() then
        self.active_size = Game.getMinSize()
    end
    self.states = self.settings:readSetting("states") or {}
    self.stats = self.settings:readSetting("stats") or {}
    self.ui.menu:registerToMainMenu(self)
end

function SlidePuzzle:addToMainMenu(menu_items)
    menu_items.slidepuzzle = {
        text = _("Slide puzzle"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Play"),
                keep_menu_open = false,
                callback = function() self:showGame() end,
            },
            {
                text_func = function()
                    if self.settings:isTrue("always_new_on_open") then
                        return _("On open: always start a fresh puzzle")
                    end
                    return _("On open: resume saved puzzle")
                end,
                checked_func = function()
                    return self.settings:isTrue("always_new_on_open")
                end,
                callback = function()
                    self.settings:toggle("always_new_on_open")
                    self.settings:flush()
                end,
                keep_menu_open = true,
            },
            {
                text = _("Reset best results"),
                keep_menu_open = true,
                callback = function()
                    self.stats = {}
                    self:_saveAll()
                    UIManager:show(InfoMessage:new{
                        text = _("Best results cleared."),
                        timeout = 2,
                    })
                end,
            },
        },
    }
end

-- Persistence helpers -----------------------------------------------------

function SlidePuzzle:_saveAll()
    self.settings:saveSetting("active_size", self.active_size)
    self.settings:saveSetting("states", self.states)
    self.settings:saveSetting("stats", self.stats)
    self.settings:flush()
end

function SlidePuzzle:_key(size)
    return tostring(size)
end

function SlidePuzzle:_loadOrCreateGame(size)
    local data = self.states[self:_key(size)]
    local game
    if data then
        game = Game.deserialize(data, size)
    else
        game = Game:new(size)
        game:shuffle()
    end
    -- Never hand out a game that is already solved or in the raw solved
    -- initial state; start a fresh puzzle instead.
    if game:isWon() or (not game:hasStarted() and game:checkSolved()) then
        game:shuffle()
    end
    self.states[self:_key(size)] = game:serialize()
    return game
end

-- API used by the Screen --------------------------------------------------

function SlidePuzzle:getCurrentGame()
    if not self._cached_game or self._cached_game:getSize() ~= self.active_size then
        self._cached_game = self:_loadOrCreateGame(self.active_size)
    end
    return self._cached_game
end

function SlidePuzzle:setActiveSize(size)
    size = tonumber(size) or Game.getMinSize()
    if size < Game.getMinSize() then size = Game.getMinSize() end
    if size > Game.getMaxSize() then size = Game.getMaxSize() end
    self.active_size = size
    self._cached_game = nil
    self:_saveAll()
end

function SlidePuzzle:startNewGame(size)
    size = tonumber(size) or self.active_size
    local game = Game:new(size)
    game:shuffle()
    self._cached_game = game
    self.active_size = size
    self.states[self:_key(size)] = game:serialize()
    self:_saveAll()
end

function SlidePuzzle:saveCurrentState(game)
    if not game then return end
    self.states[self:_key(game:getSize())] = game:serialize()
    self:_saveAll()
end

function SlidePuzzle:recordResult(game)
    if not game then return end
    local key = self:_key(game:getSize())
    local s = self.stats[key] or {}
    local elapsed = game:getElapsed()
    local moves = game:getMoves()
    if elapsed > 0 and (not s.best_time or elapsed < s.best_time) then
        s.best_time = elapsed
    end
    if moves > 0 and (not s.best_moves or moves < s.best_moves) then
        s.best_moves = moves
    end
    s.last_time = elapsed
    s.last_moves = moves
    s.plays = (s.plays or 0) + 1
    self.stats[key] = s
    self:_saveAll()
end

function SlidePuzzle:getStats(size)
    return self.stats[self:_key(size)]
end

-- Screen lifecycle --------------------------------------------------------

function SlidePuzzle:showGame()
    if self.screen then return end
    if self.settings:isTrue("always_new_on_open") then
        self:startNewGame(self.active_size)
    end
    local game = self:getCurrentGame()
    self.screen = Screen:new{
        plugin = self,
        game = game,
    }
    UIManager:show(self.screen)
end

function SlidePuzzle:onScreenClosed()
    self.screen = nil
end

return SlidePuzzle
