--// Server Hopper v0.5 — cool UI + old vicious bee detection
local players = game:GetService("Players")
local httpService = game:GetService("HttpService")
local userInput = game:GetService("UserInputService")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local teleportService = game:GetService("TeleportService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local localPlayer = players.LocalPlayer

-- ============ SINGLE INSTANCE ============
if _G.__hopper_unload then pcall(_G.__hopper_unload) end
_G.__hopper_unload = nil
_G.__hopper_loaded = true

local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request

-- ============ CONSTANTS ============
local VERSION = "v0.5 beta"
local iconId = "rbxthumb://type=Asset&id=79985085633622&w=150&h=150"
local blacklistFile = "hopper_blacklist.json"
local configFile = "hopper_config.json"
local BLACKLIST_TTL = 6 * 3600
local MAX_AUTO_RETRIES = 4
local MAX_SESSION_LOGS = 200
local MAX_ROWS = 120
local WIN_W, WIN_H = 460, 580
local HEADER_H, TABS_H = 58, 36

-- ============ STATE ============
local U = {}
local accentListeners = {}
local connections = {}
local unloaded = false
local chatLabelRef = nil

local function track(c) connections[#connections + 1] = c return c end
local function clamp(n, a, b) return math.max(a, math.min(b, n)) end

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local WHITE = rgb(255, 255, 255)

-- ============ SAFE COLORSEQUENCE ============
local realColorSequenceNew = ColorSequence.new
local function safeCS(...)
    local ok, res = pcall(realColorSequenceNew, ...)
    if ok and typeof(res) == "ColorSequence" then return res end
    warn("[hopper] bad ColorSequence.new call — falling back")
    warn(debug.traceback("", 2))
    return realColorSequenceNew(WHITE, WHITE)
end

local ck, nk = function(t, r, g, b) return ColorSequenceKeypoint.new(t, rgb(r, g, b)) end, NumberSequenceKeypoint.new

local C = {
    text     = rgb(242, 244, 250),
    textMid  = rgb(168, 172, 188),
    textDim  = rgb(118, 122, 140),
    accent   = rgb(120, 170, 245),
    accentHi = rgb(155, 200, 255),
    green    = rgb(130, 220, 165),
    yellow   = rgb(240, 205, 120),
    red      = rgb(240, 130, 140),
}

local themes = {
    {name="midnight", c1=rgb(52,68,130),  c2=rgb(20,28,55), c3=rgb(65,45,110),  accent=rgb(120,170,245), accentHi=rgb(155,200,255)},
    {name="emerald",  c1=rgb(36,100,90),  c2=rgb(18,40,42), c3=rgb(45,80,75),   accent=rgb(105,200,155), accentHi=rgb(140,225,180)},
    {name="crimson",  c1=rgb(130,45,55),  c2=rgb(45,20,28), c3=rgb(100,40,75),  accent=rgb(220,110,120), accentHi=rgb(245,145,155)},
    {name="sunset",   c1=rgb(140,70,45),  c2=rgb(60,32,40), c3=rgb(120,55,90),  accent=rgb(230,160,90),  accentHi=rgb(250,190,120)},
    {name="violet",   c1=rgb(95,55,155),  c2=rgb(38,25,65), c3=rgb(120,55,130), accent=rgb(170,130,235), accentHi=rgb(195,160,255)},
    {name="mono",     c1=rgb(75,75,82),   c2=rgb(38,38,42), c3=rgb(58,58,65),   accent=rgb(180,185,200), accentHi=rgb(210,215,230)},
    {name="rainbow",  c1=rgb(52,68,130),  c2=rgb(20,28,55), c3=rgb(65,45,110),  accent=rgb(120,170,245), accentHi=rgb(155,200,255), rainbow=true},
}

local F = {
    bold = Enum.Font.GothamBold, med = Enum.Font.GothamMedium,
    reg = Enum.Font.Gotham, code = Enum.Font.Code,
}

-- ============ INSTANCE HELPERS ============
local function new(class, props, parent)
    local o = Instance.new(class)
    if props then for k, v in pairs(props) do o[k] = v end end
    o.Parent = parent
    return o
end

local function corner(o, r)
    return new("UICorner", {CornerRadius = (r == "full") and UDim.new(1, 0) or UDim.new(0, r)}, o)
end

local function stroke(o, color, thick, transp)
    return new("UIStroke", {
        Color = color or WHITE, Thickness = thick or 1, Transparency = transp or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, o)
end

local function gradient(o, color, transparency, rot)
    local g = Instance.new("UIGradient")
    g.Rotation = rot or 90
    if color then g.Color = color end
    if transparency then g.Transparency = transparency end
    g.Parent = o
    return g
end

local function lbl(parent, text, font, size, color, props)
    local l = new("TextLabel", {
        BackgroundTransparency = 1, Text = text, Font = font, TextSize = size,
        TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7,
    }, nil)
    if props then for k, v in pairs(props) do l[k] = v end end
    l.Parent = parent
    return l
end

-- ============ TWEEN HELPERS ============
local function lerpNumberSeq(a, b, t)
    local ka, kb = a.Keypoints, b.Keypoints
    if #ka ~= #kb then return b end
    local out = {}
    for i = 1, #ka do
        out[i] = nk(ka[i].Time, ka[i].Value + (kb[i].Value - ka[i].Value) * t,
            ka[i].Envelope + (kb[i].Envelope - ka[i].Envelope) * t)
    end
    return NumberSequence.new(out)
end

local function lerpColorSeq(a, b, t)
    local ka, kb = a.Keypoints, b.Keypoints
    if #ka ~= #kb then return b end
    local out = {}
    for i = 1, #ka do
        out[i] = ColorSequenceKeypoint.new(ka[i].Time, ka[i].Value:Lerp(kb[i].Value, t))
    end
    return safeCS(out)
end

local seqTokens = setmetatable({}, {__mode = "k"})
local function tweenSeq(obj, prop, target, dur, lerp)
    local tok = seqTokens[obj]
    if not tok then tok = {} seqTokens[obj] = tok end
    local id = (tok[prop] or 0) + 1
    tok[prop] = id
    task.spawn(function()
        local from = obj[prop]
        local steps = math.max(6, math.floor(dur * 40))
        for i = 1, steps do
            if unloaded or not obj.Parent or tok[prop] ~= id then return end
            local e = 1 - (1 - i / steps) ^ 3
            obj[prop] = lerp(from, target, e)
            task.wait(dur / steps)
        end
        if not unloaded and obj.Parent and tok[prop] == id then obj[prop] = target end
    end)
end

local function tw(o, p, t, style, dir)
    t = t or 0.24
    if o:IsA("UIGradient") then
        if p.Color ~= nil then tweenSeq(o, "Color", p.Color, t, lerpColorSeq) end
        if p.Transparency ~= nil then tweenSeq(o, "Transparency", p.Transparency, t, lerpNumberSeq) end
        local rest
        for k, v in pairs(p) do
            if k ~= "Color" and k ~= "Transparency" then rest = rest or {} rest[k] = v end
        end
        if not rest then return end
        p = rest
    end
    local tween = tweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out), p)
    tween:Play()
    return tween
end

-- ============ LOGGING ============
local sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
local sessionFile = "hopper_session_" .. sessionId .. ".log"
local sessionLogs = {}

local function diskAppend(path, line)
    if appendfile then pcall(appendfile, path, line .. "\n") return end
    if not (writefile and readfile and isfile) then return end
    local ok, existing = pcall(function() return isfile(path) and readfile(path) or "" end)
    pcall(writefile, path, (ok and existing or "") .. line .. "\n")
end

local function esc(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function renderLogs()
    if not chatLabelRef then return end
    local dim = C.textDim:ToHex()
    local out = table.create(#sessionLogs)
    for i, e in ipairs(sessionLogs) do
        out[i] = ('<font color="#%s">%s</font>  <font color="#%s">%s</font>'):format(dim, e.t, e.color:ToHex(), esc(e.text))
    end
    chatLabelRef.Text = table.concat(out, "\n")
end

local function log(text, color, persist)
    local stamp = os.date("%H:%M:%S")
    sessionLogs[#sessionLogs + 1] = {t = stamp, text = text, color = color or C.textMid}
    if #sessionLogs > MAX_SESSION_LOGS then table.remove(sessionLogs, 1) end
    if persist then diskAppend(sessionFile, "[" .. stamp .. "] " .. text) end
    renderLogs()
end

local function logInfo(t) log(t, C.accent, true) end
local function logGood(t) log(t, C.green, true) end
local function logWarn(t) log(t, C.yellow, true) end
local function logBad(t) log(t, C.red, true) end

if not httpRequest then logWarn("no http request function found — using HttpGet fallback") end

-- ============ CONFIG ============
local config = {
    maxPages = 15, minPlayers = 1, maxPlayerRatio = 0.9,
    autoHopDelay = 4, hopOnJoin = false, preferLessFull = true, skipEmpty = true,
    viciousBeeMode = false,
    viciousBeeAutoRehop = true,
    viciousBeeWaitTime = 6,
    viciousBeeRecheckInterval = 10,
    -- folder names to look inside for the bee (case-insensitive)
    viciousBeeFolders = {"Monsters", "monsters", "Enemies", "enemies", "NPCs", "npcs", "Mobs", "mobs"},
}
local persistConfig = {
    themeIdx = 1, scale = 1, preferLessFull = true, skipEmpty = true, hopOnJoin = false,
    viciousBeeMode = false,
    viciousBeeAutoRehop = true,
}

local function loadConfigFromDisk()
    if not (readfile and isfile and isfile(configFile)) then return end
    local ok, data = pcall(function() return httpService:JSONDecode(readfile(configFile)) end)
    if not (ok and type(data) == "table") then return end
    if type(data.themeIdx) == "number" then persistConfig.themeIdx = data.themeIdx end
    if type(data.scale) == "number" then persistConfig.scale = clamp(data.scale, 0.7, 1.5) end
    for _, k in ipairs({"preferLessFull", "skipEmpty", "hopOnJoin", "viciousBeeMode", "viciousBeeAutoRehop"}) do
        if type(data[k]) == "boolean" then persistConfig[k] = data[k] end
    end
end

local saveCfgPending = false
local function saveConfigToDisk()
    if not writefile or saveCfgPending then return end
    saveCfgPending = true
    task.delay(0.3, function()
        saveCfgPending = false
        pcall(function() writefile(configFile, httpService:JSONEncode(persistConfig)) end)
    end)
end

loadConfigFromDisk()
config.preferLessFull = persistConfig.preferLessFull
config.skipEmpty = persistConfig.skipEmpty
config.hopOnJoin = persistConfig.hopOnJoin
config.maxPlayerRatio = config.preferLessFull and 0.9 or 1.0
config.minPlayers = config.skipEmpty and 1 or 0
config.viciousBeeMode = persistConfig.viciousBeeMode
config.viciousBeeAutoRehop = persistConfig.viciousBeeAutoRehop

local currentThemeIdx = persistConfig.themeIdx
if currentThemeIdx < 1 or currentThemeIdx > #themes then currentThemeIdx = 1 persistConfig.themeIdx = 1 end
local currentScale = persistConfig.scale
local targetScale = persistConfig.scale
local scaleVelocity = 0

-- ============ BLACKLIST ============
local blacklist = {}
local sessionVisited = {}
local expectedJobId = nil

local function pruneBlacklist()
    local now = os.time()
    for id, t in pairs(blacklist) do
        if now - t > BLACKLIST_TTL then blacklist[id] = nil end
    end
end

local function loadBlacklist()
    if not (readfile and isfile and isfile(blacklistFile)) then return end
    local ok, data = pcall(function() return httpService:JSONDecode(readfile(blacklistFile)) end)
    if not (ok and type(data) == "table") then return end
    local now = os.time()
    for k, v in pairs(data) do
        if type(k) == "number" then blacklist[tostring(v)] = now
        elseif type(v) == "number" then blacklist[tostring(k)] = v end
    end
    pruneBlacklist()
end

local saveBlPending = false
local function saveBlacklist()
    if not writefile or saveBlPending then return end
    saveBlPending = true
    task.delay(0.4, function()
        saveBlPending = false
        pcall(function() writefile(blacklistFile, httpService:JSONEncode(blacklist)) end)
    end)
end

loadBlacklist()

local function getCurrentServerId()
    local jid = game.JobId
    return (jid and jid ~= "") and tostring(jid) or nil
end

local currentServerId = getCurrentServerId()

local function markVisited(id)
    if not id then return end
    blacklist[id] = os.time()
    sessionVisited[id] = true
end

if currentServerId then markVisited(currentServerId) saveBlacklist() end

local function isBad(id)
    return id == currentServerId or blacklist[id] ~= nil or sessionVisited[id] == true
end

local function shortId(id)
    id = tostring(id)
    return #id > 10 and id:sub(1, 10) or id
end

-- ============ VICIOUS BEE DETECTION (old Monsters-folder logic) ============
-- Old logic: the Vicious Bee lives inside a "Monsters" folder (or similar)
-- in workspace. Walk that folder and check for anything with "vicious" in the name.
local function isViciousName(name)
    local n = tostring(name):lower()
    return n:find("vicious", 1, true) ~= nil
end

local function checkForViciousBee()
    local scanned = 0
    local containerFound = nil
    local found = nil

    -- Try each known folder name in order
    for _, folderName in ipairs(config.viciousBeeFolders) do
        local folder = workspace:FindFirstChild(folderName)
        if not folder then
            -- also try case-insensitive scan of workspace children (covers odd capitalizations)
            for _, child in ipairs(workspace:GetChildren()) do
                if tostring(child.Name):lower() == folderName:lower() then
                    folder = child
                    break
                end
            end
        end

        if folder then
            containerFound = folder
            local kids = folder:GetChildren()
            for i = 1, #kids do
                scanned = scanned + 1
                local k = kids[i]
                if isViciousName(k.Name) then
                    found = k
                    break
                end
            end
        end
        if found then break end
    end

    -- Fallback: no Monsters folder anywhere — do a shallow workspace scan
    -- for anything named like the bee directly (belt-and-suspenders).
    if not containerFound then
        for _, child in ipairs(workspace:GetChildren()) do
            scanned = scanned + 1
            if isViciousName(child.Name) then
                found = child
                break
            end
        end
    end

    return found, scanned, containerFound
end

-- ============ GUI ROOT + UNLOAD ============
local gui = new("ScreenGui", {
    Name = "hopper", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
}, nil)
do
    local ok, p = pcall(function() return gethui and gethui() end)
    if ok and p then
        local ok2 = pcall(function() gui.Parent = p end)
        if not (ok2 and gui.Parent == p) then gui.Parent = nil end
    end
    if not gui.Parent then gui.Parent = localPlayer:WaitForChild("PlayerGui") end
end

local function unload()
    if unloaded then return end
    unloaded = true
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    if gui then gui:Destroy() end
    if _G.__hopper_unload == unload then _G.__hopper_unload = nil end
    _G.__hopper_loaded = false
    print("[hopper] unloaded")
end
_G.__hopper_unload = unload

-- ============ THEME ENGINE ============
local function registerAccent(obj, prop, use)
    accentListeners[#accentListeners + 1] = {obj = obj, prop = prop, use = use}
end

local function setBg(c1, c2, c3)
    U.shown = {c1, c2, c3}
    if U.bgGrad then
        U.bgGrad.Color = safeCS({
            ColorSequenceKeypoint.new(0, c1),
            ColorSequenceKeypoint.new(0.5, c2),
            ColorSequenceKeypoint.new(1, c3),
        })
    end
end

local function setAccent(listener, hi, base, animated)
    local o = listener.obj
    if not (o and o.Parent) then return end
    if listener.use == "grad" then
        local seq = safeCS(hi, base)
        if animated then tw(o, {Color = seq}, 0.6) else o.Color = seq end
    else
        local target = (listener.use == "hi") and hi or base
        if animated then tw(o, {[listener.prop] = target}, 0.6) else o[listener.prop] = target end
    end
end

local themeToken = 0
local function applyTheme(idx, save, instant)
    if unloaded then return end
    currentThemeIdx = idx
    persistConfig.themeIdx = idx
    if save then saveConfigToDisk() end
    local t = themes[idx]
    if U.themeLabel then U.themeLabel.Text = "theme · " .. t.name end
    themeToken = themeToken + 1
    local id = themeToken
    if t.rainbow then return end

    local from = U.shown or {t.c1, t.c2, t.c3}
    if instant then
        setBg(t.c1, t.c2, t.c3)
    else
        task.spawn(function()
            for s = 1, 24 do
                if unloaded or themeToken ~= id then return end
                local e = 1 - (1 - s / 24) ^ 3
                setBg(from[1]:Lerp(t.c1, e), from[2]:Lerp(t.c2, e), from[3]:Lerp(t.c3, e))
                task.wait(0.03)
            end
        end)
    end
    for _, pair in ipairs({{U.orb1, t.c1}, {U.orb2, t.c3}, {U.orb3, t.c2}}) do
        local orb, col = pair[1], pair[2]
        if orb then
            if instant then orb.BackgroundColor3 = col
            else tweenService:Create(orb, TweenInfo.new(0.9, Enum.EasingStyle.Quart), {BackgroundColor3 = col}):Play() end
        end
    end
    for _, l in ipairs(accentListeners) do setAccent(l, t.accentHi, t.accent, not instant) end
end

do
    local hue, acc = 0, 0
    track(runService.Heartbeat:Connect(function(dt)
        if unloaded or not themes[currentThemeIdx].rainbow then return end
        if not (U.container and U.container.Visible) then return end
        hue = (hue + dt * 0.08) % 1
        acc = acc + dt
        if acc < 1 / 30 then return end
        acc = 0
        setBg(Color3.fromHSV(hue, 0.55, 0.55), Color3.fromHSV(hue, 0.55, 0.22), Color3.fromHSV(hue, 0.55, 0.45))
        if U.orb1 then U.orb1.BackgroundColor3 = Color3.fromHSV(hue, 0.55, 0.5) end
        if U.orb2 then U.orb2.BackgroundColor3 = Color3.fromHSV(hue, 0.55, 0.45) end
        if U.orb3 then U.orb3.BackgroundColor3 = Color3.fromHSV(hue, 0.55, 0.35) end
        local hi, base = Color3.fromHSV(hue, 0.45, 1), Color3.fromHSV(hue, 0.55, 1)
        for _, l in ipairs(accentListeners) do setAccent(l, hi, base, false) end
    end))
end

-- ============ STATUS ============
local function setStatus(state, txt)
    local col, label = C.red, txt or "idle"
    if state == "ok" then col, label = C.green, txt or "ready"
    elseif state == "loading" then col, label = C.yellow, txt or "scanning"
    elseif state == "bee" then col, label = rgb(255, 200, 60), txt or "bee found" end
    if U.statusDot then tw(U.statusDot, {BackgroundColor3 = col}, 0.36) end
    if U.statusRing then tw(U.statusRing, {Color = col}, 0.36) end
    if U.pillDot then tw(U.pillDot, {BackgroundColor3 = col}, 0.36) end
    if U.statusText then U.statusText.Text = label end
end

-- ============ FETCH / SCAN ============
local function fetchPage(cursor)
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&excludeFullGames=true&limit=100")
        :format(game.PlaceId, config.preferLessFull and "Asc" or "Desc")
    if cursor and cursor ~= "" then url = url .. "&cursor=" .. httpService:UrlEncode(cursor) end

    for attempt = 1, 3 do
        local body
        if httpRequest then
            local ok, res = pcall(httpRequest, {Url = url, Method = "GET"})
            if ok and type(res) == "table" then body = res.Body end
        end
        if not body then
            local ok, res = pcall(game.HttpGet, game, url)
            if ok then body = res end
        end
        if body then
            local ok, data = pcall(httpService.JSONDecode, httpService, body)
            if ok and type(data) == "table" and type(data.data) == "table" then return data end
        end
        if unloaded then return nil end
        task.wait(1.5 * attempt)
    end
    return nil
end

local function scanServers(stopAt, onPage)
    local all, candidates = {}, {}
    local stats = {total = 0, bad = 0, full = 0, empty = 0, crowded = 0, failed = false}
    local cursor
    for page = 1, config.maxPages do
        if unloaded then break end
        local data = fetchPage(cursor)
        if not data then stats.failed = true break end
        for _, s in ipairs(data.data) do
            local e = {id = tostring(s.id), playing = s.playing or 0, maxPlayers = s.maxPlayers or 0, ping = s.ping}
            all[#all + 1] = e
            stats.total = stats.total + 1
            if isBad(e.id) then stats.bad = stats.bad + 1
            elseif e.playing >= e.maxPlayers then stats.full = stats.full + 1
            elseif e.playing < config.minPlayers then stats.empty = stats.empty + 1
            elseif config.maxPlayerRatio < 1 and (e.playing / e.maxPlayers >= config.maxPlayerRatio or e.maxPlayers - e.playing < 2) then
                stats.crowded = stats.crowded + 1
            else
                candidates[#candidates + 1] = e
            end
        end
        if onPage then onPage(page, #all) end
        cursor = data.nextPageCursor
        if not cursor or cursor == "" or (stopAt and #candidates >= stopAt) then break end
    end
    return all, candidates, stats
end

-- ============ HOP LOGIC ============
local hopping, hopToken, hopAttempts, retryOnFail = false, 0, 0, false
local doHop

local function failTeleport(reason)
    if not hopping then return end
    logWarn("teleport failed: " .. tostring(reason))
    hopping = false
    hopToken = hopToken + 1
    if retryOnFail and hopAttempts < MAX_AUTO_RETRIES then
        hopAttempts = hopAttempts + 1
        logInfo("retry " .. hopAttempts .. "/" .. MAX_AUTO_RETRIES)
        setStatus("loading", "retrying")
        task.delay(1.5, function() if not unloaded then doHop(true) end end)
    else
        if retryOnFail then logBad("giving up after " .. MAX_AUTO_RETRIES .. " failed attempts") end
        setStatus("ok", "ready")
    end
end

local function beginTeleport(id, auto)
    hopping = true
    hopToken = hopToken + 1
    local my = hopToken
    retryOnFail = auto
    expectedJobId = id
    setStatus("loading", "hopping")
    markVisited(currentServerId)
    markVisited(id)
    saveBlacklist()
    task.wait(auto and 0.7 or 0.5)
    if unloaded or hopToken ~= my then return end

    local ok = pcall(function() teleportService:TeleportToPlaceInstance(game.PlaceId, id, localPlayer) end)
    if not ok then
        ok = pcall(function()
            local opts = Instance.new("TeleportOptions")
            opts.ServerInstanceId = id
            opts.ShouldReserveServer = false
            teleportService:TeleportAsync(game.PlaceId, {localPlayer}, opts)
        end)
    end
    if not ok then failTeleport("request rejected") return end

    task.delay(20, function()
        if hopping and hopToken == my and not unloaded then
            logWarn("teleport timed out")
            hopping = false
            hopToken = hopToken + 1
            setStatus("ok", "ready")
        end
    end)
end

track(teleportService.TeleportInitFailed:Connect(function(player, result, msg)
    if player == localPlayer and hopping then failTeleport(msg ~= "" and msg or result) end
end))

doHop = function(isRetry)
    if hopping then return end
    if not isRetry then hopAttempts = 0 end
    hopping = true
    hopToken = hopToken + 1
    local my = hopToken
    setStatus("loading", "scanning")
    logInfo("hopping — session " .. sessionId)

    task.spawn(function()
        local chosen
        for attempt = 1, MAX_AUTO_RETRIES do
            if unloaded or hopToken ~= my then return end
            logInfo("scanning for open servers...")
            local all, candidates, stats = scanServers(80)
            log("scanned " .. stats.total .. " · skipped " .. stats.bad .. " visited, " ..
                stats.full .. " full, " .. stats.crowded .. " crowded")
            if #candidates > 0 then
                logGood("found " .. #candidates .. " candidates")
                local less = config.preferLessFull
                table.sort(candidates, function(a, b)
                    if a.playing ~= b.playing then
                        if less then return a.playing < b.playing end
                        return a.playing > b.playing
                    end
                    return a.id < b.id
                end)
                chosen = candidates[math.random(1, math.max(1, math.floor(#candidates / 3)))]
                break
            end
            logBad(stats.failed and "scan failed — http error or rate limit" or "no fresh servers available")
            if attempt < MAX_AUTO_RETRIES then
                logWarn("retry " .. attempt .. "/" .. MAX_AUTO_RETRIES .. " in 3s")
                task.wait(3)
            end
        end

        if unloaded or hopToken ~= my then return end
        if not chosen then
            logBad("giving up after " .. MAX_AUTO_RETRIES .. " attempts")
            hopping = false
            hopToken = hopToken + 1
            setStatus("ok", "ready")
            return
        end
        logGood("selected " .. shortId(chosen.id) .. " (" .. chosen.playing .. "/" .. chosen.maxPlayers .. ")")
        beginTeleport(chosen.id, true)
    end)
end

-- ============ UI COMPONENTS ============
local function emptyState(parent, text)
    local f = new("Frame", {
        BackgroundColor3 = WHITE, BackgroundTransparency = 0.93, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 1, ZIndex = 6,
    }, parent)
    corner(f, 10)
    stroke(f, WHITE, 1, 0.7)
    lbl(f, text, F.reg, 11, C.textMid, {Size = UDim2.new(1, -24, 1, 0), Position = UDim2.new(0, 12, 0, 0)})
end

local function glassSurface(parent, order)
    local f = new("Frame", {
        BackgroundColor3 = WHITE, BackgroundTransparency = 0.9, BorderSizePixel = 0,
        ZIndex = 5, LayoutOrder = order or 0,
    }, parent)
    corner(f, 12)
    gradient(f, safeCS({ck(0, 255, 255, 255), ck(0.6, 230, 232, 240), ck(1, 200, 205, 218)}),
        NumberSequence.new(0.86, 0.94), 90)
    local st = stroke(f, WHITE, 1, 0)
    gradient(st, safeCS({ck(0, 255, 255, 255), ck(0.5, 200, 210, 230), ck(1, 140, 148, 168)}),
        NumberSequence.new({nk(0, 0.4), nk(0.5, 0.68), nk(1, 0.85)}), 90)
    return f
end

local function glassButton(parent, height, order)
    local b = new("TextButton", {
        BackgroundColor3 = WHITE, BackgroundTransparency = 0.88, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, height or 44), Text = "", AutoButtonColor = false,
        ZIndex = 5, LayoutOrder = order or 0,
    }, parent)
    corner(b, 10)
    local g = gradient(b, safeCS(WHITE, rgb(210, 214, 226)), NumberSequence.new(0.85, 0.93), 90)
    local st = stroke(b, WHITE, 1, 0)
    local sg = gradient(st, safeCS(WHITE, rgb(150, 158, 178)), NumberSequence.new(0.5, 0.82), 90)
    b.MouseEnter:Connect(function()
        tw(g, {Transparency = NumberSequence.new(0.78, 0.88)}, 0.22)
        tw(sg, {Transparency = NumberSequence.new(0.35, 0.7)}, 0.22)
    end)
    b.MouseLeave:Connect(function()
        tw(g, {Transparency = NumberSequence.new(0.85, 0.93)}, 0.26)
        tw(sg, {Transparency = NumberSequence.new(0.5, 0.82)}, 0.26)
    end)
    return b
end

local function makeBtn(parent, o)
    local z = o.z or 6
    local b = new("TextButton", {
        BackgroundColor3 = o.bg or WHITE, BackgroundTransparency = o.bgT or 0, BorderSizePixel = 0,
        Size = o.size, Position = o.pos or UDim2.new(), Text = "", AutoButtonColor = false,
        LayoutOrder = o.order or 0, ZIndex = z,
    }, parent)
    corner(b, o.r or 8)
    local g = gradient(b, o.grad, nil, 90)
    local s = stroke(b, WHITE, 1, o.strokeT or 0.55)
    local l = lbl(b, o.text or "", o.font or F.bold, o.tsize or 11, o.tcolor or WHITE, {
        Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 1,
    })
    return b, l, g, s
end

local function hoverStroke(b, s)
    b.MouseEnter:Connect(function() tw(s, {Transparency = 0.35}, 0.18) end)
    b.MouseLeave:Connect(function() tw(s, {Transparency = 0.55}, 0.22) end)
end

local function draggable(frame, handle)
    local dragging, startPos, origin
    local function isPointer(i)
        return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
    end
    handle.InputBegan:Connect(function(i)
        if isPointer(i) then dragging, startPos, origin = true, i.Position, frame.Position end
    end)
    track(userInput.InputEnded:Connect(function(i) if isPointer(i) then dragging = false end end))
    track(userInput.InputChanged:Connect(function(i)
        if not dragging then return end
        if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
            local d = i.Position - startPos
            frame.Position = UDim2.new(origin.X.Scale, origin.X.Offset + d.X, origin.Y.Scale, origin.Y.Offset + d.Y)
        end
    end))
end

local function section(parent, txt, order)
    local f = new("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = order or 0, ZIndex = 5}, parent)
    new("UIPadding", {PaddingLeft = UDim.new(0, 4)}, f)
    lbl(f, string.upper(txt), F.bold, 10, C.textDim, {Size = UDim2.new(1, 0, 1, 0), ZIndex = 6})
end

local function scroller(page)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 18),
        PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
    }, page)
    local s = new("ScrollingFrame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0),
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 2, ScrollBarImageColor3 = WHITE, ScrollBarImageTransparency = 0.7, ZIndex = 5,
    }, page)
    new("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8)}, s)
    return s
end

local function toggleRow(parent, label, initial, cb, order, persistKey)
    local b = glassButton(parent, 48, order)
    new("UIPadding", {PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16)}, b)
    lbl(b, label, F.med, 12, C.text, {Size = UDim2.new(1, -84, 1, 0), ZIndex = 6})
    local PW, PH, K = 40, 22, 18
    local off = rgb(64, 66, 78)
    local trackF = new("Frame", {
        Size = UDim2.new(0, PW, 0, PH), Position = UDim2.new(1, -PW, 0.5, -PH / 2),
        BackgroundColor3 = initial and C.green or off, BorderSizePixel = 0, ZIndex = 6,
    }, b)
    corner(trackF, "full")
    local knob = new("Frame", {
        Size = UDim2.new(0, K, 0, K), Position = UDim2.new(0, initial and (PW - K - 2) or 2, 0.5, -K / 2),
        BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 7,
    }, trackF)
    corner(knob, "full")
    local state = initial
    b.MouseButton1Click:Connect(function()
        state = not state
        tw(knob, {Position = UDim2.new(0, state and (PW - K - 2) or 2, 0.5, -K / 2)}, 0.4, Enum.EasingStyle.Back)
        tw(trackF, {BackgroundColor3 = state and C.green or off}, 0.28)
        if persistKey then persistConfig[persistKey] = state saveConfigToDisk() end
        cb(state)
    end)
    return b
end

-- ============ SERVER LIST ============
local renderToken = 0
function U.renderServerList(list)
    local frame = U.serverListFrame
    if not frame then return end
    renderToken = renderToken + 1
    local my = renderToken
    for _, c in ipairs(frame:GetChildren()) do
        if not c:IsA("UIListLayout") then c:Destroy() end
    end
    if not list or #list == 0 then emptyState(frame, "no servers found — try refresh") return end

    for _, s in ipairs(list) do s.bad = isBad(s.id) s.cur = (s.id == currentServerId) s.isFull = s.playing >= s.maxPlayers end
    table.sort(list, function(a, b)
        if a.cur ~= b.cur then return a.cur end
        if a.bad ~= b.bad then return not a.bad end
        if a.isFull ~= b.isFull then return not a.isFull end
        if a.playing ~= b.playing then return a.playing > b.playing end
        return a.id < b.id
    end)

    for i = 1, math.min(#list, MAX_ROWS) do
        if unloaded or renderToken ~= my then return end
        local s = list[i]
        local row = new("TextButton", {
            BackgroundColor3 = WHITE, BackgroundTransparency = s.cur and 0.78 or 0.9, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 38), Text = "", AutoButtonColor = false, LayoutOrder = i, ZIndex = 6,
        }, frame)
        corner(row, 10)
        gradient(row, s.cur and safeCS(rgb(140, 180, 240), rgb(80, 120, 190))
            or safeCS(WHITE, rgb(210, 215, 228)), NumberSequence.new(0.88, 0.95), 90)
        stroke(row, WHITE, 1, 0.65)

        local dotColor = s.cur and C.green or (s.bad and C.red or (s.isFull and C.yellow or C.accent))
        local dot = new("Frame", {
            Size = UDim2.new(0, 7, 0, 7), Position = UDim2.new(0, 14, 0.5, -3),
            BackgroundColor3 = dotColor, BorderSizePixel = 0, ZIndex = 7,
        }, row)
        corner(dot, "full")
        lbl(row, s.id, F.code, 10, C.text, {
            Size = UDim2.new(1, -180, 1, 0), Position = UDim2.new(0, 28, 0, 0),
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        lbl(row, s.playing .. "/" .. s.maxPlayers .. ((s.ping and s.ping > 0) and ("  " .. s.ping .. "ms") or ""),
            F.code, 10, s.isFull and C.yellow or (s.cur and C.green or C.textMid), {
            Size = UDim2.new(0, 90, 1, 0), Position = UDim2.new(1, -96, 0, 0),
            TextXAlignment = Enum.TextXAlignment.Right,
        })

        row.MouseButton1Click:Connect(function()
            if hopping then logWarn("already hopping...") return end
            if s.cur then logWarn("already in that server") return end
            logInfo("manual jump to " .. shortId(s.id))
            beginTeleport(s.id, false)
        end)

        if i % 25 == 0 then task.wait() end
    end

    if #list > MAX_ROWS and renderToken == my then
        lbl(frame, "+ " .. (#list - MAX_ROWS) .. " more not shown", F.reg, 10, C.textDim, {
            Size = UDim2.new(1, 0, 0, 20), LayoutOrder = MAX_ROWS + 1,
            TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6,
        })
    end
end

function U.refreshServerScan()
    if U.scanInProgress then return end
    U.scanInProgress = true
    if not hopping then setStatus("loading", "scanning") end
    logInfo("scanning all servers...")
    task.spawn(function()
        local all, _, stats = scanServers(nil, function(page, count)
            if U.serverListStatus then U.serverListStatus.Text = "page " .. page .. " · " .. count .. " servers" end
        end)
        if #all == 0 and stats.failed then logBad("scan failed — http error or rate limit")
        else logGood("scan complete: " .. #all .. " servers") end
        U.lastScanAt = os.clock()
        U.scanInProgress = false
        if unloaded then return end
        U.renderServerList(all)
        if U.serverListStatus then
            U.serverListStatus.Text = #all .. " servers · " .. (currentServerId and shortId(currentServerId) or "?")
        end
        if not hopping then setStatus("ok", "ready") end
    end)
end

-- ============ BUILD UI ============
local guiVisible = true

local function buildUI()
    local container = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(0, WIN_W, 0, WIN_H),
        Position = UDim2.new(0, 40, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 1,
    }, gui)
    U.container = container
    local containerScale = new("UIScale", {Scale = currentScale}, container)

    track(runService.RenderStepped:Connect(function(dt)
        if unloaded then return end
        local diff = targetScale - currentScale
        if math.abs(diff) < 0.0005 and math.abs(scaleVelocity) < 0.0005 then
            if currentScale ~= targetScale then currentScale = targetScale containerScale.Scale = currentScale end
            return
        end
        dt = math.min(dt, 0.1)
        scaleVelocity = scaleVelocity + (diff * 320 - scaleVelocity * 26) * dt
        currentScale = currentScale + scaleVelocity * dt
        containerScale.Scale = currentScale
    end))

    local win = new("Frame", {
        BackgroundColor3 = rgb(14, 14, 20), BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0),
        Active = true, ClipsDescendants = true, ZIndex = 1,
    }, container)
    corner(win, 16)
    local winStroke = stroke(win, WHITE, 1, 0)
    gradient(winStroke, safeCS(WHITE, rgb(140, 148, 168)), NumberSequence.new(0.5, 0.88), 90)

    local bgLayer = new("Frame", {
        BackgroundColor3 = rgb(14, 14, 20), BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 0, ClipsDescendants = true,
    }, win)
    corner(bgLayer, 16)
    local t0 = themes[currentThemeIdx]
    local bgGrad = gradient(bgLayer, safeCS(rgb(0, 0, 0), rgb(0, 0, 0)), nil, 35)
    U.bgGrad = bgGrad
    setBg(t0.c1, t0.c2, t0.c3)
    bgGrad.Transparency = NumberSequence.new({nk(0, 0.4), nk(0.5, 0.62), nk(1, 0.4)})

    local overlay = new("Frame", {
        BackgroundColor3 = rgb(10, 10, 14), BackgroundTransparency = 0.6, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0), ZIndex = 1,
    }, bgLayer)
    corner(overlay, 16)

    local function makeOrb(color, size, startPos, d1, d2, dur, baseTrans)
        local o = new("Frame", {
            BackgroundColor3 = color, BackgroundTransparency = baseTrans, BorderSizePixel = 0,
            Size = UDim2.new(0, size, 0, size), Position = startPos, ZIndex = 2,
        }, bgLayer)
        corner(o, "full")
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
    U.orb1 = makeOrb(t0.c1, 320, UDim2.new(-0.35, 0, -0.2, 0), UDim2.new(0.55, 0, -0.1, 0), UDim2.new(-0.05, 0, 0.55, 0), 16, 0.72)
    U.orb2 = makeOrb(t0.c3, 280, UDim2.new(0.7, 0, 0.5, 0), UDim2.new(0.15, 0, 0.95, 0), UDim2.new(0.9, 0, 0.1, 0), 20, 0.78)
    U.orb3 = makeOrb(t0.c2, 240, UDim2.new(0.3, 0, 0.7, 0), UDim2.new(-0.15, 0, 0.9, 0), UDim2.new(0.75, 0, -0.05, 0), 24, 0.82)

    -- HEADER
    local header = new("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, HEADER_H), ZIndex = 5}, win)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16),
        PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
    }, header)
    draggable(container, header)

    local hLeft = new("Frame", {BackgroundTransparency = 1, Size = UDim2.new(0.55, 0, 1, 0), ZIndex = 6}, header)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 11),
    }, hLeft)

    local iconBox = new("Frame", {
        BackgroundColor3 = WHITE, BackgroundTransparency = 0.85, BorderSizePixel = 0,
        Size = UDim2.new(0, 34, 0, 34), LayoutOrder = 1, ZIndex = 6,
    }, hLeft)
    corner(iconBox, 9)
    gradient(iconBox, safeCS(WHITE, rgb(200, 205, 218)), nil, 90)
    stroke(iconBox, WHITE, 1, 0.5)
    local iconImg = new("ImageLabel", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Image = iconId, ZIndex = 7}, iconBox)
    corner(iconImg, 9)

    local titleStack = new("Frame", {BackgroundTransparency = 1, Size = UDim2.new(0, 150, 1, 0), LayoutOrder = 2, ZIndex = 6}, hLeft)
    lbl(titleStack, "server hopper", F.bold, 14, C.text, {Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 3)})
    U.headerSub = lbl(titleStack, "session " .. sessionId, F.reg, 10, C.textDim, {Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 19)})

    local hRight = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(0.45, 0, 1, 0), Position = UDim2.new(0.55, 0, 0, 0), ZIndex = 6,
    }, header)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
    }, hRight)

    local statusWrap = new("Frame", {BackgroundTransparency = 1, Size = UDim2.new(0, 84, 1, 0), LayoutOrder = 1, ZIndex = 6}, hRight)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6),
    }, statusWrap)
    U.statusText = lbl(statusWrap, "idle", F.med, 11, C.textMid, {
        Size = UDim2.new(0, 66, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 1,
    })
    U.statusDot = new("Frame", {
        BackgroundColor3 = C.red, BorderSizePixel = 0, Size = UDim2.new(0, 7, 0, 7), LayoutOrder = 2, ZIndex = 7,
    }, statusWrap)
    corner(U.statusDot, "full")
    U.statusRing = stroke(U.statusDot, C.red, 1, 0.6)

    local function iconBtn(txt, order)
        local b, l = makeBtn(hRight, {
            size = UDim2.new(0, 24, 0, 24), bg = WHITE, bgT = 0.85, r = 7, order = order,
            grad = safeCS(WHITE, rgb(210, 215, 228)), text = txt, tsize = 14,
            tcolor = C.textMid, strokeT = 0.55,
        })
        return b, l
    end
    local btnMin, minL = iconBtn("−", 2)
    local btnClose, closeL = iconBtn("×", 3)

    btnClose.MouseEnter:Connect(function()
        tw(btnClose, {BackgroundColor3 = rgb(200, 70, 85), BackgroundTransparency = 0.15}, 0.18)
        tw(closeL, {TextColor3 = rgb(255, 240, 245)}, 0.18)
    end)
    btnClose.MouseLeave:Connect(function()
        tw(btnClose, {BackgroundColor3 = WHITE, BackgroundTransparency = 0.85}, 0.22)
        tw(closeL, {TextColor3 = C.textMid}, 0.22)
    end)
    btnMin.MouseEnter:Connect(function() tw(btnMin, {BackgroundTransparency = 0.7}, 0.18) tw(minL, {TextColor3 = C.text}, 0.18) end)
    btnMin.MouseLeave:Connect(function() tw(btnMin, {BackgroundTransparency = 0.85}, 0.22) tw(minL, {TextColor3 = C.textMid}, 0.22) end)

    -- TABS
    local tabsBar = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, TABS_H), Position = UDim2.new(0, 0, 0, HEADER_H), ZIndex = 5,
    }, win)
    local tabNames = {"logs", "servers", "config", "blacklist"}
    local tabBtns, tabPages = {}, {}
    local activeTab = "logs"
    local tabW = 1 / #tabNames

    for i, name in ipairs(tabNames) do
        tabBtns[name] = new("TextButton", {
            BackgroundTransparency = 1, Size = UDim2.new(tabW, 0, 1, 0), Position = UDim2.new((i - 1) * tabW, 0, 0, 0),
            Font = F.med, TextSize = 12, TextColor3 = C.textDim, Text = name, AutoButtonColor = false, ZIndex = 6,
        }, tabsBar)
    end

    local tabUnderline = new("Frame", {
        BackgroundColor3 = WHITE, BackgroundTransparency = 0.3, BorderSizePixel = 0,
        Size = UDim2.new(tabW, -80, 0, 3), Position = UDim2.new(0, 40, 1, -4), ZIndex = 7,
    }, tabsBar)
    corner(tabUnderline, "full")
    local tuG = gradient(tabUnderline, safeCS(C.accentHi, C.accent),
        NumberSequence.new({nk(0, 0.6), nk(0.5, 0), nk(1, 0.6)}), 0)
    registerAccent(tuG, "Color", "grad")

    local content = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -HEADER_H - TABS_H),
        Position = UDim2.new(0, 0, 0, HEADER_H + TABS_H), ClipsDescendants = true, ZIndex = 4,
    }, win)
    for _, name in ipairs(tabNames) do
        tabPages[name] = new("Frame", {
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Visible = (name == activeTab), ZIndex = 4,
        }, content)
    end

    local function switchTab(name)
        if name == activeTab then return end
        activeTab = name
        local page = tabPages[name]
        page.Visible = true
        for n, p in pairs(tabPages) do if n ~= name then p.Visible = false end end
        local veil = new("Frame", {
            BackgroundColor3 = rgb(10, 10, 14), BackgroundTransparency = 0.5, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 1, 0), ZIndex = 70,
        }, page)
        tw(veil, {BackgroundTransparency = 1}, 0.32)
        task.delay(0.34, function() if veil.Parent then veil:Destroy() end end)
        tw(tabUnderline, {Position = UDim2.new((table.find(tabNames, name) - 1) * tabW, 40, 1, -4)}, 0.4)
        for n, b in pairs(tabBtns) do tw(b, {TextColor3 = (n == name) and C.text or C.textDim}, 0.24) end
        if name == "servers" and (not U.lastScanAt or os.clock() - U.lastScanAt > 60) then U.refreshServerScan() end
        if name == "blacklist" and U.refreshBlacklist then U.refreshBlacklist() end
    end
    for n, b in pairs(tabBtns) do b.MouseButton1Click:Connect(function() switchTab(n) end) end
    tabBtns[activeTab].TextColor3 = C.text

    -- LOGS TAB
    local logsPage = tabPages.logs
    local chatCard = glassSurface(logsPage)
    chatCard.Size = UDim2.new(1, -28, 1, -112)
    chatCard.Position = UDim2.new(0, 14, 0, 14)

    local chatScroll = new("ScrollingFrame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -28, 1, -28), Position = UDim2.new(0, 14, 0, 14),
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 2,
        ScrollBarImageColor3 = WHITE, ScrollBarImageTransparency = 0.7, ZIndex = 6,
    }, chatCard)
    local chatLabel = lbl(chatScroll, "", F.code, 11, C.text, {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true, RichText = true, LineHeight = 1.45,
    })
    chatLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        chatScroll.CanvasPosition = Vector2.new(0, math.max(0, chatScroll.AbsoluteCanvasSize.Y - chatScroll.AbsoluteWindowSize.Y))
    end)
    chatLabelRef = chatLabel
    renderLogs()

    local inputBar = glassSurface(logsPage)
    inputBar.Size = UDim2.new(1, -28, 0, 70)
    inputBar.Position = UDim2.new(0, 14, 1, -92)
    lbl(inputBar, "HOP CONTROL", F.bold, 10, C.textDim, {Size = UDim2.new(1, -28, 0, 14), Position = UDim2.new(0, 14, 0, 10)})

    local hopBtn, _, sbGrad, sbStroke = makeBtn(inputBar, {
        size = UDim2.new(0.55, -16, 0, 32), pos = UDim2.new(0, 14, 0, 30), bg = C.accent,
        grad = safeCS(C.accentHi, C.accent), text = "hop now", tsize = 12,
    })
    registerAccent(hopBtn, "BackgroundColor3", "accent")
    registerAccent(sbGrad, "Color", "grad")
    hoverStroke(hopBtn, sbStroke)

    local clearBtn = makeBtn(inputBar, {
        size = UDim2.new(0.45, -16, 0, 32), pos = UDim2.new(0.55, 2, 0, 30), bg = WHITE, bgT = 0.8,
        grad = safeCS(WHITE, rgb(210, 215, 228)), text = "clear log", tcolor = C.text,
    })
    clearBtn.MouseEnter:Connect(function() tw(clearBtn, {BackgroundTransparency = 0.7}, 0.18) end)
    clearBtn.MouseLeave:Connect(function() tw(clearBtn, {BackgroundTransparency = 0.8}, 0.22) end)

    hopBtn.MouseButton1Click:Connect(function()
        if hopping then logWarn("already hopping...") return end
        logInfo("manual hop triggered")
        doHop()
    end)
    clearBtn.MouseButton1Click:Connect(function() sessionLogs = {} renderLogs() end)

    -- SERVERS TAB
    local sScroll = scroller(tabPages.servers)
    section(sScroll, "scanner", 0)
    local serverStatusCard = glassSurface(sScroll, 1)
    serverStatusCard.Size = UDim2.new(1, 0, 0, 60)
    U.serverListStatus = lbl(serverStatusCard, "click refresh to scan", F.bold, 12, C.text, {
        Size = UDim2.new(1, -120, 1, 0), Position = UDim2.new(0, 16, 0, 0), ZIndex = 6,
    })
    local refreshBtn, _, rsbGrad, rsbStroke = makeBtn(serverStatusCard, {
        size = UDim2.new(0, 88, 0, 32), pos = UDim2.new(1, -104, 0.5, -16), bg = C.accent,
        grad = safeCS(C.accentHi, C.accent), text = "refresh",
    })
    registerAccent(refreshBtn, "BackgroundColor3", "accent")
    registerAccent(rsbGrad, "Color", "grad")
    hoverStroke(refreshBtn, rsbStroke)
    refreshBtn.MouseButton1Click:Connect(function() U.refreshServerScan() end)

    section(sScroll, "all servers · click to jump", 2)
    local serverListFrame = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, ZIndex = 5,
    }, sScroll)
    new("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6)}, serverListFrame)
    U.serverListFrame = serverListFrame
    emptyState(serverListFrame, "click refresh to scan servers")

    -- CONFIG TAB
    local tScroll = scroller(tabPages.config)
    section(tScroll, "appearance", 0)

    local themeCard = glassSurface(tScroll, 1)
    themeCard.Size = UDim2.new(1, 0, 0, 72)
    U.themeLabel = lbl(themeCard, "theme · " .. themes[currentThemeIdx].name, F.bold, 10, C.textDim, {
        Size = UDim2.new(1, -28, 0, 14), Position = UDim2.new(0, 14, 0, 12), ZIndex = 6,
    })
    local swatchRow = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, -28, 0, 28), Position = UDim2.new(0, 14, 0, 32), ZIndex = 6,
    }, themeCard)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Center,
    }, swatchRow)

    local swatchStrokes = {}
    for i, t in ipairs(themes) do
        local sw = new("TextButton", {
            BackgroundColor3 = t.rainbow and WHITE or t.c1, BorderSizePixel = 0, Size = UDim2.new(0, 26, 0, 26),
            Text = "", AutoButtonColor = false, LayoutOrder = i, ZIndex = 6,
        }, swatchRow)
        if t.rainbow then
            gradient(sw, safeCS({
                ck(0, 255, 80, 80), ck(0.25, 255, 220, 80), ck(0.5, 120, 255, 120), ck(0.75, 120, 180, 255), ck(1, 220, 120, 255),
            }), nil, 45)
        else
            gradient(sw, safeCS(WHITE:Lerp(t.c1, 0.6), t.c1), nil, 90)
        end
        corner(sw, "full")
        local active = (i == currentThemeIdx)
        local st = stroke(sw, active and WHITE or rgb(180, 185, 200), active and 2 or 1, active and 0.2 or 0.65)
        swatchStrokes[i] = st
        local sc = new("UIScale", {Scale = 1}, sw)
        sw.MouseEnter:Connect(function() tw(sc, {Scale = 1.15}, 0.2, Enum.EasingStyle.Back) end)
        sw.MouseLeave:Connect(function() tw(sc, {Scale = 1}, 0.24) end)
        sw.MouseButton1Click:Connect(function()
            applyTheme(i, true)
            for j, s2 in pairs(swatchStrokes) do
                local on = (j == i)
                tweenService:Create(s2, TweenInfo.new(0.26), {
                    Color = on and WHITE or rgb(180, 185, 200), Thickness = on and 2 or 1, Transparency = on and 0.2 or 0.65,
                }):Play()
            end
        end)
    end

    section(tScroll, "scale", 2)
    local scaleCard = glassSurface(tScroll, 3)
    scaleCard.Size = UDim2.new(1, 0, 0, 56)
    local scaleLabel = lbl(scaleCard, "zoom · " .. string.format("%.2f", targetScale), F.bold, 11, C.text, {
        Size = UDim2.new(1, -180, 1, 0), Position = UDim2.new(0, 16, 0, 0), ZIndex = 6,
    })
    local function setScale(v)
        targetScale = clamp(math.floor(v * 10 + 0.5) / 10, 0.7, 1.5)
        scaleLabel.Text = "zoom · " .. string.format("%.2f", targetScale)
        persistConfig.scale = targetScale
        saveConfigToDisk()
    end
    local function scaleBtn(txt, order, onClick)
        local b = makeBtn(scaleCard, {
            size = UDim2.new(0, 34, 0, 30),
            pos = UDim2.new(1, -(34 * (4 - order) + 12 + (3 - order) * 6), 0.5, -15),
            bg = WHITE, bgT = 0.8, grad = safeCS(WHITE, rgb(210, 215, 228)),
            text = txt, tsize = 13, tcolor = C.text, strokeT = 0.6,
        })
        b.MouseEnter:Connect(function() tw(b, {BackgroundTransparency = 0.68}, 0.18) end)
        b.MouseLeave:Connect(function() tw(b, {BackgroundTransparency = 0.8}, 0.22) end)
        b.MouseButton1Click:Connect(onClick)
    end
    scaleBtn("−", 1, function() setScale(targetScale - 0.1) end)
    scaleBtn("1", 2, function() setScale(1) end)
    scaleBtn("+", 3, function() setScale(targetScale + 0.1) end)

    section(tScroll, "behavior", 5)
    toggleRow(tScroll, "auto hop on join", config.hopOnJoin, function(v) config.hopOnJoin = v end, 6, "hopOnJoin")
    toggleRow(tScroll, "prefer less full servers", config.preferLessFull, function(v)
        config.preferLessFull = v
        config.maxPlayerRatio = v and 0.9 or 1.0
    end, 7, "preferLessFull")

    section(tScroll, "vicious bee", 8)
    toggleRow(tScroll, "vicious bee mode", config.viciousBeeMode, function(v)
        config.viciousBeeMode = v
        if v then
            logInfo("vicious bee mode enabled — will hop until found")
            startViciousBeeMonitor()
        else
            logInfo("vicious bee mode disabled")
        end
    end, 8.1, "viciousBeeMode")
    toggleRow(tScroll, "auto-rehop if bee dies", config.viciousBeeAutoRehop, function(v)
        config.viciousBeeAutoRehop = v
    end, 8.2, "viciousBeeAutoRehop")

    section(tScroll, "limits", 9)
    toggleRow(tScroll, "skip empty servers", config.skipEmpty, function(v)
        config.skipEmpty = v
        config.minPlayers = v and 1 or 0
    end, 10, "skipEmpty")

    section(tScroll, "system", 12)
    local unloadBtn = new("TextButton", {
        BackgroundColor3 = rgb(180, 55, 70), BackgroundTransparency = 0.15, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 52), Text = "", AutoButtonColor = false, LayoutOrder = 13, ZIndex = 5,
    }, tScroll)
    corner(unloadBtn, 10)
    gradient(unloadBtn, safeCS(rgb(220, 75, 90), rgb(150, 40, 55)), nil, 90)
    stroke(unloadBtn, rgb(255, 200, 210), 1, 0.5)
    lbl(unloadBtn, "unload hopper", F.bold, 12, rgb(255, 245, 250), {
        Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 16, 0, 10), ZIndex = 6,
    })
    lbl(unloadBtn, "removes the ui and disconnects everything", F.reg, 10, rgb(255, 200, 210), {
        Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 16, 0, 30), ZIndex = 6,
    })
    unloadBtn.MouseEnter:Connect(function() tw(unloadBtn, {BackgroundTransparency = 0}, 0.18) end)
    unloadBtn.MouseLeave:Connect(function() tw(unloadBtn, {BackgroundTransparency = 0.15}, 0.22) end)
    unloadBtn.MouseButton1Click:Connect(unload)

    -- BLACKLIST TAB
    local bScroll = scroller(tabPages.blacklist)
    section(bScroll, "stats", 0)
    local statsCard = glassSurface(bScroll, 1)
    statsCard.Size = UDim2.new(1, 0, 0, 64)
    U.statsCountLabel = lbl(statsCard, "0 blacklisted", F.bold, 14, C.text, {
        Size = UDim2.new(1, -28, 0, 20), Position = UDim2.new(0, 14, 0, 12), ZIndex = 6,
    })
    U.statsSubLabel = lbl(statsCard, "", F.reg, 10, C.textMid, {
        Size = UDim2.new(1, -28, 0, 14), Position = UDim2.new(0, 14, 0, 36), ZIndex = 6,
    })

    section(bScroll, "actions", 2)
    local actionRow = new("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3, ZIndex = 5}, bScroll)
    new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8)}, actionRow)
    local function actionBtn(txt, color, order, cb)
        local b, _, _, s = makeBtn(actionRow, {
            size = UDim2.new(0.5, -4, 1, 0), bg = color, order = order, r = 10,
            grad = safeCS(WHITE:Lerp(color, 0.5), color), text = txt,
        })
        hoverStroke(b, s)
        b.MouseButton1Click:Connect(cb)
    end
    actionBtn("clear all", rgb(200, 70, 85), 1, function()
        blacklist, sessionVisited = {}, {}
        saveBlacklist()
        logWarn("blacklist cleared")
        U.refreshBlacklist()
    end)
    actionBtn("refresh list", C.accent, 2, function() U.refreshBlacklist() end)

    section(bScroll, "servers · expire after " .. math.floor(BLACKLIST_TTL / 3600) .. "h", 4)
    local blListFrame = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5, ZIndex = 5,
    }, bScroll)
    new("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6)}, blListFrame)

    function U.refreshBlacklist()
        pruneBlacklist()
        for _, c in ipairs(blListFrame:GetChildren()) do
            if not c:IsA("UIListLayout") then c:Destroy() end
        end
        local ids = {}
        for id in pairs(blacklist) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b)
            if blacklist[a] ~= blacklist[b] then return blacklist[a] > blacklist[b] end
            return a < b
        end)
        U.statsCountLabel.Text = #ids .. " blacklisted"
        U.statsSubLabel.Text = "current job: " .. (currentServerId and shortId(currentServerId) or "unknown")
        if #ids == 0 then emptyState(blListFrame, "no servers blacklisted yet") return end

        for i = 1, math.min(#ids, MAX_ROWS) do
            local id = ids[i]
            local row = new("Frame", {
                BackgroundColor3 = WHITE, BackgroundTransparency = 0.9, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 38), LayoutOrder = i, ZIndex = 6,
            }, blListFrame)
            corner(row, 10)
            gradient(row, safeCS(WHITE, rgb(210, 215, 228)), NumberSequence.new(0.88, 0.95), 90)
            stroke(row, WHITE, 1, 0.65)
            lbl(row, id, F.code, 10, C.text, {
                Size = UDim2.new(1, -100, 1, 0), Position = UDim2.new(0, 14, 0, 0), TextTruncate = Enum.TextTruncate.AtEnd,
            })
            local del = makeBtn(row, {
                size = UDim2.new(0, 70, 0, 24), pos = UDim2.new(1, -82, 0.5, -12), bg = rgb(200, 70, 85), bgT = 0.2,
                r = 7, z = 7, grad = safeCS(rgb(220, 90, 105), rgb(160, 50, 65)),
                text = "remove", tsize = 10, tcolor = rgb(255, 240, 245), strokeT = 1,
            })
            del.MouseEnter:Connect(function() tw(del, {BackgroundTransparency = 0}, 0.18) end)
            del.MouseLeave:Connect(function() tw(del, {BackgroundTransparency = 0.2}, 0.22) end)
            del.MouseButton1Click:Connect(function()
                blacklist[id] = nil
                sessionVisited[id] = nil
                saveBlacklist()
                log("removed " .. shortId(id), C.yellow)
                U.refreshBlacklist()
            end)
        end
    end

    -- MINIMIZE / CLOSE / PILL
    local versionTag = lbl(win, VERSION, F.reg, 9, C.textDim, {
        Size = UDim2.new(0, 120, 0, 14), Position = UDim2.new(0, 14, 1, -18), TextTransparency = 0.45, ZIndex = 40,
    })

    local minimized = false
    local function setMinimized(state)
        minimized = state
        if state then
            content.Visible, tabsBar.Visible, versionTag.Visible = false, false, false
            tw(win, {Size = UDim2.new(1, 0, 0, HEADER_H)}, 0.36)
        else
            content.Visible, tabsBar.Visible, versionTag.Visible = true, true, true
            tw(win, {Size = UDim2.new(1, 0, 1, 0)}, 0.4)
        end
    end
    btnMin.MouseButton1Click:Connect(function() setMinimized(not minimized) end)

    local pill = new("TextButton", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(0, 160, 0, 46),
        Position = UDim2.new(0.5, -80, 0, -60), Text = "", AutoButtonColor = false, Visible = false, ZIndex = 200,
    }, gui)
    corner(pill, "full")
    local pillBg = new("Frame", {
        BackgroundColor3 = WHITE, BackgroundTransparency = 0.82, BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0), ZIndex = 200,
    }, pill)
    corner(pillBg, "full")
    gradient(pillBg, safeCS(WHITE, rgb(210, 215, 228)), NumberSequence.new(0.78, 0.88), 90)
    stroke(pillBg, WHITE, 1, 0.5)
    local pillIconBox = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(0, 30, 0, 30), Position = UDim2.new(0, 8, 0.5, -15), ZIndex = 201,
    }, pillBg)
    corner(pillIconBox, 15)
    local pillIcon = new("ImageLabel", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Image = iconId, ZIndex = 202}, pillIconBox)
    corner(pillIcon, 15)
    lbl(pillBg, "server hopper", F.bold, 12, C.text, {Size = UDim2.new(1, -76, 1, 0), Position = UDim2.new(0, 46, 0, 0), ZIndex = 201})
    U.pillDot = new("Frame", {
        BackgroundColor3 = C.red, BorderSizePixel = 0, Size = UDim2.new(0, 8, 0, 8), Position = UDim2.new(1, -24, 0.5, -4), ZIndex = 201,
    }, pillBg)
    corner(U.pillDot, "full")
    pill.MouseEnter:Connect(function() tw(pillBg, {BackgroundTransparency = 0.7}, 0.2) end)
    pill.MouseLeave:Connect(function() tw(pillBg, {BackgroundTransparency = 0.82}, 0.24) end)

    local visToken = 0
    function U.hideUI()
        guiVisible = false
        visToken = visToken + 1
        local my = visToken
        pill.Visible = true
        pill.Position = UDim2.new(0.5, -80, 0, -60)
        tw(pill, {Position = UDim2.new(0.5, -80, 0, 14)}, 0.46, Enum.EasingStyle.Back)
        tw(win, {BackgroundTransparency = 1}, 0.16)
        task.delay(0.16, function() if not unloaded and visToken == my then container.Visible = false end end)
    end
    function U.showUI()
        guiVisible = true
        visToken = visToken + 1
        local my = visToken
        container.Visible = true
        win.BackgroundTransparency = 0
        tw(pill, {Position = UDim2.new(0.5, -80, 0, -60)}, 0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)
        task.delay(0.32, function() if not unloaded and visToken == my then pill.Visible = false end end)
    end
    btnClose.MouseButton1Click:Connect(U.hideUI)
    pill.MouseButton1Click:Connect(U.showUI)

    applyTheme(currentThemeIdx, false, true)
    U.refreshBlacklist()
