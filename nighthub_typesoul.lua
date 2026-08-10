--[[
╔══════════════════════════════════════════════════════════════╗
║           NightHub — Type Soul Edition                       ║
║           Built on Obsidian/LinoriaLib                       ║
║           Delta / Arceus X / Fluxus / Wave / Synapse X       ║
╚══════════════════════════════════════════════════════════════╝

LOAD LINE:
loadstring(game:HttpGet("https://raw.githubusercontent.com/YOURNAME/nighthub/main/nighthub_typesoul.lua"))()
]]

-- ═══════════════════════════════════════════════════════
--  LIBRARY LOAD
-- ═══════════════════════════════════════════════════════
local repo         = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

Library.ShowToggleFrameInKeybinds = true

-- ═══════════════════════════════════════════════════════
--  SERVICES
-- ═══════════════════════════════════════════════════════
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP   = Players.LocalPlayer
local Char = LP.Character or LP.CharacterAdded:Wait()
local Hum  = Char:WaitForChild("Humanoid")
local Root = Char:WaitForChild("HumanoidRootPart")

-- ═══════════════════════════════════════════════════════
--  EXECUTOR DETECTION
-- ═══════════════════════════════════════════════════════
local ExecName = "unknown"
pcall(function()
    if identifyexecutor then
        ExecName = identifyexecutor():lower()
    elseif getexecutorname then
        ExecName = getexecutorname():lower()
    end
end)

-- ═══════════════════════════════════════════════════════
--  SAFE KEY PRESS
--  Delta uses keypress()/keyrelease()
--  Synapse X / Wave use VirtualInputManager
-- ═══════════════════════════════════════════════════════
local function safeKeyPress(key, holdTime)
    holdTime = holdTime or 0.08
    if keypress then
        pcall(function()
            keypress(key.Value)
            task.wait(holdTime)
            keyrelease(key.Value)
        end)
        return
    end
    pcall(function()
        local VIS = game:GetService("VirtualInputManager")
        VIS:SendKeyEvent(true,  key, false, game)
        task.wait(holdTime)
        VIS:SendKeyEvent(false, key, false, game)
    end)
end

local function safeMouseClick(holdTime)
    holdTime = holdTime or 0.05
    if mouse1press then
        pcall(function()
            mouse1press()
            task.wait(holdTime)
            mouse1release()
        end)
        return
    end
    pcall(function()
        local VIS = game:GetService("VirtualInputManager")
        VIS:SendMouseButtonEvent(0, 0, 0, true,  game, 1)
        task.wait(holdTime)
        VIS:SendMouseButtonEvent(0, 0, 0, false, game, 1)
    end)
end

-- ═══════════════════════════════════════════════════════
--  WINDOW
-- ═══════════════════════════════════════════════════════
local Window = Library:CreateWindow({
    Title             = "NightHub",
    Footer            = "Type Soul Edition",
    NotifySide        = "Right",
    ShowCustomCursor  = true,
    AutoShow          = true,
    MobileButtonsSide = "Right",
})

local Tabs = {
    AutoParry = Window:AddTab("Auto Parry", "shield"),
    Combat    = Window:AddTab("Combat",     "sword"),
    Movement  = Window:AddTab("Movement",   "zap"),
    Visual    = Window:AddTab("Visuals",    "eye"),
    Settings  = Window:AddTab("Settings",   "settings"),
}

-- ═══════════════════════════════════════════════════════
--  AUTO PARRY ENGINE
--  4-layer detection matching Insanity Hub approach
--  Type Soul parry window ≈ 350ms
-- ═══════════════════════════════════════════════════════
local Parry = {
    Enabled     = false,
    Parrying    = false,
    LastFire    = 0,
    Count       = 0,
    Cooldown    = 0.35,   -- Type Soul parry window ~350ms
    HoldTime    = 0.08,   -- key hold duration
    PreBuffer   = 0.05,   -- fire before damage lands
    Threshold   = 0.04,   -- 4% HP drop triggers parry
    Key         = Enum.KeyCode.F,
    Conns       = {},
}

