local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = Remotes.Parent or ReplicatedStorage

local remoteList = {
	-- Money System
	Sync = "RemoteEvent",
	Unsync = "RemoteEvent",
	TransferRequest = "RemoteFunction",
	TransferNotice = "RemoteEvent",
	GetBalance = "RemoteFunction",
	BalanceChanged = "RemoteEvent",
}

local remotes = {}

for name, className in pairs(remoteList) do
	local remote = Remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = Remotes
	end
	remotes[name] = remote
end

return remotes
