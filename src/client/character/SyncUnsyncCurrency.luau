-- ========================================
-- LOCAL SCRIPT (StarterCharacterScripts/AvatarContextMenu)
-- Sync/Unsync + Transfer + Notif + Sound (mobile-friendly + keyboard avoid)
-- ========================================

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Remotes: Sync
local SyncRemote = ReplicatedStorage:WaitForChild("Sync")
local UnsyncRemote = ReplicatedStorage:WaitForChild("Unsync")

-- Remotes: Currency
local GetBalanceRF = ReplicatedStorage:WaitForChild("GetBalance")
local TransferRF = ReplicatedStorage:WaitForChild("TransferRequest")
local BalanceChangedRE = ReplicatedStorage:WaitForChild("BalanceChanged")
local TransferNoticeRE = ReplicatedStorage:WaitForChild("TransferNotice") -- notifikasi transfer

-- Sound ID
local SOUND_ID = "rbxassetid://17208361335"

-- Enable avatar context menu
StarterGui:SetCore("AvatarContextMenuEnabled", true)
pcall(function()
	StarterGui:SetCore("RemoveAvatarContextMenuOption", Enum.AvatarContextMenuOption.Emote)
end)

-- =========================
-- Helpers
-- =========================
local currentSyncTarget = nil

local function resolveTarget(arg)
	if typeof(arg) == "Instance" and arg:IsA("Player") then
		return arg
	elseif typeof(arg) == "number" then
		return Players:GetPlayerByUserId(arg)
	elseif typeof(arg) == "string" then
		return Players:FindFirstChild(arg)
	end
	return nil
end

local function systemMsg(text, color)
	StarterGui:SetCore("ChatMakeSystemMessage", {
		Text = text,
		Color = color or Color3.new(1, 1, 1),
	})
end

local function showToast(title, text, duration)
	duration = duration or 3
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title,
			Text = text,
			Duration = duration,
		})
	end)
end

local function formatRupiah(n)
	n = math.floor(tonumber(n) or 0)
	local s = tostring(n)
	local result = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if result:sub(1, 1) == "." then
		result = result:sub(2)
	end
	return "Rp" .. result
end

-- =========================
-- Sync / Unsync
-- =========================
local function unsyncAll()
	UnsyncRemote:FireServer()
	currentSyncTarget = nil
	systemMsg("Stopped all syncing!", Color3.new(1, 0.5, 0))
end

local function syncWithPlayer(targetArg)
	local targetPlayer = resolveTarget(targetArg)
	if not targetPlayer or targetPlayer == LocalPlayer then
		systemMsg("Cannot sync: invalid target.", Color3.new(1, 0, 0))
		return
	end
	if currentSyncTarget and currentSyncTarget ~= targetPlayer then
		UnsyncRemote:FireServer()
		task.wait()
	end
	SyncRemote:FireServer(targetPlayer)
	currentSyncTarget = targetPlayer
	systemMsg("Syncing with " .. targetPlayer.Name .. " (dance).", Color3.new(0, 1, 0))
end

-- =========================
-- Transfer Modal (mobile-friendly + keyboard avoid)
-- =========================
local transferGui -- ScreenGui
local transferTarget -- Player instance
local _snd -- beep sound instance

local function tapFeedback(btn)
	local orig = btn.Size
	btn:TweenSize(orig - UDim2.new(0, 4, 0, 2), "Out", "Quad", 0.06, true, function()
		btn:TweenSize(orig, "Out", "Quad", 0.06, true)
	end)
end

