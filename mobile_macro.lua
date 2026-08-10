-- Mobile Macro Recorder (TinyTask-style)
-- Universal: works on any Roblox game
-- Records touch inputs, camera movement, key presses and replays them

local Players        = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService     = game:GetService("RunService")
local VIM           = game:GetService("VirtualInputManager")
local GuiService    = game:GetService("GuiService")

local localPlayer   = Players.LocalPlayer
local playerGui     = localPlayer:WaitForChild("PlayerGui")

-- ─────────────────────────────────────────────
--  STATE
-- ─────────────────────────────────────────────

local recording     = false
local playing       = false
local recordStart   = 0
local macro         = {}        -- { { time, type, data }, ... }
local connections   = {}
local playTask      = nil
local loopEnabled   = false
local playSpeed     = 1.0       -- playback speed multiplier

-- ─────────────────────────────────────────────
--  UI SETUP
-- ─────────────────────────────────────────────

-- Remove old instance if re-running
local old = playerGui:FindFirstChild("MacroUI")
if old then old:Destroy() end

local screenGui     = Instance.new("ScreenGui")
screenGui.Name      = "MacroUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 999
screenGui.IgnoreGuiInset = true
screenGui.Parent    = playerGui

-- ── Draggable main frame ──────────────────────
local frame = Instance.new("Frame")
frame.Name  = "Main"
frame.Size  = UDim2.new(0, 240, 0, 310)
frame.Position = UDim2.new(0, 10, 0.5, -155)
frame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
frame.BorderSizePixel = 0
frame.Active   = true
frame.Draggable = true
frame.Parent   = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color     = Color3.fromRGB(80, 80, 110)
stroke.Thickness = 1
stroke.Parent    = frame

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size  = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
titleBar.BorderSizePixel = 0
titleBar.Parent = frame

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 10)
titleCorner.Parent = titleBar

-- fix bottom corners of titlebar
local titleFix = Instance.new("Frame")
titleFix.Size  = UDim2.new(1, 0, 0, 10)
titleFix.Position = UDim2.new(0, 0, 1, -10)
titleFix.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
titleFix.BorderSizePixel  = 0
titleFix.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size  = UDim2.new(1, -10, 1, 0)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text  = "📱 Macro Recorder"
titleLabel.TextColor3 = Color3.fromRGB(210, 210, 255)
titleLabel.TextSize   = 14
titleLabel.Font  = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

-- Status label
local statusLabel = Instance.new("TextLabel")
statusLabel.Size  = UDim2.new(1, -16, 0, 24)
statusLabel.Position = UDim2.new(0, 8, 0, 42)
statusLabel.BackgroundTransparency = 1
statusLabel.Text  = "● Idle"
statusLabel.TextColor3 = Color3.fromRGB(130, 130, 160)
statusLabel.TextSize   = 13
statusLabel.Font  = Enum.Font.Gotham
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = frame

-- Event count label
local countLabel = Instance.new("TextLabel")
countLabel.Size  = UDim2.new(1, -16, 0, 20)
countLabel.Position = UDim2.new(0, 8, 0, 66)
countLabel.BackgroundTransparency = 1
countLabel.Text  = "Events: 0"
countLabel.TextColor3 = Color3.fromRGB(100, 100, 130)
countLabel.TextSize   = 12
countLabel.Font  = Enum.Font.Gotham
countLabel.TextXAlignment = Enum.TextXAlignment.Left
countLabel.Parent = frame

-- ── Helper: make a button ────────────────────
local function makeButton(text, posY, bgColor)
    local btn = Instance.new("TextButton")
    btn.Size  = UDim2.new(1, -16, 0, 38)
    btn.Position = UDim2.new(0, 8, 0, posY)
    btn.BackgroundColor3 = bgColor or Color3.fromRGB(55, 55, 75)
    btn.BorderSizePixel  = 0
    btn.Text  = text
    btn.TextColor3 = Color3.fromRGB(230, 230, 255)
    btn.TextSize   = 13
    btn.Font  = Enum.Font.GothamBold
    btn.AutoButtonColor = true
    btn.Parent = frame

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 7)
    c.Parent = btn
    return btn
