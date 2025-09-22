local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp = character:WaitForChild("HumanoidRootPart")

-- Ambil Part sumber suara langsung dari folder MusicArea
local stagePart = workspace:WaitForChild("MusicArea"):WaitForChild("MusicSource")

-- Daftar 20 lagu (ganti dengan ID lagu Anda)
local songPlaylist = {
	"rbxassetid://79388369148217",
	"rbxassetid://98476803821039", -- Lagu 1
	"rbxassetid://127875834030904", -- Lagu 2
	"rbxassetid://84287287568185", -- Lagu 20
}

-- Setup sound di part
local sound = Instance.new("Sound")
sound.Looped = false -- Ubah menjadi false agar tidak loop
sound.Volume = 0
sound.Parent = stagePart

-- Parameter radius
local frontRadius = 300
local backRadius = 700
local maxVolume = 1

-- Variabel untuk sistem playlist
local currentSongIndex = 1
local isPlaying = false
local fadeTime = 2 -- Waktu fade antara lagu (detik)
local isFading = false

-- Fungsi untuk memainkan lagu berikutnya
local function playNextSong()
	if isFading then
		return
	end
	isFading = true
	isPlaying = false

	-- Fade out lagu saat ini
	local currentVolume = sound.Volume
	local fadeOutTime = fadeTime / 2

	for i = 1, 10 do
		if sound then
			sound.Volume = currentVolume * (1 - i / 10)
		end
		wait(fadeOutTime / 10)
	end

	-- Ganti ke lagu berikutnya
	currentSongIndex = currentSongIndex + 1
	if currentSongIndex > #songPlaylist then
		currentSongIndex = 1 -- Kembali ke lagu pertama
	end

	if sound then
		sound.SoundId = songPlaylist[currentSongIndex]
		sound:Stop()
		sound:Play()
		isPlaying = true
	end

	-- Fade in lagu baru
	for i = 1, 10 do
		if sound then
			sound.Volume = currentVolume * (i / 10)
		end
		wait(fadeTime / 20)
	end

	isFading = false
	print("Now playing song #" .. currentSongIndex)
end

-- Fungsi untuk memainkan lagu acak
local function playRandomSong()
	if isFading then
		return
	end
	local randomIndex = math.random(1, #songPlaylist)
	if randomIndex == currentSongIndex then
		-- Pastikan tidak mengulang lagu yang sama
		randomIndex = randomIndex + 1
		if randomIndex > #songPlaylist then
			randomIndex = 1
		end
	end

	isFading = true
	isPlaying = false

	local currentVolume = sound.Volume
	if sound then
		sound.Volume = 0
		sound.SoundId = songPlaylist[randomIndex]
		sound:Stop()
		sound:Play()
		isPlaying = true
	end

	-- Restore volume
	if sound then
		sound.Volume = currentVolume
	end
	isFading = false
	currentSongIndex = randomIndex
	print("Random song #" .. currentSongIndex .. " is now playing")
end

-- Mulai dengan lagu pertama
if sound then
	sound.SoundId = songPlaylist[currentSongIndex]
	sound.Looped = false -- Pastikan tidak loop
	sound:Play()
	isPlaying = true
	print("Music system started with song #" .. currentSongIndex)
end

-- Fungsi cek apakah player di depan Part
local function isInFront(playerPos, part)
	local lookVector = part.CFrame.LookVector
	local toPlayer = (playerPos - part.Position).Unit
	local dot = lookVector:Dot(toPlayer)
	return dot > 0
end

-- Event listener untuk deteksi akhir lagu
if sound then
	sound.Ended:Connect(function()
		if isPlaying and not isFading then
			wait(1) -- Tunggu sebentar sebelum lagu berikutnya
			playNextSong()
		end
	end)
end

-- Update volume berdasarkan posisi player
RunService.Heartbeat:Connect(function()
	if not character or not hrp or not sound then
		return
	end

	local playerPos = hrp.Position
	local distance = (playerPos - stagePart.Position).Magnitude
	local inFront = isInFront(playerPos, stagePart)
	local currentRadius = inFront and frontRadius or backRadius

	if distance <= currentRadius then
		local fade = 1 - (distance / currentRadius)
		local targetVolume = math.clamp(fade * maxVolume, 0, maxVolume)
		sound.Volume = sound.Volume + (targetVolume - sound.Volume) * 0.1
	else
		sound.Volume = sound.Volume + (0 - sound.Volume) * 0.1
	end
end)

-- Fungsi kontrol tambahan (opsional)
-- Panggil fungsi ini dari script lain atau GUI untuk kontrol manual

-- Fungsi untuk skip ke lagu berikutnya
function skipToNext()
	playNextSong()
end

-- Fungsi untuk putar lagu acak
function shufflePlay()
	playRandomSong()
end

-- Fungsi untuk pause/resume
function togglePause()
	if sound and sound.IsPlaying then
		sound:Pause()
		isPlaying = false
		print("Music paused")
	elseif sound then
		sound:Resume()
		isPlaying = true
		print("Music resumed")
	end
end

-- Fungsi untuk set lagu spesifik
function playSong(songNumber)
	if songNumber >= 1 and songNumber <= #songPlaylist and sound then
		currentSongIndex = songNumber
		sound.SoundId = songPlaylist[currentSongIndex]
		sound:Stop()
		sound:Play()
		isPlaying = true
		print("Playing song #" .. currentSongIndex)
	end
end

-- Debug info (hapus jika tidak diperlukan)
spawn(function()
	while true do
		wait(5)
		if sound and sound.IsPlaying then
			local timeLeft = sound.TimeLength - sound.TimePosition
			print("Song #" .. currentSongIndex .. " - Time left: " .. math.floor(timeLeft) .. " seconds")
		end
	end
end)