local function ensureTransferGui()
	if transferGui and transferGui.Parent then
		return transferGui
	end

	transferGui = Instance.new("ScreenGui")
	transferGui.Name = "TransferModalGui"
	transferGui.ResetOnSpawn = false
	transferGui.IgnoreGuiInset = true
	transferGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	transferGui.DisplayOrder = 1000 -- di atas HUD lain
	transferGui.Enabled = false
	transferGui.Parent = PlayerGui

	-- Overlay: TextButton agar menyerap tap & blok UI di bawah
	local bg = Instance.new("TextButton")
	bg.Name = "Dim"
	bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bg.BackgroundTransparency = 0.35
	bg.AutoButtonColor = false
	bg.Text = ""
	bg.Size = UDim2.fromScale(1, 1)
	bg.ZIndex = 5
	bg.Parent = transferGui
	bg.MouseButton1Click:Connect(function()
		transferGui.Enabled = false
	end)

	-- Modal
	local modal = Instance.new("Frame")
	modal.Name = "Modal"
	modal.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	modal.Size = UDim2.fromScale(0.9, 0.34) -- responsif
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.ZIndex = 10
	modal.Active = true -- blok input di bawah modal
	modal.Parent = transferGui
	Instance.new("UICorner", modal).CornerRadius = UDim.new(0, 12)

	-- Batas ukuran agar nyaman di hp/desktop
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(320, 180)
	sizeConstraint.MaxSize = Vector2.new(560, 300)
	sizeConstraint.Parent = modal

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = modal

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Text = "Transfer Money"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, 0, 0, 28)
	title.ZIndex = 11
	title.Parent = modal

	local targetLabel = Instance.new("TextLabel")
	targetLabel.Name = "Target"
	targetLabel.BackgroundTransparency = 1
	targetLabel.Text = "Target: -"
	targetLabel.Font = Enum.Font.Gotham
	targetLabel.TextSize = 18
	targetLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	targetLabel.TextXAlignment = Enum.TextXAlignment.Left
	targetLabel.Position = UDim2.new(0, 0, 0, 36)
	targetLabel.Size = UDim2.new(1, 0, 0, 22)
	targetLabel.ZIndex = 11
	targetLabel.Parent = modal

	local amountBox = Instance.new("TextBox")
	amountBox.Name = "AmountBox"
	amountBox.PlaceholderText = "Masukkan nominal (contoh: 5000)"
	amountBox.ClearTextOnFocus = false
	amountBox.Text = ""
	amountBox.Font = Enum.Font.Gotham
	amountBox.TextSize = 18
	amountBox.TextColor3 = Color3.fromRGB(20, 20, 20)
	amountBox.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
	amountBox.Size = UDim2.new(1, 0, 0, 44)
	amountBox.Position = UDim2.new(0, 0, 0, 70)
	amountBox.ZIndex = 11
	amountBox.Parent = modal
	Instance.new("UICorner", amountBox).CornerRadius = UDim.new(0, 8)
	local padAmount = Instance.new("UIPadding")
	padAmount.PaddingLeft = UDim.new(0, 12)
	padAmount.Parent = amountBox

	local buttonRow = Instance.new("Frame")
	buttonRow.Name = "Buttons"
	buttonRow.BackgroundTransparency = 1
	buttonRow.Size = UDim2.new(1, 0, 0, 48)
	buttonRow.Position = UDim2.new(0, 0, 1, -56)
	buttonRow.ZIndex = 11
	buttonRow.Parent = modal

	local uiList = Instance.new("UIListLayout")
	uiList.FillDirection = Enum.FillDirection.Horizontal
	uiList.Padding = UDim.new(0, 12)
	uiList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	uiList.VerticalAlignment = Enum.VerticalAlignment.Center
	uiList.Parent = buttonRow

	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Name = "Cancel"
	cancelBtn.Text = "Cancel"
	cancelBtn.Font = Enum.Font.GothamBold
	cancelBtn.TextSize = 18
	cancelBtn.TextColor3 = Color3.fromRGB(30, 30, 35)
	cancelBtn.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
	cancelBtn.Size = UDim2.new(0.45, 0, 1, 0) -- scale (responsif)
	cancelBtn.ZIndex = 12
	cancelBtn.AutoButtonColor = true
	cancelBtn.Parent = buttonRow
	Instance.new("UICorner", cancelBtn).CornerRadius = UDim.new(0, 10)

	local sendBtn = Instance.new("TextButton")
	sendBtn.Name = "Send"
	sendBtn.Text = "Send"
	sendBtn.Font = Enum.Font.GothamBold
	sendBtn.TextSize = 18
	sendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	sendBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 90)
	sendBtn.Size = UDim2.new(0.45, 0, 1, 0) -- scale (responsif)
	sendBtn.ZIndex = 12
	sendBtn.AutoButtonColor = true
	sendBtn.Parent = buttonRow
	Instance.new("UICorner", sendBtn).CornerRadius = UDim.new(0, 10)

	-- === Keyboard avoid: angkat modal saat textbox fokus ===
	local originalPos = UDim2.fromScale(0.5, 0.5)
	local function raisedPos()
		local v = workspace.CurrentCamera.ViewportSize
		local portrait = v.Y > v.X
		-- jika portrait (keyboard lebih tinggi), naik lebih jauh
		return portrait and UDim2.fromScale(0.5, 0.32) or UDim2.fromScale(0.5, 0.25)
	end

	local function tweenPos(pos)
		TweenService
			:Create(modal, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = pos })
			:Play()
	end

	amountBox.Focused:Connect(function()
		amountBox.Text = amountBox.Text:gsub("%D", "")
		tweenPos(raisedPos())
	end)

	amountBox.FocusLost:Connect(function()
		tweenPos(originalPos)
	end)

	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if amountBox:IsFocused() then
			modal.Position = raisedPos()
		end
	end)

	-- Validasi angka
	amountBox:GetPropertyChangedSignal("Text"):Connect(function()
		local digits = amountBox.Text:gsub("%D", "")
		if amountBox.Text ~= digits then
			amountBox.Text = digits
		end
	end)

	-- Tombol
	cancelBtn.MouseButton1Click:Connect(function()
		tapFeedback(cancelBtn)
		transferGui.Enabled = false
	end)

	local sending = false
	sendBtn.MouseButton1Click:Connect(function()
		tapFeedback(sendBtn)
		if sending then
			return
		end
		if not transferTarget or not transferTarget.Parent then
			systemMsg("Target sudah tidak tersedia.", Color3.new(1, 0, 0))
			transferGui.Enabled = false
			return
		end
		local amt = tonumber(amountBox.Text)
		if not amt or amt <= 0 then
			systemMsg("Nominal tidak valid.", Color3.new(1, 0, 0))
			return
		end

		sending = true
		local ok, resOrErr = pcall(function()
			return TransferRF:InvokeServer(transferTarget.UserId, amt)
		end)
		sending = false

		if not ok then
			systemMsg("Transfer gagal: " .. tostring(resOrErr), Color3.new(1, 0, 0))
			return
		end

		local res = resOrErr
		if res and res.success then
			transferGui.Enabled = false -- notif & sound akan datang dari server
		else
			systemMsg(res and res.message or "Transfer gagal.", Color3.new(1, 0, 0))
		end
	end)

	return transferGui
