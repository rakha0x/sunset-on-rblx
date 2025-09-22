local Workspace = game:GetService("Workspace")
-- IMPORT MODELS POT JOBS
local FarmJobs = Workspace:WaitForChild("FarmJobs")
-- ITEM POT CONTAINERS
local Leaves = FarmJobs:WaitForChild("Leaves")
local Palm = FarmJobs:WaitForChild("Palm")
local Broco = FarmJobs:WaitForChild("Broco")

-- DATASTORE
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
-- local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- DataStore Configuration
local InventoryDataStore = DataStoreService:GetDataStore("player_inventory_v1")
local MoneyDataStore = DataStoreService:GetDataStore("player_money_v1")
local AUTO_SAVE_INTERVAL = 60 -- Auto save setiap 60 detik
local RETRY_ATTEMPTS = 3 -- Maksimal retry jika save/load gagal

-- Configuration
local HOLD_DURATION = 3 -- 3 detik hold untuk harvest
local RESPAWN_TIME = 10 -- 10 detik untuk respawn
local MAX_DISTANCE = 10

-- Harga untuk setiap item
local ITEM_PRICES = {
	Leaves = 15000,
	Broco = 20000,
	Palm = 50000,
}

-- Cache untuk mengurangi DataStore calls
local inventoryCache = {}
local moneyCache = {}
local pendingSaves = {}

-- Remote events/functions untuk update UI
local BalanceChangedRE = Instance.new("RemoteEvent")
BalanceChangedRE.Name = "BalanceChanged"
BalanceChangedRE.Parent = ReplicatedStorage

local GetBalanceRF = Instance.new("RemoteFunction")
GetBalanceRF.Name = "GetBalance"
GetBalanceRF.Parent = ReplicatedStorage

-- ==================== DATASTORE FUNCTIONS ====================
-- Function untuk load inventory dari DataStore
local function loadInventory(player)
	local success, data

	for attempt = 1, RETRY_ATTEMPTS do
		success, data = pcall(function()
			return InventoryDataStore:GetAsync(player.UserId)
		end)

		if success then
			break
		else
			warn("Failed to load inventory for " .. player.Name .. " (Attempt " .. attempt .. "): " .. tostring(data))
			wait(1) -- Wait before retry
		end
	end

	if success and data then
		inventoryCache[player.UserId] = data
		print("Loaded inventory for " .. player.Name .. ": " .. (data.Leaves or 0) .. " leaves")
		return data
	else
		-- Default inventory jika load gagal
		inventoryCache[player.UserId] = { Leaves = 0 }
		warn("Failed to load inventory for " .. player.Name .. ", using default")
		return inventoryCache[player.UserId]
	end
end

-- Function untuk load money dari DataStore
local function loadMoney(player)
	local success, data

	for attempt = 1, RETRY_ATTEMPTS do
		success, data = pcall(function()
			return MoneyDataStore:GetAsync(player.UserId)
		end)

		if success then
			break
		else
			warn("Failed to load money for " .. player.Name .. " (Attempt " .. attempt .. "): " .. tostring(data))
			wait(1) -- Wait before retry
		end
	end

	if success and data then
		moneyCache[player.UserId] = data
		print("Loaded money for " .. player.Name .. ": $" .. (data or 0))
		BalanceChangedRE:FireClient(player, moneyCache[player.UserId])
		return data
	else
		moneyCache[player.UserId] = 0
		warn("Failed to load money for " .. player.Name .. ", using default")
		BalanceChangedRE:FireClient(player, 0)
		return 0
	end
end

-- Function untuk save inventory ke DataStore
local function saveInventory(player, forced)
	if not forced and pendingSaves[player.UserId] then
		return
	end

	local data = inventoryCache[player.UserId]
	if not data then
		return
	end

	pendingSaves[player.UserId] = true

	spawn(function()
		local success, errorMessage

		for attempt = 1, RETRY_ATTEMPTS do
			success, errorMessage = pcall(function()
				InventoryDataStore:SetAsync(player.UserId, data)
			end)

			if success then
				break
			else
				warn(
					"Failed to save inventory for "
						.. player.Name
						.. " (Attempt "
						.. attempt
						.. "): "
						.. tostring(errorMessage)
				)
				wait(1)
			end
		end

		if success then
			print("Saved inventory for " .. player.Name .. ": " .. data.Leaves .. " leaves")
		else
			warn("Failed to save inventory for " .. player.Name .. " after " .. RETRY_ATTEMPTS .. " attempts")
		end

		pendingSaves[player.UserId] = nil
	end)
