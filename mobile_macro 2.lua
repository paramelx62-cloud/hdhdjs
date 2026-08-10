-- Mobile Macro Recorder (TinyTask-style)
-- Universal: works on any Roblox game
-- Replays by directly moving character + camera instead of faking touch events

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local localPlayer  = Players.LocalPlayer
local playerGui    = localPlayer:WaitForChild("PlayerGui")
local camera       = workspace.CurrentCamera

-- ─────────────────────────────────────────────
--  STATE
-- ─────────────────────────────────────────────

local recording    = false
local playing      = false
local loopEnabled  = false
local recordStart  = 0
local macro        = {}
local connections  = {}
local playTask     = nil
local playSpeed    = 1.0

-- snapshot every N seconds during recording for smooth camera/position replay
local SNAPSHOT_RATE = 0.05

-- ─────────────────────────────────────────────
--  UI
-- ─────────────────────────────────────────────

local old = playerGui:FindFirstChild("MacroUI")
if old then old:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name            = "MacroUI"
screenGui.ResetOnSpawn    = false
screenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder    = 999
screenGui.IgnoreGuiInset  = true
screenGui.Parent          = playerGui

local frame = Instance.new("Frame")
frame.Name              = "Main"
frame.Size              = UDim2.new(0, 240, 0, 330)
frame.Position          = UDim2.new(0, 10, 0.5, -165)
frame.BackgroundColor3  = Color3.fromRGB(22, 22, 28)
frame.BorderSizePixel   = 0
frame.Active            = true
frame.Draggable         = true
frame.Parent            = screenGui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(80, 80, 110); stroke.Thickness = 1

local titleBar = Instance.new("Frame", frame)
titleBar.Size             = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
titleBar.BorderSizePixel  = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)
local fix = Instance.new("Frame", titleBar)
fix.Size = UDim2.new(1,0,0,10); fix.Position = UDim2.new(0,0,1,-10)
fix.BackgroundColor3 = Color3.fromRGB(35,35,48); fix.BorderSizePixel = 0

local titleLabel = Instance.new("TextLabel", titleBar)
titleLabel.Size = UDim2.new(1,-10,1,0); titleLabel.Position = UDim2.new(0,10,0,0)
titleLabel.BackgroundTransparency = 1; titleLabel.Text = "📱 Macro Recorder"
titleLabel.TextColor3 = Color3.fromRGB(210,210,255); titleLabel.TextSize = 14
titleLabel.Font = Enum.Font.GothamBold; titleLabel.TextXAlignment = Enum.TextXAlignment.Left

local statusLabel = Instance.new("TextLabel", frame)
statusLabel.Size = UDim2.new(1,-16,0,22); statusLabel.Position = UDim2.new(0,8,0,42)
statusLabel.BackgroundTransparency = 1; statusLabel.Text = "● Idle"
statusLabel.TextColor3 = Color3.fromRGB(130,130,160); statusLabel.TextSize = 13
statusLabel.Font = Enum.Font.Gotham; statusLabel.TextXAlignment = Enum.TextXAlignment.Left

local countLabel = Instance.new("TextLabel", frame)
countLabel.Size = UDim2.new(1,-16,0,18); countLabel.Position = UDim2.new(0,8,0,64)
countLabel.BackgroundTransparency = 1; countLabel.Text = "Snapshots: 0"
countLabel.TextColor3 = Color3.fromRGB(100,100,130); countLabel.TextSize = 12
countLabel.Font = Enum.Font.Gotham; countLabel.TextXAlignment = Enum.TextXAlignment.Left

local function makeButton(text, posY, bg)
    local btn = Instance.new("TextButton", frame)
    btn.Size = UDim2.new(1,-16,0,36); btn.Position = UDim2.new(0,8,0,posY)
    btn.BackgroundColor3 = bg or Color3.fromRGB(55,55,75); btn.BorderSizePixel = 0
    btn.Text = text; btn.TextColor3 = Color3.fromRGB(230,230,255)
    btn.TextSize = 13; btn.Font = Enum.Font.GothamBold; btn.AutoButtonColor = true
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,7)
    return btn
end

local recordBtn = makeButton("⏺  Record",  88,  Color3.fromRGB(180,50,50))
local stopBtn   = makeButton("⏹  Stop",   132,  Color3.fromRGB(60,60,80))
local playBtn   = makeButton("▶  Play",   176,  Color3.fromRGB(40,130,80))
local clearBtn  = makeButton("🗑  Clear",  220,  Color3.fromRGB(70,50,70))

