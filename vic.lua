--// Server Hopper
local players = game:GetService("Players")
local httpService = game:GetService("HttpService")
local userInput = game:GetService("UserInputService")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local teleportService = game:GetService("TeleportService")
local localPlayer = players.LocalPlayer

-- ============ GLOBALS (must be declared before any function uses them) ============
local U = {}
local accentListeners = {}

if _G.__hopper_loaded then
    local pg = localPlayer:FindFirstChild("PlayerGui")
    if pg then
        local old = pg:FindFirstChild("hopper")
        if old then old:Destroy() end
    end
    _G.__hopper_loaded = false
    _G.__hopper_unload = nil
end
_G.__hopper_loaded = true

local http = (syn and syn.request) or (http and http.request) or http_request or request
if not http then _G.__hopper_loaded = false warn("no http executor") return end

local VERSION = "v0.1 beta"
local iconId = "rbxthumb://type=Asset&id=79985085633622&w=150&h=150"
local blacklistFile = "hopper_blacklist.json"
local configFile    = "hopper_config.json"

-- ============ SESSION ============
local sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
local sessionFile = "hopper_session_" .. sessionId .. ".log"
local sessionLogs = {}
local MAX_SESSION_LOGS = 200

local function diskAppend(path, line)
    if not writefile or not readfile then return end
    local ok, existing = pcall(function() return readfile(path) end)
    local content = (ok and existing) or ""
    local lines = {}
    for l in content:gmatch("[^\n]+") do table.insert(lines, l) end
    table.insert(lines, line)
    while #lines > 2000 do table.remove(lines, 1) end
    pcall(function() writefile(path, table.concat(lines, "\n")) end)
end

local function sessionLog(prefix, speaker, text, color)
    color = color or Color3.fromRGB(242, 244, 250)
    local line = prefix .. speaker .. ": " .. text
    table.insert(sessionLogs, line)
    if #sessionLogs > MAX_SESSION_LOGS then table.remove(sessionLogs, 1) end
    if speaker == "hopper" and (
        text:find("^hopping") or text:find("selected") or text:find("landed") or
        text:find("no fresh") or text:find("rerouted") or text:find("manual hop") or
        text:find("scanning") or text:find("found %d+ candidates") or
        text:find("giving up") or text:find("retry") or text:find("scanned")
    ) then
        diskAppend(sessionFile, "[" .. os.date("%H:%M:%S") .. "] " .. line)
    end
    if U and U.chatLabel then
        local out = {}
        for _, l in ipairs(sessionLogs) do table.insert(out, l) end
        U.chatLabel.Text = table.concat(out, "\n")
    end
end

local function log(text, color) sessionLog("·  ", "hopper", text, color or Color3.fromRGB(168, 172, 188)) end
local function logInfo(text) log(text, Color3.fromRGB(120, 170, 245)) end
local function logGood(text) log(text, Color3.fromRGB(130, 220, 165)) end
local function logWarn(text) log(text, Color3.fromRGB(240, 205, 120)) end
local function logBad(text) log(text, Color3.fromRGB(240, 130, 140)) end

-- ============ CONFIG ============
local config = {
    maxPages = 15,
    minPlayers = 1,
    maxPlayerRatio = 1.0,
    autoHopDelay = 3,
    hopOnJoin = false,
    preferLessFull = true,
    skipEmpty = true,
}

local persistConfig = {
    themeIdx = 1,
    scale = 1,
    preferLessFull = true,
    skipEmpty = true,
}

local function loadConfigFromDisk()
    if not readfile or not isfile then return end
    if not isfile(configFile) then return end
    local ok, data = pcall(function() return httpService:JSONDecode(readfile(configFile)) end)
    if ok and type(data) == "table" then
        if type(data.themeIdx) == "number" then persistConfig.themeIdx = data.themeIdx end
        if type(data.scale) == "number" then persistConfig.scale = data.scale end
        if type(data.preferLessFull) == "boolean" then persistConfig.preferLessFull = data.preferLessFull end
        if type(data.skipEmpty) == "boolean" then persistConfig.skipEmpty = data.skipEmpty end
    end
end

local function saveConfigToDisk()
    if not writefile then return end
    pcall(function()
        writefile(configFile, httpService:JSONEncode(persistConfig))
    end)
end

loadConfigFromDisk()

config.preferLessFull = persistConfig.preferLessFull
config.skipEmpty = persistConfig.skipEmpty
config.maxPlayerRatio = config.preferLessFull and 0.9 or 1.0
config.minPlayers = config.skipEmpty and 1 or 0

local blacklist = {}
local sessionVisited = {}
local expectedJobId = nil
local hopAttempts = 0
local MAX_AUTO_RETRIES = 4

local connections = {}
local unloaded = false
local currentScale = persistConfig.scale or 1
local targetScale = persistConfig.scale or 1
local scaleVelocity = 0
local currentThemeIdx = persistConfig.themeIdx or 1
local hopping = false

local function track(c) table.insert(connections, c) return c end
local function clamp(n, a, b) return math.max(a, math.min(b, n)) end

local function loadBlacklist()
    if readfile and isfile and isfile(blacklistFile) then
        local ok, data = pcall(function() return httpService:JSONDecode(readfile(blacklistFile)) end)
        if ok and type(data) == "table" then
            for _, id in ipairs(data) do blacklist[tostring(id)] = true end
        end
    end
end

local function saveBlacklist()
    if writefile then
        local list = {}
        for id in pairs(blacklist) do table.insert(list, id) end
        pcall(function() writefile(blacklistFile, httpService:JSONEncode(list)) end)
    end
end

loadBlacklist()

local function getCurrentServerId()
    local jid = game.JobId
    if jid and jid ~= "" then return tostring(jid) end
    local ok, info = pcall(function() return teleportService:GetLocalPlayerTeleportData() end)
    if ok and type(info) == "table" and info.JobId then return tostring(info.JobId) end
    return nil
end

local currentServerId = getCurrentServerId()
if currentServerId then
    blacklist[currentServerId] = true
    sessionVisited[currentServerId] = true
    saveBlacklist()
end

local function shortId(id)
    id = tostring(id)
    return #id > 10 and id:sub(1, 10) or id
end

-- ============ UI FRAMEWORK ============

local C = {
    text     = Color3.fromRGB(242, 244, 250),
    textMid  = Color3.fromRGB(168, 172, 188),
    textDim  = Color3.fromRGB(118, 122, 140),
    accent   = Color3.fromRGB(120, 170, 245),
    accentHi = Color3.fromRGB(155, 200, 255),
    green    = Color3.fromRGB(130, 220, 165),
    yellow   = Color3.fromRGB(240, 205, 120),
    red      = Color3.fromRGB(240, 130, 140),
}

-- Theme list — rainbow is a normal entry
local themes = {
    {name="midnight", c1=Color3.fromRGB(52,68,130),  c2=Color3.fromRGB(20,28,55),  c3=Color3.fromRGB(65,45,110),  accent=Color3.fromRGB(120,170,245), accentHi=Color3.fromRGB(155,200,255)},
    {name="emerald",  c1=Color3.fromRGB(36,100,90),  c2=Color3.fromRGB(18,40,42),  c3=Color3.fromRGB(45,80,75),   accent=Color3.fromRGB(105,200,155), accentHi=Color3.fromRGB(140,225,180)},
    {name="crimson",  c1=Color3.fromRGB(130,45,55),  c2=Color3.fromRGB(45,20,28),  c3=Color3.fromRGB(100,40,75),  accent=Color3.fromRGB(220,110,120), accentHi=Color3.fromRGB(245,145,155)},
    {name="sunset",   c1=Color3.fromRGB(140,70,45),  c2=Color3.fromRGB(60,32,40),  c3=Color3.fromRGB(120,55,90),  accent=Color3.fromRGB(230,160,90),  accentHi=Color3.fromRGB(250,190,120)},
    {name="violet",   c1=Color3.fromRGB(95,55,155),  c2=Color3.fromRGB(38,25,65),  c3=Color3.fromRGB(120,55,130), accent=Color3.fromRGB(170,130,235), accentHi=Color3.fromRGB(195,160,255)},
    {name="mono",     c1=Color3.fromRGB(75,75,82),   c2=Color3.fromRGB(38,38,42),  c3=Color3.fromRGB(58,58,65),   accent=Color3.fromRGB(180,185,200), accentHi=Color3.fromRGB(210,215,230)},
    {name="rainbow",  c1=Color3.fromRGB(52,68,130),  c2=Color3.fromRGB(20,28,55),  c3=Color3.fromRGB(65,45,110),  accent=Color3.fromRGB(120,170,245), accentHi=Color3.fromRGB(155,200,255), rainbow=true},
}

if currentThemeIdx < 1 or currentThemeIdx > #themes then
    currentThemeIdx = 1
    persistConfig.themeIdx = 1
end

local WIN_W, WIN_H = 460, 580
local HEADER_H = 58
local TABS_H = 36

local gui = Instance.new("ScreenGui")
gui.Name = "hopper"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = localPlayer:WaitForChild("PlayerGui")

local function registerAccent(obj, prop, use)
    table.insert(accentListeners, {obj = obj, prop = prop, use = use})
end