local function fireParry()
    if not Parry.Enabled then return end
    local now = tick()
    if Parry.Parrying then return end
    if (now - Parry.LastFire) < Parry.Cooldown then return end

    -- randomize timing slightly if anti-detection on
    local variance = 0
    if Toggles.RandomizeTimings and Toggles.RandomizeTimings.Value then
        variance = (math.random() * 2 - 1) * ((Options.RandomVariance and Options.RandomVariance.Value or 15) / 1000)
    end

    Parry.Parrying = true
    Parry.LastFire = now
    Parry.Count   += 1

    task.wait(math.max(0, Parry.PreBuffer + variance))
    safeKeyPress(Parry.Key, Parry.HoldTime)

    -- update counter label
    pcall(function()
        Options.ParryCountLabel:SetText("Parries Fired: " .. Parry.Count)
    end)

    Library:Notify({
        Title       = "NightHub",
        Description = "Parried! (" .. Parry.Count .. ")",
        Time        = 1,
    })

    task.wait(Parry.HoldTime + 0.05)
    Parry.Parrying = false
end

local function hookCharacter(char)
    for _, c in pairs(Parry.Conns) do pcall(function() c:Disconnect() end) end
    Parry.Conns = {}

    Char = char
    Hum  = char:WaitForChild("Humanoid", 5)
    Root = char:WaitForChild("HumanoidRootPart", 5)
    if not Hum then return end

    local lastHP = Hum.Health

    -- Layer 1: HealthChanged
    local c1 = Hum.HealthChanged:Connect(function(hp)
        local delta = lastHP - hp
        if delta > 0 and (delta / math.max(Hum.MaxHealth, 1)) >= Parry.Threshold then
            task.spawn(fireParry)
        end
        lastHP = hp
    end)
    table.insert(Parry.Conns, c1)

    -- Layer 2: RemoteEvent / BindableEvent scan
    local hitKeywords = {
        "hit","damage","strike","attack","slash","clash",
        "block","guard","parry","deflect","stun","knockback",
        "hurt","wound","impact","counter"
    }
    local function hookRemote(obj)
        if not (obj:IsA("RemoteEvent") or obj:IsA("BindableEvent")) then return end
        local n = obj.Name:lower()
        for _, kw in ipairs(hitKeywords) do
            if n:find(kw) then
                local c2
                if obj:IsA("RemoteEvent") then
                    c2 = obj.OnClientEvent:Connect(function() task.spawn(fireParry) end)
                else
                    c2 = obj.Event:Connect(function() task.spawn(fireParry) end)
                end
                table.insert(Parry.Conns, c2)
                break
            end
        end
    end
    task.spawn(function()
        local function scan(p, d)
            if d > 5 then return end
            for _, v in pairs(p:GetChildren()) do
                pcall(hookRemote, v)
                scan(v, d + 1)
            end
        end
        scan(ReplicatedStorage, 0)
        scan(workspace, 0)
    end)

    -- Layer 3: AnimationTrack detection
    local animator = Hum:FindFirstChildOfClass("Animator")
    if animator then
        local animKw = {
            "hit","stun","hurt","knockback","damage",
            "flinch","block","parry","clash","guard","counter"
        }
        local c3 = animator.AnimationPlayed:Connect(function(track)
            local n = track.Name:lower()
            for _, kw in ipairs(animKw) do
                if n:find(kw) then
                    task.spawn(fireParry)
                    break
                end
            end
        end)
        table.insert(Parry.Conns, c3)
    end

    -- Layer 4: Type Soul CharValue watch
    local function watchValue(name)
        local val = char:FindFirstChild(name) or char:WaitForChild(name, 2)
        if val and (val:IsA("BoolValue") or val:IsA("IntValue") or val:IsA("NumberValue")) then
            local cv = val.Changed:Connect(function() task.spawn(fireParry) end)
            table.insert(Parry.Conns, cv)
        end
    end
    task.spawn(function()
        watchValue("Blocking")
        watchValue("Stunned")
        watchValue("Hit")
        watchValue("CanParry")
        watchValue("GotHit")
    end)
