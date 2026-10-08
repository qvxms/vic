--// Services
local ts = game:GetService("TeleportService")
local ps = game:GetService("Players")
local hs = game:GetService("HttpService")
local lp = ps.LocalPlayer
local cg = game:GetService("CoreGui")

local requestFunc = (syn and syn.request) or http_request or request

--// Config
local BLACKLIST_FILE = "server_blacklist.json"
local MAX_PAGES = 8
local MIN_PLAYERS = 1        -- skip empty servers
local MAX_PLAYER_RATIO = 0.9 -- skip near-full servers

--// In-memory blacklist
local blacklist = {}

local function loadBlacklist()
    if readfile and isfile and isfile(BLACKLIST_FILE) then
        local ok, data = pcall(function()
            return hs:JSONDecode(readfile(BLACKLIST_FILE))
        end)
        if ok and type(data) == "table" then
            for _, id in ipairs(data) do
                blacklist[tostring(id)] = true
            end
        end
    end
end

local function saveBlacklist()
    if writefile then
        local list = {}
        for id in pairs(blacklist) do table.insert(list, id) end
        pcall(function()
            writefile(BLACKLIST_FILE, hs:JSONEncode(list))
        end)
    end
end

loadBlacklist()

-- Capture current JobId (may be empty on some executors)
local currentJobId = tostring(game.JobId or "")
if currentJobId ~= "" then
    blacklist[currentJobId] = true
    saveBlacklist()
end

--// GUI (no background, just floating text)
local gui = Instance.new("ScreenGui")
gui.Name = "ServerHopperLogs"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = (pcall(function() return cg end) and cg) or lp:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.BackgroundTransparency = 1
frame.Position = UDim2.new(0, 20, 0, 20)
frame.Size = UDim2.new(0, 380, 0, 260)
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
logHolder.Size = UDim2.new(1, 0, 0, 230)
logHolder.LayoutOrder = 2
logHolder.Parent = frame

local logLayout = Instance.new("UIListLayout")
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Padding = UDim.new(0, 2)
logLayout.Parent = logHolder

local logs = {}
local MAX_LOGS = 16

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
        local old = table.remove(logs, 1)
        old:Destroy()
    end
end

--// Helpers
local function shortId(id)
    id = tostring(id)
    if #id > 8 then return id:sub(1, 8) end
    return id
end

local function isBlacklisted(id)
    return blacklist[tostring(id)] == true
end

local function addToBlacklist(id)
    if id and id ~= "" and not isBlacklisted(id) then
        blacklist[tostring(id)] = true
        saveBlacklist()
    end
end

local function fetchPage(cursor)
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100")
        :format(game.PlaceId)
    if cursor then url = url .. "&cursor=" .. cursor end

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
    if ok then return decoded end
    return nil
end

--// Hop logic
local function serverHop()
    pushLog("scanning for open servers...", Color3.fromRGB(180, 200, 255))

    local candidates = {}
    local cursor = nil

    for page = 1, MAX_PAGES do
        local data = fetchPage(cursor)
        if not data or not data.data then
            pushLog("page " .. page .. " failed", Color3.fromRGB(255, 150, 150))
            break
        end

        for _, s in ipairs(data.data) do
            local id = tostring(s.id)
            local ratio = s.playing / math.max(s.maxPlayers, 1)
            if id ~= currentJobId
                and not isBlacklisted(id)
                and s.playing >= MIN_PLAYERS
                and ratio < MAX_PLAYER_RATIO then
                table.insert(candidates, s)
            end
        end

        pushLog("page " .. page .. " → " .. #candidates .. " candidates")

        cursor = data.nextPageCursor
        if not cursor then break end
    end

    if #candidates == 0 then
        pushLog("no fresh servers found", Color3.fromRGB(255, 120, 120))
        pushLog("try again in a minute", Color3.fromRGB(180, 180, 180))
        return
    end

    local chosen = candidates[math.random(1, #candidates)]
    pushLog("selected " .. shortId(chosen.id) ..
        " (" .. chosen.playing .. "/" .. chosen.maxPlayers .. ")",
        Color3.fromRGB(150, 255, 180))

    if currentJobId ~= "" then
        addToBlacklist(currentJobId)
    end

    task.wait(0.6)

    local ok = pcall(function()
        local opts = Instance.new("TeleportOptions")
        opts.ServerInstanceId = chosen.id
        ts:TeleportAsync(game.PlaceId, { lp }, opts)
    end)

    if not ok then
        pushLog("teleportAsync failed, retrying...", Color3.fromRGB(255, 200, 120))
        pcall(function()
            ts:TeleportToPlaceInstance(game.PlaceId, chosen.id, lp)
        end)
    end
end

--// Public API
_G.ServerBlacklist = {
    add = addToBlacklist,
    remove = function(id)
        id = tostring(id)
        if blacklist[id] then
            blacklist[id] = nil
            saveBlacklist()
            pushLog("removed " .. shortId(id), Color3.fromRGB(255, 200, 120))
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
}

pushLog("loaded " .. tostring(#_G.ServerBlacklist.list()) .. " blacklisted servers",
    Color3.fromRGB(180, 180, 180))
pushLog("current job: " .. (currentJobId ~= "" and shortId(currentJobId) or "unknown"),
    currentJobId ~= "" and Color3.fromRGB(180, 180, 180) or Color3.fromRGB(255, 120, 120))

serverHop()
