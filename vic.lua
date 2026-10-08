--// Server Hopper
local players = game:GetService("Players")
local httpService = game:GetService("HttpService")
local userInput = game:GetService("UserInputService")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local teleportService = game:GetService("TeleportService")
local localPlayer = players.LocalPlayer

-- ============ FORWARD REFS (must exist before any function uses them) ============
local U = {}
local accentListeners = {}
local chatLabelRef = nil   -- bound inside buildUI once the log label exists

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
    if chatLabelRef then
        local out = {}
        for _, l in ipairs(sessionLogs) do table.insert(out, l) end
        chatLabelRef.Text = table.concat(out, "\n")
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
            local spring = 220
            local damp = 14
            scaleVelocity = scaleVelocity + (diff * spring - scaleVelocity * damp) * dt
            currentScale = currentScale + scaleVelocity * dt
            containerScale.Scale = currentScale
        elseif currentScale ~= targetScale then
            currentScale = targetScale
            containerScale.Scale = currentScale
            scaleVelocity = 0
        end
    end))

    -- Main Window Body Frame
    local mainFrame = Instance.new("Frame", container)
    mainFrame.BackgroundColor3 = Color3.fromRGB(20, 24, 38)
    mainFrame.BackgroundTransparency = 0.15
    mainFrame.Size = UDim2.new(1, 0, 1, 0)
    mainFrame.BorderSizePixel = 0
    mainFrame.ZIndex = 2
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 16)
    
    local bgGrad = Instance.new("UIGradient", mainFrame)
    bgGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.0, themes[currentThemeIdx].c1),
        ColorSequenceKeypoint.new(0.5, themes[currentThemeIdx].c2),
        ColorSequenceKeypoint.new(1.0, themes[currentThemeIdx].c3),
    })
    bgGrad.Rotation = 45
    U.bgGrad = bgGrad

    draggable(container, mainFrame)

    -- Header
    local header = Instance.new("Frame", mainFrame)
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1, 0, 0, HEADER_H)
    header.ZIndex = 3

    local titleLbl = Instance.new("TextLabel", header)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Position = UDim2.new(0, 16, 0, 0)
    titleLbl.Size = UDim2.new(0, 200, 1, 0)
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextSize = 16
    titleLbl.TextColor3 = C.text
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Text = "Server Hopper"
    titleLbl.ZIndex = 4

    local themeLbl = Instance.new("TextLabel", header)
    themeLbl.BackgroundTransparency = 1
    themeLbl.Position = UDim2.new(0, 16, 0, 22)
    themeLbl.Size = UDim2.new(0, 200, 1, 0)
    themeLbl.Font = Enum.Font.Gotham
    themeLbl.TextSize = 10
    themeLbl.TextColor3 = C.textMid
    themeLbl.TextXAlignment = Enum.TextXAlignment.Left
    themeLbl.Text = "theme · " .. themes[currentThemeIdx].name
    themeLbl.ZIndex = 4
    U.themeLabel = themeLbl

    -- Status Pill in Header
    local pill = Instance.new("Frame", header)
    pill.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    pill.BackgroundTransparency = 0.6
    pill.Size = UDim2.new(0, 100, 0, 24)
    pill.Position = UDim2.new(1, -116, 0.5, -12)
    pill.ZIndex = 4
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

    local pillDot = Instance.new("Frame", pill)
    pillDot.BackgroundColor3 = C.green
    pillDot.Size = UDim2.new(0, 6, 0, 6)
    pillDot.Position = UDim2.new(0, 10, 0.5, -3)
    pillDot.ZIndex = 5
    Instance.new("UICorner", pillDot).CornerRadius = UDim.new(1, 0)
    U.pillDot = pillDot

    local pillText = Instance.new("TextLabel", pill)
    pillText.BackgroundTransparency = 1
    pillText.Position = UDim2.new(0, 22, 0, 0)
    pillText.Size = UDim2.new(1, -22, 1, 0)
    pillText.Font = Enum.Font.GothamMedium
    pillText.TextSize = 10
    pillText.TextColor3 = C.text
    pillText.TextXAlignment = Enum.TextXAlignment.Left
    pillText.Text = "ready"
    pillText.ZIndex = 5
    U.statusText = pillText
    U.statusDot = pillDot

    -- Content Area Container
    local contentArea = Instance.new("Frame", mainFrame)
    contentArea.BackgroundTransparency = 1
    contentArea.Position = UDim2.new(0, 16, 0, HEADER_H + TABS_H + 8)
    contentArea.Size = UDim2.new(1, -32, 1, -(HEADER_H + TABS_H + 24))
    contentArea.ZIndex = 3

    -- Server list tab frame
    local serverListFrame = Instance.new("ScrollingFrame", contentArea)
    serverListFrame.BackgroundTransparency = 1
    serverListFrame.Size = UDim2.new(1, 0, 1, -50)
    serverListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    serverListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    serverListFrame.ScrollBarThickness = 4
    serverListFrame.ZIndex = 5
    U.serverListFrame = serverListFrame

    local listLayout = Instance.new("UIListLayout", serverListFrame)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 6)

    -- Quick hop button at bottom
    local hopBtn = glassButton(contentArea, 44)
    hopBtn.Position = UDim2.new(0, 0, 1, -44)
    local hopBtnText = Instance.new("TextLabel", hopBtn)
    hopBtnText.BackgroundTransparency = 1
    hopBtnText.Size = UDim2.new(1, 0, 1, 0)
    hopBtnText.Font = Enum.Font.GothamBold
    hopBtnText.TextSize = 12
    hopBtnText.TextColor3 = C.text
    hopBtnText.Text = "Hop to Fresh Server Now"
    hopBtnText.ZIndex = 6
    track(hopBtn.MouseButton1Click:Connect(doHop))

    setStatus("ok", "ready")
end

buildUI()
logGood("server hopper initialized (" .. VERSION .. ")")