end

local recordBtn = makeButton("⏺  Record",  96,  Color3.fromRGB(180, 50, 50))
local stopBtn   = makeButton("⏹  Stop",    142, Color3.fromRGB(60, 60, 80))
local playBtn   = makeButton("▶  Play",    188, Color3.fromRGB(40, 130, 80))
local clearBtn  = makeButton("🗑  Clear",   234, Color3.fromRGB(60, 50, 70))

-- Loop toggle
local loopFrame = Instance.new("Frame")
loopFrame.Size  = UDim2.new(1, -16, 0, 28)
loopFrame.Position = UDim2.new(0, 8, 0, 278)
loopFrame.BackgroundTransparency = 1
loopFrame.Parent = frame

local loopLabel = Instance.new("TextLabel")
loopLabel.Size  = UDim2.new(0.6, 0, 1, 0)
loopLabel.BackgroundTransparency = 1
loopLabel.Text  = "Loop playback"
loopLabel.TextColor3 = Color3.fromRGB(160, 160, 200)
loopLabel.TextSize   = 12
loopLabel.Font  = Enum.Font.Gotham
loopLabel.TextXAlignment = Enum.TextXAlignment.Left
loopLabel.Parent = loopFrame

local loopToggle = Instance.new("TextButton")
loopToggle.Size  = UDim2.new(0, 44, 0, 22)
loopToggle.Position = UDim2.new(1, -44, 0, 3)
loopToggle.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
loopToggle.BorderSizePixel  = 0
loopToggle.Text  = "OFF"
loopToggle.TextColor3 = Color3.fromRGB(180, 180, 200)
loopToggle.TextSize   = 11
loopToggle.Font  = Enum.Font.GothamBold
loopToggle.Parent = loopFrame

local ltc = Instance.new("UICorner")
ltc.CornerRadius = UDim.new(0, 5)
ltc.Parent = loopToggle

-- ─────────────────────────────────────────────
--  RECORDING LOGIC
-- ─────────────────────────────────────────────

local function setStatus(text, color)
    statusLabel.Text       = text
    statusLabel.TextColor3 = color or Color3.fromRGB(130, 130, 160)
end

local function updateCount()
    countLabel.Text = "Events: " .. #macro
end

