-- Auto Parry Template
-- UI: LinoriaLib (Obsidian fork by deividcomsono)
-- Feature: Timing-based auto parry with custom timing recorder

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

Library.ShowToggleFrameInKeybinds = true

local Window = Library:CreateWindow({
    Title = "Auto Parry",
    Footer = "timing based parry",
    ShowCustomCursor = true,
    NotifySide = "Right",
})

local Tabs = {
    Parry       = Window:AddTab("Parry", "shield"),
    Timings     = Window:AddTab("Timings", "clock"),
    ["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

-- ─────────────────────────────────────────────
--  STATE
-- ─────────────────────────────────────────────

local recordedTimings = {}   -- { { delay = number, label = string }, ... }
local isRecording     = false
local recordStart     = 0
local parryActive     = false
local scheduledTasks  = {}

-- ─────────────────────────────────────────────
--  PARRY LOGIC
-- ─────────────────────────────────────────────

-- Replace this function body with your actual parry action.
-- e.g. fire a remote, simulate input, etc.
local function executeParry(label)
    Library:Notify({
        Title = "Parry Executed",
        Description = "Timing: " .. label,
        Time = 1.5,
    })
    -- TODO: your parry action here
    -- Example: game:GetService("VirtualInputManager"):SendKeyEvent(true, Enum.KeyCode.F, false, nil)
end

local function cancelScheduled()
    for _, conn in ipairs(scheduledTasks) do
        task.cancel(conn)
    end
    scheduledTasks = {}
end

local function runTimingSequence()
    cancelScheduled()
    if #recordedTimings == 0 then
        Library:Notify({ Title = "No Timings", Description = "Record some timings first!", Time = 2 })
        return
    end

    for _, entry in ipairs(recordedTimings) do
        local t = task.delay(entry.delay, function()
            if parryActive then
                executeParry(entry.label)
            end
        end)
        table.insert(scheduledTasks, t)
    end
end

-- ─────────────────────────────────────────────
--  PARRY TAB
-- ─────────────────────────────────────────────

local ParryGroup = Tabs.Parry:AddLeftGroupbox("Auto Parry", "shield")

ParryGroup:AddToggle("ParryEnabled", {
    Text    = "Enable Auto Parry",
    Default = false,
    Tooltip = "Toggles the auto parry system",
    Callback = function(val)
        parryActive = val
        if not val then cancelScheduled() end
    end,
})

ParryGroup:AddLabel("Trigger Keybind"):AddKeyPicker("ParryTrigger", {
    Default  = "Q",
    Mode     = "Press",
    Text     = "Trigger Parry Sequence",
    Callback = function()
        if Toggles.ParryEnabled.Value then
            runTimingSequence()
        end
    end,
})

ParryGroup:AddDivider()

ParryGroup:AddSlider("ParryHoldDuration", {
    Text     = "Hold Duration (ms)",
    Default  = 100,
    Min      = 10,
    Max      = 500,
    Rounding = 0,
    Tooltip  = "How long the parry key is held (if your game needs it)",
})

ParryGroup:AddToggle("ParryLoop", {
    Text    = "Loop on Trigger",
    Default = false,
    Tooltip = "Repeats the full timing sequence in a loop while active",
})

-- Loop logic
task.spawn(function()
    while true do
        task.wait(0.05)
        if parryActive and Toggles.ParryEnabled.Value and Toggles.ParryLoop.Value then
            -- compute total sequence duration
            local maxDelay = 0
            for _, e in ipairs(recordedTimings) do
                if e.delay > maxDelay then maxDelay = e.delay end
            end
            if maxDelay > 0 then
                runTimingSequence()
                task.wait(maxDelay + 0.1)
            else
                task.wait(0.5)
            end
        end
    end
end)

-- ─────────────────────────────────────────────
--  TIMINGS TAB
-- ─────────────────────────────────────────────

local RecGroup   = Tabs.Timings:AddLeftGroupbox("Recorder", "clock")
local ListGroup  = Tabs.Timings:AddRightGroupbox("Saved Timings", "list")

local timingListLabel = ListGroup:AddLabel("No timings recorded yet.", true)

local function refreshTimingList()
    if #recordedTimings == 0 then
        timingListLabel:SetText("No timings recorded yet.")
        return
    end
    local lines = {}
    for i, e in ipairs(recordedTimings) do
        table.insert(lines, string.format("[%d] %s — %.3fs", i, e.label, e.delay))
    end
    timingListLabel:SetText(table.concat(lines, "\n"))
end

RecGroup:AddLabel("1. Start recording, then press\nthe Mark key at each parry moment.\n2. Stop when done.", true)
RecGroup:AddDivider()

RecGroup:AddToggle("RecordingActive", {
    Text    = "Start / Stop Recording",
    Default = false,
    Tooltip = "Toggle to begin or end a timing recording session",
    Callback = function(val)
        if val then
            isRecording = true
            recordStart = tick()
            Library:Notify({ Title = "Recording Started", Description = "Press the Mark key at each parry timing.", Time = 2 })
        else
            isRecording = false
            Library:Notify({ Title = "Recording Stopped", Description = tostring(#recordedTimings) .. " timings saved.", Time = 2 })
            refreshTimingList()
        end
    end,
})

RecGroup:AddInput("TimingLabel", {
    Default     = "parry",
    Text        = "Timing Label",
    Placeholder = "e.g. first hit, dodge, etc.",
    Finished    = false,
})

RecGroup:AddLabel("Mark Keybind"):AddKeyPicker("MarkKey", {
    Default  = "E",
    Mode     = "Press",
    Text     = "Mark Timing",
    Callback = function()
        if not isRecording then
            Library:Notify({ Title = "Not Recording", Description = "Enable recording first!", Time = 1.5 })
            return
        end

        local elapsed = tick() - recordStart
        local label   = Options.TimingLabel.Value ~= "" and Options.TimingLabel.Value or ("timing_" .. #recordedTimings + 1)

        table.insert(recordedTimings, { delay = elapsed, label = label })

        Library:Notify({
            Title       = "Timing Marked",
            Description = label .. " @ " .. string.format("%.3f", elapsed) .. "s",
            Time        = 1.5,
        })
    end,
})

RecGroup:AddDivider()

RecGroup:AddButton({
    Text   = "Clear All Timings",
    Func   = function()
        recordedTimings = {}
        refreshTimingList()
        Library:Notify({ Title = "Cleared", Description = "All timings removed.", Time = 1.5 })
    end,
    Tooltip = "Removes every recorded timing",
})

RecGroup:AddButton({
    Text  = "Remove Last Timing",
    Func  = function()
        if #recordedTimings > 0 then
            local removed = table.remove(recordedTimings)
            refreshTimingList()
            Library:Notify({ Title = "Removed", Description = "Removed: " .. removed.label, Time = 1.5 })
        else
            Library:Notify({ Title = "Nothing to remove", Time = 1 })
        end
    end,
    Tooltip = "Removes the most recently added timing",
})

-- manual timing editor (add by hand)
RecGroup:AddDivider()
RecGroup:AddLabel("— Manual Entry —", true)

RecGroup:AddInput("ManualDelay", {
    Default     = "0.5",
    Numeric     = true,
    Finished    = true,
    Text        = "Delay (seconds)",
    Placeholder = "e.g. 0.25",
})

RecGroup:AddButton({
    Text = "Add Manual Timing",
    Func = function()
        local delay = tonumber(Options.ManualDelay.Value)
        if not delay then
            Library:Notify({ Title = "Invalid", Description = "Enter a valid number.", Time = 1.5 })
            return
        end

        local label = Options.TimingLabel.Value ~= "" and Options.TimingLabel.Value or ("manual_" .. #recordedTimings + 1)
        table.insert(recordedTimings, { delay = delay, label = label })

        -- keep sorted by delay
        table.sort(recordedTimings, function(a, b) return a.delay < b.delay end)

        refreshTimingList()
        Library:Notify({
            Title       = "Added",
            Description = label .. " @ " .. string.format("%.3f", delay) .. "s",
            Time        = 1.5,
        })
    end,
    Tooltip = "Manually add a timing entry by typing the delay above",
})

-- ─────────────────────────────────────────────
--  UI SETTINGS TAB
-- ─────────────────────────────────────────────

local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu", "wrench")

MenuGroup:AddToggle("ShowCustomCursor", {
    Text     = "Custom Cursor",
    Default  = Library.ShowCustomCursor,
    Callback = function(val) Library.ShowCustomCursor = val end,
})

MenuGroup:AddDropdown("NotificationSide", {
    Values   = { "Left", "Right" },
    Default  = "Right",
    Text     = "Notification Side",
    Callback = function(val) Library:SetNotifySide(val) end,
})

MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu Keybind")
    :AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })

MenuGroup:AddButton("Unload", function() Library:Unload() end)

Library.ToggleKeybind = Options.MenuKeybind

-- Addons
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })

ThemeManager:SetFolder("AutoParry")
SaveManager:SetFolder("AutoParry/configs")

SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])

SaveManager:LoadAutoloadConfig()