end

hookCharacter(Char)
LP.CharacterAdded:Connect(function(c)
    task.wait(0.6)
    hookCharacter(c)
end)

-- ═══════════════════════════════════════════════════════
--  AUTO PARRY TAB
-- ═══════════════════════════════════════════════════════
local APLeft  = Tabs.AutoParry:AddLeftGroupbox("Auto Parry", "shield")
local APRight = Tabs.AutoParry:AddRightGroupbox("Timing",    "clock")
local APInfo  = Tabs.AutoParry:AddLeftGroupbox("Info",       "info")

APLeft:AddToggle("AutoParryEnabled", {
    Text     = "Enable Auto Parry",
    Default  = false,
    Tooltip  = "Fires parry key automatically on hit detection",
    Callback = function(v) Parry.Enabled = v end,
})

APLeft:AddLabel("Parry Keybind"):AddKeyPicker("ParryKeybind", {
    Default         = "F",
    Mode            = "Press",
    Text            = "Parry Key",
    NoUI            = false,
    SyncToggleState = false,
    Callback        = function() end,
    ChangedCallback = function(NewKey)
        if NewKey and NewKey.EnumType == Enum.KeyCode then
            Parry.Key = NewKey
        end
    end,
})

APLeft:AddToggle("PerfectParryMode", {
    Text     = "Perfect Parry Mode",
    Default  = true,
    Tooltip  = "Adds pre-buffer to hit Type Soul's perfect parry window",
    Callback = function(v)
        Parry.PreBuffer = v and (Options.ParryPreBuffer.Value / 1000) or 0
    end,
})

APLeft:AddToggle("AntiSpam", {
    Text     = "Anti Spam",
    Default  = true,
    Tooltip  = "Enforces cooldown between parry attempts",
    Callback = function(v)
        Parry.Cooldown = v and (Options.ParryCooldown.Value / 1000) or 0
    end,
})

APLeft:AddDivider()

APLeft:AddButton({
    Text    = "Reset Parry Count",
    Tooltip = "Resets counter to 0",
    Func    = function()
        Parry.Count = 0
        pcall(function() Options.ParryCountLabel:SetText("Parries Fired: 0") end)
    end,
})

-- Timing (right side) — pre-loaded to Type Soul values
APRight:AddSlider("ParryCooldown", {
    Text     = "Cooldown (ms)",
    Default  = 350,
    Min      = 50,
    Max      = 1000,
    Rounding = 0,
    Suffix   = "ms",
    Tooltip  = "Min gap between parry attempts. Type Soul window ~350ms",
    Callback = function(v)
        if Toggles.AntiSpam and Toggles.AntiSpam.Value then
            Parry.Cooldown = v / 1000
        end
    end,
})

APRight:AddSlider("ParryHoldTime", {
    Text     = "Hold Time (ms)",
    Default  = 80,
    Min      = 30,
    Max      = 300,
    Rounding = 0,
    Suffix   = "ms",
    Tooltip  = "How long the parry key is held",
    Callback = function(v) Parry.HoldTime = v / 1000 end,
})

APRight:AddSlider("ParryPreBuffer", {
    Text     = "Pre-Buffer (ms)",
    Default  = 50,
    Min      = 0,
    Max      = 200,
    Rounding = 0,
    Suffix   = "ms",
    Tooltip  = "Fire parry this many ms before damage lands",
    Callback = function(v)
        if Toggles.PerfectParryMode and Toggles.PerfectParryMode.Value then
            Parry.PreBuffer = v / 1000
        end
    end,
})

