-- Server Hopper v0.2 · liquid glass · vicious bee hunter
local Players         = game:GetService("Players")
local HttpService     = game:GetService("HttpService")
local UIS             = game:GetService("UserInputService")
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local lp = Players.LocalPlayer

-- fully tear down any previous instance (connections + gui), not just the gui
if _G.__hopper_unload then pcall(_G.__hopper_unload) end

local request = (syn and syn.request) or (http and http.request) or http_request or request

local VERSION  = "v0.3 beta"
local ICON     = "rbxthumb://type=Asset&id=79985085633622&w=150&h=150"
local FILE_BL  = "hopper_blacklist.json"
local FILE_CFG = "hopper_config.json"
local BL_TTL   = 6 * 3600
local MAX_PAGES, WANT, MAX_RETRIES, MAX_ROWS = 15, 40, 4, 80

local rgb, CSK, NSK = Color3.fromRGB, ColorSequenceKeypoint.new, NumberSequenceKeypoint.new
local WHITE = rgb(255, 255, 255)
local C = {
    text = rgb(242, 244, 250), mid = rgb(168, 172, 188), dim = rgb(118, 122, 140),
    green = rgb(130, 220, 165), yellow = rgb(240, 205, 120), red = rgb(240, 130, 140), blue = rgb(120, 170, 245),
}

-- ============ CORE STATE ============
local connections, unloaded = {}, false
local function track(c) connections[#connections + 1] = c return c end
local function clamp(n, a, b) return math.max(a, math.min(b, n)) end
local function debounce(fn, d)
    local pending = false
    return function()
        if pending then return end
        pending = true
        task.delay(d, function() pending = false fn() end)
    end
end

local U = {}

-- ============ DISK ============
local canFS = writefile and readfile and isfile
local function readJSON(path)
    if not canFS or not isfile(path) then return nil end
    local ok, d = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    return ok and d or nil
end
local function writeJSON(path, data)
    if canFS then pcall(writefile, path, HttpService:JSONEncode(data)) end
end

-- ============ LOGGING ============
local sessionId = os.time() .. "_" .. math.random(1000, 9999)
local sessionFile = "hopper_session_" .. sessionId .. ".log"
local logLines, logDirty, MAX_LOG = {}, false, 150

local function esc(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function log(text, color, persist)
    color = color or C.mid
    logLines[#logLines + 1] = ('<font color="#%s">·  %s</font>'):format(color:ToHex(), esc(text))
    if #logLines > MAX_LOG then table.remove(logLines, 1) end
    logDirty = true
    if persist and appendfile then
        pcall(appendfile, sessionFile, ("[%s] %s\n"):format(os.date("%H:%M:%S"), text))
    end
end
local function logInfo(t) log(t, C.blue, true) end
local function logGood(t) log(t, C.green, true) end
local function logWarn(t) log(t, C.yellow, true) end
local function logBad(t)  log(t, C.red, true) end

-- ============ CONFIG ============
local cfg = { themeIdx = 1, scale = 1, preferLessFull = true, skipEmpty = true, hopOnJoin = false, viciousBeeMode = false }
do
    local d = readJSON(FILE_CFG)
    if type(d) == "table" then
        for k, v in pairs(cfg) do
            if type(d[k]) == type(v) then cfg[k] = d[k] end
        end
    end
end
local saveCfg = debounce(function() writeJSON(FILE_CFG, cfg) end, 0.4)

-- ============ BLACKLIST (id -> timestamp, auto-expiring) ============
local blacklist = {}
do
    local d, now = readJSON(FILE_BL), os.time()
    if type(d) == "table" then
        for k, v in pairs(d) do
            local id, t
            if type(k) == "number" then id, t = tostring(v), now
            else id, t = k, tonumber(v) or now end
            if now - t < BL_TTL then blacklist[id] = t end
        end
    end
end
local function saveBL() writeJSON(FILE_BL, blacklist) end
local function ban(id)
    if id and id ~= "" then blacklist[id] = os.time() saveBL() end
end

local currentId = (game.JobId ~= "" and game.JobId) or nil
ban(currentId)

local function shortId(id) id = tostring(id) return #id > 10 and id:sub(1, 10) or id end

-- ============ THEMES / PALETTE ============
local function T(name, c1, c2, c3, acc, hi, rainbow)
    return { name = name, rainbow = rainbow, pal = { c1 = c1, c2 = c2, c3 = c3, acc = acc, hi = hi } }
end
local themes = {
    T("midnight", rgb(52,68,130),  rgb(20,28,55), rgb(65,45,110),  rgb(120,170,245), rgb(155,200,255)),
    T("emerald",  rgb(36,100,90),  rgb(18,40,42), rgb(45,80,75),   rgb(105,200,155), rgb(140,225,180)),
    T("crimson",  rgb(130,45,55),  rgb(45,20,28), rgb(100,40,75),  rgb(220,110,120), rgb(245,145,155)),
    T("sunset",   rgb(140,70,45),  rgb(60,32,40), rgb(120,55,90),  rgb(230,160,90),  rgb(250,190,120)),
    T("violet",   rgb(95,55,155),  rgb(38,25,65), rgb(120,55,130), rgb(170,130,235), rgb(195,160,255)),
    T("mono",     rgb(75,75,82),   rgb(38,38,42), rgb(58,58,65),   rgb(180,185,200), rgb(210,215,230)),
    T("rainbow",  rgb(52,68,130),  rgb(20,28,55), rgb(65,45,110),  rgb(120,170,245), rgb(155,200,255), true),
}
if cfg.themeIdx < 1 or cfg.themeIdx > #themes then cfg.themeIdx = 1 end
cfg.scale = clamp(cfg.scale, 0.7, 1.5)

local function rainbowPal(h)
    return {
        c1 = Color3.fromHSV(h, .55, .55), c2 = Color3.fromHSV(h, .55, .22), c3 = Color3.fromHSV(h, .55, .45),
        acc = Color3.fromHSV(h, .55, 1),  hi = Color3.fromHSV(h, .45, 1),
    }
end
local function lerpPal(a, b, t)
    return { c1 = a.c1:Lerp(b.c1, t), c2 = a.c2:Lerp(b.c2, t), c3 = a.c3:Lerp(b.c3, t),
             acc = a.acc:Lerp(b.acc, t), hi = a.hi:Lerp(b.hi, t) }
end

local pal = themes[cfg.themeIdx].pal
local rainbowOn = themes[cfg.themeIdx].rainbow or false
local hue, transitioning = 0, false
local registry = {}
local function reg(obj, prop, kind) registry[#registry + 1] = { obj, prop, kind } end

local function paint(p)
    pal = p
    if U.bgGrad then U.bgGrad.Color = ColorSequence.new({ CSK(0, p.c1), CSK(.5, p.c2), CSK(1, p.c3) }) end
    if U.orb1 then U.orb1.BackgroundColor3 = p.c1 U.orb2.BackgroundColor3 = p.c3 U.orb3.BackgroundColor3 = p.c2 end
    for _, r in ipairs(registry) do
        local o, prop, kind = r[1], r[2], r[3]
        if o.Parent then
            if kind == "grad" then o.Color = ColorSequence.new(p.hi, p.acc)
            else o[prop] = (kind == "hi") and p.hi or p.acc end
        end
    end
end

-- ============ UI HELPERS ============
local function tw(o, p, t, style, dir)
    local x = TweenService:Create(o, TweenInfo.new(t or .24, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out), p)
    x:Play()
    return x
end

local function make(class, props, parent)
    local o = Instance.new(class)
    if o:IsA("GuiObject") then o.BorderSizePixel = 0 end
    if class == "TextButton" then o.AutoButtonColor = false end
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local function corner(o, r) return make("UICorner", { CornerRadius = UDim.new(0, r) }, o) end
local function grad(o, c, t, rot) return make("UIGradient", { Color = c, Transparency = t, Rotation = rot or 90 }, o) end
local function stroke(o, th, tr, col) return make("UIStroke", { Thickness = th or 1, Transparency = tr or .55, Color = col or WHITE }, o) end

local function text(parent, p)
    local d = { BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = C.text,
                TextXAlignment = Enum.TextXAlignment.Left }
    for k, v in pairs(p) do d[k] = v end
    return make("TextLabel", d, parent)
end

local function hover(o, on, off, s, sOn, sOff)
    track(o.MouseEnter:Connect(function() tw(o, on, .18) if s then tw(s, sOn, .18) end end))
    track(o.MouseLeave:Connect(function() tw(o, off, .22) if s then tw(s, sOff, .22) end end))
end

local GL_C = ColorSequence.new({ CSK(0, WHITE), CSK(.6, rgb(230,232,240)), CSK(1, rgb(200,205,218)) })
local GL_T = NumberSequence.new(0.86, 0.94)
local ST_C = ColorSequence.new({ CSK(0, WHITE), CSK(.5, rgb(200,210,230)), CSK(1, rgb(140,148,168)) })
local ST_T = NumberSequence.new({ NSK(0, .4), NSK(.5, .68), NSK(1, .85) })
local SOFT_C = ColorSequence.new(WHITE, rgb(210, 215, 228))

local function glass(parent, class, radius, order)
    local btn = class == "TextButton"
    local f = make(class, { BackgroundColor3 = WHITE, BackgroundTransparency = btn and .88 or .9,
        LayoutOrder = order or 0, Text = btn and "" or nil }, parent)
    corner(f, radius)
    grad(f, GL_C, GL_T)
    local s = make("UIStroke", { Color = WHITE, Thickness = 1 }, f)
    grad(s, ST_C, ST_T)
    if btn then hover(f, { BackgroundTransparency = .8 }, { BackgroundTransparency = .88 }, s, { Thickness = 1.5 }, { Thickness = 1 }) end
    return f, s
end

local function solidButton(parent, txt, color, props, accent)
    props.Text, props.Font, props.TextSize, props.TextColor3 = txt, Enum.Font.GothamBold, 11, WHITE
    props.BackgroundColor3 = color
    local b = make("TextButton", props, parent)
    corner(b, 8)
    local g = grad(b, ColorSequence.new(WHITE:Lerp(color, .5), color), NumberSequence.new(0))
    stroke(b, 1, .55)
    if accent then reg(b, "BackgroundColor3", "acc") reg(g, "Color", "grad") end
    hover(b, { BackgroundTransparency = .1 }, { BackgroundTransparency = 0 })
    return b
end

local function section(parent, txt, order)
    local f = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = order }, parent)
    make("UIPadding", { PaddingLeft = UDim.new(0, 4) }, f)
    text(f, { Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = C.dim, Text = txt:upper() })
end

local function emptyCard(parent, txt)
    local e = make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = .93, Size = UDim2.new(1, 0, 0, 60) }, parent)
    corner(e, 10) stroke(e, 1, .7)
    text(e, { Size = UDim2.new(1, -24, 1, 0), Position = UDim2.new(0, 12, 0, 0), TextColor3 = C.mid, Text = txt })
