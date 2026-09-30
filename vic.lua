local ts = game:GetService("TeleportService")
local ps = game:GetService("Players")
local hs = game:GetService("HttpService")
local lp = ps.LocalPlayer

local requestFunc = (syn and syn.request) or http_request or request

local function serverHop()
    print("Finding fresh server...")
    
    local success, result = pcall(function()
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Desc&limit=100"
        if requestFunc then
            local res = requestFunc({Url = url, Method = "GET"})
            if res and res.Body then
                return hs:JSONDecode(res.Body)
            end
        end
        return hs:JSONDecode(game:HttpGet(url))
    end)

    if success and result and result.data then
        local servers = {}
        for _, s in ipairs(result.data) do
            if type(s) == "table" and s.playing < s.maxPlayers and s.id ~= game.JobId and s.playing >= 1 then
                table.insert(servers, s.id)
            end
        end
        
        if #servers > 0 then
            local targetServer = servers[math.random(1, #servers)]
            print("Hopping to instance: " .. targetServer)
            
            local tpSuccess = pcall(function()
                ts:TeleportToPlaceInstance(game.PlaceId, targetServer, lp)
            end)
            
            if tpSuccess then return end
        end
    end
    
    -- Fallback
    pcall(function()
        ts:Teleport(game.PlaceId, lp)
    end)
end

local monsters = workspace:WaitForChild("Monsters", 10)
if not monsters then
    serverHop()
    return
end

local hasVicious = false
for _, mob in ipairs(monsters:GetChildren()) do
    if string.find(mob.Name, "Vicious") then
        hasVicious = true
        break
    end
end

if not hasVicious then
    print("No stingers here, hopping...")
    serverHop()
    return
end

local hopped = false
local function triggerHop()
    if hopped then return end
    hopped = true
    print("Triggering forced server hop...")
    serverHop()
end

-- Live state watcher (scans every 300ms)
task.spawn(function()
    task.wait(3)
    
    while not hopped do
        task.wait(0.3)
        local currentMonsters = workspace:FindFirstChild("Monsters")
        local stillHasVicious = false
        
        if currentMonsters then
            for _, mob in ipairs(currentMonsters:GetChildren()) do
                if string.find(mob.Name, "Vicious") then
                    stillHasVicious = true
                    break
                end
            end
        end
        
        if not stillHasVicious then
            print("Vicious bee gone, hopping now...")
            triggerHop()
            break
        end
    end
end)

-- The Big Red Button (5-minute safety net)
task.spawn(function()
    task.wait(300)
    if not hopped then
        print("Safety net timer reached: forcing hop")
        triggerHop()
    end
end)

-- Execute external script
print("Vic is here, executing script...")
pcall(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Chris12089/atlasbss/main/script.lua"))()
end)