APRight:AddSlider("ParryThreshold", {
    Text     = "Damage Threshold (%)",
    Default  = 4,
    Min      = 1,
    Max      = 25,
    Rounding = 0,
    Suffix   = "%",
    Tooltip  = "Min HP% drop to trigger parry",
    Callback = function(v) Parry.Threshold = v / 100 end,
})

APRight:AddDivider()

APRight:AddDropdown("DetectionLayer", {
    Values  = {"All Layers", "Health Only", "Remote Only", "Animation Only"},
    Default = "All Layers",
    Text    = "Detection Layer",
    Tooltip = "All Layers is most reliable for Type Soul",
    Callback = function(v) getgenv().NightDetection = v end,
})

-- Info
APInfo:AddLabel("Detection Layers:", true)
APInfo:AddLabel("1. HealthChanged (universal)", true)
APInfo:AddLabel("2. RemoteEvent scan (pre-damage)", true)
APInfo:AddLabel("3. AnimationTrack (anime games)", true)
APInfo:AddLabel("4. CharValue watch (Type Soul)", true)
APInfo:AddDivider()
APInfo:AddLabel("ParryCountLabel", {
    Text     = "Parries Fired: 0",
    DoesWrap = false,
})
APInfo:AddLabel("Executor: " .. ExecName, true)

-- ═══════════════════════════════════════════════════════
--  COMBAT TAB
-- ═══════════════════════════════════════════════════════
local CombatLeft  = Tabs.Combat:AddLeftGroupbox("Auto Combat", "sword")
local CombatRight = Tabs.Combat:AddRightGroupbox("Settings",   "sliders")

-- Auto M1
local autoM1Running = false
CombatLeft:AddToggle("AutoM1", {
    Text     = "Auto M1",
    Default  = false,
    Tooltip  = "Automatically spams left click",
    Callback = function(v)
        autoM1Running = v
        if v then
            task.spawn(function()
                while autoM1Running do
                    safeMouseClick(0.05)
                    local delay = (Options.M1Delay.Value / 1000)
                    if Toggles.RandomizeTimings and Toggles.RandomizeTimings.Value then
                        delay = delay + (math.random() * 2 - 1) * ((Options.RandomVariance.Value or 15) / 1000)
                    end
                    task.wait(math.max(0.05, delay))
                end
            end)
        end
    end,
})

CombatLeft:AddSlider("M1Delay", {
    Text     = "M1 Delay (ms)",
    Default  = 200,
    Min      = 50,
    Max      = 800,
    Rounding = 0,
    Suffix   = "ms",
    Tooltip  = "Delay between each M1 click",
})

CombatLeft:AddDivider()

-- Auto Skill
local autoSkillRunning = false
CombatLeft:AddToggle("AutoSkill", {
    Text     = "Auto Skill Spam",
    Default  = false,
    Tooltip  = "Automatically spams your selected skill key",
    Callback = function(v)
        autoSkillRunning = v
        if v then
            task.spawn(function()
                while autoSkillRunning do
                    local key = Enum.KeyCode[Options.SkillKey.Value] or Enum.KeyCode.Q
                    safeKeyPress(key, 0.05)
                    task.wait(math.max(0.05, Options.SkillDelay.Value / 1000))
                end
            end)
        end
    end,
})

CombatLeft:AddDropdown("SkillKey", {
    Values  = {"Q","E","R","T","G","H","Z","X","C","V","B","N","M"},
    Default = "Q",
    Text    = "Skill Key",
    Tooltip = "Key to spam for auto skill",
})

CombatLeft:AddSlider("SkillDelay", {
    Text     = "Skill Delay (ms)",
    Default  = 300,
    Min      = 50,
    Max      = 2000,
    Rounding = 0,
    Suffix   = "ms",
    Tooltip  = "Delay between each skill press",
})

CombatLeft:AddDivider()