end

local function counter() local n = 0 return function() n = n + 1 return n end end

local function draggable(frame, handle)
    local dragging, start, orig
    local function isPtr(i) return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch end
    track(handle.InputBegan:Connect(function(i) if isPtr(i) then dragging, start, orig = true, i.Position, frame.Position end end))
    track(handle.InputEnded:Connect(function(i) if isPtr(i) then dragging = false end end))
    track(UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - start
            frame.Position = UDim2.new(orig.X.Scale, orig.X.Offset + d.X, orig.Y.Scale, orig.Y.Offset + d.Y)
        end
    end))
end

local function setStatus(state, txt)
    if not U.statusDot then return end
    local col = (state == "ok" and C.green) or (state == "loading" and C.yellow) or (state == "bee" and C.green) or C.red
    U.statusText.Text = txt or ((state == "ok" and "ready") or (state == "loading" and "scanning") or "idle")
    tw(U.statusDot, { BackgroundColor3 = col }, .36)
    tw(U.statusRing, { Color = col }, .36)
    U.pillDot.BackgroundColor3 = col
end

-- ============ VICIOUS BEE DETECTION ============
-- Scans workspace (direct + common containers) and PlayerGui for anything named/messaged "vicious".
-- Returns (true, source) if found, (false, nil) otherwise.

local BEE_CONTAINERS = { "Bees", "NPCs", "Mobs", "Enemies", "Entities", "Spawns", "Hostiles", "Bosses" }