local function lerpNumberSeq(a, b, t)
    local out = {}
    local kpsA, kpsB = a.Keypoints, b.Keypoints
    local n = math.min(#kpsA, #kpsB)
    for i = 1, n do
        local ka, kb = kpsA[i], kpsB[i]
        table.insert(out, NumberSequenceKeypoint.new(
            ka.Time,
            ka.Value + (kb.Value - ka.Value) * t,
            ka.Envelope + (kb.Envelope - ka.Envelope) * t
        ))
    end
    return NumberSequence.new(out)
end

local function lerpColorSeq(a, b, t)
    local out = {}
    local kpsA, kpsB = a.Keypoints, b.Keypoints
    local n = math.min(#kpsA, #kpsB)
    for i = 1, n do
        local ka, kb = kpsA[i], kpsB[i]
        table.insert(out, ColorSequenceKeypoint.new(ka.Time, ka.Value:Lerp(kb.Value, t)))
    end
    return ColorSequence.new(out)
end

local function tweenNumSeq(obj, target, dur)
    task.spawn(function()
        local startSeq = obj.Transparency
        local steps = math.max(6, math.floor(dur * 40))
        for i = 1, steps do
            if unloaded or not obj.Parent then return end
            local t = i / steps
            local et = 1 - math.pow(1 - t, 3)
            obj.Transparency = lerpNumberSeq(startSeq, target, et)
            task.wait(dur / steps)
        end
        if not unloaded and obj.Parent then obj.Transparency = target end
    end)
end

local function tweenColorSeq(obj, target, dur)
    task.spawn(function()
        local startSeq = obj.Color
        local steps = math.max(8, math.floor(dur * 40))
        for i = 1, steps do
            if unloaded or not obj.Parent then return end
            local t = i / steps
            local et = 1 - math.pow(1 - t, 3)
            obj.Color = lerpColorSeq(startSeq, target, et)
            task.wait(dur / steps)
        end
        if not unloaded and obj.Parent then obj.Color = target end
    end)
end

local function tw(o, p, t, style, dir)
    if o:IsA("UIGradient") then
        if p.Color ~= nil then tweenColorSeq(o, p.Color, t or 0.24) end
        if p.Transparency ~= nil then tweenNumSeq(o, p.Transparency, t or 0.24) end
        local rest = {}
        for k, v in pairs(p) do
            if k ~= "Color" and k ~= "Transparency" then rest[k] = v end
        end
        if next(rest) then
            local t2 = tweenService:Create(o, TweenInfo.new(t or 0.24, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out), rest)
            t2:Play()
            return t2
        end
        return nil
    end
    local t2 = tweenService:Create(o, TweenInfo.new(t or 0.24, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out), p)
    t2:Play()
    return t2
end

local function draggable(frame, handle)
    handle = handle or frame
    local drag, start, orig
    track(handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag, start, orig = true, i.Position, frame.Position
        end
    end))
    track(handle.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = false end
    end))
    track(userInput.InputChanged:Connect(function(i)
        if not drag then return end
        if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
            local d = i.Position - start
            frame.Position = UDim2.new(orig.X.Scale, orig.X.Offset + d.X, orig.Y.Scale, orig.Y.Offset + d.Y)
        end
    end))
end

local function glassSurface(parent, order)
    local f = Instance.new("Frame", parent)
    f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    f.BackgroundTransparency = 0.9
    f.BorderSizePixel = 0
    f.ZIndex = 5
    if order then f.LayoutOrder = order end
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 12)
    local grad = Instance.new("UIGradient", f)
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.6, Color3.fromRGB(230, 232, 240)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 205, 218)),
    })
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.86),
        NumberSequenceKeypoint.new(1, 0.94),
    })
    grad.Rotation = 90
    local stroke = Instance.new("UIStroke", f)
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Thickness = 1
    local sg = Instance.new("UIGradient", stroke)
    sg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 210, 230)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 148, 168)),
    })
    sg.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(0.5, 0.68),
        NumberSequenceKeypoint.new(1, 0.85),
    })
    sg.Rotation = 90
    return f
end

local function glassButton(parent, height, order)
    local b = Instance.new("TextButton", parent)
    b.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    b.BackgroundTransparency = 0.88
    b.BorderSizePixel = 0
    b.Size = UDim2.new(1, 0, 0, height or 44)
    b.Text = ""
    b.AutoButtonColor = false
    b.ZIndex = 5
    if order then b.LayoutOrder = order end
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
    local grad = Instance.new("UIGradient", b)
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 214, 226)),
    })
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.85),
        NumberSequenceKeypoint.new(1, 0.93),
    })
    grad.Rotation = 90
    local stroke = Instance.new("UIStroke", b)
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Thickness = 1
    local sGrad = Instance.new("UIGradient", stroke)
    sGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 158, 178)),
    })
    sGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 0.82),
    })
    sGrad.Rotation = 90
    track(b.MouseEnter:Connect(function()
        if b:GetAttribute("pressed") then return end
        tweenNumSeq(grad, NumberSequence.new({NumberSequenceKeypoint.new(0, 0.78), NumberSequenceKeypoint.new(1, 0.88)}), 0.22)
        tweenNumSeq(sGrad, NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.7)}), 0.22)
    end))
    track(b.MouseLeave:Connect(function()
        b:SetAttribute("pressed", false)
        tweenNumSeq(grad, NumberSequence.new({NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(1, 0.93)}), 0.26)
        tweenNumSeq(sGrad, NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.82)}), 0.26)
    end))
    return b
end

local function applyTheme(idx, save)
    if unloaded then return end
    currentThemeIdx = idx
    persistConfig.themeIdx = idx
    if save then saveConfigToDisk() end
    local t = themes[idx]

    if not t.rainbow then
        task.spawn(function()
            local prev = themes[(idx - 2) % #themes + 1]
            for s = 1, 24 do
                if unloaded then break end
                local p = s / 24
                local ep = 1 - math.pow(1 - p, 3)
                local c1 = prev.c1:Lerp(t.c1, ep)
                local c2 = prev.c2:Lerp(t.c2, ep)
                local c3 = prev.c3:Lerp(t.c3, ep)
                if U.bgGrad then
                    U.bgGrad.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0.0, c1),
                        ColorSequenceKeypoint.new(0.5, c2),
                        ColorSequenceKeypoint.new(1.0, c3),
                    })
                end
                task.wait(0.03)
            end
        end)
        if U.orb1 then tweenService:Create(U.orb1, TweenInfo.new(0.9, Enum.EasingStyle.Quart), {BackgroundColor3 = t.c1}):Play() end
        if U.orb2 then tweenService:Create(U.orb2, TweenInfo.new(0.9, Enum.EasingStyle.Quart), {BackgroundColor3 = t.c3}):Play() end
        if U.orb3 then tweenService:Create(U.orb3, TweenInfo.new(0.9, Enum.EasingStyle.Quart), {BackgroundColor3 = t.c2}):Play() end
        for _, listener in ipairs(accentListeners) do
            if listener.obj and listener.obj.Parent then
                if listener.use == "grad" then
                    tweenColorSeq(listener.obj, ColorSequence.new(t.accentHi, t.accent), 0.6)
                else
                    local target = (listener.use == "hi") and t.accentHi or t.accent
                    tweenService:Create(listener.obj, TweenInfo.new(0.6, Enum.EasingStyle.Quart), {[listener.prop] = target}):Play()
                end
            end
        end
    end

    if U.themeLabel then U.themeLabel.Text = "theme · " .. t.name end
end

-- Rainbow loop
task.spawn(function()
    local hue = 0
    while not unloaded do
        local dt = runService.RenderStepped:Wait()
        if themes[currentThemeIdx].rainbow then
            hue = (hue + dt * 0.08) % 1

            if U.bgGrad then
                local c1 = Color3.fromHSV(hue, 0.55, 0.55)
                local c2 = Color3.fromHSV(hue, 0.55, 0.22)
                local c3 = Color3.fromHSV(hue, 0.55, 0.45)
                U.bgGrad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0.0, c1),
                    ColorSequenceKeypoint.new(0.5, c2),
                    ColorSequenceKeypoint.new(1.0, c3),
                })
            end

            if U.orb1 then U.orb1.BackgroundColor3 = Color3.fromHSV(hue, 0.55, 0.5) end
            if U.orb2 then U.orb2.BackgroundColor3 = Color3.fromHSV(hue, 0.55, 0.45) end
            if U.orb3 then U.orb3.BackgroundColor3 = Color3.fromHSV(hue, 0.55, 0.35) end

            local acc1 = Color3.fromHSV(hue, 0.55, 1)
            local acc2 = Color3.fromHSV(hue, 0.45, 1)
            for _, listener in ipairs(accentListeners) do
                if listener.obj and listener.obj.Parent then
                    if listener.use == "grad" then
                        listener.obj.Color = ColorSequence.new(acc2, acc1)
                    else
                        local target = (listener.use == "hi") and acc2 or acc1
                        listener.obj[listener.prop] = target
                    end
                end
            end
        end
    end
end)

local function setStatus(state, txt)
    if not U.statusDot then return end
    local col = C.red
    local label, lc = txt or "idle", C.textMid
    if state == "ok" then col = C.green; label = txt or "ready"
    elseif state == "loading" then col = C.yellow; label = txt or "scanning" end
    tw(U.statusDot, {BackgroundColor3 = col}, 0.36, Enum.EasingStyle.Quart)
    tw(U.statusText, {TextColor3 = lc}, 0.36, Enum.EasingStyle.Quart)
    if U.statusRing then tw(U.statusRing, {Color = col}, 0.36, Enum.EasingStyle.Quart) end
    U.statusText.Text = label
    if U.pillDot then U.pillDot.BackgroundColor3 = col end
end

-- ============ FETCH + HOP LOGIC ============

local function fetchPage(cursor)
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100")
        :format(game.PlaceId)
    if cursor and cursor ~= "" then
        url = url .. "&cursor=" .. cursor
    end
    local body
    local ok, res = pcall(function()
        return http({Url = url, Method = "GET"})
    end)
    if ok and res and res.Body then body = res.Body end
    if not body then
        local ok2, res2 = pcall(game.HttpGet, game, url)
        if ok2 then body = res2 end
    end
    if not body then return nil end
    local ok3, decoded = pcall(function() return httpService:JSONDecode(body) end)
    return ok3 and decoded or nil
end

