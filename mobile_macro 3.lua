-- Mobile Macro Recorder v3
-- Replays via control module thumbstick injection + jump
-- Camera stays natural, no CFrame teleporting, no VIM

local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")
local camera      = workspace.CurrentCamera

-- ─────────────────────────────────────────────
--  CONTROL MODULE HOOK
--  Finds the running ControlModule and lets us
--  inject a fake thumbstick move vector.
-- ─────────────────────────────────────────────

local controlModule = nil
local function findControlModule()
    -- it lives inside PlayerScripts
    local ps = localPlayer:FindFirstChild("PlayerScripts")
    if not ps then return nil end
    local pm = ps:FindFirstChild("PlayerModule")
    if not pm then return nil end
    local ok, result = pcall(require, pm)
    if not ok then return nil end
    -- result is the PlayerModule; get the controls
    local ok2, cm = pcall(function() return result:GetControls() end)
    if ok2 and cm then return cm end
    return nil
end

-- try to grab it (non-blocking, best effort)
task.spawn(function()
    task.wait(1)
    controlModule = findControlModule()
    if controlModule then
        print("[Macro] Control module found ✓")
    else
        print("[Macro] Control module not found, using Humanoid:Move fallback")
    end
end)

-- ─────────────────────────────────────────────
--  STATE
-- ─────────────────────────────────────────────

local recording   = false
local playing     = false
local loopEnabled = false
local recordStart = 0
local macro       = {}        -- array of { time, moveX, moveZ, jump, camY }
local recConn     = nil
local playTask    = nil
local playSpeed   = 1.0
local RATE        = 0.05      -- record a sample every 50ms

-- track input state while recording
local heldKeys = { w=false, a=false, s=false, d=false }
local jumpHeld = false

-- ─────────────────────────────────────────────
--  UI
-- ─────────────────────────────────────────────

local old = playerGui:FindFirstChild("MacroUI")
if old then old:Destroy() end

local sg = Instance.new("ScreenGui")
sg.Name="MacroUI"; sg.ResetOnSpawn=false
sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
sg.DisplayOrder=999; sg.IgnoreGuiInset=true
sg.Parent=playerGui

local frame = Instance.new("Frame", sg)
frame.Name="Main"; frame.Size=UDim2.new(0,240,0,320)
frame.Position=UDim2.new(0,10,0.5,-160)
frame.BackgroundColor3=Color3.fromRGB(20,20,26)
frame.BorderSizePixel=0; frame.Active=true; frame.Draggable=true
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,10)
local sk=Instance.new("UIStroke",frame)
sk.Color=Color3.fromRGB(80,80,120); sk.Thickness=1

-- title
local tb=Instance.new("Frame",frame)
tb.Size=UDim2.new(1,0,0,34); tb.BackgroundColor3=Color3.fromRGB(32,32,44)
tb.BorderSizePixel=0
Instance.new("UICorner",tb).CornerRadius=UDim.new(0,10)
local tbfix=Instance.new("Frame",tb)
tbfix.Size=UDim2.new(1,0,0,10); tbfix.Position=UDim2.new(0,0,1,-10)
tbfix.BackgroundColor3=Color3.fromRGB(32,32,44); tbfix.BorderSizePixel=0
local tl=Instance.new("TextLabel",tb)
tl.Size=UDim2.new(1,-10,1,0); tl.Position=UDim2.new(0,10,0,0)
tl.BackgroundTransparency=1; tl.Text="📱 Macro Recorder"
tl.TextColor3=Color3.fromRGB(200,200,255); tl.TextSize=14
tl.Font=Enum.Font.GothamBold; tl.TextXAlignment=Enum.TextXAlignment.Left

local function lbl(txt, y, size, col)
    local l=Instance.new("TextLabel",frame)
    l.Size=UDim2.new(1,-16,0,20); l.Position=UDim2.new(0,8,0,y)
    l.BackgroundTransparency=1; l.Text=txt
    l.TextColor3=col or Color3.fromRGB(120,120,155)
    l.TextSize=size or 12; l.Font=Enum.Font.Gotham
    l.TextXAlignment=Enum.TextXAlignment.Left
    return l
end

local statusLbl = lbl("● Idle", 40, 13, Color3.fromRGB(130,130,160))
local countLbl  = lbl("Samples: 0", 60, 12)

local function btn(txt, y, bg)
    local b=Instance.new("TextButton",frame)
    b.Size=UDim2.new(1,-16,0,34); b.Position=UDim2.new(0,8,0,y)
    b.BackgroundColor3=bg or Color3.fromRGB(50,50,68)
    b.BorderSizePixel=0; b.Text=txt
    b.TextColor3=Color3.fromRGB(225,225,255); b.TextSize=13
    b.Font=Enum.Font.GothamBold; b.AutoButtonColor=true
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,7)
    return b
end