-- Auto Block
local blockHeld = false
CombatLeft:AddToggle("AutoBlock", {
    Text     = "Auto Block",
    Default  = false,
    Tooltip  = "Holds block key automatically",
    Callback = function(v)
        local blockKey = Enum.KeyCode[Options.BlockKey.Value] or Enum.KeyCode.G
        if v and not blockHeld then
            blockHeld = true
            if keypress then
                pcall(function() keypress(blockKey.Value) end)
            else
                pcall(function()
                    game:GetService("VirtualInputManager"):SendKeyEvent(true, blockKey, false, game)
                end)
            end
        elseif not v and blockHeld then
            blockHeld = false
            if keyrelease then
                pcall(function() keyrelease(blockKey.Value) end)
            else
                pcall(function()
                    game:GetService("VirtualInputManager"):SendKeyEvent(false, blockKey, false, game)
                end)
            end
        end
    end,
})

CombatLeft:AddDropdown("BlockKey", {
    Values  = {"G","F","Q","E","R","T","H","V","B"},
    Default = "G",
    Text    = "Block Key",
    Tooltip = "Key to hold for blocking",
})

-- Right side settings
CombatRight:AddToggle("RandomizeTimings", {
    Text    = "Randomize Timings",
    Default = true,
    Tooltip = "Adds slight random variance to all timings to avoid detection",
})

CombatRight:AddToggle("HumanizeInput", {
    Text    = "Humanize Input",
    Default = true,
    Tooltip = "Adds human-like imperfections to key presses",
})

CombatRight:AddDivider()

CombatRight:AddSlider("RandomVariance", {
    Text     = "Random Variance (ms)",
    Default  = 15,
    Min      = 0,
    Max      = 100,
    Rounding = 0,
    Suffix   = "ms",
    Tooltip  = "Max random ms added/subtracted from timings",
})

-- ═══════════════════════════════════════════════════════
--  MOVEMENT TAB
-- ═══════════════════════════════════════════════════════
local MoveLeft  = Tabs.Movement:AddLeftGroupbox("Speed / Fly", "zap")
local MoveRight = Tabs.Movement:AddRightGroupbox("Teleport",   "map-pin")

-- Speed
MoveLeft:AddToggle("SpeedEnabled", {
    Text     = "Speed Hack",
    Default  = false,
    Tooltip  = "Modifies WalkSpeed",
    Callback = function(v)
        local c = LP.Character
        if c then
            local h = c:FindFirstChildOfClass("Humanoid")
            if h then h.WalkSpeed = v and Options.SpeedValue.Value or 16 end
        end
    end,
})

MoveLeft:AddSlider("SpeedValue", {
    Text     = "Walk Speed",
    Default  = 32,
    Min      = 16,
    Max      = 250,
    Rounding = 0,
    Callback = function(v)
        if Toggles.SpeedEnabled and Toggles.SpeedEnabled.Value then
            local c = LP.Character
            if c then
                local h = c:FindFirstChildOfClass("Humanoid")
                if h then h.WalkSpeed = v end
            end
        end
    end,
})

MoveLeft:AddDivider()

