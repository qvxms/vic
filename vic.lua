local ts = game:GetService("TeleportService")
local ps = game:GetService("Players")
local hs = game:GetService("HttpService")
local lp = ps.LocalPlayer

local requestFunc = (syn and syn.request) or http_request or request

local BLACKLIST_FILE = "server_blacklist.json"

-- In-memory blacklist (always works)
local blacklist = {}

-- Load persisted blacklist
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
        for id, _ in pairs(blacklist) do
            table.insert(list, id)
        end
        pcall(function()
            writefile(BLACKLIST_FILE, hs:JSONEncode(list))
        end)
    end
end

loadBlacklist()

-- Always blacklist the CURRENT server immediately on load
if game.JobId and game.JobId ~= "" then
    blacklist[tostring(game.JobId)] = true
    saveBlacklist()
    print("[Blacklist] Current server blacklisted: " .. game.JobId)
end

local function isBlacklisted(serverId)
    return blacklist[tostring(serverId)] == true
end

local function addToBlacklist(serverId)
    if serverId and serverId ~= "" and not isBlacklisted(serverId) then
        blacklist[tostring(serverId)] = true
        saveBlacklist()
        print("[Blacklist] Added: " .. tostring(serverId))
    end
end

local function removeFromBlacklist(serverId)
    serverId = tostring(serverId)
    if blacklist[serverId] then
        blacklist[serverId] = nil
        saveBlacklist()
        print("[Blacklist] Removed: " .. serverId)
        return true
    end
    return false
end

local function clearBlacklist()
    blacklist = {}
    saveBlacklist()
    print("[Blacklist] Cleared")
end

local function fetchServers(cursor)
    local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Desc&limit=100"
    if cursor then
        url = url .. "&cursor=" .. cursor
    end

    local body
    if requestFunc then
        local ok, res = pcall(function()
            return requestFunc({ Url = url, Method = "GET" })
        end)
        if ok and res and res.Body then
            body = res.Body
        end
    end

    if not body then
        local ok, res = pcall(function()
            return game:HttpGet(url)
        end)
        if ok then body = res end
    end

    if not body then return nil end

    local ok, decoded = pcall(function()
        return hs:JSONDecode(body)
    end)
    if ok then return decoded end
    return nil
end

local function serverHop()
    print("[ServerHop] Searching for a fresh server...")

    -- Collect servers across multiple pages to find a non-blacklisted one
    local cursor = nil
    local chosen = nil

    for page = 1, 5 do
        local data = fetchServers(cursor)
        if not data or not data.data then break end

        for _, server in ipairs(data.data) do
            local id = tostring(server.id)
            if id ~= tostring(game.JobId)
                and server.playing < server.maxPlayers
                and not isBlacklisted(id) then
                chosen = server
                break
            end
        end

        if chosen then break end
        cursor = data.nextPageCursor
        if not cursor then break end
    end

    if not chosen then
        warn("[ServerHop] No fresh servers available. All are blacklisted or full.")
        return
    end

    print("[ServerHop] Hopping to " .. chosen.id .. " (" .. chosen.playing .. "/" .. chosen.maxPlayers .. ")")

    -- Blacklist current before teleporting
    if game.JobId and game.JobId ~= "" then
        addToBlacklist(game.JobId)
    end

    -- Use Teleport with teleport options (more reliable than TeleportToPlaceInstance)
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
end

_G.ServerBlacklist = {
    add = addToBlacklist,
    remove = removeFromBlacklist,
    clear = clearBlacklist,
    list = function()
        local t = {}
        for id, _ in pairs(blacklist) do table.insert(t, id) end
        return t
    end,
    has = isBlacklisted,
}

serverHop()