-- speed slider
local speedLabel = Instance.new("TextLabel", frame)
speedLabel.Size = UDim2.new(1,-16,0,18); speedLabel.Position = UDim2.new(0,8,0,264)
speedLabel.BackgroundTransparency = 1; speedLabel.Text = "Speed: 1.0x"
speedLabel.TextColor3 = Color3.fromRGB(150,150,190); speedLabel.TextSize = 12
speedLabel.Font = Enum.Font.Gotham; speedLabel.TextXAlignment = Enum.TextXAlignment.Left

local speedSlider = Instance.new("TextButton", frame)
speedSlider.Size = UDim2.new(1,-16,0,10); speedSlider.Position = UDim2.new(0,8,0,284)
speedSlider.BackgroundColor3 = Color3.fromRGB(55,55,75); speedSlider.BorderSizePixel = 0
speedSlider.Text = ""; speedSlider.AutoButtonColor = false
Instance.new("UICorner", speedSlider).CornerRadius = UDim.new(0,5)

local sliderFill = Instance.new("Frame", speedSlider)
sliderFill.Size = UDim2.new(0.33,0,1,0); sliderFill.BackgroundColor3 = Color3.fromRGB(100,160,255)
sliderFill.BorderSizePixel = 0
Instance.new("UICorner", sliderFill).CornerRadius = UDim.new(0,5)

-- loop toggle
local loopFrame = Instance.new("Frame", frame)
loopFrame.Size = UDim2.new(1,-16,0,24); loopFrame.Position = UDim2.new(0,8,0,300)
loopFrame.BackgroundTransparency = 1

local loopLbl = Instance.new("TextLabel", loopFrame)
loopLbl.Size = UDim2.new(0.6,0,1,0); loopLbl.BackgroundTransparency = 1
loopLbl.Text = "Loop"; loopLbl.TextColor3 = Color3.fromRGB(150,150,190)
loopLbl.TextSize = 12; loopLbl.Font = Enum.Font.Gotham
loopLbl.TextXAlignment = Enum.TextXAlignment.Left

local loopBtn = Instance.new("TextButton", loopFrame)
loopBtn.Size = UDim2.new(0,44,0,20); loopBtn.Position = UDim2.new(1,-44,0,2)
loopBtn.BackgroundColor3 = Color3.fromRGB(60,60,80); loopBtn.BorderSizePixel = 0
loopBtn.Text = "OFF"; loopBtn.TextColor3 = Color3.fromRGB(180,180,200)
loopBtn.TextSize = 11; loopBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", loopBtn).CornerRadius = UDim.new(0,5)

-- ─────────────────────────────────────────────
--  HELPERS
-- ─────────────────────────────────────────────

local function setStatus(text, color)
    statusLabel.Text = text
    statusLabel.TextColor3 = color or Color3.fromRGB(130,130,160)
end

local function updateCount()
    countLabel.Text = "Snapshots: " .. #macro
end

local function getSnapshot()
    local char = localPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    return {
        -- character position + orientation
        cframe   = hrp and hrp.CFrame or nil,
        moveDir  = hum and hum.MoveDirection or Vector3.zero,
        -- camera
        camCF    = camera.CFrame,
        -- held keys snapshot (for movement reconstruction)
        keys     = {
            w = UserInputService:IsKeyDown(Enum.KeyCode.W),
            a = UserInputService:IsKeyDown(Enum.KeyCode.A),
            s = UserInputService:IsKeyDown(Enum.KeyCode.S),
            d = UserInputService:IsKeyDown(Enum.KeyCode.D),
            space = UserInputService:IsKeyDown(Enum.KeyCode.Space),
        },
        -- jump state
        jumping  = hum and hum.Jump or false,
    }
end