local function detectViciousBee()
    if unloaded then return false end

    -- 1) direct workspace children (name match, case-insensitive)
    for _, obj in ipairs(workspace:GetChildren()) do
        local n = obj.Name:lower()
        if n:find("vicious", 1, true) then
            return true, "workspace." .. obj.Name
        end
    end

    -- 2) common containers, one level deep
    for _, cName in ipairs(BEE_CONTAINERS) do
        local c = workspace:FindFirstChild(cName)
        if c then
            for _, obj in ipairs(c:GetChildren()) do
                if obj.Name:lower():find("vicious", 1, true) then
                    return true, cName .. "." .. obj.Name
                end
            end
        end
    end

    -- 3) PlayerGui text (boss bars, spawn notifications)
    local pg = lp:FindFirstChild("PlayerGui")
    if pg then
        for _, gui in ipairs(pg:GetDescendants()) do
            if (gui:IsA("TextLabel") or gui:IsA("TextButton")) and gui.Visible then
                local t = gui.Text
                if t and t ~= "" and t:lower():find("vicious", 1, true) then
                    return true, "gui:" .. gui.Name
                end
            end
        end
    end

    -- 4) CoreGui (if accessible)
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then
        for _, gui in ipairs(cg:GetDescendants()) do
            if (gui:IsA("TextLabel") or gui:IsA("TextButton")) and gui.Visible then
                local t = gui.Text
                if t and t ~= "" and t:lower():find("vicious", 1, true) then
                    return true, "coregui:" .. gui.Name
                end
            end
        end
    end

    return false, nil
end

local beeFound, hunting = false, false

local function flashWin(times, color)
    if not U.win then return end
    task.spawn(function()
        local original = U.win.BackgroundColor3
        for i = 1, times do
            if unloaded then return end
            tw(U.win, { BackgroundColor3 = color }, .16)
            task.wait(.16)
            if unloaded then return end
            tw(U.win, { BackgroundColor3 = original }, .16)
            task.wait(.16)
        end
    end)
end

local function huntViciousBee()
    if unloaded or beeFound then return end
    if not cfg.viciousBeeMode then return end
    if hunting then return end
    hunting = true

    logInfo("checking for vicious bee in this server...")
    setStatus("loading", "checking")

    -- give the game time to load / spawn things, check once per second for 8s
    local found, src = false, nil
    for i = 1, 8 do
        task.wait(1)
        if unloaded or not cfg.viciousBeeMode then hunting = false return end
        found, src = detectViciousBee()
        if found then break end
    end

    if found then
        beeFound = true
        logGood("═══════════════════════════")
        logGood("VICIOUS BEE FOUND!")
        logGood("source: " .. tostring(src))
        logGood("═══════════════════════════")
        setStatus("bee", "bee found")
        flashWin(8, C.green)
        hunting = false
        return
    end

    logWarn("no vicious bee — hopping to next server")
    hunting = false
    if not unloaded and cfg.viciousBeeMode and not hopping then
        task.wait(0.4)
        doHop()
    end
end

-- ============ NETWORK + HOP LOGIC ============
local function httpGet(url)
    if request then
        local ok, res = pcall(request, { Url = url, Method = "GET" })
        if ok and res then return res.Body, res.StatusCode end
    end
    local ok, body = pcall(game.HttpGet, game, url)
    if ok then return body, 200 end
    return nil, nil
end

local function fetchPage(cursor)
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100"):format(game.PlaceId)
    if cursor then url = url .. "&cursor=" .. HttpService:UrlEncode(cursor) end
    for attempt = 1, 3 do
        if unloaded then return nil end
        local body, status = httpGet(url)
        if status == 429 then
            task.wait(1.5 * attempt)
        elseif body then
            local ok, d = pcall(HttpService.JSONDecode, HttpService, body)
            if ok and type(d) == "table" and type(d.data) == "table" then return d end
            return nil
        else
            return nil
        end
    end
    return nil
end

local function usable(s)
    if s.id == currentId or blacklist[s.id] then return false end
    if s.maxPlayers <= 0 or s.playing >= s.maxPlayers then return false end
    if s.playing < (cfg.skipEmpty and 1 or 0) then return false end
    return s.playing / s.maxPlayers <= (cfg.preferLessFull and 0.9 or 1)
end