local function scanAllServers(progressCb)
    local all = {}
    local cursor = nil
    for page = 1, config.maxPages do
        local data = fetchPage(cursor)
        if not data or not data.data then break end
        for _, s in ipairs(data.data) do
            table.insert(all, {
                id = tostring(s.id),
                playing = s.playing,
                maxPlayers = s.maxPlayers,
                ping = s.ping,
                fps = s.fps,
            })
        end
        if progressCb then progressCb(page, #all) end
        cursor = data.nextPageCursor
        if not cursor or cursor == "" then break end
    end
    return all
end

local function scanServers()
    logInfo("scanning for open servers...")

    local candidates = {}
    local cursor = nil
    local totalScanned = 0
    local skippedBlacklist = 0
    local skippedFull = 0

    for page = 1, config.maxPages do
        local data = fetchPage(cursor)
        if not data or not data.data then break end

        for _, s in ipairs(data.data) do
            totalScanned = totalScanned + 1
            local id = tostring(s.id)

            if id == currentServerId or blacklist[id] or sessionVisited[id] then
                skippedBlacklist = skippedBlacklist + 1
            elseif s.playing >= s.maxPlayers then
                skippedFull = skippedFull + 1
            elseif s.playing < config.minPlayers then
                -- too empty
            elseif s.playing >= (s.maxPlayers - 1) and config.maxPlayerRatio < 1.0 then
                skippedFull = skippedFull + 1
            else
                table.insert(candidates, s)
            end
        end

        cursor = data.nextPageCursor
        if not cursor or cursor == "" then break end
    end

    log("scanned " .. totalScanned .. " servers")
    log("skipped " .. skippedBlacklist .. " blacklisted, " .. skippedFull .. " full")
    if #candidates > 0 then
        logGood("found " .. #candidates .. " candidates")
    else
        logBad("no fresh servers available")
    end
    return candidates
end

function U.renderServerList(list)
    if not U.serverListFrame then return end
    for _, c in ipairs(U.serverListFrame:GetChildren()) do
        if not c:IsA("UIListLayout") then c:Destroy() end
    end
    if not list or #list == 0 then
        local empty = Instance.new("Frame", U.serverListFrame)
        empty.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        empty.BackgroundTransparency = 0.93
        empty.BorderSizePixel = 0
        empty.Size = UDim2.new(1, 0, 0, 60)
        empty.LayoutOrder = 1
        empty.ZIndex = 6
        Instance.new("UICorner", empty).CornerRadius = UDim.new(0, 10)
        local st = Instance.new("UIStroke", empty)
        st.Color = Color3.fromRGB(255, 255, 255)
        st.Thickness = 1
        st.Transparency = 0.7
        local lbl = Instance.new("TextLabel", empty)
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(1, -24, 1, 0)
        lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 11
        lbl.TextColor3 = C.textMid
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = "click refresh to scan servers"
        lbl.ZIndex = 7
        return
    end

    table.sort(list, function(a, b)
        local aBad = (blacklist[a.id] or a.id == currentServerId or sessionVisited[a.id])
        local bBad = (blacklist[b.id] or b.id == currentServerId or sessionVisited[b.id])
        if aBad ~= bBad then return not aBad end
        local aFull = a.playing >= a.maxPlayers
        local bFull = b.playing >= b.maxPlayers
        if aFull ~= bFull then return not aFull end
        return a.playing > b.playing
    end)

    for i, s in ipairs(list) do
        local isCurrent = (s.id == currentServerId)
        local isBlacklisted = blacklist[s.id] or sessionVisited[s.id]
        local isFull = s.playing >= s.maxPlayers

        local row = Instance.new("TextButton", U.serverListFrame)
        row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        row.BackgroundTransparency = isCurrent and 0.78 or 0.9
        row.BorderSizePixel = 0
        row.Size = UDim2.new(1, 0, 0, 38)
        row.Text = ""
        row.AutoButtonColor = false
        row.LayoutOrder = i
        row.ZIndex = 6
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
        local rGrad = Instance.new("UIGradient", row)
        rGrad.Color = isCurrent and
            ColorSequence.new(Color3.fromRGB(140, 180, 240), Color3.fromRGB(80, 120, 190)) or
            ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(210, 215, 228))
        rGrad.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.88), NumberSequenceKeypoint.new(1, 0.95)})
        rGrad.Rotation = 90
        local rStroke = Instance.new("UIStroke", row)
        rStroke.Color = Color3.fromRGB(255, 255, 255)
        rStroke.Thickness = 1
        rStroke.Transparency = 0.65

        local dot = Instance.new("Frame", row)
        dot.Size = UDim2.new(0, 7, 0, 7)
        dot.Position = UDim2.new(0, 14, 0.5, -3)
        dot.BorderSizePixel = 0
        dot.ZIndex = 7
        if isCurrent then
            dot.BackgroundColor3 = Color3.fromRGB(130, 220, 165)
        elseif isBlacklisted then
            dot.BackgroundColor3 = Color3.fromRGB(240, 130, 140)
        elseif isFull then
            dot.BackgroundColor3 = Color3.fromRGB(240, 205, 120)
        else
            dot.BackgroundColor3 = Color3.fromRGB(120, 170, 245)
        end
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

        local idLbl = Instance.new("TextLabel", row)
        idLbl.BackgroundTransparency = 1
        idLbl.Size = UDim2.new(1, -180, 1, 0)
        idLbl.Position = UDim2.new(0, 28, 0, 0)
        idLbl.Font = Enum.Font.Code
        idLbl.TextSize = 10
        idLbl.TextColor3 = C.text
        idLbl.TextXAlignment = Enum.TextXAlignment.Left
        idLbl.TextTruncate = Enum.TextTruncate.AtEnd
        idLbl.Text = s.id
        idLbl.ZIndex = 7

        local countLbl = Instance.new("TextLabel", row)
        countLbl.BackgroundTransparency = 1
        countLbl.Size = UDim2.new(0, 90, 1, 0)
        countLbl.Position = UDim2.new(1, -96, 0, 0)
        countLbl.Font = Enum.Font.Code
        countLbl.TextSize = 10
        countLbl.TextColor3 = isFull and C.yellow or (isCurrent and C.green or C.textMid)
        countLbl.TextXAlignment = Enum.TextXAlignment.Right
        countLbl.Text = s.playing .. "/" .. s.maxPlayers ..
            (s.ping and s.ping > 0 and ("  " .. s.ping .. "ms") or "")
        countLbl.ZIndex = 7

        track(row.MouseButton1Click:Connect(function()
            if hopping then return end
            if isCurrent then logWarn("already in that server") return end
            hopping = true
            setStatus("loading", "hopping")
            logInfo("manual jump to " .. shortId(s.id))
            if currentServerId then
                blacklist[currentServerId] = true
                sessionVisited[currentServerId] = true
                saveBlacklist()
            end
            expectedJobId = tostring(s.id)
            task.wait(0.5)
            local ok = pcall(function()
                local opts = Instance.new("TeleportOptions")
                opts.ServerInstanceId = tostring(s.id)
                opts.ShouldReserveServer = false
                teleportService:TeleportAsync(game.PlaceId, {localPlayer}, opts)
            end)
            if not ok then
                pcall(function()
                    teleportService:TeleportToPlaceInstance(game.PlaceId, tostring(s.id), localPlayer)
                end)
            end
            task.delay(12, function() hopping = false end)
        end))
    end
end