local function stopRecording()
    recording = false
    for _, c in ipairs(connections) do c:Disconnect() end
    connections = {}
    setStatus("● Idle  [" .. #macro .. " snaps]", Color3.fromRGB(130,130,160))
end

local function stopPlaying()
    playing = false
    if playTask then task.cancel(playTask); playTask = nil end
    -- restore camera type
    camera.CameraType = Enum.CameraType.Custom
    setStatus("● Idle", Color3.fromRGB(130,130,160))
end

-- ─────────────────────────────────────────────
--  RECORDING
-- ─────────────────────────────────────────────

local function startRecording()
    if playing then stopPlaying() end
    macro = {}; recording = true; recordStart = tick()
    setStatus("⏺  Recording...", Color3.fromRGB(220,80,80))
    updateCount()

    -- snapshot loop
    local snap = RunService.Heartbeat:Connect(function()
        if not recording then return end
        local t = tick() - recordStart
        -- only record every SNAPSHOT_RATE seconds
        if #macro == 0 or (t - macro[#macro].time) >= SNAPSHOT_RATE then
            local s = getSnapshot()
            s.time = t
            table.insert(macro, s)
            updateCount()
        end
    end)

    connections = { snap }
end

-- ─────────────────────────────────────────────
--  PLAYBACK
-- ─────────────────────────────────────────────

local function replayMacro()
    if #macro == 0 then
        setStatus("⚠ Nothing recorded", Color3.fromRGB(220,180,50))
        return
    end

    playing = true
    setStatus("▶  Playing...", Color3.fromRGB(60,200,120))

    playTask = task.spawn(function()
        repeat
            local startTime = tick()

            for i, snap in ipairs(macro) do
                if not playing then break end

                -- wait for the right moment
                local targetTime = snap.time / playSpeed
                local elapsed    = tick() - startTime
                local remaining  = targetTime - elapsed
                if remaining > 0 then task.wait(remaining) end
                if not playing then break end

                local char = localPlayer.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                local hum  = char and char:FindFirstChildOfClass("Humanoid")

                -- replay camera
                if snap.camCF then
                    camera.CameraType = Enum.CameraType.Scriptable
                    camera.CFrame = snap.camCF
                end

                -- replay character position
                if hrp and snap.cframe then
                    hrp.CFrame = snap.cframe
                end

                -- replay jump
                if hum and snap.jumping then
                    hum.Jump = true
                end

                -- replay humanoid move direction
                if hum and snap.moveDir then
                    hum:Move(snap.moveDir, true)
                end
            end

            if loopEnabled and playing then
                setStatus("▶  Looping...", Color3.fromRGB(60,200,120))
                task.wait(0.05)
            end

        until not loopEnabled or not playing

        if playing then stopPlaying() end
    end)
end

-- ─────────────────────────────────────────────
--  SPEED SLIDER
-- ─────────────────────────────────────────────

local slidingSpeed = false
speedSlider.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.Touch
    or inp.UserInputType == Enum.UserInputType.MouseButton1 then
        slidingSpeed = true
    end
end)
UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.Touch
    or inp.UserInputType == Enum.UserInputType.MouseButton1 then
        slidingSpeed = false
    end
end)
UserInputService.InputChanged:Connect(function(inp)
    if not slidingSpeed then return end
    if inp.UserInputType ~= Enum.UserInputType.Touch
    and inp.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local absPos  = speedSlider.AbsolutePosition
    local absSize = speedSlider.AbsoluteSize
    local rel = math.clamp((inp.Position.X - absPos.X) / absSize.X, 0, 1)
    sliderFill.Size = UDim2.new(rel, 0, 1, 0)
    -- range: 0.25x → 3x
    playSpeed = 0.25 + rel * 2.75
    speedLabel.Text = string.format("Speed: %.2fx", playSpeed)
end)

-- ─────────────────────────────────────────────
--  BUTTON CALLBACKS
-- ─────────────────────────────────────────────

recordBtn.MouseButton1Click:Connect(function()
    if recording then return end
    startRecording()
end)

stopBtn.MouseButton1Click:Connect(function()
    if recording then stopRecording()
    elseif playing then stopPlaying() end
end)

playBtn.MouseButton1Click:Connect(function()
    if playing or recording then return end
    replayMacro()
end)

clearBtn.MouseButton1Click:Connect(function()
    if recording then stopRecording() end
    if playing   then stopPlaying()   end
    macro = {}; updateCount()
    setStatus("● Cleared", Color3.fromRGB(130,130,160))
end)

loopBtn.MouseButton1Click:Connect(function()
    loopEnabled = not loopEnabled
    if loopEnabled then
        loopBtn.Text = "ON"
        loopBtn.BackgroundColor3 = Color3.fromRGB(40,130,80)
        loopBtn.TextColor3 = Color3.fromRGB(200,255,220)
    else
        loopBtn.Text = "OFF"
        loopBtn.BackgroundColor3 = Color3.fromRGB(60,60,80)
        loopBtn.TextColor3 = Color3.fromRGB(180,180,200)
    end
end)

-- ─────────────────────────────────────────────
--  DRAG (touch friendly)
-- ─────────────────────────────────────────────

local dragging, dragStart, startPos
titleBar.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.Touch
    or inp.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true; dragStart = inp.Position; startPos = frame.Position
    end
end)
UserInputService.InputChanged:Connect(function(inp)
    if not dragging then return end
    if inp.UserInputType ~= Enum.UserInputType.Touch
    and inp.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local d = inp.Position - dragStart
    frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                startPos.Y.Scale, startPos.Y.Offset + d.Y)
end)
UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.Touch
    or inp.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

print("[Macro] Ready! Record → Stop → Play")