end

-- Function untuk save money ke DataStore
local function saveMoney(player, forced)
	if not forced and pendingSaves[player.UserId .. "_money"] then
		return
	end

	local money = moneyCache[player.UserId]
	if not money then
		return
	end

	pendingSaves[player.UserId .. "_money"] = true

	spawn(function()
		local success, errorMessage

		for attempt = 1, RETRY_ATTEMPTS do
			success, errorMessage = pcall(function()
				MoneyDataStore:SetAsync(player.UserId, money)
			end)

			if success then
				break
			else
				warn(
					"Failed to save money for "
						.. player.Name
						.. " (Attempt "
						.. attempt
						.. "): "
						.. tostring(errorMessage)
				)
				wait(1)
			end
		end

		if success then
			print("Saved money for " .. player.Name .. ": $" .. money)
		else
			warn("Failed to save money for " .. player.Name .. " after " .. RETRY_ATTEMPTS .. " attempts")
		end

		pendingSaves[player.UserId .. "_money"] = nil
	end)
end

-- ==================== INVENTORY CACHE FUNCTIONS ====================
-- Function untuk menambah item ke cache
local function addToInventoryCache(player, itemName, quantity)
	if not inventoryCache[player.UserId] then
		inventoryCache[player.UserId] = { [itemName] = 0 }
	end

	if not inventoryCache[player.UserId][itemName] then
		inventoryCache[player.UserId][itemName] = 0
	end

	inventoryCache[player.UserId][itemName] = inventoryCache[player.UserId][itemName] + quantity

	-- Update folder inventory untuk konsistensi
	local inventory = player:FindFirstChild("Inventory")
	if not inventory then
		inventory = Instance.new("Folder")
		inventory.Name = "Inventory"
		inventory.Parent = player
	end

	local itemValue = inventory:FindFirstChild(itemName)
	if itemValue then
		itemValue.Value = inventoryCache[player.UserId][itemName]
	else
		itemValue = Instance.new("IntValue")
		itemValue.Name = itemName
		itemValue.Value = inventoryCache[player.UserId][itemName]
		itemValue.Parent = inventory
	end

	saveInventory(player, false)
	return inventoryCache[player.UserId][itemName]
end

-- Function untuk mengurangi item dari cache
local function removeFromInventoryCache(player, itemName, quantity)
	if not inventoryCache[player.UserId] or not inventoryCache[player.UserId][itemName] then
		return 0
	end

	inventoryCache[player.UserId][itemName] = math.max(0, inventoryCache[player.UserId][itemName] - quantity)

	-- Update folder inventory
	local inventory = player:FindFirstChild("Inventory")
	if inventory then
		local itemValue = inventory:FindFirstChild(itemName)
		if itemValue then
			itemValue.Value = inventoryCache[player.UserId][itemName]
		end
	end

	saveInventory(player, false)
	return inventoryCache[player.UserId][itemName]
end

-- Function untuk menambah uang ke cache
local function addMoneyToCache(player, amount)
	if not moneyCache[player.UserId] then
		moneyCache[player.UserId] = 0
	end

	moneyCache[player.UserId] = moneyCache[player.UserId] + amount
	BalanceChangedRE:FireClient(player, moneyCache[player.UserId])
	saveMoney(player, false)
	return moneyCache[player.UserId]
end

-- ==================== TOOL MANAGEMENT FUNCTIONS ====================
-- Function untuk mencari tool berdasarkan item type di backpack atau character
local function findItemTool(player, itemType)
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, item in pairs(backpack:GetChildren()) do
			if item.Name:find(itemType) then
				return item
			end
		end
	end

	local character = player.Character
	if character then
		for _, item in pairs(character:GetChildren()) do
			if item:IsA("Tool") and item.Name:find(itemType) then
				return item
			end
		end
	end

	return nil
end