local function stopRecording()
    recording = false
    for _, c in ipairs(connections) do c:Disconnect() end
    connections = {}
    setStatus("● Idle  [" .. #macro .. " events]", Color3.fromRGB(130, 130, 160))
end

local function stopPlaying()
    playing = false
    if playTask then task.cancel(playTask) playTask = nil end
    setStatus("● Idle", Color3.fromRGB(130, 130, 160))
end

-- Record a touch event
local function recordEvent(evtType, data)
    if not recording then return end
    local t = tick() - recordStart
    table.insert(macro, { time = t, type = evtType, data = data })
    updateCount()
end

local function startRecording()
    if playing then stopPlaying() end
    macro        = {}
    recording    = true
    recordStart  = tick()
    setStatus("⏺  Recording...", Color3.fromRGB(220, 80, 80))
    updateCount()

    -- Touch began
    local c1 = UserInputService.TouchStarted:Connect(function(touch, processed)
        recordEvent("TouchBegan", {
            pos  = { x = touch.Position.X, y = touch.Position.Y },
        })
    end)

    -- Touch moved
    local c2 = UserInputService.TouchMoved:Connect(function(touch, processed)
        recordEvent("TouchMoved", {
            pos  = { x = touch.Position.X, y = touch.Position.Y },
        })
    end)

    -- Touch ended
    local c3 = UserInputService.TouchEnded:Connect(function(touch, processed)
        recordEvent("TouchEnded", {
            pos  = { x = touch.Position.X, y = touch.Position.Y },
        })
    end)

    -- Key presses (for keyboards / controller)
    local c4 = UserInputService.InputBegan:Connect(function(input, processed)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            recordEvent("KeyDown", { key = input.KeyCode.Name })
        end
    end)

    local c5 = UserInputService.InputEnded:Connect(function(input, processed)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            recordEvent("KeyUp", { key = input.KeyCode.Name })
        end
    end)

    connections = { c1, c2, c3, c4, c5 }
end

-- ─────────────────────────────────────────────
--  PLAYBACK LOGIC
-- ─────────────────────────────────────────────

local function replayMacro()
    if #macro == 0 then
        setStatus("⚠ No events to play", Color3.fromRGB(220, 180, 50))
        return
    end

    playing = true
    setStatus("▶  Playing...", Color3.fromRGB(60, 200, 120))

    playTask = task.spawn(function()
        repeat
            local startTime = tick()

            for i, event in ipairs(macro) do
                if not playing then break end

                -- wait until it's time for this event (adjusted by speed)
                local waitTime = event.time / playSpeed
                local elapsed  = tick() - startTime
                local remaining = waitTime - elapsed
                if remaining > 0 then
                    task.wait(remaining)
                end

                if not playing then break end

                -- replay the event
                local d = event.data
                if event.type == "TouchBegan" then
                    pcall(function()
                        VIM:SendTouchEvent(d.pos.x, d.pos.y, Enum.UserInputType.Touch, Enum.UserInputState.Begin)
                    end)
                elseif event.type == "TouchMoved" then
                    pcall(function()
                        VIM:SendTouchEvent(d.pos.x, d.pos.y, Enum.UserInputType.Touch, Enum.UserInputState.Change)
                    end)
                elseif event.type == "TouchEnded" then
                    pcall(function()
                        VIM:SendTouchEvent(d.pos.x, d.pos.y, Enum.UserInputType.Touch, Enum.UserInputState.End)
                    end)
                elseif event.type == "KeyDown" then
                    pcall(function()
                        local kc = Enum.KeyCode[d.key]
                        if kc then VIM:SendKeyEvent(true, kc, false, nil) end
                    end)
                elseif event.type == "KeyUp" then
                    pcall(function()
                        local kc = Enum.KeyCode[d.key]
                        if kc then VIM:SendKeyEvent(false, kc, false, nil) end
                    end)
                end
            end

            if loopEnabled and playing then
                setStatus("▶  Looping...", Color3.fromRGB(60, 200, 120))
                task.wait(0.05)
            end

        until not loopEnabled or not playing

        if playing then
            stopPlaying()
        end
    end)
end

-- ─────────────────────────────────────────────
--  BUTTON CALLBACKS
-- ─────────────────────────────────────────────

recordBtn.MouseButton1Click:Connect(function()
    if recording then return end
    startRecording()
end)

stopBtn.MouseButton1Click:Connect(function()
    if recording then
        stopRecording()
    elseif playing then
        stopPlaying()
    end
end)

playBtn.MouseButton1Click:Connect(function()
    if playing or recording then return end
    replayMacro()
end)

clearBtn.MouseButton1Click:Connect(function()
    if recording then stopRecording() end
    if playing   then stopPlaying()   end
    macro = {}
    updateCount()
    setStatus("● Cleared", Color3.fromRGB(130, 130, 160))
end)

loopToggle.MouseButton1Click:Connect(function()
    loopEnabled = not loopEnabled
    if loopEnabled then
        loopToggle.Text = "ON"
        loopToggle.BackgroundColor3 = Color3.fromRGB(40, 130, 80)
        loopToggle.TextColor3       = Color3.fromRGB(200, 255, 220)
    else
        loopToggle.Text = "OFF"
        loopToggle.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
        loopToggle.TextColor3       = Color3.fromRGB(180, 180, 200)
    end
end)

-- ─────────────────────────────────────────────
--  TOUCH-DRAG to move UI (mobile friendly)
-- ─────────────────────────────────────────────

local dragging, dragStart, startPos
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging  = true
        dragStart = input.Position
        startPos  = frame.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (
        input.UserInputType == Enum.UserInputType.Touch or
        input.UserInputType == Enum.UserInputType.MouseMovement
    ) then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

print("[Macro] Loaded! UI is draggable. Record → Stop → Play.")
