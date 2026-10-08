--// Auto-execute server hopper v2
if _G.__ServerHopperRan then return end
_G.__ServerHopperRan = true

local ts = game:GetService("TeleportService")
local ps = game:GetService("Players")
local hs = game:GetService("HttpService")
local lp = ps.LocalPlayer
local cg = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local requestFunc = (syn and syn.request) or http_request or request

--// Config
local BLACKLIST_FILE = "server_blacklist.json"
local MAX_PAGES = 15            -- dig deeper
local MIN_PLAYERS = 1
local MAX_PLAYER_RATIO = 1.0    -- accept full-ish servers as last resort
local AUTO_HOP_DELAY = 3
local HOP_ON_JOIN = true

--// Blacklist
local blacklist = {}
local function loadBlacklist()
    if readfile and isfile and isfile(BLACKLIST_FILE) then
        local ok, data = pcall(function() return hs:JSONDecode(readfile(BLACKLIST_FILE)) end)
        if ok and type(data) == "table" then
            for _, id in ipairs(data) do blacklist[tostring(id)] = true end
        end
    end
end
local function saveBlacklist()
    if writefile then
        local list = {}
        for id in pairs(blacklist) do table.insert(list, id) end
        pcall(function() writefile(BLACKLIST_FILE, hs:JSONEncode(list)) end)
    end
end
loadBlacklist()

local currentJobId = tostring(game.JobId or "")
if currentJobId ~= "" then
    blacklist[currentJobId] = true
    saveBlacklist()
end

--// GUI
local gui = Instance.new("ScreenGui")
gui.Name = "ServerHopperLogs"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = (pcall(function() return cg end) and cg) or lp:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.BackgroundTransparency = 1
frame.Position = UDim2.new(0, 20, 0, 20)
frame.Size = UDim2.new(0, 380, 0, 280)
frame.Parent = gui

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 3)
layout.Parent = frame

local header = Instance.new("TextLabel")
header.BackgroundTransparency = 1
header.Font = Enum.Font.Code
header.TextSize = 15
header.TextColor3 = Color3.fromRGB(255, 255, 255)
header.TextStrokeTransparency = 0.4
header.TextXAlignment = Enum.TextXAlignment.Left
header.Size = UDim2.new(1, 0, 0, 18)
header.Text = "server hopper"
header.LayoutOrder = 1
header.Parent = frame

local logHolder = Instance.new("Frame")
logHolder.BackgroundTransparency = 1
logHolder.Size = UDim2.new(1, 0, 0, 250)
logHolder.LayoutOrder = 2
logHolder.Parent = frame

local logLayout = Instance.new("UIListLayout")
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Padding = UDim.new(0, 2)
logLayout.Parent = logHolder

local logs = {}
local MAX_LOGS = 18

local function pushLog(text, color)
    color = color or Color3.fromRGB(220, 220, 220)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Code
    label.TextSize = 13
    label.TextColor3 = color
    label.TextStrokeTransparency = 0.6
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextWrapped = true
    label.Size = UDim2.new(1, 0, 0, 14)
    label.Text = "› " .. text
    label.LayoutOrder = #logs + 1
    label.Parent = logHolder
    table.insert(logs, label)
    if #logs > MAX_LOGS then
        table.remove(logs, 1):Destroy()
    end
end

--// Helpers
local function shortId(id)
    id = tostring(id)
    return #id > 8 and id:sub(1, 8) or id
end
local function isBlacklisted(id) return blacklist[tostring(id)] == true end
local function addToBlacklist(id)
    if id and id ~= "" and not isBlacklisted(id) then
        blacklist[tostring(id)] = true
        saveBlacklist()
    end
end

local function fetchPage(cursor)
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100")
        :format(game.PlaceId)
    if cursor and cursor ~= "" then
        url = url .. "&cursor=" .. cursor
    end

    local body
    if requestFunc then
        local ok, res = pcall(function()
            return requestFunc({ Url = url, Method = "GET" })
        end)
        if ok and res and res.Body then body = res.Body end
    end
    if not body then
        local ok, res = pcall(game.HttpGet, game, url)
        if ok then body = res end
    end
    if not body then return nil end

    local ok, decoded = pcall(function() return hs:JSONDecode(body) end)
    return ok and decoded or nil
