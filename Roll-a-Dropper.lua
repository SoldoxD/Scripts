-- ================= ANTI-IDLE (ANTI-AFK) =================

local Players = game:GetService("Players")

local GC = getconnections or get_signal_cons

if GC then
    for _, v in pairs(GC(Players.LocalPlayer.Idled)) do
        if v["Disable"] then v["Disable"](v) elseif v["Disconnect"] then v["Disconnect"](v) end
    end
else
    local VirtualUser = cloneref(game:GetService("VirtualUser"))
    Players.LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

print("✅ Anti-Idle enabled")

-- ================= LOAD GUI =================

local GuiLibrary = loadstring(game:HttpGet("https://raw.githubusercontent.com/SoldoxD/libery/refs/heads/main/main"))()

-- ================= SERVICES =================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local Tycoons = workspace:WaitForChild("Map"):WaitForChild("Tycoons")

-- ================= SETTINGS =================

local ENABLED              = false
local AUTO_BUY             = false
local MIN_VALUE            = 1e9
local AUTO_BUY_UPGRADERS   = false
local AUTO_CLAIM_LUCKY     = false
local AUTO_COLLECT         = false

-- ================= REMOTES =================

local function getRemote(name)
    return ReplicatedStorage
        :WaitForChild("rbxts_include"):WaitForChild("node_modules"):WaitForChild("@rbxts")
        :WaitForChild("remo"):WaitForChild("src"):WaitForChild("container"):WaitForChild(name)
end

local PurchaseEvent      = getRemote("crate.purchase")
local ShopPurchaseRemote = getRemote("shop.purchase.item")
local ClaimLuckyRemote   = getRemote("playtime.claim")
local CollectRemote      = getRemote("collector.collect")
local EventRemote        = getRemote("event")

-- ================= PRICE PARSER & MONEY =================

local function parsePrice(str)
    if not str then return 0 end
    str = tostring(str):gsub("%$", ""):gsub("%s+", ""):gsub(",", ".")
    local multiplier = 1
    if str:find("B") then multiplier = 1e9; str = str:gsub("B", "")
    elseif str:find("M") then multiplier = 1e6; str = str:gsub("M", "")
    elseif str:find("K") then multiplier = 1e3; str = str:gsub("K", "")
    end
    return (tonumber(str) or 0) * multiplier
end

local function getMoney()
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then return 0 end
    local money = leaderstats:FindFirstChild("Money")
    if not money then return 0 end
    return money.Value
end

-- ================= LOAD CLIENT STORE =================

local clientStore, upgraderList

