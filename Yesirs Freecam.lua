-- Anti-Detection: Slight initial delay
task.wait(math.random(100, 300)/1000)

-- Check if already loaded
if _G.ERXFreeCam then
    warn("FreeCam already loaded or is loading!")
    return
end

_G.ERXFreeCam = true

-- Load required libraries with error handling
local success, err = pcall(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/adamMasMusic/ERX/refs/heads/main/structure.lua"))()
end)

if not success then
    warn("Failed to load structure.lua: " .. tostring(err))
    _G.ERXFreeCam = nil
    return
end

-- Wait for structure to load
local attempts = 0
while not (_G.ERXStructure and _G.WindUI and _G.Window) and attempts < 50 do
    task.wait(0.1)
    attempts = attempts + 1
end

if not (_G.ERXStructure and _G.WindUI and _G.Window) then
    warn("Failed to load ERX Structure")
    _G.ERXFreeCam = nil
    return
end

local Players = game:GetService("Players")
local RS      = game:GetService("RunService")
local UIS     = game:GetService("UserInputService")
local WS      = game:GetService("Workspace")

local WindUI        = _G.WindUI
local Window        = _G.Window
local ConfigManager = Window.ConfigManager
local FCConfig      = ConfigManager:CreateConfig("ERXFreeCam")
local LP            = Players.LocalPlayer
local Camera        = WS.CurrentCamera

-- ============================================================
--  Config
-- ============================================================

local CFG = {
    Speed      = 1,
    ShiftMult  = 3,
    Sens       = 0.3,
    UnderMapY  = -60,
    RayDist    = 2000,
    CrossSize  = 12,
    CrossGap   = 4,
    CrossThick = 2,
    CrossColor = Color3.fromRGB(255, 255, 255),
    FlingTime  = 3,
    ShootSpeed = 100,
}

-- ============================================================
--  State
-- ============================================================

local MODES = { "FreeCam", "Shoot Vehicle", "Car Fling" }

local S = {
    on         = false,
    mode       = 1,
    rot        = Vector2.zero,
    pos        = Vector3.zero,
    keys       = {},
    conns      = {},
    draws      = {},
    acting     = false,
    shooting   = false,
    flinging   = false,
    hoveredCar = nil,
    lastCarMove = 0,
}

-- ============================================================
--  Tab
-- ============================================================

local FCTab = Window:Tab({
    Title  = "FreeCam",
    Icon   = "video",
    Locked = false,
})

-- ============================================================
--  Anti-Detection Helper
-- ============================================================

local function safeSet(obj, prop, val)
    pcall(function()
        obj[prop] = val
    end)
end

local function setSimRadius()
    pcall(function()
        if sethiddenproperty then
            sethiddenproperty(LP, "SimulationRadius", 1500000)
        end
        LP.SimulationRadius = 1500000
    end)
end

-- ============================================================
--  Helpers
-- ============================================================

local function char()
    return LP.Character or LP.CharacterAdded:Wait()
end

local function getHRP()
    local c = char()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local c = char()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function getVehicleSeat()
    local c = LP.Character
    if not c then return nil end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    local seat = hum.SeatPart
    if seat and seat:IsA("VehicleSeat") then return seat end
    return nil
end

local function getVehicleModel(seat)
    if not seat then return nil end
    return seat:FindFirstAncestorOfClass("Model")
end

local function getVehicleRoot(seat)
    local model = getVehicleModel(seat)
    if model and model.PrimaryPart then return model.PrimaryPart end
    return seat
end

-- ============================================================
--  Drawing Helpers
-- ============================================================

local function makeDraw(class, props)
    local d = Drawing.new(class)
    for k, v in pairs(props) do 
        pcall(function() d[k] = v end) 
    end
    d.Visible = true
    return d
end

local function clearDraws()
    for _, v in pairs(S.draws) do
        if type(v) == "table" then
            for _, d in pairs(v) do pcall(function() d:Remove() end) end
        else
            pcall(function() v:Remove() end)
        end
    end
    S.draws = {}
end

-- ============================================================
--  Crosshair
-- ============================================================