local function scan(onPage, stopAt)
    local all, good, cursor = {}, 0, nil
    for page = 1, MAX_PAGES do
        if unloaded then break end
        local d = fetchPage(cursor)
        if not d then break end
        for _, s in ipairs(d.data) do
            local e = { id = tostring(s.id), playing = s.playing or 0, maxPlayers = s.maxPlayers or 0, ping = s.ping }
            all[#all + 1] = e
            if usable(e) then good = good + 1 end
        end
        if onPage then onPage(page, #all) end
        cursor = d.nextPageCursor
        if not cursor or cursor == "" or (stopAt and good >= stopAt) then break end
        task.wait(0.12)
    end
    return all, good
end

local scanCache = { t = 0, list = {}, full = false }
local hopping, hopToken, failStreak, lastForced, scanning = false, 0, 0, false, false

local function release(token)
    if token == hopToken then hopping = false setStatus("ok", "ready") end
end

local function teleportTo(id)
    ban(currentId)
    local ok = pcall(function()
        local o = Instance.new("TeleportOptions")
        o.ServerInstanceId = id
        TeleportService:TeleportAsync(game.PlaceId, { lp }, o)
    end)
    if not ok then
        logWarn("teleportAsync failed — falling back")
        ok = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, game.PlaceId, id, lp)
    end
    return ok
end

local function pickCandidate()
    local age = os.clock() - scanCache.t
    local list = scanCache.list
    if age > 20 or #list == 0 then
        setStatus("loading", "scanning")
        logInfo("scanning for open servers...")
        local good
        list, good = scan(nil, WANT)
        scanCache = { t = os.clock(), list = list, full = false }
        logInfo(("scanned %d servers · %d usable"):format(#list, good))
    end
    local cands = {}
    for _, s in ipairs(list) do if usable(s) then cands[#cands + 1] = s end end
    if #cands == 0 then return nil end
    table.sort(cands, function(a, b)
        if a.playing ~= b.playing then return a.playing > b.playing end
        return a.id < b.id
    end)
    return cands[math.random(1, math.max(1, math.floor(#cands / 3)))]
end

local function doHop(forcedId)
    if hopping then return end
    hopping, lastForced = true, forcedId ~= nil
    hopToken = hopToken + 1
    local token = hopToken
    setStatus("loading", "scanning")
    task.spawn(function()
        local target = forcedId
        if not target then
            for attempt = 1, MAX_RETRIES + 1 do
                local c = pickCandidate()
                if c then
                    target = c.id
                    logGood(("selected %s (%d/%d)"):format(shortId(c.id), c.playing, c.maxPlayers))
                    break
                end
                if attempt > MAX_RETRIES then break end
                logWarn(("no fresh servers — retry %d/%d in 3s"):format(attempt, MAX_RETRIES))
                task.wait(3)
                scanCache.t = 0
            end
            if not target then logBad("giving up — no fresh servers") release(token) return end
        end
        setStatus("loading", "hopping")
        task.wait(0.3)
        if not teleportTo(target) then
            logBad("teleport call failed")
            ban(target)
            release(token)
            return
        end
        task.delay(15, function() release(token) end)
    end)
end

track(TeleportService.TeleportInitFailed:Connect(function(plr, result, msg)
    if plr ~= lp then return end
    logWarn("teleport failed: " .. tostring(result))
    local wasForced = lastForced
    hopping = false
    setStatus("ok", "ready")
    if wasForced then return end
    failStreak = failStreak + 1
    if failStreak <= MAX_RETRIES then
        task.delay(1, function() if not unloaded then doHop() end end)
    else
        failStreak = 0
        logBad("giving up after repeated teleport failures")
    end
end))

-- ============ SERVER LIST RENDER ============
local renderToken = 0
local function cmpServers(a, b)
    local aBad = (a.id == currentId) or (blacklist[a.id] ~= nil)
    local bBad = (b.id == currentId) or (blacklist[b.id] ~= nil)
    if aBad ~= bBad then return not aBad end
    if a.playing ~= b.playing then return a.playing > b.playing end
    return a.id < b.id
end

local function makeServerRow(frame, s, order)
    local isCur = s.id == currentId
    local isBad = blacklist[s.id] ~= nil
    local isFull = s.playing >= s.maxPlayers
    local row = make("TextButton", { BackgroundColor3 = WHITE, BackgroundTransparency = isCur and .78 or .9,
        Size = UDim2.new(1, 0, 0, 38), Text = "", LayoutOrder = order }, frame)
    corner(row, 10)
    grad(row, isCur and ColorSequence.new(rgb(140,180,240), rgb(80,120,190)) or SOFT_C,
        NumberSequence.new(0.88, 0.95))
    stroke(row, 1, .65)
    local dot = make("Frame", { Size = UDim2.fromOffset(7, 7), Position = UDim2.new(0, 14, .5, -3),
        BackgroundColor3 = (isCur and C.green) or (isBad and C.red) or (isFull and C.yellow) or C.blue }, row)
    corner(dot, 4)
    text(row, { Size = UDim2.new(1, -180, 1, 0), Position = UDim2.new(0, 28, 0, 0), Font = Enum.Font.Code, TextSize = 10,
        TextTruncate = Enum.TextTruncate.AtEnd, Text = s.id })
    text(row, { Size = UDim2.new(0, 90, 1, 0), Position = UDim2.new(1, -96, 0, 0), Font = Enum.Font.Code, TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextColor3 = isFull and C.yellow or (isCur and C.green or C.mid),
        Text = s.playing .. "/" .. s.maxPlayers .. ((s.ping and s.ping > 0) and ("  " .. s.ping .. "ms") or "") })
    row.MouseEnter:Connect(function() tw(row, { BackgroundTransparency = isCur and .7 or .82 }, .16) end)
    row.MouseLeave:Connect(function() tw(row, { BackgroundTransparency = isCur and .78 or .9 }, .2) end)
    row.MouseButton1Click:Connect(function()
        if hopping then return end
        if isCur then logWarn("already in that server") return end
        logInfo("manual jump to " .. shortId(s.id))
        failStreak = 0
        doHop(s.id)
    end)
end

function U.renderServerList(list)
    local frame = U.serverListFrame
    if not frame then return end
    renderToken = renderToken + 1
    local token = renderToken
    for _, c in ipairs(frame:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
    if #list == 0 then emptyCard(frame, "no servers found — hit refresh") return end
    local rows = table.move(list, 1, #list, 1, {})
    table.sort(rows, cmpServers)
    for i = 1, math.min(#rows, MAX_ROWS) do
        if token ~= renderToken or unloaded then return end
        makeServerRow(frame, rows[i], i)
        if i % 20 == 0 then task.wait() end
    end
    if #rows > MAX_ROWS and token == renderToken then
        local f = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = MAX_ROWS + 1 }, frame)
        text(f, { Size = UDim2.fromScale(1, 1), TextColor3 = C.dim, TextSize = 10, Text = ("+%d more not shown"):format(#rows - MAX_ROWS) })
    end
end

function U.refreshServerScan(force)
    if scanning then return end
    if not force and scanCache.full and os.clock() - scanCache.t < 60 then
        U.renderServerList(scanCache.list)
        return
    end
    scanning = true
    setStatus("loading", "scanning")
    logInfo("scanning all servers...")
    task.spawn(function()
        local list = scan(function(p, n)
            if U.serverStatus and not unloaded then U.serverStatus.Text = ("page %d · %d servers"):format(p, n) end
        end)
        scanCache = { t = os.clock(), list = list, full = true }
        scanning = false
        if unloaded then return end
        logGood("scan complete: " .. #list .. " servers")
        U.renderServerList(list)
        U.serverStatus.Text = #list .. " servers · " .. (currentId and shortId(currentId) or "?")
        if not hopping and not hunting then setStatus("ok", "ready") end
    end)
end

-- ============ BUILD UI ============
local WIN_W, WIN_H, HEADER_H, TABS_H = 460, 580, 58, 36
local gui = make("ScreenGui", { Name = "hopper", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, nil)
gui.Parent = lp:WaitForChild("PlayerGui")

local alpha = Instance.new("NumberValue")
local fromPal, toPal, themeTween
track(alpha:GetPropertyChangedSignal("Value"):Connect(function()
    if toPal then paint(lerpPal(fromPal, toPal, alpha.Value)) end
end))

local function setTheme(idx, save)
    if unloaded then return end
    cfg.themeIdx = idx
    if save then saveCfg() end
    local t = themes[idx]
    rainbowOn = t.rainbow or false
    fromPal, toPal = pal, (t.rainbow and rainbowPal(hue)) or t.pal
    if themeTween then themeTween:Cancel() end
    alpha.Value = 0
    transitioning = true
    local mine = tw(alpha, { Value = 1 }, .7)
    themeTween = mine
    track(mine.Completed:Connect(function() if themeTween == mine then transitioning = false end end))
    if U.themeLabel then U.themeLabel.Text = "theme · " .. t.name end
end

local function build()
    local container = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(WIN_W, WIN_H),
        Position = UDim2.new(0, 40, .5, 0), AnchorPoint = Vector2.new(0, .5) }, gui)
    U.container = container
    local uiScale = make("UIScale", { Scale = cfg.scale }, container)

    local win = make("Frame", { BackgroundColor3 = rgb(14, 14, 20), Size = UDim2.fromScale(1, 1), Active = true,
        ClipsDescendants = true }, container)
    U.win = win
    corner(win, 16)
    local wst = make("UIStroke", { Color = WHITE, Thickness = 1 }, win)
    grad(wst, ColorSequence.new(WHITE, rgb(140, 148, 168)), NumberSequence.new(0.5, 0.88))

    local bg = make("Frame", { BackgroundColor3 = rgb(14, 14, 20), Size = UDim2.fromScale(1, 1), ZIndex = 0,
        ClipsDescendants = true }, win)
    corner(bg, 16)
    U.bgGrad = make("UIGradient", {
        Color = ColorSequence.new({ CSK(0, pal.c1), CSK(.5, pal.c2), CSK(1, pal.c3) }), Rotation = 35,
        Transparency = NumberSequence.new({ NSK(0, .4), NSK(.5, .62), NSK(1, .4) }) }, bg)
    corner(make("Frame", { BackgroundColor3 = rgb(10, 10, 14), BackgroundTransparency = .6,
        Size = UDim2.fromScale(1, 1), ZIndex = 1 }, bg), 16)

    local function orb(color, size, p0, p1, dur, trans)
        local o = make("Frame", { BackgroundColor3 = color, BackgroundTransparency = trans, Size = UDim2.fromOffset(size, size),
            Position = p0, ZIndex = 2 }, bg)
        corner(o, size)
        TweenService:Create(o, TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
            { Position = p1, BackgroundTransparency = trans - .1 }):Play()
        return o
    end
    U.orb1 = orb(pal.c1, 320, UDim2.new(-.35, 0, -.2, 0), UDim2.new(.55, 0, .3, 0), 16, .72)
    U.orb2 = orb(pal.c3, 280, UDim2.new(.7, 0, .5, 0),   UDim2.new(.15, 0, .95, 0), 20, .78)
    U.orb3 = orb(pal.c2, 240, UDim2.new(.3, 0, .7, 0),   UDim2.new(.75, 0, -.05, 0), 24, .82)

    local header = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, HEADER_H) }, win)
    draggable(container, header)

    local iconBox = glass(header, "Frame", 9)
    iconBox.Size, iconBox.Position = UDim2.fromOffset(34, 34), UDim2.fromOffset(16, 12)
    corner(make("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = ICON }, iconBox), 9)
    text(header, { Size = UDim2.fromOffset(150, 16), Position = UDim2.fromOffset(62, 12), Font = Enum.Font.GothamBold,
        TextSize = 14, Text = "server hopper" })
    text(header, { Size = UDim2.fromOffset(150, 12), Position = UDim2.fromOffset(62, 29), TextSize = 10,
        TextColor3 = C.dim, Text = "session " .. sessionId })

    U.statusText = text(header, { Size = UDim2.new(0, 70, 1, 0), Position = UDim2.new(1, -162, 0, 0), Font = Enum.Font.GothamMedium,
        TextColor3 = C.mid, TextXAlignment = Enum.TextXAlignment.Right, Text = "idle" })
    U.statusDot = make("Frame", { BackgroundColor3 = C.red, Size = UDim2.fromOffset(7, 7), Position = UDim2.new(1, -84, .5, -3) }, header)
    corner(U.statusDot, 4)
    U.statusRing = stroke(U.statusDot, 1, .6, C.red)

    local function iconBtn(txt, x)
        local b = make("TextButton", { BackgroundColor3 = WHITE, BackgroundTransparency = .85, Size = UDim2.fromOffset(24, 24),
            Position = UDim2.new(1, x, .5, -12), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.mid, Text = txt }, header)
        corner(b, 7) grad(b, SOFT_C, NumberSequence.new(0)) stroke(b, 1, .55)
        return b
    end
    local btnMin, btnClose = iconBtn("−", -68), iconBtn("×", -40)
    hover(btnClose, { BackgroundColor3 = rgb(200, 70, 85), BackgroundTransparency = .15, TextColor3 = rgb(255, 240, 245) },
        { BackgroundColor3 = WHITE, BackgroundTransparency = .85, TextColor3 = C.mid })
    hover(btnMin, { BackgroundTransparency = .7, TextColor3 = C.text }, { BackgroundTransparency = .85, TextColor3 = C.mid })

    local tabsBar = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, TABS_H), Position = UDim2.fromOffset(0, HEADER_H) }, win)
    local content = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -HEADER_H - TABS_H),
        Position = UDim2.fromOffset(0, HEADER_H + TABS_H), ClipsDescendants = true }, win)

    local tabNames = { "logs", "servers", "config", "blacklist" }
    local tabBtns, pages, active = {}, {}, "logs"
    for i, name in ipairs(tabNames) do
        tabBtns[name] = make("TextButton", { BackgroundTransparency = 1, Size = UDim2.new(1 / #tabNames, 0, 1, 0),
            Position = UDim2.new((i - 1) / #tabNames, 0, 0, 0), Font = Enum.Font.GothamMedium, TextSize = 12,
            TextColor3 = name == active and C.text or C.dim, Text = name }, tabsBar)
        pages[name] = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = name == active }, content)
    end
    local underline = make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = .3, Size = UDim2.new(1 / #tabNames, -80, 0, 3),
        Position = UDim2.new(0, 40, 1, -4), ZIndex = 7 }, tabsBar)
    corner(underline, 2)
    local ug = grad(underline, ColorSequence.new(pal.hi, pal.acc), NumberSequence.new({ NSK(0, .6), NSK(.5, 0), NSK(1, .6) }), 0)
    reg(ug, "Color", "grad")

    local function switchTab(name)
        if name == active then return end
        active = name
        for n, p in pairs(pages) do p.Visible = n == name end
        local veil = make("Frame", { BackgroundColor3 = rgb(10, 10, 14), BackgroundTransparency = .5, Size = UDim2.fromScale(1, 1), ZIndex = 70 }, pages[name])
        tw(veil, { BackgroundTransparency = 1 }, .32)
        task.delay(.34, function() veil:Destroy() end)
        tw(underline, { Position = UDim2.new((table.find(tabNames, name) - 1) / #tabNames, 40, 1, -4) }, .4)
        for n, b in pairs(tabBtns) do tw(b, { TextColor3 = n == name and C.text or C.dim }, .24) end
        if name == "servers" then U.refreshServerScan()
        elseif name == "blacklist" then U.refreshBlacklist() end
    end
    for n, b in pairs(tabBtns) do
        track(b.MouseButton1Click:Connect(function() switchTab(n) end))
        underline.Position = UDim2.new((table.find(tabNames, active) - 1) / #tabNames, 40, 1, -4)
    end

    local function scrollPage(page)
        make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 18), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, page)
        local s = make("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 2, ScrollBarImageColor3 = WHITE, ScrollBarImageTransparency = .7 }, page)
        make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, s)
        return s
    end

    -- ===== LOGS =====
    U.logsPage = pages.logs
    local chatCard = glass(pages.logs, "Frame", 12)
    chatCard.Size, chatCard.Position = UDim2.new(1, -28, 1, -104), UDim2.fromOffset(14, 14)
    local logScroll = make("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.new(1, -28, 1, -28), Position = UDim2.fromOffset(14, 14),
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 2,
        ScrollBarImageColor3 = WHITE, ScrollBarImageTransparency = .7 }, chatCard)
    U.logLabel = text(logScroll, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Font = Enum.Font.Code,
        TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, LineHeight = 1.45, RichText = true, Text = "" })
    track(logScroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
        logScroll.CanvasPosition = Vector2.new(0, math.max(0, logScroll.AbsoluteCanvasSize.Y - logScroll.AbsoluteSize.Y))
    end))
    logDirty = true

    local inputBar = glass(pages.logs, "Frame", 12)
    inputBar.Size, inputBar.Position = UDim2.new(1, -28, 0, 70), UDim2.new(0, 14, 1, -84)
    text(inputBar, { Size = UDim2.new(1, -28, 0, 14), Position = UDim2.fromOffset(14, 10), Font = Enum.Font.GothamBold, TextSize = 10,
        TextColor3 = C.dim, Text = "HOP CONTROL" })
    local hopBtn = solidButton(inputBar, "hop now", pal.acc, { Size = UDim2.new(.55, -16, 0, 32), Position = UDim2.fromOffset(14, 30), TextSize = 12 }, true)
    local clearBtn = glass(inputBar, "TextButton", 8)
    clearBtn.Size, clearBtn.Position = UDim2.new(.45, -16, 0, 32), UDim2.new(.55, 2, 0, 30)
    clearBtn.Text, clearBtn.Font, clearBtn.TextSize, clearBtn.TextColor3 = "clear log", Enum.Font.GothamBold, 11, C.text

    track(hopBtn.MouseButton1Click:Connect(function()
        if hopping then logWarn("already hopping...") return end
        logInfo("manual hop triggered")
        failStreak = 0
        doHop()
    end))
    track(clearBtn.MouseButton1Click:Connect(function() logLines = {} logDirty = true end))

    -- ===== SERVERS =====
    local sScroll = scrollPage(pages.servers)
    section(sScroll, "scanner", 0)
    local statusCard = glass(sScroll, "Frame", 12, 1)
    statusCard.Size = UDim2.new(1, 0, 0, 60)
    U.serverStatus = text(statusCard, { Size = UDim2.new(1, -120, 1, 0), Position = UDim2.fromOffset(16, 0), Font = Enum.Font.GothamBold,
        TextSize = 12, Text = "click refresh to scan" })
    local refreshBtn = solidButton(statusCard, "refresh", pal.acc, { Size = UDim2.fromOffset(88, 32), Position = UDim2.new(1, -104, .5, -16) }, true)
    track(refreshBtn.MouseButton1Click:Connect(function() U.refreshServerScan(true) end))
    section(sScroll, "all servers · click to jump", 2)
    U.serverListFrame = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 }, sScroll)
    make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, U.serverListFrame)
    emptyCard(U.serverListFrame, "click refresh to scan servers")

    -- ===== CONFIG =====
    local tScroll = scrollPage(pages.config)
    local n = counter()
    section(tScroll, "appearance", n())

    local themeCard = glass(tScroll, "Frame", 12, n())
    themeCard.Size = UDim2.new(1, 0, 0, 72)
    U.themeLabel = text(themeCard, { Size = UDim2.new(1, -28, 0, 14), Position = UDim2.fromOffset(14, 12), Font = Enum.Font.GothamBold,
        TextSize = 10, TextColor3 = C.dim, Text = "theme · " .. themes[cfg.themeIdx].name })
    local swatchRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -28, 0, 28), Position = UDim2.fromOffset(14, 32) }, themeCard)
    make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Center }, swatchRow)

    local swatches = {}
    local function markSwatch(sel)
        for i, s in ipairs(swatches) do
            local on = i == sel
            tw(s, { Color = on and WHITE or rgb(180, 185, 200), Thickness = on and 2 or 1, Transparency = on and .2 or .65 }, .26)
        end
    end
    for i, t in ipairs(themes) do
        local sw = make("TextButton", { BackgroundColor3 = t.rainbow and WHITE or t.pal.c1, Size = UDim2.fromOffset(26, 26), Text = "", LayoutOrder = i }, swatchRow)
        corner(sw, 13)
        if t.rainbow then
            grad(sw, ColorSequence.new({ CSK(0, rgb(255,80,80)), CSK(.25, rgb(255,220,80)), CSK(.5, rgb(120,255,120)),
                CSK(.75, rgb(120,180,255)), CSK(1, rgb(220,120,255)) }), NumberSequence.new(0), 45)
        else
            grad(sw, ColorSequence.new(WHITE:Lerp(t.pal.c1, .6), t.pal.c1), NumberSequence.new(0))
        end
        local on = i == cfg.themeIdx
        swatches[i] = stroke(sw, on and 2 or 1, on and .2 or .65, on and WHITE or rgb(180, 185, 200))
        track(sw.MouseEnter:Connect(function() tw(sw, { Size = UDim2.fromOffset(30, 30) }, .2, Enum.EasingStyle.Back) end))
        track(sw.MouseLeave:Connect(function() tw(sw, { Size = UDim2.fromOffset(26, 26) }, .24) end))
        track(sw.MouseButton1Click:Connect(function() setTheme(i, true) markSwatch(i) end))
    end

    section(tScroll, "scale", n())
    local scaleCard = glass(tScroll, "Frame", 12, n())
    scaleCard.Size = UDim2.new(1, 0, 0, 56)
    local scaleLabel = text(scaleCard, { Size = UDim2.new(1, -180, 1, 0), Position = UDim2.fromOffset(16, 0), Font = Enum.Font.GothamBold,
        Text = ("zoom · %.2f"):format(cfg.scale) })
    local function setScale(v)
        v = math.floor(clamp(v, .7, 1.5) * 100 + .5) / 100
        cfg.scale = v
        scaleLabel.Text = ("zoom · %.2f"):format(v)
        tw(uiScale, { Scale = v }, .35, Enum.EasingStyle.Back)
        saveCfg()
    end
    for order, def in ipairs({ { "−", function() setScale(cfg.scale - .1) end }, { "1", function() setScale(1) end }, { "+", function() setScale(cfg.scale + .1) end } }) do
        local b = glass(scaleCard, "TextButton", 8)
        b.Size, b.Position = UDim2.fromOffset(34, 30), UDim2.new(1, -12 - 34 * (4 - order) - 6 * (3 - order), .5, -15)
        b.Text, b.Font, b.TextSize, b.TextColor3 = def[1], Enum.Font.GothamBold, 13, C.text
        track(b.MouseButton1Click:Connect(def[2]))
    end

    local function toggleRow(label, key, order, onChange)
        local b = glass(tScroll, "TextButton", 10, order)
        b.Size = UDim2.new(1, 0, 0, 48)
        make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, b)
        text(b, { Size = UDim2.new(1, -84, 1, 0), Font = Enum.Font.GothamMedium, TextSize = 12, Text = label })
        local PW, PH, K = 40, 22, 18
        local state = cfg[key]
        local trackF = make("Frame", { Size = UDim2.fromOffset(PW, PH), Position = UDim2.new(1, -PW, .5, -PH / 2),
            BackgroundColor3 = state and C.green or rgb(64, 66, 78) }, b)
        corner(trackF, PH)
        local knob = make("Frame", { Size = UDim2.fromOffset(K, K), BackgroundColor3 = WHITE,
            Position = UDim2.new(0, state and (PW - K - 2) or 2, .5, -K / 2) }, trackF)
        corner(knob, K)
        track(b.MouseButton1Click:Connect(function()
            state = not state
            cfg[key] = state
            saveCfg()
            tw(knob, { Position = UDim2.new(0, state and (PW - K - 2) or 2, .5, -K / 2) }, .4, Enum.EasingStyle.Back)
            tw(trackF, { BackgroundColor3 = state and C.green or rgb(64, 66, 78) }, .28)
            if onChange then onChange(state) end
        end))
        return b
    end

    section(tScroll, "vicious bee", n())
    toggleRow("vicious bee hunter (auto-hop until found)", "viciousBeeMode", n())
    local huntBtn = solidButton(tScroll, "start hunting now", pal.acc, {
        Size = UDim2.new(1, 0, 0, 44), LayoutOrder = n()
    }, true)
    track(huntBtn.MouseButton1Click:Connect(function()
        beeFound = false
        cfg.viciousBeeMode = true
        saveCfg()
        logInfo("starting vicious bee hunt from current server")
        huntViciousBee()
    end))

    section(tScroll, "behavior", n())
    toggleRow("auto hop on join (needs autoexec)", "hopOnJoin", n())
    toggleRow("prefer less full servers", "preferLessFull", n(), function() scanCache.t = 0 end)
    section(tScroll, "limits", n())
    toggleRow("skip empty servers", "skipEmpty", n(), function() scanCache.t = 0 end)
    section(tScroll, "system", n())

    local unloadBtn = make("TextButton", { BackgroundColor3 = rgb(180, 55, 70), BackgroundTransparency = .15,
        Size = UDim2.new(1, 0, 0, 52), Text = "", LayoutOrder = n() }, tScroll)
    corner(unloadBtn, 10)
    grad(unloadBtn, ColorSequence.new(rgb(220, 75, 90), rgb(150, 40, 55)), NumberSequence.new(0))
    stroke(unloadBtn, 1, .5, rgb(255, 200, 210))
    text(unloadBtn, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(16, 10), Font = Enum.Font.GothamBold, TextSize = 12,
        TextColor3 = rgb(255, 245, 250), Text = "unload hopper" })
    text(unloadBtn, { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(16, 30), TextSize = 10,
        TextColor3 = rgb(255, 200, 210), Text = "removes the ui and disconnects everything" })
    hover(unloadBtn, { BackgroundTransparency = 0 }, { BackgroundTransparency = .15 })
    track(unloadBtn.MouseButton1Click:Connect(function() if _G.__hopper_unload then _G.__hopper_unload() end end))

    -- ===== BLACKLIST =====
    local bScroll = scrollPage(pages.blacklist)
    section(bScroll, "stats", 0)
    local statsCard = glass(bScroll, "Frame", 12, 1)
    statsCard.Size = UDim2.new(1, 0, 0, 64)
    U.statsCount = text(statsCard, { Size = UDim2.new(1, -28, 0, 20), Position = UDim2.fromOffset(14, 12), Font = Enum.Font.GothamBold,
        TextSize = 14, Text = "0 blacklisted" })
    U.statsSub = text(statsCard, { Size = UDim2.new(1, -28, 0, 14), Position = UDim2.fromOffset(14, 36), TextSize = 10, TextColor3 = C.mid, Text = "" })
    section(bScroll, "actions", 2)
    local actionRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3 }, bScroll)
    make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, actionRow)
    local clearAll = solidButton(actionRow, "clear all", rgb(200, 70, 85), { Size = UDim2.new(.5, -4, 1, 0), LayoutOrder = 1 })
    local refreshBL = solidButton(actionRow, "refresh list", pal.acc, { Size = UDim2.new(.5, -4, 1, 0), LayoutOrder = 2 }, true)
    section(bScroll, "servers", 4)
    local blList = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5 }, bScroll)
    make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, blList)

    local function age(t)
        local d = os.time() - t
        return d < 60 and (d .. "s") or d < 3600 and (math.floor(d / 60) .. "m") or (math.floor(d / 3600) .. "h")
    end

    function U.refreshBlacklist()
        for _, c in ipairs(blList:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
        local ids = {}
        for id, t in pairs(blacklist) do ids[#ids + 1] = { id = id, t = t } end
        table.sort(ids, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.id < b.id end)
        U.statsCount.Text = #ids .. " blacklisted"
        U.statsSub.Text = "current job: " .. (currentId and shortId(currentId) or "unknown") .. " · entries expire after 6h"
        if #ids == 0 then emptyCard(blList, "no servers blacklisted yet") return end
        for i = 1, math.min(#ids, MAX_ROWS) do
            local e = ids[i]
            local row = make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = .9, Size = UDim2.new(1, 0, 0, 38), LayoutOrder = i }, blList)
            corner(row, 10) grad(row, SOFT_C, NumberSequence.new(0.88, 0.95)) stroke(row, 1, .65)
            text(row, { Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(14, 0), Font = Enum.Font.Code, TextSize = 10,
                TextTruncate = Enum.TextTruncate.AtEnd, Text = e.id })
            text(row, { Size = UDim2.fromOffset(40, 38), Position = UDim2.new(1, -124, 0, 0), Font = Enum.Font.Code, TextSize = 10,
                TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right, Text = age(e.t) })
            local del = make("TextButton", { BackgroundColor3 = rgb(200, 70, 85), BackgroundTransparency = .2, Size = UDim2.fromOffset(70, 24),
                Position = UDim2.new(1, -82, .5, -12), Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = rgb(255, 240, 245), Text = "remove" }, row)
            corner(del, 7)
            grad(del, ColorSequence.new(rgb(220, 90, 105), rgb(160, 50, 65)), NumberSequence.new(0))
            del.MouseButton1Click:Connect(function()
                blacklist[e.id] = nil
                saveBL()
                log("removed " .. shortId(e.id), C.yellow)
                U.refreshBlacklist()
            end)
        end
        if #ids > MAX_ROWS then
            local f = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = MAX_ROWS + 1 }, blList)
            text(f, { Size = UDim2.fromScale(1, 1), TextColor3 = C.dim, TextSize = 10, Text = ("+%d more not shown"):format(#ids - MAX_ROWS) })
        end
    end
    track(clearAll.MouseButton1Click:Connect(function()
        blacklist = {}
        ban(currentId)
        logWarn("blacklist cleared")
        U.refreshBlacklist()
    end))
    track(refreshBL.MouseButton1Click:Connect(function() U.refreshBlacklist() end))

    -- ===== minimize / pill =====
    local minimized = false
    track(btnMin.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            tw(win, { Size = UDim2.new(1, 0, 0, HEADER_H) }, .36)
            content.Visible, tabsBar.Visible = false, false
        else
            content.Visible, tabsBar.Visible = true, true
            tw(win, { Size = UDim2.fromScale(1, 1) }, .4)
        end
    end))

    local pill = glass(gui, "TextButton", 23)
    pill.Size, pill.Position, pill.Visible, pill.ZIndex = UDim2.fromOffset(160, 46), UDim2.new(.5, -80, 0, -60), false, 200
    corner(make("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(30, 30), Position = UDim2.new(0, 8, .5, -15),
        Image = ICON, ZIndex = 201 }, pill), 15)
    text(pill, { Size = UDim2.new(1, -76, 1, 0), Position = UDim2.fromOffset(46, 0), Font = Enum.Font.GothamBold, TextSize = 12,
        Text = "server hopper", ZIndex = 201 })
    U.pillDot = make("Frame", { BackgroundColor3 = C.red, Size = UDim2.fromOffset(8, 8), Position = UDim2.new(1, -24, .5, -4), ZIndex = 201 }, pill)
    corner(U.pillDot, 4)

    function U.hideUI()
        container.Visible = false
        pill.Visible = true
        pill.Position = UDim2.new(.5, -80, 0, -60)
        tw(pill, { Position = UDim2.new(.5, -80, 0, 14) }, .46, Enum.EasingStyle.Back)
    end
    function U.showUI()
        container.Visible = true
        tw(pill, { Position = UDim2.new(.5, -80, 0, -60) }, .3, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)
        task.delay(.32, function() if container.Visible then pill.Visible = false end end)
    end
    track(btnClose.MouseButton1Click:Connect(U.hideUI))
    track(pill.MouseButton1Click:Connect(U.showUI))

    text(win, { Size = UDim2.fromOffset(120, 14), Position = UDim2.new(0, 14, 1, -16), TextSize = 9, TextColor3 = C.dim,
        TextTransparency = .45, Text = VERSION, ZIndex = 40 })
end

build()
paint(pal)
U.refreshBlacklist()

-- ============ HEARTBEAT: log flush + rainbow ============
local acc = 0
track(RunService.Heartbeat:Connect(function(dt)
    local visible = U.container and U.container.Visible
    if logDirty and visible and U.logsPage.Visible then
        logDirty = false
        U.logLabel.Text = table.concat(logLines, "\n")
    end
    if rainbowOn then
        hue = (hue + dt * .08) % 1
        acc = acc + dt
        if acc >= 1 / 24 and not transitioning and visible then
            acc = 0
            paint(rainbowPal(hue))
        end
    end
end))

-- ============ INPUT ============
track(UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    local k = input.KeyCode
    if k == Enum.KeyCode.RightShift then
        if U.container.Visible then U.hideUI() else U.showUI() end
    elseif k == Enum.KeyCode.F2 and not hopping then
        logInfo("hotkey hop (F2)")
        failStreak = 0
        doHop()
    elseif k == Enum.KeyCode.F3 then
        logInfo("hotkey scan servers (F3)")
        U.refreshServerScan(true)
    elseif k == Enum.KeyCode.F4 then
        logInfo("hotkey hunt vicious bee (F4)")
        beeFound = false
        cfg.viciousBeeMode = true
        saveCfg()
        huntViciousBee()
    end
end))

