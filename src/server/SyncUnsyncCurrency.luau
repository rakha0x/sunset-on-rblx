-- ========================================
-- SERVER SCRIPT (ServerScriptService/SyncController)
-- FEATURE
-- SYNC
-- UNSYNC
-- CURRENCY TRANSFER + Notification
-- ========================================
-- IMPORT
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SyncRemote = ReplicatedStorage:WaitForChild("Sync")
local UnsyncRemote = ReplicatedStorage:WaitForChild("Unsync")
local DataStoreService = game:GetService("DataStoreService")

-- ========================================
-- START CURRENCY SYSTEM
-- ========================================
local DEFAULT_BALANCE = 100000 -- Rp100.000 saldo awal
local STORE = DataStoreService:GetDataStore("player_money_v1")

-- Ensure remotes exist (creates if missing)
local function ensureRemote(className, name)
	local obj = ReplicatedStorage:FindFirstChild(name)
	if not obj or not obj:IsA(className) then
		if obj then
			obj:Destroy()
		end
		obj = Instance.new(className)
		obj.Name = name
		obj.Parent = ReplicatedStorage
	end
	return obj
end

-- Currency remotes
local GetBalanceRF = ensureRemote("RemoteFunction", "GetBalance")
local TransferRF = ensureRemote("RemoteFunction", "TransferRequest")
local BalanceChangedRE = ensureRemote("RemoteEvent", "BalanceChanged")
local TransferNoticeRE = ensureRemote("RemoteEvent", "TransferNotice") -- NEW: notifikasi

-- In-memory balances
local balances = {}

local function loadBalance(userId)
	local key = tostring(userId)
	local ok, val = pcall(function()
		return STORE:GetAsync(key)
	end)
	if not ok then
		warn("GetAsync failed for user " .. userId, val)
	end
	if type(val) ~= "number" then
		val = DEFAULT_BALANCE
	end
	balances[userId] = val
	return val
end

local function saveBalance(userId, value)
	local key = tostring(userId)
	local ok, err = pcall(function()
		STORE:SetAsync(key, value)
	end)
	if not ok then
		warn("SetAsync failed for user " .. userId, err)
	end
end

local function pushBalance(p)
	local bal = balances[p.UserId] or 0
	BalanceChangedRE:FireClient(p, bal)
end

Players.PlayerAdded:Connect(function(p)
	-- local bal = loadBalance(p.UserId)
	task.defer(function()
		pushBalance(p)
	end)
end)

Players.PlayerRemoving:Connect(function(p)
	local bal = balances[p.UserId]
	if bal ~= nil then
		saveBalance(p.UserId, bal)
	end
end)

-- Client requests
GetBalanceRF.OnServerInvoke = function(p)
	return balances[p.UserId] or loadBalance(p.UserId)
end

-- Transfer logic + notifications
TransferRF.OnServerInvoke = function(p, targetUserId, amount)
	if typeof(targetUserId) ~= "number" then
		return { success = false, message = "Target tidak valid." }
	end
	if targetUserId == p.UserId then
		return { success = false, message = "Tidak bisa transfer ke diri sendiri." }
	end
	if typeof(amount) ~= "number" then
		return { success = false, message = "Nominal tidak valid." }
	end

	amount = math.floor(amount)
	if amount <= 0 then
		return { success = false, message = "Nominal harus lebih dari 0." }
	end

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		return { success = false, message = "Target harus online." }
	end

	local fromBal = balances[p.UserId]
	if fromBal == nil then
		fromBal = loadBalance(p.UserId)
	end
	local toBal = balances[targetUserId]
	if toBal == nil then
		toBal = loadBalance(targetUserId)
	end

	if fromBal < amount then
		return { success = false, message = "Saldo tidak cukup." }
	end

	-- Update in-memory
	fromBal -= amount
	toBal += amount
	balances[p.UserId] = fromBal
	balances[targetUserId] = toBal

	-- Persist (best-effort)
	task.spawn(function()
		saveBalance(p.UserId, fromBal)
		saveBalance(targetUserId, toBal)
	end)

	-- Push fresh balance
	pushBalance(p)
	pushBalance(targetPlayer)

	-- NEW: Notifikasi ke pengirim & penerima
	TransferNoticeRE:FireClient(p, {
		kind = "sent",
		amount = amount,
		otherName = targetPlayer.Name,
	})
	TransferNoticeRE:FireClient(targetPlayer, {
		kind = "received",
		amount = amount,
		otherName = p.Name,
	})

	return { success = true, message = "Transfer berhasil.", newBalance = fromBal }
end
-- ========================================
-- END CURRENCY SERVICE
-- ========================================

-- ========================================
-- START FUNCTIONS SYNC + UNSYNC SERVICE
-- ========================================
local followerMap = {}
local function getHumanoid(character)
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function getAnimator(humanoid)
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

local function stopAllMirrors(follower)
	local data = followerMap[follower]
	if not data then
		return
	end
	for _, track in pairs(data.mirrored) do
		pcall(function()
			track:Stop(0.1)
			track:Destroy()
		end)
	end
	data.mirrored = {}
end