task.wait(2)
pcall(function()
    local module_3 = require(ReplicatedStorage:WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
    clientStore = module_3.import(script, ReplicatedStorage, "TS", "modules", "store", "client").client
    local upgradersConfig = module_3.import(script, ReplicatedStorage, "TS", "modules", "configs", "upgraders", "upgraders")
    upgraderList = upgradersConfig.upgraderList
end)

-- ================= GUI =================
GuiLibrary.Icon = 105049082124083
local window  = GuiLibrary:CreateWindow("Build Ur Tycoon GUI - By cyber_modz", UDim2.new(0, 540, 0, 450))
local mainTab = GuiLibrary:CreateTab(window, "Main")

-- Scanner

GuiLibrary:CreateSection(mainTab, "Scanner")

GuiLibrary:CreateToggle(mainTab, "Enable Scanner", false, function(state)
    ENABLED = state
end)

GuiLibrary:CreateToggle(mainTab, "Auto Buy Crates", false, function(state)
    AUTO_BUY = state
end)

GuiLibrary:CreateInput(mainTab, "Min Value (e.g. 1B, 500M)", function(text)
    local value = parsePrice(text)
    if value > 0 then
        MIN_VALUE = value
        GuiLibrary:CreateNotification("Value Set", "Min value set to " .. text, 2, "success")
    else
        GuiLibrary:CreateNotification("Invalid Input", "Use formats like 1B, 500M, 50K", 3, "error")
    end
end)

GuiLibrary:CreateLabel(mainTab, "Only buys crates you can afford")

-- Upgraders

GuiLibrary:CreateSection(mainTab, "Upgraders")

GuiLibrary:CreateToggle(mainTab, "Auto Buy Upgraders 2-6", false, function(state)
    AUTO_BUY_UPGRADERS = state
    print(state and "✅ Auto Buy Upgraders 2-6 ENABLED" or "❌ Auto Buy Upgraders 2-6 DISABLED")
end)

-- Collector

GuiLibrary:CreateSection(mainTab, "Collector")

GuiLibrary:CreateToggle(mainTab, "Auto Collect", false, function(state)
    AUTO_COLLECT = state
    print(state and "✅ Auto Collect ENABLED" or "❌ Auto Collect DISABLED")
end)

-- Lucky Blocks

GuiLibrary:CreateSection(mainTab, "Lucky Blocks")

GuiLibrary:CreateToggle(mainTab, "Auto Claim Lucky Blocks", false, function(state)
    AUTO_CLAIM_LUCKY = state
    print(state and "✅ Auto Claim Lucky Blocks ENABLED" or "❌ Auto Claim Lucky Blocks DISABLED")
end)

-- ================= FIND TYCOON =================

local myTycoon = nil

for _, tycoon in pairs(Tycoons:GetChildren()) do
    local owner = tycoon:GetAttribute("ownerId")
    if owner and tonumber(owner) == player.UserId then
        myTycoon = tycoon
        break
    end
end

if not myTycoon then
    GuiLibrary:CreateNotification("Error", "Tycoon not found — rejoin and rerun!", 5, "error")
    warn("❌ Tycoon not found")
    return
end

print("✅ Found your tycoon:", myTycoon.Name)

-- ================= AUTO COLLECT =================

local unitsFolder = myTycoon:WaitForChild("Placement"):WaitForChild("Units")
local collectors  = {}

local function rebuildCollectors()
    collectors = {}
    for _, u in pairs(unitsFolder:GetChildren()) do
        if u:IsA("Model") and u:GetAttribute("unitType") == "collector" then
            table.insert(collectors, u)
        end
    end
end

rebuildCollectors()
unitsFolder.ChildAdded:Connect(rebuildCollectors)
unitsFolder.ChildRemoved:Connect(rebuildCollectors)

task.spawn(function()
    while true do
        task.wait()
        if AUTO_COLLECT then
            for _, u in ipairs(collectors) do
                task.spawn(CollectRemote.InvokeServer, CollectRemote, u)
            end
        end
    end
end)

-- ================= CRATE SCANNER =================

local cratesFolder = myTycoon:WaitForChild("DropperConveyor"):WaitForChild("Crates")

local function getPriceText(crate)
    for _, obj in ipairs(crate:GetDescendants()) do
        if obj.Name == "Price" and obj:IsA("TextLabel") then return obj.Text end
    end
end

local function buyCrate(crate)
    if not AUTO_BUY then return end
    pcall(function() PurchaseEvent:InvokeServer(crate) end)
end

local function scanCrate(crate)
    if not ENABLED then return end
    local priceText = getPriceText(crate)
    if not priceText then return end
    local value = parsePrice(priceText)
    if value >= MIN_VALUE and getMoney() >= value then
        print("💰 BUYABLE CRATE:", crate.Name, priceText)
        GuiLibrary:CreateNotification("Crate Found", crate.Name .. " (" .. priceText .. ")", 2, "success")
        buyCrate(crate)
    end
end

for _, crate in pairs(cratesFolder:GetChildren()) do
    task.spawn(scanCrate, crate)
end

cratesFolder.ChildAdded:Connect(function(crate)
    task.wait(0.2)
    scanCrate(crate)
end)

-- ================= AUTO BUY UPGRADERS =================

local canBuyThisRestock = true

local function tryBuyUpgraders()
    if not AUTO_BUY_UPGRADERS or not canBuyThisRestock or not clientStore then return end
    local stock = clientStore().stock or {}
    local upgraderStock = stock.upgraders or {}
    for i = 2, 6 do
        if (upgraderStock[tostring(i)] or 0) > 0 and canBuyThisRestock then
            print("📦 Upgrader " .. i .. " in stock! Buying...")
            pcall(function()
                ShopPurchaseRemote:InvokeServer({ type = "upgrader", upgraderType = tostring(i), variant = "N" })
            end)
            canBuyThisRestock = false
            break
        end
    end
end

EventRemote.OnClientEvent:Connect(function(data)
    if typeof(data) == "table" and data.type == "on-shop-restocked" then
        print("🛒 Shop restocked!")
        canBuyThisRestock = true
        task.wait(1.2)
        tryBuyUpgraders()
    end
end)

task.wait(2)
tryBuyUpgraders()

-- ================= AUTO CLAIM LUCKY BLOCKS =================

local claimedThisCycle = {}

local function tryClaimLuckyBlocks()
    if not AUTO_CLAIM_LUCKY then return end

    for _, obj in ipairs(workspace:GetDescendants()) do
        if not obj:IsA("Model") then continue end

        local crateType = obj:GetAttribute("crateType")
        if not crateType then continue end

        if crateType ~= "Lucky_Block" and crateType ~= "Epic_Lucky_Block" and crateType ~= "Secret_Lucky_Block" then
            continue
        end

        local ownerId  = obj:GetAttribute("ownerId")
        local timeLeft = obj:GetAttribute("timeLeft") or 0
        local claimed  = obj:GetAttribute("claimed") or false

        if ownerId == player.UserId
            and not claimed
            and timeLeft <= 0
            and not claimedThisCycle[crateType]
        then
            print(`🟢 Ready Lucky Block detected! (Type: {crateType}) - Claiming...`)

            local success = pcall(function()
                ClaimLuckyRemote:InvokeServer(crateType)
            end)

            if success then
                print(`✅ Successfully claimed: {crateType}`)
                claimedThisCycle[crateType] = true
                task.wait(3.5)
            else
                print(`❌ Failed to claim: {crateType}`)
                task.wait(1)
            end
        end
    end
end

task.spawn(function()
    while true do
        task.wait(12)
        tryClaimLuckyBlocks()
    end
end)

EventRemote.OnClientEvent:Connect(function(data)
    if typeof(data) == "table" and data.type == "on-shop-restocked" then
        claimedThisCycle = {}
        print("🔄 Lucky Block claim tracker reset for new restock cycle")
    end
end)

print("✅ Build Ur Tycoon GUI loaded!")