-- Function untuk membuat Tool berdasarkan item type dan quantity
local function updateItemTool(player, itemType)
	local totalItems = inventoryCache[player.UserId] and inventoryCache[player.UserId][itemType] or 0

	if totalItems <= 0 then
		local tool = findItemTool(player, itemType)
		if tool then
			tool:Destroy()
		end
		return 0
	end

	local itemTool = findItemTool(player, itemType)

	if itemTool then
		itemTool.Name = itemType .. " (" .. totalItems .. ")"
		local quantity = itemTool:FindFirstChild("Quantity")
		if quantity then
			quantity.Value = totalItems
		end
	else
		itemTool = Instance.new("Tool")
		itemTool.Name = itemType .. " (" .. totalItems .. ")"
		itemTool.RequiresHandle = true
		itemTool.CanBeDropped = false

		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.5, 0.1, 0.5)
		handle.Material = Enum.Material.Grass
		handle.CanCollide = false
		handle.Parent = itemTool

		-- Set warna berdasarkan item type
		if itemType == "Leaves" then
			handle.Color = Color3.new(0, 0.8, 0) -- Hijau untuk leaves
		elseif itemType == "Palm" then
			handle.Color = Color3.new(0.8, 0.6, 0.2) -- Coklat untuk palm
		elseif itemType == "Broco" then
			handle.Color = Color3.new(0.2, 0.8, 0.3) -- Hijau terang untuk broco
		end

		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 0.3, 1)
		mesh.Parent = handle

		local quantity = Instance.new("NumberValue")
		quantity.Name = "Quantity"
		quantity.Value = totalItems
		quantity.Parent = itemTool

		itemTool.AncestryChanged:Connect(function()
			if itemTool.Parent == workspace then
				itemTool:Destroy()
			end
		end)

		itemTool.Parent = player.Backpack
	end

	return totalItems
end

-- Function untuk update semua tools yang dimiliki player
local function updateAllPlayerTools(player)
	local inventory = inventoryCache[player.UserId]
	if not inventory then
		return
	end

	-- Update tool untuk setiap item type yang dimiliki
	for itemType, quantity in pairs(inventory) do
		if quantity > 0 then
			updateItemTool(player, itemType)
		else
			-- Hapus tool jika quantity = 0
			local tool = findItemTool(player, itemType)
			if tool then
				tool:Destroy()
			end
		end
	end
end

-- ==================== VISUAL FUNCTIONS ====================
-- Function untuk menyembunyikan semua part dalam model
local function hideAllPartsInModel(model)
	for _, child in pairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			child.Transparency = 1
			child.CanCollide = false
		elseif child:IsA("Decal") or child:IsA("Texture") then
			child.Transparency = 1
		end
	end
end

-- Function untuk menampilkan kembali semua part dalam model
local function showAllPartsInModel(model)
	for _, child in pairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			child.Transparency = 0
			child.CanCollide = true
		elseif child:IsA("Decal") or child:IsA("Texture") then
			child.Transparency = 0
		end
	end
end

-- Function untuk menyembunyikan model berdasarkan tipe
local function hideModel(potModel, modelType)
	local modelToHide = potModel:FindFirstChild(modelType)
	if modelToHide then
		if modelToHide:IsA("Model") then
			-- Jika ini adalah Model, sembunyikan semua part di dalamnya
			hideAllPartsInModel(modelToHide)
		elseif modelToHide:IsA("BasePart") then
			-- Jika ini adalah Part tunggal
			modelToHide.Transparency = 1
			modelToHide.CanCollide = false
		end
	end
end

-- Function untuk menampilkan model kembali berdasarkan tipe
local function showModel(potModel, modelType)
	local modelToShow = potModel:FindFirstChild(modelType)
	if modelToShow then
		if modelToShow:IsA("Model") then
			-- Jika ini adalah Model, tampilkan semua part di dalamnya
			showAllPartsInModel(modelToShow)
		elseif modelToShow:IsA("BasePart") then
			-- Jika ini adalah Part tunggal
			modelToShow.Transparency = 0
			modelToShow.CanCollide = true
		end
	end
end