end

local ok, err = xpcall(buildUI, function(e) return debug.traceback(tostring(e), 2) end)
if not ok then
    warn("[hopper] ui failed to build:\n" .. tostring(err))
    unload()
    return
end

-- ============ VICIOUS BEE MONITOR ============
local vbeeMonitorToken = 0
function startViciousBeeMonitor()
    vbeeMonitorToken = vbeeMonitorToken + 1
    local my = vbeeMonitorToken
    task.spawn(function()
        task.wait(config.viciousBeeWaitTime)
        if unloaded or my ~= vbeeMonitorToken then return end

        local bee, scanned, folder = checkForViciousBee()
        if bee then
            logGood("vicious bee found: " .. bee:GetFullName() .. " (" .. scanned .. " checked in " ..
                (folder and folder.Name or "workspace") .. ")")
            setStatus("bee", "bee found")
            if U.headerSub then U.headerSub.Text = "bee · " .. bee.Name end
        else
            logWarn("vicious bee not found (" .. scanned .. " checked)")
            if not folder then
                logWarn("no Monsters folder found in workspace")
            end
            setStatus("ok", "no bee")
            if config.viciousBeeAutoRehop and not hopping then
                logInfo("auto-rehop to find a fresh server")
                doHop()
                return
            end
        end

        while not unloaded and my == vbeeMonitorToken and config.viciousBeeMode do
            task.wait(config.viciousBeeRecheckInterval)
            if unloaded or my ~= vbeeMonitorToken then return end

            local b, sc = checkForViciousBee()
            if b then
                if U.headerSub then U.headerSub.Text = "bee · " .. b.Name end
                setStatus("bee", "bee found")
            else
                if U.headerSub then U.headerSub.Text = "session " .. sessionId end
                setStatus("ok", "no bee")
                if config.viciousBeeAutoRehop and not hopping then
                    logWarn("vicious bee gone — hopping for a fresh server")
                    doHop()
                    return
                end
            end
        end
    end)