local function createCrosshair()
    local vp = Camera.ViewportSize
    local cx, cy = vp.X / 2, vp.Y / 2
    local sz, gp, th = CFG.CrossSize, CFG.CrossGap, CFG.CrossThick
    local col = CFG.CrossColor

    local lines = {
        { Vector2.new(cx - sz, cy), Vector2.new(cx - gp, cy) },
        { Vector2.new(cx + gp, cy), Vector2.new(cx + sz, cy) },
        { Vector2.new(cx, cy - sz), Vector2.new(cx, cy - gp) },
        { Vector2.new(cx, cy + gp), Vector2.new(cx, cy + sz) },
    }
    S.draws.cross = {}
    for _, l in ipairs(lines) do
        S.draws.cross[#S.draws.cross + 1] = makeDraw("Line", {
            From = l[1], To = l[2], Color = col, Thickness = th
        })
    end
    S.draws.dot = makeDraw("Circle", {
        Position = Vector2.new(cx, cy), Radius = 2, Color = col, Filled = true
    })
end

-- ============================================================
--  HUD
-- ============================================================

local function createHUD()
    local vp = Camera.ViewportSize
    local baseY = vp.Y - 80
    local lineH = 18

    S.draws.modeLabels = {}
    for i, name in ipairs(MODES) do
        local isActive = (i == S.mode)
        S.draws.modeLabels[i] = makeDraw("Text", {
            Position = Vector2.new(vp.X / 2, baseY + (i - 1) * lineH),
            Text     = name,
            Size     = 14,
            Color    = isActive and Color3.fromRGB(0, 220, 120) or Color3.fromRGB(180, 180, 180),
            Center   = true,
            Outline  = true,
        })
    end

    S.draws.pageInd = makeDraw("Text", {
        Position = Vector2.new(vp.X / 2 + 80, baseY),
        Text     = S.mode .. "/" .. #MODES,
        Size     = 12,
        Color    = Color3.fromRGB(140, 140, 140),
        Center   = true,
        Outline  = true,
    })

    S.draws.coords = makeDraw("Text", {
        Position = Vector2.new(vp.X / 2, baseY + #MODES * lineH + 6),
        Text     = "",
        Size     = 12,
        Color    = Color3.fromRGB(140, 140, 140),
        Center   = true,
        Outline  = true,
    })

    S.draws.info = makeDraw("Text", {
        Position = Vector2.new(vp.X / 2, vp.Y / 2 - 30),
        Text     = "",
        Size     = 13,
        Color    = Color3.fromRGB(255, 255, 255),
        Center   = true,
        Outline  = true,
    })
end

local function refreshHUD()
    if not S.draws.modeLabels then return end
    for i, lbl in ipairs(S.draws.modeLabels) do
        lbl.Color = (i == S.mode) and Color3.fromRGB(0, 220, 120) or Color3.fromRGB(180, 180, 180)
    end
    if S.draws.pageInd then
        S.draws.pageInd.Text = S.mode .. "/" .. #MODES
    end
end

local function updateCoords()
    if S.draws.coords then
        S.draws.coords.Text = ("X: %.1f  Y: %.1f  Z: %.1f"):format(S.pos.X, S.pos.Y, S.pos.Z)
    end
end

local function updateInfo(text, color)
    if S.draws.info then
        S.draws.info.Text  = text or ""
        S.draws.info.Color = color or Color3.fromRGB(255, 255, 255)
    end
end

-- ============================================================
--  Raycast from Camera
-- ============================================================

local function rayFromCam()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local filterList = { char() }
    local seat = getVehicleSeat()
    if seat then
        local model = getVehicleModel(seat)
        if model then filterList[#filterList + 1] = model end
    end
    params.FilterDescendantsInstances = filterList
    local origin = Camera.CFrame.Position
    local dir    = Camera.CFrame.LookVector * CFG.RayDist
    return WS:Raycast(origin, dir, params)
end

local function vehicleOf(part)
    if not part then return nil end
    local cur = part
    while cur and cur ~= WS do
        if cur:FindFirstChildWhichIsA("VehicleSeat") then return cur end
        cur = cur.Parent
    end
    return nil
end

local function vehicleHasPassenger(vehicle)
    if not vehicle then return false end
    for _, desc in ipairs(vehicle:GetDescendants()) do
        if desc:IsA("Seat") or desc:IsA("VehicleSeat") then
            local occupant = desc.Occupant
            if occupant then
                local player = Players:GetPlayerFromCharacter(occupant.Parent)
                if player and player ~= LP then
                    return true
                end
            end
        end
    end
    return false
end

-- ============================================================
--  Highlight Management
-- ============================================================

local currentHighlight = nil

local function clearHighlight()
    if currentHighlight then
        pcall(function() currentHighlight:Destroy() end)
        currentHighlight = nil
    end
end

local function setHighlight(model, hasPassenger)
    clearHighlight()
    if not model then return end

    local hl = Instance.new("Highlight")
    hl.FillColor       = hasPassenger and Color3.fromRGB(0, 200, 80) or Color3.fromRGB(200, 50, 50)
    hl.FillTransparency = 0.7
    hl.OutlineColor    = hasPassenger and Color3.fromRGB(0, 255, 100) or Color3.fromRGB(255, 60, 60)
    hl.OutlineTransparency = 0.3
    hl.Adornee = model
    hl.Parent  = model
    currentHighlight = hl
end

-- ============================================================
--  Actions
-- ============================================================

local function protectCharacter()
    local c = char()
    if not c then return end
    for _, part in ipairs(c:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function() part.CanCollide = false end)
        end
    end
end

local function unprotectCharacter()
    local c = char()
    if not c then return end
    for _, part in ipairs(c:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            pcall(function() part.CanCollide = true end)
        end
    end
end

local function doShootVehicle()
    if S.shooting then return end

    local seat = getVehicleSeat()
    if not seat then return end
    local myModel = getVehicleModel(seat)
    if not myModel then return end

    S.shooting = true

    protectCharacter()

    local launchSpeed = CFG.ShootSpeed
    local launchDir = Camera.CFrame.LookVector

    local spawnCF = CFrame.lookAt(S.pos, S.pos + launchDir)
    
    pcall(function()
        myModel:PivotTo(spawnCF)
    end)

    for _, part in ipairs(myModel:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function()
                part.Anchored = false
                part.AssemblyLinearVelocity = launchDir * launchSpeed
                part.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end

    task.spawn(function()
        task.wait(1)

        if not S.on then
            unprotectCharacter()
            S.shooting = false
            return
        end

        for _, part in ipairs(myModel:GetDescendants()) do
            if part:IsA("BasePart") then
                pcall(function()
                    part.Anchored = true
                    part.AssemblyLinearVelocity = Vector3.zero
                    part.AssemblyAngularVelocity = Vector3.zero
                end)
            end
        end
        
        pcall(function()
            myModel:PivotTo(CFrame.new(S.pos.X, CFG.UnderMapY, S.pos.Z))
        end)

        unprotectCharacter()

        task.wait(0.1)
        local currentSeat = getVehicleSeat()
        if not currentSeat then
            local hum = getHumanoid()
            if hum and seat then
                pcall(function() seat:Sit(hum) end)
            end
        end

        S.shooting = false
    end)
end

local function doCarFling(targetVehicle)
    if S.flinging then return end
    if not targetVehicle then return end
    if not vehicleHasPassenger(targetVehicle) then return end

    S.flinging = true

    _G.CarFling = true

    local seat = getVehicleSeat()
    if not seat then _G.CarFling = false; S.flinging = false; return end
    local myModel = getVehicleModel(seat)
    if not myModel then _G.CarFling = false; S.flinging = false; return end

    local targetRoot = targetVehicle.PrimaryPart
    if not targetRoot then
        for _, p in ipairs(targetVehicle:GetDescendants()) do
            if p:IsA("VehicleSeat") then targetRoot = p; break end
        end
    end
    if not targetRoot then _G.CarFling = false; S.flinging = false; return end

    protectCharacter()

    for _, part in ipairs(myModel:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function() part.Anchored = false end)
        end
    end

    local startTime = tick()
    local flingConn
    flingConn = RS.Heartbeat:Connect(function()
        if not S.on or (tick() - startTime) > CFG.FlingTime then
            flingConn:Disconnect()
            _G.CarFling = false

            for _, part in ipairs(myModel:GetDescendants()) do
                if part:IsA("BasePart") then
                    pcall(function()
                        part.Anchored = true
                        part.AssemblyLinearVelocity = Vector3.zero
                        part.AssemblyAngularVelocity = Vector3.zero
                    end)
                end
            end
            
            pcall(function()
                myModel:PivotTo(CFrame.new(S.pos.X, CFG.UnderMapY, S.pos.Z))
            end)

            unprotectCharacter()

            task.spawn(function()
                task.wait(0.1)
                local currentSeat = getVehicleSeat()
                if not currentSeat then
                    local hum = getHumanoid()
                    if hum and seat then
                        pcall(function() seat:Sit(hum) end)
                    end
                end
            end)

            S.flinging = false
            return
        end

        setSimRadius()
        protectCharacter()
        local targetCF = targetRoot.CFrame
        local offset = CFrame.new(0, 2, 0) * CFrame.Angles(0, tick() * 20, tick() * 15)
        pcall(function()
            myModel:PivotTo(targetCF * offset)
        end)
    end)
end

local function executeAction()
    if S.acting then return end
    if S.mode == 1 then return end

    if S.mode == 2 then
        doShootVehicle()
    elseif S.mode == 3 then
        local result = rayFromCam()
        local vehicle = vehicleOf(result and result.Instance)
        if vehicle and vehicleHasPassenger(vehicle) then
            task.spawn(doCarFling, vehicle)
        end
    end
end

-- ============================================================
--  Vehicle Freeze
-- ============================================================

local function freezeVehicle(model)
    if not model then return end
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function() part.Anchored = true end)
        end
    end
end

local function unfreezeVehicle(model)
    if not model then return end
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function()
                part.Anchored = false
                part.AssemblyLinearVelocity = Vector3.zero
                part.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end
end

-- ============================================================
--  FreeCam Core
-- ============================================================

local function enableFreeCam()
    if S.on then return end

    local seat = getVehicleSeat()
    if not seat then
        WindUI:Notify({
            Title   = "Freecam",
            Content = "You must be in a vehicle to use Freecam!",
            Duration = 3,
        })
        return
    end

    S.on = true
    setSimRadius()

    local root  = getVehicleRoot(seat)
    local model = getVehicleModel(seat)

    S.pos = Vector3.new(root.CFrame.X, root.CFrame.Y + 30, root.CFrame.Z)
    local rotX, rotY, _ = Camera.CFrame:ToEulerAnglesYXZ()
    S.rot = Vector2.new(math.deg(rotX), math.deg(rotY))

    freezeVehicle(model)

    pcall(function()
        model:PivotTo(CFrame.new(root.CFrame.X, CFG.UnderMapY, root.CFrame.Z))
    end)

    Camera.CameraType    = Enum.CameraType.Scriptable
    UIS.MouseBehavior    = Enum.MouseBehavior.LockCenter
    UIS.MouseIconEnabled = false

    createCrosshair()
    createHUD()
    refreshHUD()

    S.conns.move = RS.RenderStepped:Connect(function(dt)
        if not S.on then return end

        setSimRadius()

        local speed = CFG.Speed * (S.keys[Enum.KeyCode.LeftShift] and CFG.ShiftMult or 1)
        local move = Vector3.zero

        if S.keys[Enum.KeyCode.W] then move = move + Vector3.new(0, 0, -1) end
        if S.keys[Enum.KeyCode.S] then move = move + Vector3.new(0, 0, 1) end
        if S.keys[Enum.KeyCode.A] then move = move + Vector3.new(-1, 0, 0) end
        if S.keys[Enum.KeyCode.D] then move = move + Vector3.new(1, 0, 0) end
        if S.keys[Enum.KeyCode.E] then move = move + Vector3.new(0, 1, 0) end
        if S.keys[Enum.KeyCode.Q] then move = move + Vector3.new(0, -1, 0) end

        if move.Magnitude > 0 then
            move = move.Unit * speed
        end

        local camCF = CFrame.new(S.pos)
            * CFrame.Angles(0, math.rad(S.rot.Y), 0)
            * CFrame.Angles(math.rad(S.rot.X), 0, 0)

        S.pos = S.pos + camCF:VectorToWorldSpace(move)

        Camera.CFrame = CFrame.new(S.pos)
            * CFrame.Angles(0, math.rad(S.rot.Y), 0)
            * CFrame.Angles(math.rad(S.rot.X), 0, 0)

        if not S.flinging and not S.shooting then
            local currentSeat = getVehicleSeat()
            if currentSeat then
                local carModel = getVehicleModel(currentSeat)
                if carModel then
                    if tick() - S.lastCarMove > 0.15 then
                        pcall(function()
                            carModel:PivotTo(CFrame.new(S.pos.X, CFG.UnderMapY, S.pos.Z))
                        end)
                        S.lastCarMove = tick()
                    end
                end
            end
        end

        updateCoords()

        if S.mode == 3 then
            local result = rayFromCam()
            local vehicle = vehicleOf(result and result.Instance)
            if vehicle then
                local hasPass = vehicleHasPassenger(vehicle)
                if S.hoveredCar ~= vehicle then
                    S.hoveredCar = vehicle
                    setHighlight(vehicle, hasPass)
                end
                if hasPass then
                    updateInfo("Ready To Fling!", Color3.fromRGB(0, 220, 100))
                else
                    updateInfo("Wait For Someone To Enter!", Color3.fromRGB(255, 80, 80))
                end
            else
                if S.hoveredCar then
                    S.hoveredCar = nil
                    clearHighlight()
                end
                updateInfo("")
            end
        else
            if S.hoveredCar then
                S.hoveredCar = nil
                clearHighlight()
            end
            updateInfo("")
        end
    end)

    S.conns.mouse = UIS.InputChanged:Connect(function(input)
        if not S.on then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            S.rot = Vector2.new(
                math.clamp(S.rot.X - input.Delta.Y * CFG.Sens, -89, 89),
                S.rot.Y - input.Delta.X * CFG.Sens
            )
        end
    end)

    S.conns.keyDown = UIS.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.UserInputType == Enum.UserInputType.Keyboard then
            S.keys[input.KeyCode] = true
            local num = tonumber(input.KeyCode.Name)
            if num and num >= 1 and num <= #MODES then
                S.mode = num
                refreshHUD()
            end
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            task.spawn(executeAction)
        end
    end)

    S.conns.keyUp = UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            S.keys[input.KeyCode] = nil
        end
    end)

    S.conns.scroll = UIS.InputChanged:Connect(function(input)
        if not S.on then return end
        if input.UserInputType == Enum.UserInputType.MouseWheel then
            S.mode = ((S.mode - 1 + (input.Position.Z > 0 and 1 or -1)) % #MODES) + 1
            refreshHUD()
        end
    end)

    WindUI:Notify({
        Title   = "Freecam",
        Content = "Freecam ON — car underground.",
        Duration = 3,
    })
end

local function disableFreeCam()
    if not S.on then return end
    S.on = false

    for _, conn in pairs(S.conns) do
        if conn then conn:Disconnect() end
    end
    S.conns = {}
    S.keys  = {}
    clearDraws()
    clearHighlight()

    _G.CarFling = false
    S.flinging = false
    unprotectCharacter()

    setSimRadius()
    local seat = getVehicleSeat()
    if seat then
        local model = getVehicleModel(seat)
        local targetCF = CFrame.new(S.pos.X, S.pos.Y, S.pos.Z)
            * CFrame.Angles(0, math.rad(S.rot.Y), 0)
        if model then
            pcall(function()
                model:PivotTo(targetCF)
            end)
        end

        task.wait(0.1)
        unfreezeVehicle(model)
    end

    Camera.CameraType    = Enum.CameraType.Custom
    UIS.MouseBehavior    = Enum.MouseBehavior.Default
    UIS.MouseIconEnabled = true

    WindUI:Notify({
        Title   = "FreeCam",
        Content = "FreeCam OFF — car placed at camera position.",
        Duration = 2,
    })
end

-- ============================================================
--  UI Elements
-- ============================================================

FCTab:Section({ Title = "FreeCam" })

local freecamToggle = FCTab:Toggle({
    Title    = "Enable FreeCam",
    Desc     = "Fly the camera freely. Vehicle follows underground, TPs to cam on disable.",
    Value    = false,
    Callback = function(v)
        if v then 
            task.spawn(enableFreeCam)
        else 
            task.spawn(disableFreeCam)
        end
    end,
})
FCConfig:Register("freecamToggle", freecamToggle)

FCTab:Keybind({
    Title    = "FreeCam Keybind",
    Desc     = "Quick toggle for FreeCam",
    Value    = "V",
    Callback = function()
        if S.on then
            disableFreeCam()
            freecamToggle:Set(false)
        else
            enableFreeCam()
            freecamToggle:Set(true)
        end
    end,
})

local modeDropdown = FCTab:Dropdown({
    Title    = "Action Mode",
    Desc     = "What happens when you click (also use 1-3 keys or scroll)",
    Values   = MODES,
    Value    = MODES[1],
    Callback = function(v)
        for i, name in ipairs(MODES) do
            if name == v then S.mode = i; break end
        end
        refreshHUD()
    end,
})
FCConfig:Register("modeDropdown", modeDropdown)

FCTab:Section({ Title = "Settings" })

local speedSlider = FCTab:Slider({
    Title    = "Cam Speed",
    Desc     = "How fast the camera moves",
    Step     = 0.5,
    Value    = { Min = 0.5, Max = 10, Default = 1 },
    Callback = function(v) CFG.Speed = v end,
})
FCConfig:Register("speedSlider", speedSlider)

local sensSlider = FCTab:Slider({
    Title    = "Sensitivity",
    Desc     = "Mouse look sensitivity",
    Step     = 0.05,
    Value    = { Min = 0.05, Max = 1, Default = 0.3 },
    Callback = function(v) CFG.Sens = v end,
})
FCConfig:Register("sensSlider", sensSlider)

local flingSlider = FCTab:Slider({
    Title    = "Fling Duration",
    Desc     = "How long your car stays glued to target (seconds)",
    Step     = 0.5,
    Value    = { Min = 1, Max = 8, Default = 3 },
    Callback = function(v) CFG.FlingTime = v end,
})
FCConfig:Register("flingSlider", flingSlider)

local shootSpeedSlider = FCTab:Slider({
    Title    = "Shoot Speed",
    Desc     = "How fast the car launches forward (studs/s)",
    Step     = 10,
    Value    = { Min = 1, Max = 1000, Default = 100 },
    Callback = function(v) CFG.ShootSpeed = v end,
})
FCConfig:Register("shootSpeedSlider", shootSpeedSlider)

FCTab:Section({ Title = "Controls" })

FCTab:Paragraph({
    Title = "How to Use",
    Desc  = "1. Get in a vehicle\n2. Enable FreeCam (toggle or keybind)\n3. Camera is free, car follows underground\n4. Click = action based on mode\n5. Disable = car teleports to camera position\n\nWASD = Move  |  Q/E = Down/Up  |  Shift = Fast\n1/2/3 or Scroll = Switch mode\n\nModes:\n- FreeCam: Just fly\n- Shoot Vehicle: Click to launch car forward from cam\n- Car Fling: Click on car with passenger to fling",
})

FCTab:Section({ Title = "Config" })

FCTab:Button({
    Title    = "Save Config",
    Desc     = "Saves FreeCam settings",
    Callback = function() FCConfig:Save() end,
})

-- ============================================================
--  Config Load
-- ============================================================

-- Load config with error handling
pcall(function()
    FCConfig:Load()
end)

-- Notify with slight delay to ensure UI is ready
task.wait(0.5)
WindUI:Notify({
    Title   = "FreeCam Loaded",
    Content = "Modes: FreeCam, Shoot Vehicle, Car Fling. Scroll to change modes whilst in.",
    Duration = 4,
})