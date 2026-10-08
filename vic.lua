local playeruser = game:GetService("Players").LocalPlayer.Name

if game:GetService("Players").LocalPlayer.Name == playeruser then
    local ts = game:GetService("TeleportService")
    local ps = game:GetService("Players")
    local hs = game:GetService("HttpService")
    local lp = ps.LocalPlayer

    -- Use executor request function if available to prevent HttpService blocks
    local requestFunc = (syn and syn.request) or http_request or request

    local function serverHop()
        print("finding fresh server via request...")
        
        local success, result = pcall(function()
            local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Desc&limit=100"
            local response = requestFunc({
                Url = url,
                Method = "GET"
            })
            if response and response.Body then
                return hs:JSONDecode(response.Body)
            end
            return nil
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
                print("hopping to instance: " .. targetServer)
                
                local tpSuccess = pcall(function()
                    ts:TeleportToPlaceInstance(game.PlaceId, targetServer, lp)
                end)
                
                if tpSuccess then return end
            end
        end
        
        -- Ultimate Fallback: standard queue if request api acts up
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
        print("no stingers bud")
        serverHop()
        return
    end

    local hopped = false
    local function triggerHop()
        if hopped then return end
        hopped = true
        print("triggering forced server hop...")
        serverHop()
    end

    -- 1. Independent State Watcher (Scans every 300ms)
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
                print("vicious bee is officially gone, hopping...")
                triggerHop()
                break
            end
        end
    end)

    -- 2. The Big Red Button (5-minute max safety net)
    task.spawn(function()
        task.wait(300)
        if not hopped then
            print("safety net timer reached: forcing hop")
            triggerHop()
        end
    end)

    -- 3. Execute External Script Safely
    print("vic is here, executing script...")
    pcall(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/Chris12089/atlasbss/main/script.lua"))()
    end)
end