-- ============ UNLOAD ============
local function unload()
    if unloaded then return end
    unloaded = true
    for _, c in ipairs(connections) do pcall(c.Disconnect, c) end
    connections = {}
    if themeTween then themeTween:Cancel() end
    alpha:Destroy()
    gui:Destroy()
    _G.__hopper_unload = nil
    print("[hopper] unloaded")
end
_G.__hopper_unload = unload

-- ============ STARTUP ============
do
    local n = 0
    for _ in pairs(blacklist) do n = n + 1 end
    log("session " .. sessionId .. " started")
    log("loaded " .. n .. " blacklisted servers")
end
log("current job: " .. (currentId and shortId(currentId) or "unknown"), currentId and C.mid or C.red)
log("rightshift toggle · F2 hop · F3 scan · F4 hunt bee · servers tab = browse")
setStatus("ok", "ready")

-- Vicious bee mode takes priority over plain auto-hop
if cfg.viciousBeeMode then
    log("vicious bee hunter: ON — checking this server (unload to cancel)", C.yellow)
    task.delay(3, huntViciousBee)
elseif cfg.hopOnJoin then
    log("auto hop on join: ON — hopping in 3s (unload to cancel)", C.yellow)
    task.delay(3, function() if not unloaded and not hopping then doHop() end end)
end