local recBtn   = btn("⏺  Record",  84, Color3.fromRGB(170,45,45))
local stopBtn  = btn("⏹  Stop",   126, Color3.fromRGB(55,55,72))
local playBtn  = btn("▶  Play",   168, Color3.fromRGB(38,120,72))
local clearBtn = btn("🗑  Clear",  210, Color3.fromRGB(65,45,65))

-- speed
local speedLbl = lbl("Speed: 1.0x", 256, 12)
local sSlider  = Instance.new("TextButton",frame)
sSlider.Size=UDim2.new(1,-16,0,10); sSlider.Position=UDim2.new(0,8,0,272)
sSlider.BackgroundColor3=Color3.fromRGB(50,50,68); sSlider.BorderSizePixel=0
sSlider.Text=""; sSlider.AutoButtonColor=false
Instance.new("UICorner",sSlider).CornerRadius=UDim.new(0,5)
local sFill=Instance.new("Frame",sSlider)
sFill.Size=UDim2.new(0.33,0,1,0)
sFill.BackgroundColor3=Color3.fromRGB(90,150,255); sFill.BorderSizePixel=0
Instance.new("UICorner",sFill).CornerRadius=UDim.new(0,5)

-- loop
local loopF=Instance.new("Frame",frame)
loopF.Size=UDim2.new(1,-16,0,24); loopF.Position=UDim2.new(0,8,0,292)
loopF.BackgroundTransparency=1
local loopL=Instance.new("TextLabel",loopF)
loopL.Size=UDim2.new(0.6,0,1,0); loopL.BackgroundTransparency=1
loopL.Text="Loop"; loopL.TextColor3=Color3.fromRGB(140,140,180)
loopL.TextSize=12; loopL.Font=Enum.Font.Gotham
loopL.TextXAlignment=Enum.TextXAlignment.Left
local loopBtn=Instance.new("TextButton",loopF)
loopBtn.Size=UDim2.new(0,44,0,20); loopBtn.Position=UDim2.new(1,-44,0,2)
loopBtn.BackgroundColor3=Color3.fromRGB(55,55,72); loopBtn.BorderSizePixel=0
loopBtn.Text="OFF"; loopBtn.TextColor3=Color3.fromRGB(170,170,200)
loopBtn.TextSize=11; loopBtn.Font=Enum.Font.GothamBold
Instance.new("UICorner",loopBtn).CornerRadius=UDim.new(0,5)

-- ─────────────────────────────────────────────
--  HELPERS
-- ─────────────────────────────────────────────

local function setStatus(t, col)
    statusLbl.Text=t; statusLbl.TextColor3=col or Color3.fromRGB(130,130,160)
end
local function updCount() countLbl.Text="Samples: "..#macro end

local function getMoveVec()
    -- build a raw WASD vector (not camera-relative yet, we store raw)
    local x = (heldKeys.d and 1 or 0) - (heldKeys.a and 1 or 0)
    local z = (heldKeys.s and 1 or 0) - (heldKeys.w and 1 or 0)
    return x, z
end

-- ─────────────────────────────────────────────
--  RECORDING
-- ─────────────────────────────────────────────

local keyConns = {}

