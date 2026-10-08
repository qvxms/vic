local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local PlaceID = game.PlaceId
local AllIDs = {}
local AllServersSeen = {}
local Blacklist = {}

local fileName = "NotSameServers.json"
if writefile and readfile and isfile and isfile(fileName) then
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(fileName))
    end)
    if ok and type(data) == "table" then
        AllIDs = data
    end
end

local WEBHOOK_URL = "https://discord.com/api/webhooks/1459586387031490580/LS84d1jaEqUy_3oyqKEupflHBBnxAfMVuclTy789gKMAo9hu27CsxcIR6JdBpgDGwj2i"

local function waitForTeleport()
    local attempts = 0
    while TeleportService:GetTeleportSetting("IsTeleporting") do
        wait(1)
        attempts = attempts + 1
        if attempts > 10 then break end
    end
end

local function attemptJoin(serverId)
    waitForTeleport()
    local success = pcall(function()
        TeleportService:TeleportToPlaceInstance(PlaceID, serverId, LocalPlayer)
    end)
    if success then
        return true
    else
        table.insert(Blacklist, serverId)
        return false
    end
end

local function fetchServers(cursor)
    local url = "https://games.roblox.com/v1/games/" .. PlaceID .. "/servers/Public?sortOrder=Asc&limit=100"
    if cursor and cursor ~= "" then
        url = url .. "&cursor=" .. cursor
    end
    local ok, res = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)
    if ok and res then
        return res
    end
    return nil
end

local function sendvic()
    if WEBHOOK_URL == "" then return end
    local httpfunc = http_request or request or syn.request or http.request
    if not httpfunc then return end

    local data = {
        username = "Bee Finder",
        content = "Vicious Bee found!\nGame: https://www.roblox.com/games/" .. PlaceID ..
                  "\nJoin: roblox://placeId=" .. PlaceID .. "&gameInstanceId=" .. game.JobId ..
                  "\nJobId: " .. game.JobId
    }

    pcall(function()
        httpfunc({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(data)
        })
    end)
end

local function serverHop()
    while true do
        local cursor = ""
        local foundAvailable = false

        repeat
            local res = fetchServers(cursor)
            if not res then break end

            cursor = res.nextPageCursor or ""

            for _, v in ipairs(res.data or {}) do
                local id = tostring(v.id)
                if not table.find(AllServersSeen, id) then
                    table.insert(AllServersSeen, id)
                end

                if v.playing < v.maxPlayers and id ~= game.JobId
                   and not table.find(Blacklist, id)
                   and not table.find(AllIDs, id) then
                    table.insert(AllIDs, id)
                    if writefile then
                        pcall(function()
                            writefile(fileName, HttpService:JSONEncode(AllIDs))
                        end)
                    end
                    if attemptJoin(id) then
                        foundAvailable = true
                        wait(2)
                    end
                end
            end
        until cursor == ""

        if not foundAvailable then
            local fallbackId = nil
            for _, id in ipairs(AllServersSeen) do
                if not table.find(AllIDs, id) and not table.find(Blacklist, id) then
                    fallbackId = id
                    break
                end
            end

            if fallbackId then
                table.insert(AllIDs, fallbackId)
                if writefile then
                    pcall(function()
                        writefile(fileName, HttpService:JSONEncode(AllIDs))
                    end)
                end
                attemptJoin(fallbackId)
            else
                Blacklist = {}
                AllIDs = {}
                if writefile then
                    pcall(function()
                        writefile(fileName, HttpService:JSONEncode(AllIDs))
                    end)
                end
                wait(5)
            end
        end

        wait(1)
    end
end

local monsters = workspace:WaitForChild("Monsters", 10)
if monsters then
    for _, v in ipairs(monsters:GetChildren()) do
        if v.Name:find("Vicious Bee") then
            sendvic()
            break
        end
    end
end

serverHop()