end

-- ============ HOTKEYS ============
track(userInput.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        if guiVisible then U.hideUI() else U.showUI() end
    elseif input.KeyCode == Enum.KeyCode.F2 and not hopping then
        logInfo("hotkey hop (F2)")
        doHop()
    elseif input.KeyCode == Enum.KeyCode.F3 then
        logInfo("hotkey scan servers (F3)")
        U.refreshServerScan()
    elseif input.KeyCode == Enum.KeyCode.F4 then
        local bee, scanned, folder = checkForViciousBee()
        if bee then
            logGood("bee found: " .. bee:GetFullName() .. " in " .. (folder and folder.Name or "workspace"))
        else
            logWarn("no bee found (" .. scanned .. " checked)")
        end
    end
end))

-- ============ STARTUP ============
do
    local blCount = 0
    for _ in pairs(blacklist) do blCount = blCount + 1 end
    log("session " .. sessionId .. " started")
    log("loaded " .. blCount .. " blacklisted servers")
end
log("current job: " .. (currentServerId and shortId(currentServerId) or "unknown"),
    currentServerId and C.textMid or C.red)
log("hop on join: " .. (config.hopOnJoin and "ON" or "OFF"))

if config.viciousBeeMode then
    logInfo("vicious bee mode: ON — checking this server first")
    logInfo("rightshift toggle · F2 hop · F3 scan · F4 bee check")
    setStatus("loading", "bee check")
    startViciousBeeMonitor()
else
    log("rightshift toggle · F2 hop · F3 scan · servers tab = browse")
    setStatus("ok", "ready")
    if config.hopOnJoin then
        logWarn("auto hop in " .. config.autoHopDelay .. "s — disable it in config to cancel")
        task.delay(config.autoHopDelay, function()
            if not unloaded and config.hopOnJoin and not hopping then doHop() end
        end)
    end
end