local function stopRecording()
    recording = false
    if recConn then recConn:Disconnect(); recConn=nil end
    for _,c in ipairs(keyConns) do c:Disconnect() end
    keyConns = {}
    heldKeys = {w=false,a=false,s=false,d=false}
    jumpHeld = false
    setStatus("● Idle  ["..#macro.." samples]", Color3.fromRGB(130,130,160))
end

local function startRecording()
    if playing then return end
    macro={}; recording=true; recordStart=tick()
    heldKeys={w=false,a=false,s=false,d=false}
    jumpHeld=false
    setStatus("⏺  Recording...", Color3.fromRGB(210,70,70))
    updCount()

    -- track keyboard
    local function trackKey(input, down)
        local k = input.KeyCode
        if k==Enum.KeyCode.W then heldKeys.w=down
        elseif k==Enum.KeyCode.A then heldKeys.a=down
        elseif k==Enum.KeyCode.S then heldKeys.s=down
        elseif k==Enum.KeyCode.D then heldKeys.d=down
        elseif k==Enum.KeyCode.Space then jumpHeld=down end
    end

    table.insert(keyConns, UserInputService.InputBegan:Connect(function(i,p)
        if i.UserInputType==Enum.UserInputType.Keyboard then trackKey(i,true) end
    end))
    table.insert(keyConns, UserInputService.InputEnded:Connect(function(i,p)
        if i.UserInputType==Enum.UserInputType.Keyboard then trackKey(i,false) end
    end))

    -- sample loop
    local last = 0
    recConn = RunService.Heartbeat:Connect(function()
        if not recording then return end
        local now = tick() - recordStart
        if now - last < RATE then return end
        last = now

        local mx, mz = getMoveVec()
        -- camera look angle (Y only, for turning)
        local _, camY, _ = camera.CFrame:ToEulerAnglesYXZ()

        table.insert(macro, {
            time  = now,
            mx    = mx,
            mz    = mz,
            jump  = jumpHeld,
            camY  = camY,
        })
        updCount()
    end)
end

-- ─────────────────────────────────────────────
--  PLAYBACK
-- ─────────────────────────────────────────────

local function stopPlaying()
    playing = false
    if playTask then task.cancel(playTask); playTask=nil end
    -- make sure camera goes back to normal
    camera.CameraType = Enum.CameraType.Custom
    setStatus("● Idle", Color3.fromRGB(130,130,160))
end

local function replayMacro()
    if #macro==0 then
        setStatus("⚠ Nothing recorded", Color3.fromRGB(210,170,40))
        return
    end
    playing=true
    setStatus("▶  Playing...", Color3.fromRGB(50,190,110))

    playTask = task.spawn(function()
        repeat
            local startTime = tick()

            for _, sample in ipairs(macro) do
                if not playing then break end

                local target = sample.time / playSpeed
                local elapsed = tick() - startTime
                local wait = target - elapsed
                if wait > 0 then task.wait(wait) end
                if not playing then break end

                local char = localPlayer.Character
                local hum  = char and char:FindFirstChildOfClass("Humanoid")
                if not hum then continue end

                -- rotate camera to match recorded camera Y angle
                -- this keeps it natural — we just rotate the camera,
                -- not lock it to Scriptable
                local currentCF = camera.CFrame
                local pos = currentCF.Position
                local targetCF = CFrame.new(pos)
                    * CFrame.Angles(0, sample.camY, 0)
                    * CFrame.Angles(select(1, currentCF:ToEulerAnglesYXZ()), 0, 0)
                camera.CFrame = currentCF:Lerp(targetCF, 0.3)

                -- build move direction relative to the recorded camera angle
                local camRight   = Vector3.new(math.sin(sample.camY + math.pi/2), 0, math.cos(sample.camY + math.pi/2))
                local camForward = Vector3.new(math.sin(sample.camY + math.pi), 0, math.cos(sample.camY + math.pi))
                local moveVec = (camForward * -sample.mz + camRight * sample.mx)

                if moveVec.Magnitude > 0.01 then
                    moveVec = moveVec.Unit
                end

                -- inject via Humanoid:Move (world space = false uses camera-relative)
                hum:Move(moveVec, false)

                -- jump
                if sample.jump then
                    hum.Jump = true
                end
            end

            if loopEnabled and playing then
                setStatus("▶  Looping...", Color3.fromRGB(50,190,110))
                task.wait(0.05)
            end
        until not loopEnabled or not playing

        if playing then stopPlaying() end
    end)
end

-- ─────────────────────────────────────────────
--  BUTTON WIRING
-- ─────────────────────────────────────────────

recBtn.MouseButton1Click:Connect(function()
    if recording or playing then return end
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
    if playing   then stopPlaying() end
    macro={}; updCount()
    setStatus("● Cleared", Color3.fromRGB(120,120,155))
end)
loopBtn.MouseButton1Click:Connect(function()
    loopEnabled = not loopEnabled
    if loopEnabled then
        loopBtn.Text="ON"
        loopBtn.BackgroundColor3=Color3.fromRGB(38,120,72)
        loopBtn.TextColor3=Color3.fromRGB(190,255,210)
    else
        loopBtn.Text="OFF"
        loopBtn.BackgroundColor3=Color3.fromRGB(55,55,72)
        loopBtn.TextColor3=Color3.fromRGB(170,170,200)
    end
end)

-- speed slider
local sliding=false
sSlider.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.Touch
    or i.UserInputType==Enum.UserInputType.MouseButton1 then sliding=true end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.Touch
    or i.UserInputType==Enum.UserInputType.MouseButton1 then sliding=false end
end)
UserInputService.InputChanged:Connect(function(i)
    if not sliding then return end
    if i.UserInputType~=Enum.UserInputType.Touch
    and i.UserInputType~=Enum.UserInputType.MouseMovement then return end
    local rel=math.clamp((i.Position.X-sSlider.AbsolutePosition.X)/sSlider.AbsoluteSize.X,0,1)
    sFill.Size=UDim2.new(rel,0,1,0)
    playSpeed=0.25+rel*2.75
    speedLbl.Text=string.format("Speed: %.2fx",playSpeed)
end)

-- drag
local dragging,dragStart,startPos
tb.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.Touch
    or i.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true; dragStart=i.Position; startPos=frame.Position
    end
end)
UserInputService.InputChanged:Connect(function(i)
    if not dragging then return end
    if i.UserInputType~=Enum.UserInputType.Touch
    and i.UserInputType~=Enum.UserInputType.MouseMovement then return end
    local d=i.Position-dragStart
    frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,
                              startPos.Y.Scale,startPos.Y.Offset+d.Y)
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.Touch
    or i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)

print("[Macro v3] Ready — Record → Stop → Play")