function U.refreshServerScan()
    if U.scanInProgress then return end
    U.scanInProgress = true
    setStatus("loading", "scanning")
    logInfo("scanning all servers...")
    task.spawn(function()
        local all = scanAllServers(function(page, count)
            if U.serverListStatus then
                U.serverListStatus.Text = "page " .. page .. " · " .. count .. " servers"
            end
        end)
        logGood("scan complete: " .. #all .. " servers")
        U.renderServerList(all)
        if U.serverListStatus then
            U.serverListStatus.Text = #all .. " servers · " .. (currentServerId and shortId(currentServerId) or "?")
        end
        U.scanInProgress = false
        setStatus("ok", "ready")
    end)
end

local function doHop()
    if hopping then return end
    hopping = true
    setStatus("loading", "scanning")
    logInfo("hopping — session " .. sessionId)

    task.spawn(function()
        local candidates = scanServers()

        if #candidates == 0 then
            hopAttempts = hopAttempts + 1
            if hopAttempts > MAX_AUTO_RETRIES then
                logBad("giving up after " .. MAX_AUTO_RETRIES .. " failed attempts")
                hopping = false
                setStatus("ok", "ready")
                return
            end
            logWarn("no candidates — retry " .. hopAttempts .. "/" .. MAX_AUTO_RETRIES .. " in 3s")
            task.wait(3)
            candidates = scanServers()
            if #candidates == 0 then
                logBad("still no fresh servers")
                hopping = false
                setStatus("ok", "ready")
                return
            end
        end

        table.sort(candidates, function(a, b) return a.playing > b.playing end)
        local poolSize = math.max(1, math.floor(#candidates / 3))
        local chosen = candidates[math.random(1, poolSize)]

        logGood("selected " .. shortId(chosen.id) .. " (" .. chosen.playing .. "/" .. chosen.maxPlayers .. ")")

        if currentServerId then
            blacklist[currentServerId] = true
            sessionVisited[currentServerId] = true
            saveBlacklist()
        end

        expectedJobId = tostring(chosen.id)
        task.wait(0.7)

        local ok = pcall(function()
            local opts = Instance.new("TeleportOptions")
            opts.ServerInstanceId = tostring(chosen.id)
            opts.ShouldReserveServer = false
            teleportService:TeleportAsync(game.PlaceId, {localPlayer}, opts)
        end)

        if not ok then
            logWarn("teleportAsync failed — falling back")
            pcall(function()
                teleportService:TeleportToPlaceInstance(game.PlaceId, tostring(chosen.id), localPlayer)
            end)
        end

        task.delay(12, function() hopping = false end)
    end)
end

-- ============ BUILD UI ============

local function buildUI()
    local container = Instance.new("Frame", gui)
    container.BackgroundTransparency = 1
    container.Size = UDim2.new(0, WIN_W, 0, WIN_H)
    container.Position = UDim2.new(0, 40, 0.5, 0)
    container.AnchorPoint = Vector2.new(0, 0.5)
    container.ZIndex = 1
    U.container = container
    local containerScale = Instance.new("UIScale", container)
    containerScale.Scale = currentScale
    U.containerScale = containerScale

    track(runService.RenderStepped:Connect(function(dt)
        if unloaded then return end
        if dt > 0.1 then dt = 0.1 end
        local diff = targetScale - currentScale
        local still = math.abs(diff) < 0.0005 and math.abs(scaleVelocity) < 0.0005
        if not still then
            scaleVelocity = scaleVelocity + (diff * 320 - scaleVelocity * 26) * dt
            currentScale = currentScale + scaleVelocity * dt
            containerScale.Scale = currentScale
        end
    end))

    local win = Instance.new("Frame", container)
    win.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
    win.BorderSizePixel = 0
    win.Size = UDim2.new(1, 0, 1, 0)
    win.Active = true
    win.ClipsDescendants = true
    win.ZIndex = 1
    U.win = win
    Instance.new("UICorner", win).CornerRadius = UDim.new(0, 16)
    local winStroke = Instance.new("UIStroke", win)
    winStroke.Color = Color3.fromRGB(255, 255, 255)
    winStroke.Thickness = 1
    local winSG = Instance.new("UIGradient", winStroke)
    winSG.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(140, 148, 168))
    winSG.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.88)})
    winSG.Rotation = 90
    draggable(container, win)

    local bgLayer = Instance.new("Frame", win)
    bgLayer.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
    bgLayer.BorderSizePixel = 0
    bgLayer.Size = UDim2.new(1, 0, 1, 0)
    bgLayer.ZIndex = 0
    bgLayer.ClipsDescendants = true
    Instance.new("UICorner", bgLayer).CornerRadius = UDim.new(0, 16)

    local bgGrad = Instance.new("UIGradient", bgLayer)
    local t0 = themes[currentThemeIdx]
    bgGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.0, t0.c1),
        ColorSequenceKeypoint.new(0.5, t0.c2),
        ColorSequenceKeypoint.new(1.0, t0.c3),
    })
    bgGrad.Rotation = 35
    bgGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(0.5, 0.62),
        NumberSequenceKeypoint.new(1, 0.4),
    })
    U.bgGrad = bgGrad

    local bgOverlay = Instance.new("Frame", bgLayer)
    bgOverlay.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
    bgOverlay.BackgroundTransparency = 0.6
    bgOverlay.BorderSizePixel = 0
    bgOverlay.Size = UDim2.new(1, 0, 1, 0)
    bgOverlay.ZIndex = 1
    Instance.new("UICorner", bgOverlay).CornerRadius = UDim.new(0, 16)

    local function makeOrb(color, size, startPos, d1, d2, dur, baseTrans)
        local o = Instance.new("Frame", bgLayer)
        o.BackgroundColor3 = color
        o.BackgroundTransparency = baseTrans
        o.BorderSizePixel = 0
        o.Size = UDim2.new(0, size, 0, size)
        o.Position = startPos
        o.ZIndex = 2
        Instance.new("UICorner", o).CornerRadius = UDim.new(1, 0)
        task.spawn(function()
            while not unloaded and o.Parent do
                tw(o, {Position = d1, BackgroundTransparency = baseTrans - 0.15}, dur, Enum.EasingStyle.Sine)
                task.wait(dur)
                if unloaded or not o.Parent then break end
                tw(o, {Position = d2, BackgroundTransparency = baseTrans + 0.05}, dur, Enum.EasingStyle.Sine)
                task.wait(dur)
                if unloaded or not o.Parent then break end
                tw(o, {Position = startPos, BackgroundTransparency = baseTrans}, dur, Enum.EasingStyle.Sine)
                task.wait(dur)
            end
        end)
        return o
    end

    U.orb1 = makeOrb(themes[currentThemeIdx].c1, 320, UDim2.new(-0.35, 0, -0.2, 0),
        UDim2.new(0.55, 0, -0.1, 0), UDim2.new(-0.05, 0, 0.55, 0), 16, 0.72)
    U.orb2 = makeOrb(themes[currentThemeIdx].c3, 280, UDim2.new(0.7, 0, 0.5, 0),
        UDim2.new(0.15, 0, 0.95, 0), UDim2.new(0.9, 0, 0.1, 0), 20, 0.78)
    U.orb3 = makeOrb(themes[currentThemeIdx].c2, 240, UDim2.new(0.3, 0, 0.7, 0),
        UDim2.new(-0.15, 0, 0.9, 0), UDim2.new(0.75, 0, -0.05, 0), 24, 0.82)

    -- Header
    local header = Instance.new("Frame", win)
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1, 0, 0, HEADER_H)
    header.ZIndex = 5
    local hPad = Instance.new("UIPadding", header)
    hPad.PaddingLeft = UDim.new(0, 16)
    hPad.PaddingRight = UDim.new(0, 16)
    hPad.PaddingTop = UDim.new(0, 12)
    hPad.PaddingBottom = UDim.new(0, 12)

    local hLeft = Instance.new("Frame", header)
    hLeft.BackgroundTransparency = 1
    hLeft.Size = UDim2.new(0.55, 0, 1, 0)
    hLeft.ZIndex = 6
    local hLL = Instance.new("UIListLayout", hLeft)
    hLL.FillDirection = Enum.FillDirection.Horizontal
    hLL.VerticalAlignment = Enum.VerticalAlignment.Center
    hLL.SortOrder = Enum.SortOrder.LayoutOrder
    hLL.Padding = UDim.new(0, 11)

    local iconBox = Instance.new("Frame", hLeft)
    iconBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    iconBox.BackgroundTransparency = 0.85
    iconBox.BorderSizePixel = 0
    iconBox.Size = UDim2.new(0, 34, 0, 34)
    iconBox.LayoutOrder = 1
    iconBox.ZIndex = 6
    Instance.new("UICorner", iconBox).CornerRadius = UDim.new(0, 9)
    local ibG = Instance.new("UIGradient", iconBox)
    ibG.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 205, 218))
    ibG.Rotation = 90
    local ibS = Instance.new("UIStroke", iconBox)
    ibS.Color = Color3.fromRGB(255, 255, 255)
    ibS.Thickness = 1
    ibS.Transparency = 0.5
    local iconImg = Instance.new("ImageLabel", iconBox)
    iconImg.BackgroundTransparency = 1
    iconImg.Size = UDim2.new(1, 0, 1, 0)
    iconImg.Image = iconId
    iconImg.ZIndex = 7
    Instance.new("UICorner", iconImg).CornerRadius = UDim.new(0, 9)

    local titleStack = Instance.new("Frame", hLeft)
    titleStack.BackgroundTransparency = 1
    titleStack.Size = UDim2.new(0, 150, 1, 0)
    titleStack.LayoutOrder = 2
    titleStack.ZIndex = 6
    local titleL = Instance.new("TextLabel", titleStack)
    titleL.BackgroundTransparency = 1
    titleL.Size = UDim2.new(1, 0, 0, 16)
    titleL.Position = UDim2.new(0, 0, 0, 3)
    titleL.Font = Enum.Font.GothamBold
    titleL.TextSize = 14
    titleL.TextColor3 = C.text
    titleL.TextXAlignment = Enum.TextXAlignment.Left
    titleL.Text = "server hopper"
    titleL.ZIndex = 7
    local subL = Instance.new("TextLabel", titleStack)
    subL.BackgroundTransparency = 1
    subL.Size = UDim2.new(1, 0, 0, 12)
    subL.Position = UDim2.new(0, 0, 0, 19)
    subL.Font = Enum.Font.Gotham
    subL.TextSize = 10
    subL.TextColor3 = C.textDim
    subL.TextXAlignment = Enum.TextXAlignment.Left
    subL.Text = "session " .. sessionId
    subL.ZIndex = 7

    local hRight = Instance.new("Frame", header)
    hRight.BackgroundTransparency = 1
    hRight.Size = UDim2.new(0.45, 0, 1, 0)
    hRight.Position = UDim2.new(0.55, 0, 0, 0)
    hRight.ZIndex = 6
    local hRL = Instance.new("UIListLayout", hRight)
    hRL.FillDirection = Enum.FillDirection.Horizontal
    hRL.HorizontalAlignment = Enum.HorizontalAlignment.Right
    hRL.VerticalAlignment = Enum.VerticalAlignment.Center
    hRL.SortOrder = Enum.SortOrder.LayoutOrder
    hRL.Padding = UDim.new(0, 8)

    local statusWrap = Instance.new("Frame", hRight)
    statusWrap.BackgroundTransparency = 1
    statusWrap.Size = UDim2.new(0, 84, 1, 0)
    statusWrap.LayoutOrder = 1
    statusWrap.ZIndex = 6
    local statusL = Instance.new("UIListLayout", statusWrap)
    statusL.FillDirection = Enum.FillDirection.Horizontal
    statusL.HorizontalAlignment = Enum.HorizontalAlignment.Right
    statusL.VerticalAlignment = Enum.VerticalAlignment.Center
    statusL.SortOrder = Enum.SortOrder.LayoutOrder
    statusL.Padding = UDim.new(0, 6)

    local statusText = Instance.new("TextLabel", statusWrap)
    statusText.BackgroundTransparency = 1
    statusText.Size = UDim2.new(0, 66, 1, 0)
    statusText.Font = Enum.Font.GothamMedium
    statusText.TextSize = 11
    statusText.TextColor3 = C.textMid
    statusText.TextXAlignment = Enum.TextXAlignment.Right
    statusText.Text = "idle"
    statusText.LayoutOrder = 1
    statusText.ZIndex = 7
    U.statusText = statusText

    local statusDot = Instance.new("Frame", statusWrap)
    statusDot.BackgroundColor3 = C.red
    statusDot.BorderSizePixel = 0
    statusDot.Size = UDim2.new(0, 7, 0, 7)
    statusDot.LayoutOrder = 2
    statusDot.ZIndex = 7
    Instance.new("UICorner", statusDot).CornerRadius = UDim.new(1, 0)
    local sdRing = Instance.new("UIStroke", statusDot)
    sdRing.Color = C.red
    sdRing.Thickness = 1
    sdRing.Transparency = 0.6
    U.statusDot = statusDot
    U.statusRing = sdRing

    local function iconBtn(txt, order)
        local b = Instance.new("TextButton", hRight)
        b.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        b.BackgroundTransparency = 0.85
        b.BorderSizePixel = 0
        b.Size = UDim2.new(0, 24, 0, 24)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 14
        b.TextColor3 = C.textMid
        b.Text = txt
        b.AutoButtonColor = false
        b.LayoutOrder = order
        b.ZIndex = 6
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        local bg = Instance.new("UIGradient", b)
        bg.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(210, 215, 228))
        bg.Rotation = 90
        local st = Instance.new("UIStroke", b)
        st.Color = Color3.fromRGB(255, 255, 255)
        st.Thickness = 1
        st.Transparency = 0.55
        return b
    end

    local btnMin = iconBtn("−", 2)
    local btnClose = iconBtn("×", 3)

    track(btnClose.MouseEnter:Connect(function() tw(btnClose, {BackgroundColor3 = Color3.fromRGB(200, 70, 85), BackgroundTransparency = 0.15, TextColor3 = Color3.fromRGB(255, 240, 245)}, 0.18) end))
    track(btnClose.MouseLeave:Connect(function() tw(btnClose, {BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.85, TextColor3 = C.textMid}, 0.22) end))
    track(btnMin.MouseEnter:Connect(function() tw(btnMin, {BackgroundTransparency = 0.7, TextColor3 = C.text}, 0.18) end))
    track(btnMin.MouseLeave:Connect(function() tw(btnMin, {BackgroundTransparency = 0.85, TextColor3 = C.textMid}, 0.22) end))

    local tabsBar = Instance.new("Frame", win)
    tabsBar.BackgroundTransparency = 1
    tabsBar.Size = UDim2.new(1, 0, 0, TABS_H)
    tabsBar.Position = UDim2.new(0, 0, 0, HEADER_H)
    tabsBar.ZIndex = 5

    local tabNames = {"logs", "servers", "config", "blacklist"}
    local tabBtns, tabPages = {}, {}
    local activeTab = "logs"

    for i, name in ipairs(tabNames) do
        local b = Instance.new("TextButton", tabsBar)
        b.BackgroundTransparency = 1
        b.Size = UDim2.new(1/#tabNames, 0, 1, 0)
        b.Position = UDim2.new((i - 1) / #tabNames, 0, 0, 0)
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 12
        b.TextColor3 = C.textDim
        b.Text = name
        b.AutoButtonColor = false
        b.ZIndex = 6
        tabBtns[name] = b
    end

    local tabUnderline = Instance.new("Frame", tabsBar)
    tabUnderline.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    tabUnderline.BackgroundTransparency = 0.3
    tabUnderline.BorderSizePixel = 0
    tabUnderline.Size = UDim2.new(1/#tabNames, -80, 0, 3)
    tabUnderline.Position = UDim2.new(0, 40, 1, -4)
    tabUnderline.ZIndex = 7
    Instance.new("UICorner", tabUnderline).CornerRadius = UDim.new(1, 0)
    local tuG = Instance.new("UIGradient", tabUnderline)
    tuG.Color = ColorSequence.new(C.accentHi, C.accent)
    tuG.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.6)})
    registerAccent(tuG, "Color", "grad")

    local content = Instance.new("Frame", win)
    content.BackgroundTransparency = 1
    content.Size = UDim2.new(1, 0, 1, -HEADER_H - TABS_H)
    content.Position = UDim2.new(0, 0, 0, HEADER_H + TABS_H)
    content.ClipsDescendants = true
    content.ZIndex = 4

    for _, name in ipairs(tabNames) do
        local page = Instance.new("Frame", content)
        page.BackgroundTransparency = 1
        page.Size = UDim2.new(1, 0, 1, 0)
        page.Visible = (name == activeTab)
        page.ZIndex = 4
        tabPages[name] = page
    end

    local function switchTab(name)
        if name == activeTab then return end
        activeTab = name
        local newPage = tabPages[name]
        newPage.Visible = true
        local veil = Instance.new("Frame", newPage)
        veil.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
        veil.BackgroundTransparency = 0.5
        veil.BorderSizePixel = 0
        veil.Size = UDim2.new(1, 0, 1, 0)
        veil.ZIndex = 70
        tw(veil, {BackgroundTransparency = 1}, 0.32)
        task.delay(0.34, function() if veil and veil.Parent then veil:Destroy() end end)
        for n, p in pairs(tabPages) do
            if n ~= name then p.Visible = false end
        end
        local idx = table.find(tabNames, name)
        local tabW = 1 / #tabNames
        tw(tabUnderline, {Position = UDim2.new((idx - 1) * tabW, 40, 1, -4)}, 0.4, Enum.EasingStyle.Quart)
        for n, b in pairs(tabBtns) do
            tw(b, {TextColor3 = (n == name) and C.text or C.textDim}, 0.24)
        end
        if name == "servers" and U.refreshServerScan then
            U.refreshServerScan()
        end
    end

    for n, b in pairs(tabBtns) do
        track(b.MouseButton1Click:Connect(function() switchTab(n) end))
    end

    local idx = table.find(tabNames, activeTab)
    local tabW = 1 / #tabNames
    tabUnderline.Position = UDim2.new((idx - 1) * tabW, 40, 1, -4)
    tabBtns[activeTab].TextColor3 = C.text

    local function section(parent, txt, order)
        local f = Instance.new("Frame", parent)
        f.BackgroundTransparency = 1
        f.Size = UDim2.new(1, 0, 0, 18)
        f.LayoutOrder = order or 0
        f.ZIndex = 5
        local l = Instance.new("TextLabel", f)
        l.BackgroundTransparency = 1
        l.Size = UDim2.new(1, 0, 1, 0)
        l.Font = Enum.Font.GothamBold
        l.TextSize = 10
        l.TextColor3 = C.textDim
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Text = string.upper(txt)
        l.ZIndex = 6
        local pl = Instance.new("UIPadding", f)
        pl.PaddingLeft = UDim.new(0, 4)
    end

    local function toggleRow(parent, label, initial, cb, order, persistKey)
        local b = glassButton(parent, 48, order)
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
        local rowPad = Instance.new("UIPadding", b)
        rowPad.PaddingLeft = UDim.new(0, 16)
        rowPad.PaddingRight = UDim.new(0, 16)
        local l = Instance.new("TextLabel", b)
        l.BackgroundTransparency = 1
        l.Size = UDim2.new(1, -84, 1, 0)
        l.Font = Enum.Font.GothamMedium
        l.TextSize = 12
        l.TextColor3 = C.text
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Text = label
        l.ZIndex = 6
        local PW, PH, K = 40, 22, 18
        local toggleTrack = Instance.new("Frame", b)
        toggleTrack.Size = UDim2.new(0, PW, 0, PH)
        toggleTrack.Position = UDim2.new(1, -PW, 0.5, -PH / 2)
        toggleTrack.BackgroundColor3 = initial and C.green or Color3.fromRGB(64, 66, 78)
        toggleTrack.BorderSizePixel = 0
        toggleTrack.ZIndex = 6
        Instance.new("UICorner", toggleTrack).CornerRadius = UDim.new(1, 0)
        local knob = Instance.new("Frame", toggleTrack)
        knob.Size = UDim2.new(0, K, 0, K)
        knob.Position = UDim2.new(0, initial and (PW - K - 2) or 2, 0.5, -K / 2)
        knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        knob.BorderSizePixel = 0
        knob.ZIndex = 7
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
        local state = initial
        track(b.MouseButton1Click:Connect(function()
            state = not state
            local tx = state and (PW - K - 2) or 2
            tw(knob, {Position = UDim2.new(0, tx, 0.5, -K / 2)}, 0.4, Enum.EasingStyle.Back)
            tw(toggleTrack, {
                BackgroundColor3 = state and C.green or Color3.fromRGB(64, 66, 78),
            }, 0.28)
            if persistKey then
                persistConfig[persistKey] = state
                saveConfigToDisk()
            end
            cb(state)
        end))
        return b
    end

    -- ===== LOGS TAB =====
    local logsPage = tabPages["logs"]

    local chatCard = glassSurface(logsPage)
    chatCard.Size = UDim2.new(1, -28, 1, -104)
    chatCard.Position = UDim2.new(0, 14, 0, 14)

    local chatScroll = Instance.new("ScrollingFrame", chatCard)
    chatScroll.BackgroundTransparency = 1
    chatScroll.BorderSizePixel = 0
    chatScroll.Size = UDim2.new(1, -28, 1, -28)
    chatScroll.Position = UDim2.new(0, 14, 0, 14)
    chatScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    chatScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    chatScroll.ScrollBarThickness = 2
    chatScroll.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
    chatScroll.ScrollBarImageTransparency = 0.7
    chatScroll.ZIndex = 6

    local chatLabel = Instance.new("TextLabel", chatScroll)
    chatLabel.BackgroundTransparency = 1
    chatLabel.Size = UDim2.new(1, 0, 0, 0)
    chatLabel.AutomaticSize = Enum.AutomaticSize.Y
    chatLabel.Font = Enum.Font.Code
    chatLabel.TextSize = 11
    chatLabel.TextColor3 = C.text
    chatLabel.TextXAlignment = Enum.TextXAlignment.Left
    chatLabel.TextYAlignment = Enum.TextYAlignment.Top
    chatLabel.TextWrapped = true
    chatLabel.LineHeight = 1.45
    chatLabel.Text = ""
    chatLabel.ZIndex = 7
    U.chatLabel = chatLabel

    -- Redraw existing logs now that chatLabel exists
    do
        local out = {}
        for _, l in ipairs(sessionLogs) do table.insert(out, l) end
        if #out > 0 then chatLabel.Text = table.concat(out, "\n") end
    end

    local inputBar = glassSurface(logsPage)
    inputBar.Size = UDim2.new(1, -28, 0, 70)
    inputBar.Position = UDim2.new(0, 14, 1, -84)

    local ibLabel = Instance.new("TextLabel", inputBar)
    ibLabel.BackgroundTransparency = 1
    ibLabel.Size = UDim2.new(1, -28, 0, 14)
    ibLabel.Position = UDim2.new(0, 14, 0, 10)
    ibLabel.Font = Enum.Font.GothamBold
    ibLabel.TextSize = 10
    ibLabel.TextColor3 = C.textDim
    ibLabel.TextXAlignment = Enum.TextXAlignment.Left
    ibLabel.Text = "HOP CONTROL"
    ibLabel.ZIndex = 7

    local hopBtn = Instance.new("TextButton", inputBar)
    hopBtn.BackgroundColor3 = C.accent
    hopBtn.BorderSizePixel = 0
    hopBtn.Size = UDim2.new(0.55, -16, 0, 32)
    hopBtn.Position = UDim2.new(0, 14, 0, 30)
    hopBtn.Font = Enum.Font.GothamBold
    hopBtn.TextSize = 12
    hopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    hopBtn.Text = "hop now"
    hopBtn.AutoButtonColor = false
    hopBtn.ZIndex = 6
    Instance.new("UICorner", hopBtn).CornerRadius = UDim.new(0, 8)
    local sbGrad = Instance.new("UIGradient", hopBtn)
    sbGrad.Color = ColorSequence.new(C.accentHi, C.accent)
    sbGrad.Rotation = 90
    local sbStroke = Instance.new("UIStroke", hopBtn)
    sbStroke.Color = Color3.fromRGB(255, 255, 255)
    sbStroke.Thickness = 1
    sbStroke.Transparency = 0.55
    registerAccent(hopBtn, "BackgroundColor3", "accent")
    registerAccent(sbGrad, "Color", "grad")

    local clearBtn = Instance.new("TextButton", inputBar)
    clearBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    clearBtn.BackgroundTransparency = 0.8
    clearBtn.BorderSizePixel = 0
    clearBtn.Size = UDim2.new(0.45, -16, 0, 32)
    clearBtn.Position = UDim2.new(0.55, 2, 0, 30)
    clearBtn.Font = Enum.Font.GothamBold
    clearBtn.TextSize = 11
    clearBtn.TextColor3 = C.text
    clearBtn.Text = "clear log"
    clearBtn.AutoButtonColor = false
    clearBtn.ZIndex = 6
    Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0, 8)
    local cbGrad = Instance.new("UIGradient", clearBtn)
    cbGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(210, 215, 228))
    cbGrad.Rotation = 90
    local cbStroke = Instance.new("UIStroke", clearBtn)
    cbStroke.Color = Color3.fromRGB(255, 255, 255)
    cbStroke.Thickness = 1
    cbStroke.Transparency = 0.55

    track(hopBtn.MouseEnter:Connect(function() tweenService:Create(sbStroke, TweenInfo.new(0.18), {Transparency = 0.35}):Play() end))
    track(hopBtn.MouseLeave:Connect(function() tweenService:Create(sbStroke, TweenInfo.new(0.22), {Transparency = 0.55}):Play() end))
    track(clearBtn.MouseEnter:Connect(function() tw(clearBtn, {BackgroundTransparency = 0.7}, 0.18) end))
    track(clearBtn.MouseLeave:Connect(function() tw(clearBtn, {BackgroundTransparency = 0.8}, 0.22) end))

    track(hopBtn.MouseButton1Click:Connect(function()
        if hopping then logWarn("already hopping...") return end
        logInfo("manual hop triggered")
        doHop()
    end))

    track(clearBtn.MouseButton1Click:Connect(function()
        sessionLogs = {}
        if U.chatLabel then U.chatLabel.Text = "" end
    end))

    -- ===== SERVERS TAB =====
    local serversPage = tabPages["servers"]
    local sPad = Instance.new("UIPadding", serversPage)
    sPad.PaddingTop = UDim.new(0, 14)
    sPad.PaddingBottom = UDim.new(0, 18)
    sPad.PaddingLeft = UDim.new(0, 14)
    sPad.PaddingRight = UDim.new(0, 14)

    local sScroll = Instance.new("ScrollingFrame", serversPage)
    sScroll.BackgroundTransparency = 1
    sScroll.BorderSizePixel = 0
    sScroll.Size = UDim2.new(1, 0, 1, 0)
    sScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    sScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sScroll.ScrollBarThickness = 2
    sScroll.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
    sScroll.ScrollBarImageTransparency = 0.7
    sScroll.ZIndex = 5
    local sList = Instance.new("UIListLayout", sScroll)
    sList.SortOrder = Enum.SortOrder.LayoutOrder
    sList.Padding = UDim.new(0, 8)

    section(sScroll, "scanner", 0)

    local serverStatusCard = glassSurface(sScroll, 1)
    serverStatusCard.Size = UDim2.new(1, 0, 0, 60)

    local serverListStatus = Instance.new("TextLabel", serverStatusCard)
    serverListStatus.BackgroundTransparency = 1
    serverListStatus.Size = UDim2.new(1, -120, 1, 0)
    serverListStatus.Position = UDim2.new(0, 16, 0, 0)
    serverListStatus.Font = Enum.Font.GothamBold
    serverListStatus.TextSize = 12
    serverListStatus.TextColor3 = C.text
    serverListStatus.TextXAlignment = Enum.TextXAlignment.Left
    serverListStatus.Text = "click refresh to scan"
    serverListStatus.ZIndex = 6
    U.serverListStatus = serverListStatus

    local refreshServersBtn = Instance.new("TextButton", serverStatusCard)
    refreshServersBtn.BackgroundColor3 = C.accent
    refreshServersBtn.BorderSizePixel = 0
    refreshServersBtn.Size = UDim2.new(0, 88, 0, 32)
    refreshServersBtn.Position = UDim2.new(1, -104, 0.5, -16)
    refreshServersBtn.Font = Enum.Font.GothamBold
    refreshServersBtn.TextSize = 11
    refreshServersBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    refreshServersBtn.Text = "refresh"
    refreshServersBtn.AutoButtonColor = false
    refreshServersBtn.ZIndex = 6
    Instance.new("UICorner", refreshServersBtn).CornerRadius = UDim.new(0, 8)
    local rsbGrad = Instance.new("UIGradient", refreshServersBtn)
    rsbGrad.Color = ColorSequence.new(C.accentHi, C.accent)
    rsbGrad.Rotation = 90
    local rsbStroke = Instance.new("UIStroke", refreshServersBtn)
    rsbStroke.Color = Color3.fromRGB(255, 255, 255)
    rsbStroke.Thickness = 1
    rsbStroke.Transparency = 0.55
    registerAccent(refreshServersBtn, "BackgroundColor3", "accent")
    registerAccent(rsbGrad, "Color", "grad")

    track(refreshServersBtn.MouseEnter:Connect(function() tweenService:Create(rsbStroke, TweenInfo.new(0.18), {Transparency = 0.35}):Play() end))
    track(refreshServersBtn.MouseLeave:Connect(function() tweenService:Create(rsbStroke, TweenInfo.new(0.22), {Transparency = 0.55}):Play() end))
    track(refreshServersBtn.MouseButton1Click:Connect(function()
        U.refreshServerScan()
    end))

    section(sScroll, "all servers · click to jump", 2)

    local serverListFrame = Instance.new("Frame", sScroll)
    serverListFrame.BackgroundTransparency = 1
    serverListFrame.Size = UDim2.new(1, 0, 0, 0)
    serverListFrame.AutomaticSize = Enum.AutomaticSize.Y
    serverListFrame.LayoutOrder = 3
    serverListFrame.ZIndex = 5
    local slLayout = Instance.new("UIListLayout", serverListFrame)
    slLayout.SortOrder = Enum.SortOrder.LayoutOrder
    slLayout.Padding = UDim.new(0, 6)
    U.serverListFrame = serverListFrame

    -- ===== CONFIG TAB =====
    local configPage = tabPages["config"]
    local tPad = Instance.new("UIPadding", configPage)
    tPad.PaddingTop = UDim.new(0, 14)
    tPad.PaddingBottom = UDim.new(0, 18)
    tPad.PaddingLeft = UDim.new(0, 14)
    tPad.PaddingRight = UDim.new(0, 14)

    local tScroll = Instance.new("ScrollingFrame", configPage)
    tScroll.BackgroundTransparency = 1
    tScroll.BorderSizePixel = 0
    tScroll.Size = UDim2.new(1, 0, 1, 0)
    tScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    tScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    tScroll.ScrollBarThickness = 2
    tScroll.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
    tScroll.ScrollBarImageTransparency = 0.7
    tScroll.ZIndex = 5
    local tList = Instance.new("UIListLayout", tScroll)
    tList.SortOrder = Enum.SortOrder.LayoutOrder
    tList.Padding = UDim.new(0, 8)

    section(tScroll, "appearance", 0)

    local themeCard = glassSurface(tScroll, 1)
    themeCard.Size = UDim2.new(1, 0, 0, 72)

    local themeLabel = Instance.new("TextLabel", themeCard)
    themeLabel.BackgroundTransparency = 1
    themeLabel.Size = UDim2.new(1, -28, 0, 14)
    themeLabel.Position = UDim2.new(0, 14, 0, 12)
    themeLabel.Font = Enum.Font.GothamBold
    themeLabel.TextSize = 10
    themeLabel.TextColor3 = C.textDim
    themeLabel.TextXAlignment = Enum.TextXAlignment.Left
    themeLabel.Text = "theme · " .. themes[currentThemeIdx].name
    themeLabel.ZIndex = 6
    U.themeLabel = themeLabel

    local swatchRow = Instance.new("Frame", themeCard)
    swatchRow.BackgroundTransparency = 1
    swatchRow.Size = UDim2.new(1, -28, 0, 28)
    swatchRow.Position = UDim2.new(0, 14, 0, 32)
    swatchRow.ZIndex = 6
    local swatchLayout = Instance.new("UIListLayout", swatchRow)
    swatchLayout.FillDirection = Enum.FillDirection.Horizontal
    swatchLayout.SortOrder = Enum.SortOrder.LayoutOrder
    swatchLayout.Padding = UDim.new(0, 10)
    swatchLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    for i, t in ipairs(themes) do
        local sw = Instance.new("TextButton", swatchRow)
        if t.rainbow then
            sw.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            local swRainbow = Instance.new("UIGradient", sw)
            swRainbow.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
                ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 80)),
                ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 255, 120)),
                ColorSequenceKeypoint.new(0.75, Color3.fromRGB(120, 180, 255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 120, 255)),
            })
            swRainbow.Rotation = 45
        else
            sw.BackgroundColor3 = t.c1
            local swGrad = Instance.new("UIGradient", sw)
            swGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255):Lerp(t.c1, 0.6), t.c1)
            swGrad.Rotation = 90
        end
        sw.BorderSizePixel = 0
        sw.Size = UDim2.new(0, 26, 0, 26)
        sw.Text = ""
        sw.AutoButtonColor = false
        sw.LayoutOrder = i
        sw.ZIndex = 6
        Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)
        local swStroke = Instance.new("UIStroke", sw)
        swStroke.Color = (i == currentThemeIdx) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 185, 200)
        swStroke.Thickness = (i == currentThemeIdx) and 2 or 1
        swStroke.Transparency = (i == currentThemeIdx) and 0.2 or 0.65
        track(sw.MouseEnter:Connect(function() tw(sw, {Size = UDim2.new(0, 30, 0, 30)}, 0.2, Enum.EasingStyle.Back) end))
        track(sw.MouseLeave:Connect(function() tw(sw, {Size = UDim2.new(0, 26, 0, 26)}, 0.24, Enum.EasingStyle.Quart) end))
        track(sw.MouseButton1Click:Connect(function()
            applyTheme(i, true)
            for _, child in ipairs(swatchRow:GetChildren()) do
                if child:IsA("TextButton") then
                    local st = child:FindFirstChildOfClass("UIStroke")
                    if st then
                        local active = (child.LayoutOrder == i)
                        tweenService:Create(st, TweenInfo.new(0.26), {
                            Color = active and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 185, 200),
                            Thickness = active and 2 or 1,
                            Transparency = active and 0.2 or 0.65,
                        }):Play()
                    end
                end
            end
        end))
    end

    section(tScroll, "scale", 2)

    local scaleCard = glassSurface(tScroll, 3)
    scaleCard.Size = UDim2.new(1, 0, 0, 56)

    local scaleLabel = Instance.new("TextLabel", scaleCard)
    scaleLabel.BackgroundTransparency = 1
    scaleLabel.Size = UDim2.new(1, -180, 1, 0)
    scaleLabel.Position = UDim2.new(0, 16, 0, 0)
    scaleLabel.Font = Enum.Font.GothamBold
    scaleLabel.TextSize = 11
    scaleLabel.TextColor3 = C.text
    scaleLabel.TextXAlignment = Enum.TextXAlignment.Left
    scaleLabel.Text = "zoom · " .. string.format("%.2f", targetScale)
    scaleLabel.ZIndex = 6
    U.scaleLabel = scaleLabel

    local function scaleBtn(txt, order, onClick)
        local b = Instance.new("TextButton", scaleCard)
        b.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        b.BackgroundTransparency = 0.8
        b.BorderSizePixel = 0
        b.Size = UDim2.new(0, 34, 0, 30)
        b.Position = UDim2.new(1, -(34 * (4 - order) + 12 + (3 - order) * 6), 0.5, -15)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 13
        b.TextColor3 = C.text
        b.Text = txt
        b.AutoButtonColor = false
        b.ZIndex = 6
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        local bg = Instance.new("UIGradient", b)
        bg.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(210, 215, 228))
        bg.Rotation = 90
        local st = Instance.new("UIStroke", b)
        st.Color = Color3.fromRGB(255, 255, 255)
        st.Thickness = 1
        st.Transparency = 0.6
        track(b.MouseEnter:Connect(function() tw(b, {BackgroundTransparency = 0.68}, 0.18) end))
        track(b.MouseLeave:Connect(function() tw(b, {BackgroundTransparency = 0.8}, 0.22) end))
        track(b.MouseButton1Click:Connect(onClick))
    end

    scaleBtn("−", 1, function()
        targetScale = clamp(targetScale - 0.1, 0.7, 1.5)
        scaleLabel.Text = "zoom · " .. string.format("%.2f", targetScale)
        persistConfig.scale = targetScale
        saveConfigToDisk()
    end)
    scaleBtn("1", 2, function()
        targetScale = 1
        scaleLabel.Text = "zoom · 1.00"
        persistConfig.scale = 1
        saveConfigToDisk()
    end)
    scaleBtn("+", 3, function()
        targetScale = clamp(targetScale + 0.1, 0.7, 1.5)
        scaleLabel.Text = "zoom · " .. string.format("%.2f", targetScale)
        persistConfig.scale = targetScale
        saveConfigToDisk()
    end)

    section(tScroll, "behavior", 5)
    toggleRow(tScroll, "auto hop on join", false, function(v) config.hopOnJoin = v end, 6, nil)
    toggleRow(tScroll, "prefer less full servers", config.preferLessFull, function(v)
        config.maxPlayerRatio = v and 0.9 or 1.0
    end, 7, "preferLessFull")

    section(tScroll, "limits", 9)
    toggleRow(tScroll, "skip empty servers", config.skipEmpty, function(v)
        config.minPlayers = v and 1 or 0
    end, 10, "skipEmpty")

    section(tScroll, "system", 12)

    local unloadBtn = Instance.new("TextButton", tScroll)
    unloadBtn.BackgroundColor3 = Color3.fromRGB(180, 55, 70)
    unloadBtn.BackgroundTransparency = 0.15
    unloadBtn.BorderSizePixel = 0
    unloadBtn.Size = UDim2.new(1, 0, 0, 52)
    unloadBtn.Text = ""
    unloadBtn.AutoButtonColor = false
    unloadBtn.LayoutOrder = 13
    unloadBtn.ZIndex = 5
    Instance.new("UICorner", unloadBtn).CornerRadius = UDim.new(0, 10)
    local ubGrad = Instance.new("UIGradient", unloadBtn)
    ubGrad.Color = ColorSequence.new(Color3.fromRGB(220, 75, 90), Color3.fromRGB(150, 40, 55))
    ubGrad.Rotation = 90
    local ubStroke = Instance.new("UIStroke", unloadBtn)
    ubStroke.Color = Color3.fromRGB(255, 200, 210)
    ubStroke.Thickness = 1
    ubStroke.Transparency = 0.5

    local ubL = Instance.new("TextLabel", unloadBtn)
    ubL.BackgroundTransparency = 1
    ubL.Size = UDim2.new(1, 0, 0, 18)
    ubL.Position = UDim2.new(0, 16, 0, 10)
    ubL.Font = Enum.Font.GothamBold
    ubL.TextSize = 12
    ubL.TextColor3 = Color3.fromRGB(255, 245, 250)
    ubL.TextXAlignment = Enum.TextXAlignment.Left
    ubL.Text = "unload hopper"
    ubL.ZIndex = 6

    local ubS = Instance.new("TextLabel", unloadBtn)
    ubS.BackgroundTransparency = 1
    ubS.Size = UDim2.new(1, 0, 0, 12)
    ubS.Position = UDim2.new(0, 16, 0, 30)
    ubS.Font = Enum.Font.Gotham
    ubS.TextSize = 10
    ubS.TextColor3 = Color3.fromRGB(255, 200, 210)
    ubS.TextXAlignment = Enum.TextXAlignment.Left
    ubS.Text = "removes the ui and disconnects everything"
    ubS.ZIndex = 6

    track(unloadBtn.MouseEnter:Connect(function() tw(unloadBtn, {BackgroundTransparency = 0}, 0.18) end))
    track(unloadBtn.MouseLeave:Connect(function() tw(unloadBtn, {BackgroundTransparency = 0.15}, 0.22) end))
    track(unloadBtn.MouseButton1Click:Connect(function()
        if _G.__hopper_unload then _G.__hopper_unload() end
    end))

    -- ===== BLACKLIST TAB =====
    local blPage = tabPages["blacklist"]
    local bPad = Instance.new("UIPadding", blPage)
    bPad.PaddingTop = UDim.new(0, 14)
    bPad.PaddingBottom = UDim.new(0, 18)
    bPad.PaddingLeft = UDim.new(0, 14)
    bPad.PaddingRight = UDim.new(0, 14)

    local bScroll = Instance.new("ScrollingFrame", blPage)
    bScroll.BackgroundTransparency = 1
    bScroll.BorderSizePixel = 0
    bScroll.Size = UDim2.new(1, 0, 1, 0)
    bScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    bScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    bScroll.ScrollBarThickness = 2
    bScroll.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
    bScroll.ScrollBarImageTransparency = 0.7
    bScroll.ZIndex = 5
    local bList = Instance.new("UIListLayout", bScroll)
    bList.SortOrder = Enum.SortOrder.LayoutOrder
    bList.Padding = UDim.new(0, 8)

    section(bScroll, "stats", 0)

    local statsCard = glassSurface(bScroll, 1)
    statsCard.Size = UDim2.new(1, 0, 0, 64)

    local statsCountLabel = Instance.new("TextLabel", statsCard)
    statsCountLabel.BackgroundTransparency = 1
    statsCountLabel.Size = UDim2.new(1, -28, 0, 20)
    statsCountLabel.Position = UDim2.new(0, 14, 0, 12)
    statsCountLabel.Font = Enum.Font.GothamBold
    statsCountLabel.TextSize = 14
    statsCountLabel.TextColor3 = C.text
    statsCountLabel.TextXAlignment = Enum.TextXAlignment.Left
    statsCountLabel.Text = "0 blacklisted"
    statsCountLabel.ZIndex = 6
    U.statsCountLabel = statsCountLabel

    local statsSubLabel = Instance.new("TextLabel", statsCard)
    statsSubLabel.BackgroundTransparency = 1
    statsSubLabel.Size = UDim2.new(1, -28, 0, 14)
    statsSubLabel.Position = UDim2.new(0, 14, 0, 36)
    statsSubLabel.Font = Enum.Font.Gotham
    statsSubLabel.TextSize = 10
    statsSubLabel.TextColor3 = C.textMid
    statsSubLabel.TextXAlignment = Enum.TextXAlignment.Left
    statsSubLabel.Text = "current job: " .. (currentServerId and shortId(currentServerId) or "unknown")
    statsSubLabel.ZIndex = 6
    U.statsSubLabel = statsSubLabel

    section(bScroll, "actions", 2)

    local actionRow = Instance.new("Frame", bScroll)
    actionRow.BackgroundTransparency = 1
    actionRow.Size = UDim2.new(1, 0, 0, 44)
    actionRow.LayoutOrder = 3
    actionRow.ZIndex = 5
    local arLayout = Instance.new("UIListLayout", actionRow)
    arLayout.FillDirection = Enum.FillDirection.Horizontal
    arLayout.SortOrder = Enum.SortOrder.LayoutOrder
    arLayout.Padding = UDim.new(0, 8)

    local function actionBtn(txt, width, color, order, cb)
        local b = Instance.new("TextButton", actionRow)
        b.BackgroundColor3 = color or C.accent
        b.BorderSizePixel = 0
        b.Size = UDim2.new(width, 0, 1, 0)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 11
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.Text = txt
        b.AutoButtonColor = false
        b.LayoutOrder = order
        b.ZIndex = 6
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
        local g = Instance.new("UIGradient", b)
        g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255):Lerp(color or C.accent, 0.5), color or C.accent)
        g.Rotation = 90
        local s = Instance.new("UIStroke", b)
        s.Color = Color3.fromRGB(255, 255, 255)
        s.Thickness = 1
        s.Transparency = 0.55
        track(b.MouseEnter:Connect(function()
            tweenService:Create(s, TweenInfo.new(0.18), {Transparency = 0.35}):Play()
        end))
        track(b.MouseLeave:Connect(function()
            tweenService:Create(s, TweenInfo.new(0.22), {Transparency = 0.55}):Play()
        end))
        track(b.MouseButton1Click:Connect(cb))
        return b
    end

    actionBtn("clear all", 0.5, Color3.fromRGB(200, 70, 85), 1, function()
        blacklist = {}
        sessionVisited = {}
        saveBlacklist()
        logWarn("blacklist cleared")
        if U.refreshBlacklist then U.refreshBlacklist() end
    end)
    actionBtn("refresh list", 0.5, C.accent, 2, function()
        if U.refreshBlacklist then U.refreshBlacklist() end
    end)

    section(bScroll, "servers", 4)

    local blListFrame = Instance.new("Frame", bScroll)
    blListFrame.BackgroundTransparency = 1
    blListFrame.Size = UDim2.new(1, 0, 0, 0)
    blListFrame.AutomaticSize = Enum.AutomaticSize.Y
    blListFrame.LayoutOrder = 5
    blListFrame.ZIndex = 5
    local blListLayout = Instance.new("UIListLayout", blListFrame)
    blListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    blListLayout.Padding = UDim.new(0, 6)
    U.blListFrame = blListFrame

    function U.refreshBlacklist()
        if not blListFrame then return end
        for _, c in ipairs(blListFrame:GetChildren()) do
            if not c:IsA("UIListLayout") then c:Destroy() end
        end

        local count = 0
        local ids = {}
        for id in pairs(blacklist) do
            count = count + 1
            table.insert(ids, id)
        end
        table.sort(ids)

        if U.statsCountLabel then
            U.statsCountLabel.Text = count .. " blacklisted"
        end
        if U.statsSubLabel then
            U.statsSubLabel.Text = "current job: " .. (currentServerId and shortId(currentServerId) or "unknown")
        end

        if count == 0 then
            local empty = Instance.new("Frame", blListFrame)
            empty.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            empty.BackgroundTransparency = 0.93
            empty.BorderSizePixel = 0
            empty.Size = UDim2.new(1, 0, 0, 60)
            empty.LayoutOrder = 1
            empty.ZIndex = 6
            Instance.new("UICorner", empty).CornerRadius = UDim.new(0, 10)
            local st = Instance.new("UIStroke", empty)
            st.Color = Color3.fromRGB(255, 255, 255)
            st.Thickness = 1
            st.Transparency = 0.7
            local lbl = Instance.new("TextLabel", empty)
            lbl.BackgroundTransparency = 1
            lbl.Size = UDim2.new(1, -24, 1, 0)
            lbl.Position = UDim2.new(0, 12, 0, 0)
            lbl.Font = Enum.Font.Gotham
            lbl.TextSize = 11
            lbl.TextColor3 = C.textMid
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Text = "no servers blacklisted yet"
            lbl.ZIndex = 7
            return
        end

        for i, id in ipairs(ids) do
            local row = Instance.new("TextButton", blListFrame)
            row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            row.BackgroundTransparency = 0.9
            row.BorderSizePixel = 0
            row.Size = UDim2.new(1, 0, 0, 38)
            row.Text = ""
            row.AutoButtonColor = false
            row.LayoutOrder = i
            row.ZIndex = 6
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
            local rGrad = Instance.new("UIGradient", row)
            rGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(210, 215, 228))
            rGrad.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.88), NumberSequenceKeypoint.new(1, 0.95)})
            rGrad.Rotation = 90
            local rStroke = Instance.new("UIStroke", row)
            rStroke.Color = Color3.fromRGB(255, 255, 255)
            rStroke.Thickness = 1
            rStroke.Transparency = 0.65

            local idLbl = Instance.new("TextLabel", row)
            idLbl.BackgroundTransparency = 1
            idLbl.Size = UDim2.new(1, -100, 1, 0)
            idLbl.Position = UDim2.new(0, 14, 0, 0)
            idLbl.Font = Enum.Font.Code
            idLbl.TextSize = 10
            idLbl.TextColor3 = C.text
            idLbl.TextXAlignment = Enum.TextXAlignment.Left
            idLbl.TextTruncate = Enum.TextTruncate.AtEnd
            idLbl.Text = id
            idLbl.ZIndex = 7

            local delBtn = Instance.new("TextButton", row)
            delBtn.BackgroundColor3 = Color3.fromRGB(200, 70, 85)
            delBtn.BackgroundTransparency = 0.2
            delBtn.BorderSizePixel = 0
            delBtn.Size = UDim2.new(0, 70, 0, 24)
            delBtn.Position = UDim2.new(1, -82, 0.5, -12)
            delBtn.Font = Enum.Font.GothamBold
            delBtn.TextSize = 10
            delBtn.TextColor3 = Color3.fromRGB(255, 240, 245)
            delBtn.Text = "remove"
            delBtn.AutoButtonColor = false
            delBtn.ZIndex = 7
            Instance.new("UICorner", delBtn).CornerRadius = UDim.new(0, 7)
            local dGrad = Instance.new("UIGradient", delBtn)
            dGrad.Color = ColorSequence.new(Color3.fromRGB(220, 90, 105), Color3.fromRGB(160, 50, 65))
            dGrad.Rotation = 90

            track(delBtn.MouseEnter:Connect(function() tw(delBtn, {BackgroundTransparency = 0}, 0.18) end))
            track(delBtn.MouseLeave:Connect(function() tw(delBtn, {BackgroundTransparency = 0.2}, 0.22) end))
            track(delBtn.MouseButton1Click:Connect(function()
                blacklist[id] = nil
                sessionVisited[id] = nil
                saveBlacklist()
                log("removed " .. shortId(id), C.yellow)
                U.refreshBlacklist()
            end))
        end
    end

    -- ===== Minimize / Close / Pill =====
    local minimized = false
    local function setMinimized(state)
        minimized = state
        if state then
            tw(win, {Size = UDim2.new(1, 0, 0, HEADER_H)}, 0.36, Enum.EasingStyle.Quart)
            content.Visible = false
            tabsBar.Visible = false
        else
            content.Visible = true
            tabsBar.Visible = true
            tw(win, {Size = UDim2.new(1, 0, 1, 0)}, 0.4, Enum.EasingStyle.Quart)
        end
    end

    local pill = Instance.new("TextButton", gui)
    pill.BackgroundTransparency = 1
    pill.BorderSizePixel = 0
    pill.Size = UDim2.new(0, 160, 0, 46)
    pill.Position = UDim2.new(0.5, -80, 0, -60)
    pill.Text = ""
    pill.AutoButtonColor = false
    pill.Visible = false
    pill.ZIndex = 200
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

    local pillBg = Instance.new("Frame", pill)
    pillBg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    pillBg.BackgroundTransparency = 0.82
    pillBg.BorderSizePixel = 0
    pillBg.Size = UDim2.new(1, 0, 1, 0)
    pillBg.ZIndex = 200
    Instance.new("UICorner", pillBg).CornerRadius = UDim.new(1, 0)
    local pillGrad = Instance.new("UIGradient", pillBg)
    pillGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(210, 215, 228))
    pillGrad.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.78), NumberSequenceKeypoint.new(1, 0.88)})
    pillGrad.Rotation = 90
    local pillStroke = Instance.new("UIStroke", pillBg)
    pillStroke.Color = Color3.fromRGB(255, 255, 255)
    pillStroke.Thickness = 1
    pillStroke.Transparency = 0.5

    local pillIconBox = Instance.new("Frame", pillBg)
    pillIconBox.BackgroundTransparency = 1
    pillIconBox.Size = UDim2.new(0, 30, 0, 30)
    pillIconBox.Position = UDim2.new(0, 8, 0.5, -15)
    pillIconBox.ZIndex = 201
    Instance.new("UICorner", pillIconBox).CornerRadius = UDim.new(0, 15)
    local pillIcon = Instance.new("ImageLabel", pillIconBox)
    pillIcon.BackgroundTransparency = 1
    pillIcon.Size = UDim2.new(1, 0, 1, 0)
    pillIcon.Image = iconId
    pillIcon.ZIndex = 202
    Instance.new("UICorner", pillIcon).CornerRadius = UDim.new(0, 15)

    local pillTitle = Instance.new("TextLabel", pillBg)
    pillTitle.BackgroundTransparency = 1
    pillTitle.Size = UDim2.new(1, -76, 1, 0)
    pillTitle.Position = UDim2.new(0, 46, 0, 0)
    pillTitle.Font = Enum.Font.GothamBold
    pillTitle.TextSize = 12
    pillTitle.TextColor3 = C.text
    pillTitle.TextXAlignment = Enum.TextXAlignment.Left
    pillTitle.Text = "server hopper"
    pillTitle.ZIndex = 201

    local pillDot = Instance.new("Frame", pillBg)
    pillDot.BackgroundColor3 = C.red
    pillDot.BorderSizePixel = 0
    pillDot.Size = UDim2.new(0, 8, 0, 8)
    pillDot.Position = UDim2.new(1, -24, 0.5, -4)
    pillDot.ZIndex = 201
    Instance.new("UICorner", pillDot).CornerRadius = UDim.new(1, 0)
    U.pillDot = pillDot

    track(pill.MouseEnter:Connect(function() tw(pillBg, {BackgroundTransparency = 0.7}, 0.2) end))
    track(pill.MouseLeave:Connect(function() tw(pillBg, {BackgroundTransparency = 0.82}, 0.24) end))

    local function hideUI()
        pill.Visible = true
        pill.Position = UDim2.new(0.5, -80, 0, -60)
        tw(pill, {Position = UDim2.new(0.5, -80, 0, 14)}, 0.46, Enum.EasingStyle.Back)
        tw(win, {BackgroundTransparency = 1}, 0.16)
        task.delay(0.16, function()
            if not unloaded then container.Visible = false end
        end)
    end

    local function showUI()
        container.Visible = true
        win.BackgroundTransparency = 0
        tw(pill, {Position = UDim2.new(0.5, -80, 0, -60)}, 0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)
        task.delay(0.32, function()
            if not unloaded then pill.Visible = false end
        end)
    end

    track(btnClose.MouseButton1Click:Connect(hideUI))
    track(pill.MouseButton1Click:Connect(showUI))
    track(btnMin.MouseButton1Click:Connect(function()
        setMinimized(not minimized)
    end))

    U.hideUI = hideUI
    U.showUI = showUI

    local versionTag = Instance.new("TextLabel", win)
    versionTag.BackgroundTransparency = 1
    versionTag.Size = UDim2.new(0, 120, 0, 14)
    versionTag.Position = UDim2.new(0, 14, 1, -16)
    versionTag.Font = Enum.Font.Gotham
    versionTag.TextSize = 9
    versionTag.TextColor3 = C.textDim
    versionTag.TextTransparency = 0.45
    versionTag.TextXAlignment = Enum.TextXAlignment.Left
    versionTag.Text = VERSION
    versionTag.ZIndex = 40