end

local function openTransferModal(targetPlayer)
	transferTarget = targetPlayer
	local gui = ensureTransferGui()
	gui.Enabled = true
	local modal = gui:WaitForChild("Modal")
	modal.Target.Text = "Target: " .. (targetPlayer and targetPlayer.Name or "-")
	local amountBox = modal:FindFirstChild("AmountBox")
	if amountBox then
		amountBox.Text = ""
		task.defer(function() -- beri 1 frame agar tween jalan dulu
			amountBox:CaptureFocus()
		end)
	end
end

-- =========================
-- Sound
-- =========================
local function playBeep()
	if not SOUND_ID or SOUND_ID == "" then
		return
	end
	if not _snd or not _snd.Parent then
		_snd = Instance.new("Sound")
		_snd.SoundId = SOUND_ID
		_snd.Volume = 0.8
		_snd.PlayOnRemove = false
		_snd.Name = "TransferBeep"
		_snd.Parent = SoundService
	end
	SoundService:PlayLocalSound(_snd)
end

-- =========================
-- Avatar Context Menu Bindables
-- =========================
local syncEvent = Instance.new("BindableEvent")
local unsyncEvent = Instance.new("BindableEvent")
local transferEvent = Instance.new("BindableEvent")

syncEvent.Event:Connect(function(arg)
	syncWithPlayer(arg)
end)
unsyncEvent.Event:Connect(function(_)
	unsyncAll()
end)
transferEvent.Event:Connect(function(arg)
	local target = resolveTarget(arg)
	if target and target ~= LocalPlayer then
		openTransferModal(target)
	else
		systemMsg("Pilih player lain untuk transfer.", Color3.new(1, 0, 0))
	end
end)

pcall(function()
	StarterGui:SetCore("AddAvatarContextMenuOption", { "Sync", syncEvent })
	StarterGui:SetCore("AddAvatarContextMenuOption", { "Unsync", unsyncEvent })
	StarterGui:SetCore("AddAvatarContextMenuOption", { "Transfer Money", transferEvent })
end)

-- =========================
-- Shortcuts
-- =========================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.U then
		unsyncAll()
	end
end)

-- =========================
-- Balance events (opsional toast)
-- =========================
BalanceChangedRE.OnClientEvent:Connect(function(newBal)
	-- showToast("Saldo Diperbarui", "Saldo: " .. formatRupiah(newBal), 2)
end)

-- =========================
-- Transfer notifications (toast + chat + sound)
-- =========================
TransferNoticeRE.OnClientEvent:Connect(function(payload)
	if not payload or type(payload) ~= "table" then
		return
	end
	local kind = payload.kind
	local otherName = payload.otherName or "Unknown"
	local amount = tonumber(payload.amount) or 0
	local amtTxt = formatRupiah(amount)

	if kind == "sent" then
		systemMsg(("✅ Transfer %s ke %s berhasil."):format(amtTxt, otherName), Color3.new(0, 1, 0))
		showToast("Transfer Berhasil", ("Mengirim %s ke %s"):format(amtTxt, otherName))
		playBeep()
	elseif kind == "received" then
		systemMsg(("💰 Kamu menerima %s dari %s."):format(amtTxt, otherName), Color3.new(0.8, 0.9, 1))
		showToast("Uang Diterima", ("Menerima %s dari %s"):format(amtTxt, otherName))
		playBeep()
	end
end)
