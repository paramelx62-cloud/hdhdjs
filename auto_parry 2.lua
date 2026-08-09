-- Auto Parry
-- UI: LinoriaLib (Obsidian fork by deividcomsono)
-- Features: Animation grabber, per-animation timing editor, auto parry

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options  = Library.Options
local Toggles  = Library.Toggles
local Players  = game:GetService("Players")
local RunService = game:GetService("RunService")

Library.ShowToggleFrameInKeybinds = true

local Window = Library:CreateWindow({
    Title = "Auto Parry",
    Footer = "anim grabber + timing editor",
    ShowCustomCursor = true,
    NotifySide = "Right",
})

local Tabs = {
    Parry    = Window:AddTab("Parry",    "shield"),
    Grabber  = Window:AddTab("Grabber",  "search"),
    Timings  = Window:AddTab("Timings",  "clock"),
    ["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

-- ─────────────────────────────────────────────
--  SHARED STATE
-- ─────────────────────────────────────────────

-- animTimings: keyed by animId string → array of { delay=number, label=string }
local animTimings   = {}   -- { ["animId"] = { {delay, label}, ... } }
local grabbedAnims  = {}   -- { { id=string, name=string }, ... }  (grabber results)
local selectedAnimId = nil -- currently selected anim in timing editor

local parryActive    = false
local scheduledTasks = {}

-- ─────────────────────────────────────────────
--  HELPERS
-- ─────────────────────────────────────────────

local function cancelScheduled()
    for _, t in ipairs(scheduledTasks) do task.cancel(t) end
    scheduledTasks = {}
end

local function executeParry(label)
    Library:Notify({ Title = "Parry!", Description = label, Time = 1 })
    -- TODO: put your actual parry action here
    -- e.g. game:GetService("VirtualInputManager"):SendKeyEvent(true, Enum.KeyCode.F, false, nil)
end

local function runTimingSequence(animId)
    cancelScheduled()
    local timings = animTimings[animId]
    if not timings or #timings == 0 then
        Library:Notify({ Title = "No Timings", Description = "Add timings for this anim first!", Time = 2 })
        return
    end
    for _, entry in ipairs(timings) do
        local t = task.delay(entry.delay, function()
            if parryActive then executeParry(entry.label) end
        end)
        table.insert(scheduledTasks, t)
    end
end

-- ─────────────────────────────────────────────
--  ANIMATION GRABBER – scan humanoid animator
-- ─────────────────────────────────────────────
-- Returns all AnimationTrack objects playing or loaded on a humanoid

local function getAnimator(character)
    if not character then return nil end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    return hum:FindFirstChildOfClass("Animator")
end

local function grabAnimationsFromCharacter(character)
    local animator = getAnimator(character)
    if not animator then return {} end
    local results = {}
    local seen = {}
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local anim = track.Animation
        if anim then
            local id = tostring(anim.AnimationId)
            -- strip rbxassetid:// prefix to get clean numeric id
            local numId = id:match("(%d+)$") or id
            if not seen[numId] then
                seen[numId] = true
                table.insert(results, {
                    id   = numId,
                    name = anim.Name ~= "" and anim.Name or ("anim_" .. numId),
                })
            end
        end
    end
    return results
end

-- ─────────────────────────────────────────────
--  GRABBER TAB
-- ─────────────────────────────────────────────

local GrabLeft  = Tabs.Grabber:AddLeftGroupbox("Scan",    "search")
local GrabRight = Tabs.Grabber:AddRightGroupbox("Results","list")

local grabResultLabel = GrabRight:AddLabel("No scan run yet.", true)

local function refreshGrabResults()
    if #grabbedAnims == 0 then
        grabResultLabel:SetText("No animations found.")
        return
    end
    local lines = {}
    for i, a in ipairs(grabbedAnims) do
        table.insert(lines, string.format("[%d] %s\n    ID: %s", i, a.name, a.id))
    end
    grabResultLabel:SetText(table.concat(lines, "\n\n"))
end

GrabLeft:AddLabel("Scans currently playing\nanims on a character.\nPick a target then scan.", true)
GrabLeft:AddDivider()

GrabLeft:AddDropdown("GrabTarget", {
    Values  = { "Local Player", "All Players", "Nearest Player" },
    Default = 1,
    Text    = "Scan Target",
    Tooltip = "Who to grab animations from",
})

GrabLeft:AddButton({
    Text = "Scan Now",
    Func = function()
        grabbedAnims = {}
        local target = Options.GrabTarget.Value
        local lp = Players.LocalPlayer

        local chars = {}
        if target == "Local Player" then
            table.insert(chars, lp.Character)
        elseif target == "All Players" then
            for _, p in ipairs(Players:GetPlayers()) do
                if p.Character then table.insert(chars, p.Character) end
            end
        elseif target == "Nearest Player" then
            local myPos = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            local best, bestDist = nil, math.huge
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= lp and p.Character then
                    local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                    if hrp and myPos then
                        local d = (hrp.Position - myPos.Position).Magnitude
                        if d < bestDist then bestDist = d; best = p.Character end
                    end
                end
            end
            if best then table.insert(chars, best) end
        end

        local seen = {}
        for _, char in ipairs(chars) do
            for _, a in ipairs(grabAnimationsFromCharacter(char)) do
                if not seen[a.id] then
                    seen[a.id] = true
                    table.insert(grabbedAnims, a)
                end
            end
        end

        refreshGrabResults()
        Library:Notify({
            Title = "Scan Complete",
            Description = tostring(#grabbedAnims) .. " animation(s) found",
            Time = 2,
        })
    end,
    Tooltip = "Grab all currently playing animations from the target",
})

GrabLeft:AddDivider()
GrabLeft:AddLabel("— Send to Timing Editor —", true)

GrabLeft:AddInput("ManualAnimId", {
    Default     = "",
    Text        = "Paste Anim ID",
    Placeholder = "e.g. 1234567890",
    Finished    = true,
})

GrabLeft:AddButton({
    Text = "Add ID to Editor",
    Func = function()
        local id = Options.ManualAnimId.Value:match("(%d+)") or Options.ManualAnimId.Value
        if id == "" then
            Library:Notify({ Title = "Empty", Description = "Paste an animation ID first.", Time = 1.5 })
            return
        end
        -- add to grabbed list if not already there
        local exists = false
        for _, a in ipairs(grabbedAnims) do
            if a.id == id then exists = true break end
        end
        if not exists then
            table.insert(grabbedAnims, { id = id, name = "anim_" .. id })
            refreshGrabResults()
        end
        if not animTimings[id] then animTimings[id] = {} end
        Library:Notify({ Title = "Added", Description = "ID " .. id .. " ready in Timings tab.", Time = 2 })
    end,
    Tooltip = "Manually add an anim ID to the timing editor",
})

-- auto-add scanned anims to timing editor when clicked
GrabRight:AddButton({
    Text = "Send All Grabbed → Editor",
    Func = function()
        local added = 0
        for _, a in ipairs(grabbedAnims) do
            if not animTimings[a.id] then
                animTimings[a.id] = {}
                added = added + 1
            end
        end
        Library:Notify({ Title = "Sent", Description = tostring(added) .. " anim(s) added to Timings tab.", Time = 2 })
    end,
    Tooltip = "Adds all grabbed animations to the timing editor",
})

-- ─────────────────────────────────────────────
--  TIMINGS TAB – per-animation timing editor
-- ─────────────────────────────────────────────

local TimLeft  = Tabs.Timings:AddLeftGroupbox("Animation Select", "list")
local TimRight = Tabs.Timings:AddRightGroupbox("Timing Editor",   "clock")

-- labels we update dynamically
local selectedLabel  = TimLeft:AddLabel("Selected: none", true)
local timingListLabel = TimRight:AddLabel("No anim selected.", true)

local isRecording = false
local recordStart = 0

local function getTimingsForSelected()
    if not selectedAnimId then return {} end
    return animTimings[selectedAnimId] or {}
end

local function refreshTimingList()
    if not selectedAnimId then
        timingListLabel:SetText("No anim selected.")
        return
    end
    local list = animTimings[selectedAnimId]
    if not list or #list == 0 then
        timingListLabel:SetText("No timings yet for this anim.")
        return
    end
    local lines = {}
    for i, e in ipairs(list) do
        table.insert(lines, string.format("[%d] %s — %.3fs", i, e.label, e.delay))
    end
    timingListLabel:SetText(table.concat(lines, "\n"))
end

local function buildAnimDropdownValues()
    local vals = {}
    for id, _ in pairs(animTimings) do
        table.insert(vals, id)
    end
    if #vals == 0 then table.insert(vals, "(none)") end
    return vals
end

-- We use a textbox for selecting anim id since dropdown values are dynamic
TimLeft:AddLabel("Paste or type the anim ID\nyou want to set timings for.", true)

TimLeft:AddInput("SelectAnimId", {
    Default     = "",
    Text        = "Anim ID",
    Placeholder = "e.g. 1234567890",
    Finished    = true,
    Callback = function(val)
        local id = val:match("(%d+)") or val
        if animTimings[id] then
            selectedAnimId = id
            selectedLabel:SetText("Selected: " .. id)
            refreshTimingList()
        else
            selectedLabel:SetText("ID not in editor yet.")
        end
    end,
})

TimLeft:AddButton({
    Text = "Create / Select",
    Func = function()
        local id = Options.SelectAnimId.Value:match("(%d+)") or Options.SelectAnimId.Value
        if id == "" then
            Library:Notify({ Title = "Empty", Description = "Type an anim ID first.", Time = 1.5 })
            return
        end
        if not animTimings[id] then animTimings[id] = {} end
        selectedAnimId = id
        selectedLabel:SetText("Selected: " .. id)
        refreshTimingList()
        Library:Notify({ Title = "Ready", Description = "Editing timings for " .. id, Time = 1.5 })
    end,
    Tooltip = "Create a timing slot for this anim ID or select it if it exists",
})

TimLeft:AddDivider()

-- list all IDs currently in editor for quick reference
local idListLabel = TimLeft:AddLabel("IDs in editor: (none)", true)

local function refreshIdList()
    local ids = {}
    for id in pairs(animTimings) do table.insert(ids, id) end
    if #ids == 0 then
        idListLabel:SetText("IDs in editor: (none)")
    else
        idListLabel:SetText("IDs in editor:\n" .. table.concat(ids, "\n"))
    end
end

-- ── Timing Editor (right side) ────────────────

TimRight:AddToggle("AnimRecordingActive", {
    Text    = "Start / Stop Recording",
    Default = false,
    Tooltip = "Mark timings in real time for the selected anim",
    Callback = function(val)
        if not selectedAnimId then
            Library:Notify({ Title = "No Anim Selected", Description = "Select an anim ID first.", Time = 2 })
            Toggles.AnimRecordingActive:SetValue(false)
            return
        end
        if val then
            isRecording = true
            recordStart = tick()
            Library:Notify({ Title = "Recording", Description = "Press Mark key to stamp timings.", Time = 2 })
        else
            isRecording = false
            refreshTimingList()
            Library:Notify({ Title = "Stopped", Description = tostring(#(animTimings[selectedAnimId] or {})) .. " timings saved.", Time = 2 })
        end
    end,
})

TimRight:AddInput("AnimTimingLabel", {
    Default     = "parry",
    Text        = "Timing Label",
    Placeholder = "e.g. first swing",
    Finished    = false,
})

TimRight:AddLabel("Mark Keybind"):AddKeyPicker("AnimMarkKey", {
    Default  = "E",
    Mode     = "Press",
    Text     = "Mark Timing",
    Callback = function()
        if not isRecording then
            Library:Notify({ Title = "Not Recording", Time = 1 })
            return
        end
        if not selectedAnimId then return end

        local elapsed = tick() - recordStart
        local label = Options.AnimTimingLabel.Value ~= "" and Options.AnimTimingLabel.Value or ("t_" .. #animTimings[selectedAnimId] + 1)
        table.insert(animTimings[selectedAnimId], { delay = elapsed, label = label })
        table.sort(animTimings[selectedAnimId], function(a, b) return a.delay < b.delay end)
        refreshTimingList()
        Library:Notify({ Title = "Marked", Description = label .. " @ " .. string.format("%.3f", elapsed) .. "s", Time = 1 })
    end,
})

TimRight:AddDivider()

TimRight:AddInput("ManualTimingDelay", {
    Default     = "0.5",
    Numeric     = true,
    Finished    = true,
    Text        = "Manual Delay (s)",
    Placeholder = "e.g. 0.3",
})

TimRight:AddButton({
    Text = "Add Manual Timing",
    Func = function()
        if not selectedAnimId then
            Library:Notify({ Title = "No Anim Selected", Time = 1.5 })
            return
        end
        local delay = tonumber(Options.ManualTimingDelay.Value)
        if not delay then
            Library:Notify({ Title = "Invalid number", Time = 1.5 })
            return
        end
        local label = Options.AnimTimingLabel.Value ~= "" and Options.AnimTimingLabel.Value or ("t_" .. #animTimings[selectedAnimId] + 1)
        table.insert(animTimings[selectedAnimId], { delay = delay, label = label })
        table.sort(animTimings[selectedAnimId], function(a, b) return a.delay < b.delay end)
        refreshTimingList()
        Library:Notify({ Title = "Added", Description = label .. " @ " .. string.format("%.3f", delay) .. "s", Time = 1.5 })
    end,
    Tooltip = "Add a timing by typing the delay manually",
})

TimRight:AddButton({
    Text = "Remove Last Timing",
    Func = function()
        if not selectedAnimId or not animTimings[selectedAnimId] or #animTimings[selectedAnimId] == 0 then
            Library:Notify({ Title = "Nothing to remove", Time = 1 })
            return
        end
        local removed = table.remove(animTimings[selectedAnimId])
        refreshTimingList()
        Library:Notify({ Title = "Removed", Description = removed.label, Time = 1.5 })
    end,
})

TimRight:AddButton({
    Text = "Clear Timings for This Anim",
    Func = function()
        if not selectedAnimId then return end
        animTimings[selectedAnimId] = {}
        refreshTimingList()
        Library:Notify({ Title = "Cleared", Time = 1.5 })
    end,
})

-- ─────────────────────────────────────────────
--  PARRY TAB
-- ─────────────────────────────────────────────

local ParryLeft  = Tabs.Parry:AddLeftGroupbox("Auto Parry",       "shield")
local ParryRight = Tabs.Parry:AddRightGroupbox("Anim Watcher",    "eye")

ParryLeft:AddToggle("ParryEnabled", {
    Text    = "Enable Auto Parry",
    Default = false,
    Tooltip = "Master toggle",
    Callback = function(val)
        parryActive = val
        if not val then cancelScheduled() end
    end,
})

ParryLeft:AddLabel("Trigger Keybind"):AddKeyPicker("ParryTrigger", {
    Default  = "Q",
    Mode     = "Press",
    Text     = "Manual Trigger",
    Callback = function()
        if not parryActive then return end
        local id = Options.WatchAnimId.Value:match("(%d+)") or Options.WatchAnimId.Value
        if id ~= "" then
            runTimingSequence(id)
        else
            Library:Notify({ Title = "No Anim Set", Description = "Set an anim to watch first.", Time = 2 })
        end
    end,
})

ParryLeft:AddSlider("ParryHoldDuration", {
    Text     = "Hold Duration (ms)",
    Default  = 100,
    Min      = 10,
    Max      = 500,
    Rounding = 0,
})

ParryLeft:AddToggle("ParryLoop", {
    Text    = "Loop Sequence",
    Default = false,
    Tooltip = "Keep repeating the timing sequence while active",
})

-- Anim Watcher – detects when a specific anim starts playing and auto-runs timings
ParryRight:AddLabel("Watches for an anim to\nstart playing, then fires\nthe timing sequence auto.", true)
ParryRight:AddDivider()

ParryRight:AddInput("WatchAnimId", {
    Default     = "",
    Text        = "Watch Anim ID",
    Placeholder = "paste anim ID here",
    Finished    = true,
})

ParryRight:AddToggle("WatcherEnabled", {
    Text    = "Enable Watcher",
    Default = false,
    Tooltip = "Auto-triggers when the watched anim starts playing",
})

local watcherStatus = ParryRight:AddLabel("Watcher: idle", true)

-- Watcher loop
local lastWatchState = false
task.spawn(function()
    while true do
        task.wait(0.05)
        if not Toggles.WatcherEnabled.Value or not parryActive then
            lastWatchState = false
            watcherStatus:SetText("Watcher: idle")
        else
            local watchId = Options.WatchAnimId.Value:match("(%d+)") or Options.WatchAnimId.Value
            if watchId == "" then
                watcherStatus:SetText("Watcher: no ID set")
            else
                local lp = Players.LocalPlayer
                local char = lp and lp.Character
                local animator = getAnimator(char)
                local playing = false
                if animator then
                    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                        local id = tostring(track.Animation and track.Animation.AnimationId or ""):match("(%d+)$")
                        if id == watchId then playing = true break end
                    end
                end

                if playing and not lastWatchState then
                    -- anim just started
                    watcherStatus:SetText("Watcher: DETECTED! firing...")
                    runTimingSequence(watchId)
                elseif playing then
                    watcherStatus:SetText("Watcher: playing...")
                else
                    watcherStatus:SetText("Watcher: listening...")
                end
                lastWatchState = playing
            end
        end
    end
end)

-- Loop logic for manual trigger
task.spawn(function()
    while true do
        task.wait(0.05)
        if parryActive and Toggles.ParryEnabled.Value and Toggles.ParryLoop.Value then
            local id = Options.WatchAnimId.Value:match("(%d+)") or Options.WatchAnimId.Value
            if id ~= "" and animTimings[id] and #animTimings[id] > 0 then
                local maxDelay = 0
                for _, e in ipairs(animTimings[id]) do
                    if e.delay > maxDelay then maxDelay = e.delay end
                end
                runTimingSequence(id)
                task.wait(maxDelay + 0.1)
            else
                task.wait(0.5)
            end
        end
    end
end)

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

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("AutoParry")
SaveManager:SetFolder("AutoParry/configs")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()