-- Fly
local flyConn = nil
MoveLeft:AddToggle("FlyEnabled", {
    Text     = "Fly",
    Default  = false,
    Tooltip  = "WASD + Space/Ctrl to fly",
    Callback = function(v)
        local c = LP.Character
        if not c then return end
        local h = c:FindFirstChildOfClass("Humanoid")
        local hrp = c:FindFirstChild("HumanoidRootPart")
        if not (h and hrp) then return end

        if v then
            h.PlatformStand = true

            local bg = Instance.new("BodyGyro")
            bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            bg.P         = 9e4
            bg.Name      = "NightFlyGyro"
            bg.Parent    = hrp

            local bv = Instance.new("BodyVelocity")
            bv.Velocity  = Vector3.zero
            bv.MaxForce  = Vector3.new(9e9, 9e9, 9e9)
            bv.Name      = "NightFlyVel"
            bv.Parent    = hrp

            flyConn = RunService.RenderStepped:Connect(function()
                if not (Toggles.FlyEnabled and Toggles.FlyEnabled.Value) then
                    flyConn:Disconnect()
                    flyConn = nil
                    return
                end
                local hrp2 = c and c:FindFirstChild("HumanoidRootPart")
                local gyro = hrp2 and hrp2:FindFirstChild("NightFlyGyro")
                local vel  = hrp2 and hrp2:FindFirstChild("NightFlyVel")
                if not (hrp2 and gyro and vel) then
                    if flyConn then flyConn:Disconnect() flyConn = nil end
                    return
                end
                local cam  = workspace.CurrentCamera
                local spd  = Options.FlySpeed and Options.FlySpeed.Value or 50
                local move = Vector3.zero
                local UIS  = UserInputService
                if UIS:IsKeyDown(Enum.KeyCode.W) then move = move + cam.CFrame.LookVector  end
                if UIS:IsKeyDown(Enum.KeyCode.S) then move = move - cam.CFrame.LookVector  end
                if UIS:IsKeyDown(Enum.KeyCode.A) then move = move - cam.CFrame.RightVector end
                if UIS:IsKeyDown(Enum.KeyCode.D) then move = move + cam.CFrame.RightVector end
                if UIS:IsKeyDown(Enum.KeyCode.Space)       then move = move + Vector3.new(0,1,0)  end
                if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then move = move - Vector3.new(0,1,0)  end
                vel.Velocity = move.Magnitude > 0 and move.Unit * spd or Vector3.zero
                gyro.CFrame  = cam.CFrame
            end)
        else
            h.PlatformStand = false
            if flyConn then flyConn:Disconnect() flyConn = nil end
            local g  = hrp:FindFirstChild("NightFlyGyro")
            local bv = hrp:FindFirstChild("NightFlyVel")
            if g  then g:Destroy()  end
            if bv then bv:Destroy() end
        end
    end,
})

MoveLeft:AddSlider("FlySpeed", {
    Text     = "Fly Speed",
    Default  = 50,
    Min      = 10,
    Max      = 500,
    Rounding = 0,
    Tooltip  = "Fly movement speed",
})

-- Teleport (right)
MoveRight:AddDropdown("TeleportTarget", {
    SpecialType        = "Player",
    ExcludeLocalPlayer = true,
    Text    = "Target Player",
    Tooltip = "Select a player to teleport to",
})

MoveRight:AddButton({
    Text    = "Teleport To Player",
    Tooltip = "Teleport to selected player",
    Func    = function()
        local name = Options.TeleportTarget.Value
        if not name then
            Library:Notify({Title="NightHub", Description="Select a player first!", Time=2})
            return
        end
        local target = Players:FindFirstChild(name)
        if not (target and target.Character) then return end
        local tRoot = target.Character:FindFirstChild("HumanoidRootPart")
        local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if tRoot and myRoot then
            myRoot.CFrame = tRoot.CFrame + Vector3.new(3, 0, 0)
            Library:Notify({Title="NightHub", Description="Teleported to " .. name, Time=2})
        end
    end,
})

MoveRight:AddDivider()

MoveRight:AddButton({
    Text    = "Teleport Nearest Enemy",
    Tooltip = "Teleports to the closest player",
    Func    = function()
        local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not myRoot then return end
        local closest, closestDist = nil, math.huge
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= LP and p.Character then
                local r = p.Character:FindFirstChild("HumanoidRootPart")
                if r then
                    local d = (r.Position - myRoot.Position).Magnitude
                    if d < closestDist then closest = r closestDist = d end
                end
            end
        end
        if closest then
            myRoot.CFrame = closest.CFrame + Vector3.new(3, 0, 0)
            Library:Notify({Title="NightHub", Description="Teleported to nearest enemy", Time=2})
        else
            Library:Notify({Title="NightHub", Description="No players found", Time=2})
        end
    end,
})