-- ==================== FARM POT SETUP FUNCTIONS ====================
-- Generic function untuk setup pot dengan proximity prompt
local function setupFarmPot(potModel, potType, itemReward, modelType)
	print("Setting up pot: " .. potModel.Name .. " | Type: " .. potType .. " | Reward: " .. itemReward)

	-- Skip jika sudah ada prompt (check recursive)
	if potModel:FindFirstChild("ProximityPrompt", true) then
		print("ProximityPrompt already exists for " .. potModel.Name)
		return
	end

	-- Variable tracking untuk pot ini
	local itemAvailable = true

	-- Cari Part yang solid untuk attach ProximityPrompt
	local targetPart = nil

	-- Coba cari PrimaryPart dulu
	if potModel.PrimaryPart then
		targetPart = potModel.PrimaryPart
		print("Using PrimaryPart for " .. potModel.Name .. ": " .. targetPart.Name)
	else
		-- Kalau tidak ada PrimaryPart, cari Part pertama yang solid
		for _, child in pairs(potModel:GetChildren()) do
			if child:IsA("BasePart") and child.CanCollide and child.Transparency < 1 then
				targetPart = child
				print("Using first solid Part for " .. potModel.Name .. ": " .. targetPart.Name)
				break
			end
		end

		-- Kalau masih tidak ada, cari Part apapun
		if not targetPart then
			for _, child in pairs(potModel:GetChildren()) do
				if child:IsA("BasePart") then
					targetPart = child
					print("Using any Part for " .. potModel.Name .. ": " .. targetPart.Name)
					break
				end
			end
		end
	end

	if not targetPart then
		warn("No suitable Part found for ProximityPrompt in " .. potModel.Name)
		return
	end

	-- Buat ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Get " .. itemReward
	prompt.ObjectText = potType .. " (" .. potModel.Name .. ")"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = HOLD_DURATION
	prompt.MaxActivationDistance = MAX_DISTANCE
	prompt.RequiresLineOfSight = false -- Tidak butuh line of sight
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton -- One per button
	prompt.Style = Enum.ProximityPromptStyle.Default -- Default style
	prompt.Parent = targetPart -- Attach ke Part, bukan ke Model

	print("ProximityPrompt created for " .. potModel.Name .. " attached to " .. targetPart.Name)

	-- Event ketika player berhasil hold E
	prompt.Triggered:Connect(function(player)
		if itemAvailable then
			print(player.Name .. " harvested " .. potModel.Name .. "!")

			-- Tambah item ke DataStore dan update tool
			local totalItems = addToInventoryCache(player, itemReward, 1)
			updateAllPlayerTools(player)

			print(player.Name .. " harvested! Total " .. itemReward .. ": " .. totalItems)

			-- Hilangkan model dari pot berdasarkan tipe
			hideModel(potModel, modelType)
			itemAvailable = false

			-- Update prompt
			prompt.ObjectText = potModel.Name .. " (Harvested)"
			prompt.ActionText = "Wait..."
			prompt.Enabled = false

			-- Respawn item setelah waktu yang ditentukan
			spawn(function()
				wait(RESPAWN_TIME)

				-- Tampilkan model kembali
				showModel(potModel, modelType)
				itemAvailable = true

				-- Aktifkan prompt kembali
				prompt.ObjectText = potType .. " (" .. potModel.Name .. ")"
				prompt.ActionText = "Hold to Harvest"
				prompt.Enabled = true

				print(potModel.Name .. " has respawned!")
			end)
		end
	end)

	-- Visual feedback saat hold
	prompt.PromptButtonHoldBegan:Connect(function(player)
		prompt.ActionText = "Harvesting..."
		print(player.Name .. " started harvesting " .. potModel.Name)
	end)

	prompt.PromptButtonHoldEnded:Connect(function(player)
		if itemAvailable then
			prompt.ActionText = "Hold to Harvest"
			print(player.Name .. " stopped harvesting " .. potModel.Name)
		end
	end)
end

-- Function untuk setup semua TreePot
local function setupTreePots()
	print("=== SETTING UP TREE POTS ===")
	for _, child in pairs(Leaves:GetChildren()) do
		print("Checking Tree child: " .. child.Name .. " | Pattern match: " .. tostring(child.Name:match("^TreePot")))
		if child.Name:match("^TreePot") then
			print("Calling setupFarmPot for: " .. child.Name)
			setupFarmPot(child, "Tree", "Leaves", "Leaf")
			print("Setup completed for TreePot: " .. child.Name)
		else
			print("Skipping " .. child.Name .. " - doesn't match TreePot pattern")
		end
	end
	print("=== TREE POTS SETUP FINISHED ===")
end

-- Function untuk setup semua PalmPot
local function setupPalmPots()
	print("=== SETTING UP PALM POTS ===")
	for _, child in pairs(Palm:GetChildren()) do
		print("Checking Palm child: " .. child.Name .. " | Pattern match: " .. tostring(child.Name:match("^PalmPot")))
		if child.Name:match("^PalmPot") then
			print("Calling setupFarmPot for: " .. child.Name)
			setupFarmPot(child, "Palm Tree", "Palm", "Leaf") -- Memberikan item "Palm"
			print("Setup completed for PalmPot: " .. child.Name)
		else
			print("Skipping " .. child.Name .. " - doesn't match PalmPot pattern")
		end
	end
	print("=== PALM POTS SETUP FINISHED ===")
