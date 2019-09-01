local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local XP = require(ReplicatedStorage.Libraries.XP)

local HealthXP = script.Parent.Main.HealthXP
local LocalPlayer = Players.LocalPlayer

local HitTick = HealthXP.Health.HitTick

local lastHealth

local hitTickSpeed = 0.3
local hitTickInfo = TweenInfo.new(hitTickSpeed, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local transparencyTickTween = {
	TweenInfo.new(hitTickSpeed / 1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
	{ BackgroundTransparency = 0.2, BackgroundColor3 = Color3.new(0.8, 0.8, 0.8) }
}

local function updateHealth(humanoid)
	local health, maxHealth = humanoid.Health, humanoid.MaxHealth

	if lastHealth > health then
		local diff = health - lastHealth

		local hitTick = HitTick:Clone()
		hitTick.Position = UDim2.new(lastHealth / maxHealth, 0, 0.5, 0)
		hitTick.Size = UDim2.new(diff / maxHealth, 0, 0, 0)
		hitTick.Parent = HealthXP.Health

		TweenService:Create(
			hitTick,
			hitTickInfo,
			{
				Size = UDim2.new(diff / maxHealth, 0, 1.2, 0)
			}
		):Play()

		TweenService:Create(hitTick, unpack(transparencyTickTween)):Play()
		Debris:AddItem(hitTick)
	end

	HealthXP.Health.Inner.Size = UDim2.new(health / maxHealth, 0, 1, 0)
	HealthXP.Health.TextLabel.Text = health .. "/" .. maxHealth
	lastHealth = health
end

local function updateAmmo(ammo)
	HealthXP.Ammo.Text = ammo
end

local function characterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	lastHealth = humanoid.MaxHealth
	updateHealth(humanoid)

	humanoid.HealthChanged:connect(function()
		updateHealth(humanoid)
	end)

	local ammo = character:WaitForChild("Gun"):WaitForChild("Ammo")
	ammo.Changed:connect(updateAmmo)
	updateAmmo(ammo.Value)
end

local playerData = LocalPlayer:WaitForChild("PlayerData")

local level = playerData:WaitForChild("Level")
local xp = playerData:WaitForChild("XP")

local function updateXP()
	local maxXp = XP.XPNeededForNextLevel(level.Value)

	HealthXP.XP.TextLabel.Text = ("%d / %d"):format(
		xp.Value,
		maxXp
	)

	HealthXP.XP.Inner.Size = UDim2.new(xp.Value / maxXp, 0, 1, 0)
end

coroutine.wrap(updateXP)()
xp.Changed:connect(updateXP)

if LocalPlayer.Character then
	characterAdded(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:connect(characterAdded)