-- ═══════════════════════════════════════════════════════
--  VISUALS TAB
-- ═══════════════════════════════════════════════════════
local VisLeft  = Tabs.Visual:AddLeftGroupbox("ESP",   "eye")
local VisRight = Tabs.Visual:AddRightGroupbox("Chams","layers")

local ESPObjects = {}

local function removeESP()
    for _, t in pairs(ESPObjects) do
        for _, obj in pairs(t) do pcall(function() obj:Destroy() end) end
    end
    ESPObjects = {}
end

local function makeESP(player)
    if player == LP or ESPObjects[player.Name] then return end
    local c = player.Character
    if not c then return end
    local hrp2 = c:FindFirstChild("HumanoidRootPart")
    if not hrp2 then return end

    local hl = Instance.new("Highlight")
    hl.FillColor          = Options.ESPFillColor    and Options.ESPFillColor.Value    or Color3.fromRGB(255,0,0)
    hl.OutlineColor       = Options.ESPOutlineColor and Options.ESPOutlineColor.Value or Color3.fromRGB(255,255,255)
    hl.FillTransparency   = 0.5
    hl.OutlineTransparency = 0
    hl.Adornee            = c
    hl.DepthMode          = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent             = c

    local bb = Instance.new("BillboardGui")
    bb.Size        = UDim2.new(0, 100, 0, 40)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Adornee     = hrp2
    bb.Parent      = hrp2

    local lbl2 = Instance.new("TextLabel")
    lbl2.Size                   = UDim2.new(1,0,1,0)
    lbl2.BackgroundTransparency = 1
    lbl2.Text                   = player.Name
    lbl2.TextColor3             = Color3.fromRGB(255,255,255)
    lbl2.TextStrokeTransparency = 0
    lbl2.Font                   = Enum.Font.GothamBold
    lbl2.TextSize               = 14
    lbl2.Parent                 = bb

    ESPObjects[player.Name] = {hl, bb}
end

VisLeft:AddToggle("ESPEnabled", {
    Text     = "Player ESP",
    Default  = false,
    Tooltip  = "Highlights all players through walls",
    Callback = function(v)
        if v then
            for _, p in pairs(Players:GetPlayers()) do makeESP(p) end
        else
            removeESP()
        end
    end,
})

VisLeft:AddLabel("Fill Color"):AddColorPicker("ESPFillColor", {
    Default      = Color3.fromRGB(255, 0, 0),
    Title        = "ESP Fill Color",
    Transparency = 0.5,
    Callback     = function(v)
        for _, t in pairs(ESPObjects) do
            if t[1] then t[1].FillColor = v end
        end
    end,
})

VisLeft:AddLabel("Outline Color"):AddColorPicker("ESPOutlineColor", {
    Default  = Color3.fromRGB(255, 255, 255),
    Title    = "ESP Outline Color",
    Callback = function(v)
        for _, t in pairs(ESPObjects) do
            if t[1] then t[1].OutlineColor = v end
        end
    end,
})

VisLeft:AddDivider()

VisLeft:AddToggle("ShowHealth", {
    Text    = "Show Health in ESP",
    Default = true,
    Tooltip = "Shows HP next to player name",
})

-- Chams
VisRight:AddToggle("ChamsEnabled", {
    Text     = "Self Chams",
    Default  = false,
    Tooltip  = "Makes your character glow",
    Callback = function(v)
        local c = LP.Character
        if not c then return end
        if v then
            local hl = Instance.new("Highlight")
            hl.Name              = "NightChams"
            hl.FillColor         = Options.ChamsFillColor and Options.ChamsFillColor.Value or Color3.fromRGB(0,170,255)
            hl.OutlineColor      = Color3.fromRGB(255,255,255)
            hl.FillTransparency  = 0.3
            hl.Adornee           = c
            hl.Parent            = c
        else
            local existing = c:FindFirstChild("NightChams")
            if existing then existing:Destroy() end
        end
    end,
})