local function disconnectAll(data)
	for _, c in ipairs(data.conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	data.conns = {}
end

local function unsyncAll(follower)
	local data = followerMap[follower]
	if not data then
		return
	end
	stopAllMirrors(follower)
	disconnectAll(data)
	followerMap[follower] = nil
end

local function mirrorSingleTrack(followerAnimator, data, targetTrack)
	if not targetTrack or not targetTrack.Animation then
		return
	end

	local animId = targetTrack.Animation.AnimationId
	if not animId or animId == "" then
		return
	end

	-- Reuse track bila sudah ada
	local followerTrack = data.mirrored[animId]
	if not followerTrack or followerTrack.IsDeleted then
		local anim = Instance.new("Animation")
		anim.AnimationId = animId
		followerTrack = followerAnimator:LoadAnimation(anim)
		data.mirrored[animId] = followerTrack
	end

	-- Sinkron play
	if targetTrack.IsPlaying and not followerTrack.IsPlaying then
		-- Play(fadeTime, weight, speed)
		local ok = pcall(function()
			followerTrack:Play(0.1, 1.0, targetTrack.Speed)
			followerTrack.TimePosition = targetTrack.TimePosition
		end)
		if not ok then
			return
		end
	elseif not targetTrack.IsPlaying and followerTrack.IsPlaying then
		pcall(function()
			followerTrack:Stop(0.1)
		end)
	end

	-- Hentikan mirror saat target stop track ini
	table.insert(
		data.conns,
		targetTrack.Stopped:Connect(function()
			pcall(function()
				followerTrack:Stop(0.1)
			end)
		end)
	)
end

local function mirrorAllCurrent(follower, target)
	local followerHum = getHumanoid(follower.Character)
	local targetHum = getHumanoid(target.Character)
	if not followerHum or not targetHum then
		return
	end

	local followerAnimator = getAnimator(followerHum)
	local targetAnimator = getAnimator(targetHum)
	if not followerAnimator or not targetAnimator then
		return
	end

	local data = followerMap[follower]
	if not data then
		return
	end

	-- Mirror semua track yang sedang dimainkan saat ini
	for _, track in ipairs(targetAnimator:GetPlayingAnimationTracks()) do
		mirrorSingleTrack(followerAnimator, data, track)
	end
end

local function bindTargetEvents(follower, target)
	local data = followerMap[follower]
	if not data then
		return
	end

	-- Re-bind saat target ganti character / respawn
	table.insert(
		data.conns,
		target.CharacterAdded:Connect(function()
			task.wait(0.2)
			mirrorAllCurrent(follower, target)
			local hum = getHumanoid(target.Character)
			if hum then
				local animator = getAnimator(hum)
				if animator then
					table.insert(
						data.conns,
						animator.AnimationPlayed:Connect(function(track)
							local fHum = getHumanoid(follower.Character)
							if not fHum then
								return
							end
							local fAnim = getAnimator(fHum)
							if not fAnim then
								return
							end
							mirrorSingleTrack(fAnim, data, track)
						end)
					)
				end
			end
		end)
	)

	-- Initial + listen AnimationPlayed
	task.defer(function()
		mirrorAllCurrent(follower, target)
		local hum = getHumanoid(target.Character)
		if hum then
			local animator = getAnimator(hum)
			if animator then
				table.insert(
					data.conns,
					animator.AnimationPlayed:Connect(function(track)
						local fHum = getHumanoid(follower.Character)
						if not fHum then
							return
						end
						local fAnim = getAnimator(fHum)
						if not fAnim then
							return
						end
						mirrorSingleTrack(fAnim, data, track)
					end)
				)
			end
		end
	end)
end

-- === Remote handlers ===
SyncRemote.OnServerEvent:Connect(function(follower, target)
	if typeof(target) ~= "Instance" or not target:IsA("Player") then
		return
	end
	if follower == target then
		return
	end

	-- Switch: selalu bersihkan yang lama
	unsyncAll(follower)

	-- Siapkan state baru
	followerMap[follower] = { target = target, conns = {}, mirrored = {} }

	-- Putus otomatis bila follower/target keluar
	table.insert(
		followerMap[follower].conns,
		follower.AncestryChanged:Connect(function(_, parent)
			if not parent then
				unsyncAll(follower)
			end
		end)
	)
	table.insert(
		followerMap[follower].conns,
		target.AncestryChanged:Connect(function(_, parent)
			if not parent then
				unsyncAll(follower)
			end
		end)
	)

	bindTargetEvents(follower, target)
end)

-- Unsync: tanpa argumen = lepas semua; kalau ada target pun kita tetap lepas semua (sesuai requirement)
UnsyncRemote.OnServerEvent:Connect(function(follower, _)
	unsyncAll(follower)
end)

-- Safety: bersihkan saat player keluar
Players.PlayerRemoving:Connect(function(p)
	unsyncAll(p)
	-- juga lepaskan siapa pun yang sedang mengikuti p
	for follower, data in pairs(followerMap) do
		if data.target == p then
			unsyncAll(follower)
		end
	end
end)
-- ========================================
-- END SYNC-UNSYNC SERVICE
-- ========================================