end

buildUI()

-- Prime initial theme
local t0 = themes[currentThemeIdx]
if not t0.rainbow then
    for _, listener in ipairs(accentListeners) do
        if listener.obj and listener.obj.Parent then
            if listener.use == "grad" then
                listener.obj.Color = ColorSequence.new(t0.accentHi, t0.accent)
            else
                local target = (listener.use == "hi") and t0.accentHi or t0.accent
                listener.obj[listener.prop] = target
            end
        end
    end
end
if U.themeLabel then U.themeLabel.Text = "theme · " .. t0.name end

if U.refreshBlacklist then U.refreshBlacklist() end

local guiVisible = true
track(userInput.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        guiVisible = not guiVisible
        if guiVisible then
            if U.showUI then U.showUI() end
        else
            if U.hideUI then U.hideUI() end
        end
    elseif input.KeyCode == Enum.KeyCode.F2 and not hopping then
        logInfo("hotkey hop (F2)")
        doHop()
    elseif input.KeyCode == Enum.KeyCode.F3 then
        logInfo("hotkey scan servers (F3)")
        if U.refreshServerScan then U.refreshServerScan() end
    end
end))

local function unload()
    if unloaded then return end
    unloaded = true
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    connections = {}
    if gui and gui.Parent then gui:Destroy() end
    _G.__hopper_loaded = false
    _G.__hopper_unload = nil
    print("[hopper] unloaded")
end

_G.__hopper_unload = unload

do
    local blCount = 0
    for _ in pairs(blacklist) do blCount = blCount + 1 end
    log("session " .. sessionId .. " started")
    log("loaded " .. blCount .. " blacklisted servers")
end
log("current job: " .. (currentServerId and shortId(currentServerId) or "unknown"),
    currentServerId and C.textMid or C.red)
log("hop on join: OFF (resets every session)")
log("rightshift toggle · F2 hop · F3 scan · servers tab = browse")
setStatus("ok", "ready")

if config.hopOnJoin then
    task.spawn(function()
        task.wait(config.autoHopDelay)
        if not hopping then doHop() end
    end)
end