VisRight:AddLabel("Chams Color"):AddColorPicker("ChamsFillColor", {
    Default      = Color3.fromRGB(0, 170, 255),
    Title        = "Chams Fill Color",
    Transparency = 0,
    Callback     = function(v)
        local c = LP.Character
        if c then
            local hl = c:FindFirstChild("NightChams")
            if hl then hl.FillColor = v end
        end
    end,
})

-- ESP update loop
RunService.RenderStepped:Connect(function()
    if not (Toggles.ESPEnabled and Toggles.ESPEnabled.Value) then return end
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP then
            if not ESPObjects[p.Name] then
                makeESP(p)
            elseif Toggles.ShowHealth and Toggles.ShowHealth.Value then
                local objs = ESPObjects[p.Name]
                if objs and objs[2] then
                    local lbl3 = objs[2]:FindFirstChildOfClass("TextLabel")
                    local ph   = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
                    if lbl3 and ph then
                        lbl3.Text = p.Name .. "\n" .. math.floor(ph.Health) .. " HP"
                    end
                end
            end
        end
    end
end)

Players.PlayerRemoving:Connect(function(p)
    if ESPObjects[p.Name] then
        for _, obj in pairs(ESPObjects[p.Name]) do
            pcall(function() obj:Destroy() end)
        end
        ESPObjects[p.Name] = nil
    end
end)

-- ═══════════════════════════════════════════════════════
--  SETTINGS TAB
-- ═══════════════════════════════════════════════════════
local MenuGroup = Tabs.Settings:AddLeftGroupbox("Menu", "wrench")

MenuGroup:AddToggle("KeybindMenuOpen", {
    Default  = Library.KeybindFrame.Visible,
    Text     = "Open Keybind Menu",
    Callback = function(v) Library.KeybindFrame.Visible = v end,
})

MenuGroup:AddToggle("ShowCustomCursor", {
    Text     = "Custom Cursor",
    Default  = Library.ShowCustomCursor,
    Callback = function(v) Library.ShowCustomCursor = v end,
})

MenuGroup:AddDropdown("NotificationSide", {
    Values   = {"Left", "Right"},
    Default  = "Right",
    Text     = "Notification Side",
    Callback = function(v) Library:SetNotifySide(v) end,
})

MenuGroup:AddDropdown("DPIDropdown", {
    Values   = {"50%","75%","100%","125%","150%","175%","200%"},
    Default  = "100%",
    Text     = "DPI Scale",
    Callback = function(v)
        Library:SetDPIScale(tonumber(v:gsub("%%", "")))
    end,
})

MenuGroup:AddSlider("UICornerSlider", {
    Text     = "Corner Radius",
    Default  = Library.CornerRadius,
    Min      = 0,
    Max      = 20,
    Rounding = 0,
    Callback = function(v) Window:SetCornerRadius(v) end,
})

MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu Keybind")
    :AddKeyPicker("MenuKeybind", {Default="RightShift", NoUI=true, Text="Menu keybind"})

MenuGroup:AddButton({
    Text = "Unload",
    Func = function()
        removeESP()
        for _, c in pairs(Parry.Conns) do pcall(function() c:Disconnect() end) end
        Library:Unload()
    end,
})

Library.ToggleKeybind = Options.MenuKeybind

-- ═══════════════════════════════════════════════════════
--  SAVE / THEME
-- ═══════════════════════════════════════════════════════
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({"MenuKeybind"})

ThemeManager:SetFolder("NightHub")
SaveManager:SetFolder("NightHub/TypeSoul")

SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)
SaveManager:LoadAutoloadConfig()

-- ═══════════════════════════════════════════════════════
--  READY
-- ═══════════════════════════════════════════════════════
Library:Notify({
    Title       = "NightHub",
    Description = "Loaded! Executor: " .. ExecName,
    Time        = 4,
})

print("[NightHub] Type Soul loaded ✓ | " .. ExecName)