end

-- Function untuk setup semua BrocoPot
local function setupBrocoPots()
	print("=== SETTING UP BROCO POTS ===")
	for _, child in pairs(Broco:GetChildren()) do
		print("Checking Broco child: " .. child.Name .. " | Pattern match: " .. tostring(child.Name:match("^BrocoPot")))
		if child.Name:match("^BrocoPot") then
			print("Calling setupFarmPot for: " .. child.Name)
			setupFarmPot(child, "Broccoli Plant", "Broco", "Leaf") -- Memberikan item "Broco"
			print("Setup completed for BrocoPot: " .. child.Name)
		else
			print("Skipping " .. child.Name .. " - doesn't match BrocoPot pattern")
		end
	end
	print("=== BROCO POTS SETUP FINISHED ===")
end

-- Function untuk setup listeners untuk pot baru
local function setupNewPotListeners()
	-- Listener untuk TreePot baru
	Leaves.ChildAdded:Connect(function(child)
		if child.Name:match("^TreePot") then
			wait(0.1)
			setupFarmPot(child, "Tree", "Leaves", "Leaf")
			print("New TreePot detected and setup: " .. child.Name)
		end
	end)

	-- Listener untuk PalmPot baru
	Palm.ChildAdded:Connect(function(child)
		if child.Name:match("^PalmPot") then
			wait(0.1)
			setupFarmPot(child, "Palm Tree", "Palm", "Leaf") -- Memberikan item "Palm"
			print("New PalmPot detected and setup: " .. child.Name)
		end
	end)

	-- Listener untuk BrocoPot baru
	Broco.ChildAdded:Connect(function(child)
		if child.Name:match("^BrocoPot") then
			wait(0.1)
			setupFarmPot(child, "Broccoli Plant", "Broco", "Leaf") -- Memberikan item "Broco"
			print("New BrocoPot detected and setup: " .. child.Name)
		end
	end)
end

-- ==================== SELLING SYSTEM FUNCTIONS ====================
-- Function untuk setup NPC selling system
local function setupSellingSystem()
	local NpcSell = FarmJobs:WaitForChild("NpcSell")
	local NPC_SELL_ALL_FARM = NpcSell:WaitForChild("NPC Sell All Farm")
	local NPC_SELL_ONE_FARM = NpcSell:WaitForChild("NPC Sell One Farm")

	-- Setup Sell One
	local promptSellOne = Instance.new("ProximityPrompt")
	promptSellOne.ActionText = "Sell One"
	promptSellOne.ObjectText = "Jual Items"
	promptSellOne.KeyboardKeyCode = Enum.KeyCode.E
	promptSellOne.HoldDuration = 3
	promptSellOne.MaxActivationDistance = 10
	promptSellOne.Parent = NPC_SELL_ONE_FARM

	promptSellOne.Triggered:Connect(function(player)
		print(player.Name .. " Sell One Item")

		local inventory = inventoryCache[player.UserId]
		if not inventory then
			return
		end

		-- Cari item pertama yang ada di inventory
		local soldItem = false
		for itemType, quantity in pairs(inventory) do
			if quantity > 0 then
				local itemPrice = ITEM_PRICES[itemType] or 0
				local remainingItems = removeFromInventoryCache(player, itemType, 1)
				local newMoney = addMoneyToCache(player, itemPrice)
				updateAllPlayerTools(player)

				print(
					player.Name
						.. " sold 1 "
						.. itemType
						.. " for $"
						.. itemPrice
						.. ". Remaining "
						.. itemType
						.. ": "
						.. remainingItems
						.. ", Money: $"
						.. newMoney
				)
				soldItem = true
				break
			end
		end

		if not soldItem then
			print(player.Name .. " tried to sell items but has none!")
		end
	end)

	-- Setup Sell All
	local promptSellAll = Instance.new("ProximityPrompt")
	promptSellAll.ActionText = "Sell All"
	promptSellAll.ObjectText = "Jual All Items"
	promptSellAll.KeyboardKeyCode = Enum.KeyCode.E
	promptSellAll.HoldDuration = 3
	promptSellAll.MaxActivationDistance = 10
	promptSellAll.Parent = NPC_SELL_ALL_FARM

	promptSellAll.Triggered:Connect(function(player)
		print(player.Name .. " Sell All Items")

		local inventory = inventoryCache[player.UserId]
		if not inventory then
			return
		end

		local totalSold = 0
		local totalMoney = 0

		-- Jual semua item di inventory
		for itemType, quantity in pairs(inventory) do
			if quantity > 0 then
				local itemPrice = ITEM_PRICES[itemType] or 0
				local itemMoney = quantity * itemPrice
				totalMoney = totalMoney + itemMoney
				totalSold = totalSold + quantity

				removeFromInventoryCache(player, itemType, quantity)
				print(
					player.Name
						.. " sold "
						.. quantity
						.. " "
						.. itemType
						.. " for $"
						.. itemMoney
						.. " (Price per item: $"
						.. itemPrice
						.. ")"
				)
			end
		end

		if totalSold > 0 then
			local newMoney = addMoneyToCache(player, totalMoney)
			updateAllPlayerTools(player)
			print(
				player.Name .. " sold total " .. totalSold .. " items for $" .. totalMoney .. ". Money: $" .. newMoney
			)
		else
			print(player.Name .. " tried to sell items but has none!")
		end
	end)