end

--// Hop
local hopping = false

local function tryApiHop()
    pushLog("scanning api...", Color3.fromRGB(180, 200, 255))

    local candidates = {}
    local cursor = nil
    local totalScanned = 0

    for page = 1, MAX_PAGES do
        local data = fetchPage(cursor)
        if not data or not data.data then break end

        for _, s in ipairs(data.data) do
            totalScanned = totalScanned + 1
            local id = tostring(s.id)
            local ratio = s.playing / math.max(s.maxPlayers, 1)
            if id ~= currentJobId
                and not isBlacklisted(id)
                and s.playing >= MIN_PLAYERS
                and ratio < MAX_PLAYER_RATIO then
                table.insert(candidates, s)
            end
        end

        cursor = data.nextPageCursor
        if not cursor or cursor == "" then break end
    end

    pushLog("scanned " .. totalScanned .. " servers")
    pushLog("found " .. #candidates .. " candidates",
        #candidates > 0 and Color3.fromRGB(150, 255, 180) or Color3.fromRGB(255, 150, 150))

    if #candidates == 0 then return false end

    local chosen = candidates[math.random(1, #candidates)]
    pushLog("selected " .. shortId(chosen.id) ..
        " (" .. chosen.playing .. "/" .. chosen.maxPlayers .. ")",
        Color3.fromRGB(150, 255, 180))

    if currentJobId ~= "" then addToBlacklist(currentJobId) end

    task.wait(0.5)

    local ok = pcall(function()
        local opts = Instance.new("TeleportOptions")
        opts.ServerInstanceId = chosen.id
        ts:TeleportAsync(game.PlaceId, { lp }, opts)
    end)

    if not ok then
        pcall(function()
            ts:TeleportToPlaceInstance(game.PlaceId, chosen.id, lp)
        end)
    end
    return true
end

local function tryBlindHop()
    pushLog("api exhausted — asking roblox for a server",
        Color3.fromRGB(255, 200, 120))

    -- Rejoin the same place; Roblox matchmaking will assign a new server
    -- most of the time, especially if we waited a moment first.
    task.wait(1)

    local ok = pcall(function()
        ts:Teleport(game.PlaceId, lp)
    end)

    if not ok then
        -- Last resort: TeleportAsync with no ServerInstanceId
        pcall(function()
            ts:TeleportAsync(game.PlaceId, { lp })
        end)
    end
    return ok
end

local function serverHop()
    if hopping then return end
    hopping = true

    if not tryApiHop() then
        tryBlindHop()
    end

    task.delay(10, function() hopping = false end)
end

--// API
_G.ServerBlacklist = {
    add = addToBlacklist,
    remove = function(id)
        id = tostring(id)
        if blacklist[id] then
            blacklist[id] = nil
            saveBlacklist()
        end
    end,
    clear = function()
        blacklist = {}
        saveBlacklist()
        pushLog("blacklist cleared", Color3.fromRGB(255, 200, 120))
    end,
    list = function()
        local t = {}
        for id in pairs(blacklist) do table.insert(t, id) end
        return t
    end,
    has = isBlacklisted,
    log = pushLog,
    hop = serverHop,
}

--// Keybinds
local guiVisible = true
UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        guiVisible = not guiVisible
        gui.Enabled = guiVisible
    elseif input.KeyCode == Enum.KeyCode.F2 and not hopping then
        pushLog("manual hop", Color3.fromRGB(200, 200, 255))
        serverHop()
    end
end)

--// Boot
pushLog("loaded " .. tostring(#_G.ServerBlacklist.list()) .. " blacklisted",
    Color3.fromRGB(180, 180, 180))
pushLog("job: " .. (currentJobId ~= "" and shortId(currentJobId) or "unknown"),
    currentJobId ~= "" and Color3.fromRGB(180, 180, 180) or Color3.fromRGB(255, 120, 120))
pushLog("rightshift toggle • F2 hop", Color3.fromRGB(160, 160, 200))

if HOP_ON_JOIN then
    task.spawn(function()
        task.wait(AUTO_HOP_DELAY)
        serverHop()
    end)
end
