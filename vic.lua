local ts = game:GetService("TeleportService")
local ps = game:GetService("Players")
local hs = game:GetService("HttpService")
local lp = ps.LocalPlayer

-- Use executor request function if available to prevent HttpService blocks
local requestFunc = (syn and syn.request) or http_request or request

-- Blacklist system
local BLACKLIST_FILE = "server_blacklist.json"

-- Load blacklist from file
local function loadBlacklist()
    if writefile and readfile and isfile then
        if isfile(BLACKLIST_FILE) then
            local success, data = pcall(function()
                return hs:JSONDecode(readfile(BLACKLIST_FILE))
            end)
            if success and type(data) == "table" then
                return data
            end
        end
    end
    return {}
end

-- Save blacklist to file
local function saveBlacklist(blacklist)
    if writefile then
        pcall(function()
            writefile(BLACKLIST_FILE, hs:JSONEncode(blacklist))
        end)
    end
end

-- Global blacklist table
local blacklist = loadBlacklist()

-- Check if a server is blacklisted
local function isBlacklisted(serverId)
    for _, id in ipairs(blacklist) do
        if tostring(id) == tostring(serverId) then
            return true
        end
    end
    return false
end

-- Add a server to blacklist
local function addToBlacklist(serverId)
    if not isBlacklisted(serverId) then
        table.insert(blacklist, tostring(serverId))
        saveBlacklist(blacklist)
        print("[Blacklist] Added server: " .. tostring(serverId))
    end
end

-- Remove a server from blacklist
local function removeFromBlacklist(serverId)
    for i, id in ipairs(blacklist) do
        if tostring(id) == tostring(serverId) then
            table.remove(blacklist, i)
            saveBlacklist(blacklist)
            print("[Blacklist] Removed server: " .. tostring(serverId))
            return true
        end
    end
    return false
end

-- Clear the blacklist
local function clearBlacklist()
    blacklist = {}
    saveBlacklist(blacklist)
    print("[Blacklist] Cleared all servers")
end

-- Server hop function with blacklist filtering
local function serverHop()
    print("Finding fresh server via request...")

    local success, result = pcall(function()
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Desc&limit=100"
        
        local response
        if requestFunc then
            response = requestFunc({
                Url = url,
                Method = "GET"
            })
        else
            response = {
                Body = game:HttpGet(url)
            }
        end

        local data = hs:JSONDecode(response.Body)
        
        if not data or not data.data then
            warn("[ServerHop] Failed to fetch server list")
            return
        end

        -- Filter out blacklisted and full servers
        local availableServers = {}
        for _, server in ipairs(data.data) do
            if server.id ~= game.JobId 
                and server.playing < server.maxPlayers 
                and not isBlacklisted(server.id) then
                table.insert(availableServers, server)
            end
        end

        if #availableServers == 0 then
            warn("[ServerHop] No available servers found (all blacklisted or full)")
            return
        end

        -- Pick a random server from available ones
        local chosen = availableServers[math.random(1, #availableServers)]
        print("[ServerHop] Hopping to server: " .. chosen.id .. " (" .. chosen.playing .. "/" .. chosen.maxPlayers .. ")")
        
        -- Blacklist the current server before hopping (so you don't return to it)
        addToBlacklist(game.JobId)
        
        ts:TeleportToPlaceInstance(game.PlaceId, chosen.id, lp)
    end)
    
    if not success then
        warn("[ServerHop] Error: " .. tostring(result))
    end
end

-- Expose blacklist functions globally for manual control
_G.ServerBlacklist = {
    add = addToBlacklist,
    remove = removeFromBlacklist,
    clear = clearBlacklist,
    list = function() return blacklist end,
    has = isBlacklisted
}

-- Run server hop
serverHop()