end

-- ==================== PLAYER MANAGEMENT FUNCTIONS ====================
-- Function untuk setup player management
local function setupPlayerManagement()
	Players.PlayerAdded:Connect(function(player)
		spawn(function()
			loadInventory(player)
			loadMoney(player)

			player.CharacterAdded:Connect(function()
				wait(2)
				updateAllPlayerTools(player)
			end)

			if player.Character then
				updateAllPlayerTools(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		saveInventory(player, true)
		saveMoney(player, true)

		-- Cleanup cache
		inventoryCache[player.UserId] = nil
		moneyCache[player.UserId] = nil
		pendingSaves[player.UserId] = nil
		pendingSaves[player.UserId .. "_money"] = nil
	end)
end

-- Function untuk setup auto-save system
local function setupAutoSaveSystem()
	spawn(function()
		while true do
			wait(AUTO_SAVE_INTERVAL)

			for _, player in pairs(Players:GetPlayers()) do
				if inventoryCache[player.UserId] then
					saveInventory(player, false)
				end
				if moneyCache[player.UserId] then
					saveMoney(player, false)
				end
			end

			print("Auto-save completed for all players")
		end
	end)
end

-- Function untuk setup shutdown save
local function setupShutdownSave()
	game:BindToClose(function()
		print("Server shutting down, saving all data...")

		for _, player in pairs(Players:GetPlayers()) do
			saveInventory(player, true)
			saveMoney(player, true)
		end

		wait(2)
	end)
end

-- ==================== INITIALIZATION ====================
-- Main initialization function
local function initializeFarmSystem()
	print("=== INITIALIZING FARM SYSTEM ===")

	-- Debug: Cek apakah folder Palm ada
	if Palm then
		print("Palm folder found! Children count: " .. #Palm:GetChildren())
		for _, child in pairs(Palm:GetChildren()) do
			print("Found in Palm folder: " .. child.Name .. " (Type: " .. child.ClassName .. ")")
		end
	else
		warn("Palm folder not found!")
	end

	-- Setup semua pot yang sudah ada
	setupTreePots()
	setupPalmPots()
	setupBrocoPots()

	-- Verify setup - Debug check untuk memastikan ProximityPrompt ada
	print("=== VERIFYING SETUP ===")
	for _, child in pairs(Palm:GetChildren()) do
		-- Cari ProximityPrompt di dalam model atau di children-nya
		local prompt = child:FindFirstChild("ProximityPrompt", true) -- true = recursive search
		if prompt then
			print(
				"✅ "
					.. child.Name
					.. " has ProximityPrompt - Enabled: "
					.. tostring(prompt.Enabled)
					.. ", Distance: "
					.. prompt.MaxActivationDistance
			)
			print("   📍 ProximityPrompt located in: " .. prompt.Parent.Name)
		else
			warn("❌ " .. child.Name .. " missing ProximityPrompt!")
		end
	end

	-- Setup listener untuk pot baru
	setupNewPotListeners()

	-- Setup selling system
	setupSellingSystem()

	-- Setup player management
	setupPlayerManagement()

	-- Setup auto-save system
	setupAutoSaveSystem()

	-- Setup shutdown save
	setupShutdownSave()

	-- Setup remote function untuk balance
	GetBalanceRF.OnServerInvoke = function(player)
		return moneyCache[player.UserId] or 0
	end

	print("=== FARM SYSTEM INITIALIZED SUCCESSFULLY ===")
end

-- Initialize the system
initializeFarmSystem()
