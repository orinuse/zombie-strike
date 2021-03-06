local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local ArenaConstants = require(ReplicatedStorage.Core.ArenaConstants)
local Buffs = require(ServerScriptService.Libraries.Buffs)
local Dungeon = require(ReplicatedStorage.Libraries.Dungeon)
local DungeonState = require(ServerScriptService.DungeonState)
local ExperienceUtil = require(ServerScriptService.Libraries.ExperienceUtil)
local FastSpawn = require(ReplicatedStorage.Core.FastSpawn)
local GetAssetsFolder = require(ReplicatedStorage.Libraries.GetAssetsFolder)
local Maid = require(ReplicatedStorage.Core.Maid)
local Nametag = require(ServerScriptService.Shared.Nametag)
local OnDied = require(ReplicatedStorage.Core.OnDied)
local Promise = require(ReplicatedStorage.Core.Promise)
local RealDelay = require(ReplicatedStorage.Core.RealDelay)

local AMOUNT_FOR_NOT_BOSS = 0.7
local DEBUG = false
local DRS_PER_PLAYER = 0.5
local LIFETIME = 4

local allZombies = {}

local Zombie = {}
Zombie.__index = Zombie

Zombie.AIAggroCheckTime = 0.35

Zombie.AttackCheckInterval = 0.1
Zombie.AttackCooldown = 3
Zombie.AttackRange = 5

Zombie.WanderSpeed = 5

function Zombie:Destroy()
	self.aliveMaid:DoCleaning()
	self.maid:DoCleaning()
end

function Zombie.Debug(_, message)
	if DEBUG then
		print("🧟‍: " .. message)
	end
end

function Zombie:Spawn(position)
	local humanoid = self.instance.Humanoid
	self.instance:SetPrimaryPartCFrame(CFrame.new(position))
	self.instance.Name = self:GetName()
	self.instance.Parent = Workspace.Zombies

	local primaryPart = self.instance.PrimaryPart
	primaryPart.AncestryChanged:connect(function()
		if not primaryPart:IsDescendantOf(game) and not self:Disappeared() then
			self:Die()
		end
	end)

	self.aliveMaid:GiveTask(ReplicatedStorage.RuddevEvents.Damaged.Event:connect(function(humanoid)
		if humanoid == self.instance.Humanoid then
			self:UpdateNametag()
		end
	end))

	self.aliveMaid:GiveTask(
		ReplicatedStorage.RuddevEvents.Damaged.Event:connect(function(damaged, damage, damagedBy)
			if damaged == humanoid then
				self.damagedEvent:Fire(damage, damagedBy)
			end
		end)
	)

	for _, part in pairs(self.instance:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				part:SetNetworkOwner()
			end)
		end
	end

	self:SetupHumanoid()
	self:UpdateNametag()
	self:InitializeAI()
	self:AfterSpawn()
	self:TurnOffShadowCasting()

	return self.instance
end

function Zombie:SetupHumanoid()
	local humanoid = self.instance.Humanoid

	local health = self:GetHealth()
	humanoid.MaxHealth = health
	humanoid.Health = health

	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Flying, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.StrafingNoPhysics, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)

	if DungeonState.CurrentGamemode.Scales() then
		local damageReceivedScale = Instance.new("NumberValue")
		damageReceivedScale.Name = "DamageReceivedScale"
		damageReceivedScale.Value = self:GetDamageReceivedScale()
		damageReceivedScale.Parent = humanoid
	end

	OnDied(humanoid):connect(function()
		self:UpdateNametag()
		self:Die()
	end)
end

function Zombie:TurnOffShadowCasting()
	for _, part in pairs(self.instance:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CastShadow = false
		end
	end
end

function Zombie:InitializeAI()
	self.defaultAiInitialized = true

	self:Wander()

	self.aliveMaid:GiveTask(self.Damaged:connect(function(_, damagedBy)
		if self.wandering then
			self.lastAttacker = damagedBy
			self:Aggro()
		end
	end))

	spawn(function()
		wait(math.random(30, 50) / 10)

		while self.alive do
			local headBump = Workspace:FindPartOnRay(
				Ray.new(
					self.instance.Head.Position,
					self.instance.Head.CFrame.UpVector * 4
				)
			)

			if headBump then
				self:Debug("can't jump, something above")
			elseif self.InitializeBossAI == nil then
				local oldJumpPower = self.instance.Humanoid.JumpPower
				self.instance.Humanoid.JumpPower = 40
				self.instance.Humanoid.Jump = true
				RunService.Heartbeat:wait()
				RunService.Heartbeat:wait()
				self.instance.Humanoid.JumpPower = oldJumpPower
			end

			wait(math.random(30, 50) / 10)
		end
	end)
end

local hasSteppedAwayFromSpawn = {}

local function partToRegion3(part)
	local abs = math.abs

	local cf = part.CFrame -- this causes a LuaBridge invocation + heap allocation to create CFrame object - expensive! - but no way around it. we need the cframe
	local size = part.Size -- this causes a LuaBridge invocation + heap allocation to create Vector3 object - expensive! - but no way around it
	local sx, sy, sz = size.X, size.Y, size.Z -- this causes 3 Lua->C++ invocations

	local x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = cf:components() -- this causes 1 Lua->C++ invocations and gets all components of cframe in one go, with no allocations

	-- https://zeuxcg.org/2010/10/17/aabb-from-obb-with-component-wise-abs/
	local wsx = 0.5 * (abs(R00) * sx + abs(R01) * sy + abs(R02) * sz) -- this requires 3 Lua->C++ invocations to call abs, but no hash lookups since we cached abs value above; otherwise this is just a bunch of local ops
	local wsy = 0.5 * (abs(R10) * sx + abs(R11) * sy + abs(R12) * sz) -- same
	local wsz = 0.5 * (abs(R20) * sx + abs(R21) * sy + abs(R22) * sz) -- same

	-- just a bunch of local ops
	local minx = x - wsx
	local miny = y - wsy
	local minz = z - wsz

	local maxx = x + wsx
	local maxy = y + wsy
	local maxz = z + wsz

	local minv, maxv = Vector3.new(minx, miny, minz), Vector3.new(maxx, maxy, maxz)
	return Region3.new(minv, maxv)
end

local spawnLocationRegion3

local function isViableAggroTarget(player)
	local character = player.Character
	if not character or character.Humanoid.Health <= 0 then
		return false
	end

	if Dungeon.GetDungeonData("Gamemode") == "Mission" then
		if hasSteppedAwayFromSpawn[player] then
			return true
		end

		if character.PrimaryPart then
			if spawnLocationRegion3 == nil then
				spawnLocationRegion3 = partToRegion3(Workspace.Rooms.StartSection.SpawnLocation)
			end

			local count = #Workspace:FindPartsInRegion3WithWhiteList(
				spawnLocationRegion3,
				{ character },
				1
			)

			if count == 0 then
				hasSteppedAwayFromSpawn[player] = true
				return true
			else
				return false
			end
		else
			return false
		end
	end

	return true
end

function Zombie:Wander()
	if not self.defaultAiInitialized then return end
	self.aggroTick = self.aggroTick + 1

	local humanoid = self.instance.Humanoid
	humanoid.WalkSpeed = self.WanderSpeed

	local noiseX = math.random()
	local noiseY = math.random()

	self.wandering = true

	spawn(function()
		while self.wandering do
			humanoid:Move(Vector3.new(
				math.noise(noiseX) * 2,
				0,
				math.noise(noiseY) * 2
			))

			noiseX = noiseX + 1 / 15
			noiseY = noiseY + 1 / 15

			wait(1)
		end
	end)

	spawn(function()
		wait(math.random(40, 60) / 100)
		while self.wandering do
			for _, player in pairs(Players:GetPlayers()) do
				local character = player.Character
				if isViableAggroTarget(player) then
					local aggroRange

					if Dungeon.GetDungeonData("Gamemode") == "Boss" then
						aggroRange = Dungeon.GetDungeonData("BossInfo").AIAggroRange
					else
						aggroRange = Dungeon.GetDungeonData("CampaignInfo").AIAggroRange
					end

					local primaryPart = self.instance.PrimaryPart
					if primaryPart == nil then
						return
					end

					if (character.PrimaryPart.Position - primaryPart.Position).Magnitude
						<= aggroRange
					then
						self:Aggro(character)
					end
				end
			end

			wait(self.AIAggroCheckTime)
		end
	end)
end

function Zombie:AIShouldMove(ourTick)
	return self.alive
		and self.aggroTick == ourTick
		and self.aggroFocus ~= nil
		and self.aggroFocus:IsDescendantOf(game)
		and self.aggroFocus.Humanoid.Health > 0
end

function Zombie:StupidAI()
	local humanoid = self.instance.Humanoid
	local ourTick = self.aggroTick

	self.aliveMaid:GiveTask(humanoid.MoveToFinished:connect(function()
		if self:AIShouldMove(ourTick) then
			humanoid:MoveTo(self.aggroFocus.PrimaryPart.Position, self.aggroFocus.PrimaryPart)
		end
	end))

	if self:AIShouldMove(ourTick) then
		humanoid:MoveTo(self.aggroFocus.PrimaryPart.Position, self.aggroFocus.PrimaryPart)
	end
end

function Zombie:Aggro(focus)
	if not self.defaultAiInitialized then return end

	local humanoid = self.instance.Humanoid
	humanoid.WalkSpeed = self:GetSpeed()

	self:AssignAggroFocus(focus)
	local focus = self.aggroFocus
	if not focus then return end

	self.wandering = false

	local ourTick = self.aggroTick + 1
	self.aggroTick = ourTick

	local reactionTime = self:GetScaleSafe("ReactionTime")
	local waitForReaction = Promise.resolve()
	if reactionTime then
		waitForReaction = Promise.delay(reactionTime)
		if not self.alive then return end
	end

	waitForReaction:andThen(function()
		FastSpawn(function()
			self:StupidAI()
			wait(math.random(40, 60) / 100)
			while self.aggroTick == ourTick do
				if self:CheckAttack() then
					wait(self:GetAttackCooldown())
				else
					wait(self.AttackCheckInterval)
				end
			end
		end)
	end)
end

function Zombie:AssignAggroFocus(force)
	local players = Players:GetPlayers()
	if #players == 0 then
		self:Debug("AssignAggroFocus: All players have left")
		self.aggroFocus = nil
		self:AggroTargetChanged(nil)
		self:Wander()
		return
	end

	if force then
		self.aggroFocus = force
	else
		self.aggroFocus = nil

		if self.lastAttacker then
			local character = self.lastAttacker.Character
			if character then
				self.aggroFocus = character
			end
		end

		if not self.aggroFocus then
			while #players > 0 do
				local player = table.remove(players, math.random(#players))
				local character = player.Character
				if character and character.Humanoid.Health > 0 then
					self.aggroFocus = character
				end
			end
		end
	end

	self:AggroTargetChanged(self.aggroFocus)

	if self.aggroFocus then
		self:Debug("Aggro focus chosen: " .. self.aggroFocus.Name)
		self.aliveMaid:GiveTask(self.aggroFocus.Humanoid.Died:connect(function()
			self:AssignAggroFocus()
		end))

		return
	end

	self:Debug("AssignAggroFocus: All players have died")
	self:Wander()
end

function Zombie:CheckAttack()
	if self.alive and
		(
			self.instance.HumanoidRootPart.Position - self.aggroFocus.PrimaryPart.Position
		).Magnitude <= self.AttackRange
	then
		return self:Attack()
	end
end

function Zombie:Die()
	if not self.alive then return end
	self.alive = false
	self.instance.Humanoid.Health = 0
	self.aliveMaid:DoCleaning()
	ReplicatedStorage.Remotes.KillEnemy:FireAllClients(self.instance)
	for _, player in pairs(Players:GetPlayers()) do
		ServerStorage.Events.GiveQuest:Fire(player, "KillZombies", 1)
	end
	self:GiveXP()
	self:PlayDeathSound()
	self:MaybeDropBuff()
	self:AfterDeath()
	self.diedEvent:Fire()

	RealDelay(LIFETIME, function()
		self:Destroy()
	end)
end

function Zombie:TakeDamage(damage)
	local defenseBuffs = self.buffs.Defense

	if defenseBuffs then
		for buff in pairs(defenseBuffs) do
			damage = damage * (1 - buff.Amount)
		end
	end

	self.instance.Humanoid:TakeDamage(damage)
end

function Zombie:GiveBuff(scaleName, amount)
	local function maybeUpdateSpeed()
		if scaleName == "Speed"
			and not self.wandering
			and self.instance:IsDescendantOf(game)
			and self:GetScaleSafe("Speed")
		then
			self.instance.Humanoid.WalkSpeed = self:GetSpeed()
		end
	end

	if self.buffs[scaleName] == nil then
		self.buffs[scaleName] = {}
	end

	local result

	result = {
		Amount = amount,
		Destroy = function()
			self.buffs[scaleName][result] = nil
			maybeUpdateSpeed()
		end,
	}

	self.buffs[scaleName][result] = true
	maybeUpdateSpeed()

	return result
end

function Zombie:MaybeDropBuff()
	local primaryPart = self.instance.PrimaryPart
	if primaryPart then
		Buffs.MaybeDropBuff(primaryPart.Position)
	end
end

function Zombie:LoadAnimation(animation)
	return self.instance.Humanoid:LoadAnimation(animation)
end

-- START XP
function Zombie:GiveXP()
	local xpGain = self:GetXP()

	if xpGain > 0 then
		for _, player in pairs(Players:GetPlayers()) do
			ExperienceUtil.GivePlayerXP(player, xpGain, self.instance.PrimaryPart)
		end
	end
end

function Zombie.GetXP()
	if DungeonState.CurrentGamemode.Scales() then
		-- Boss gives the XP, makes everything simpler
		return 0
	end

	return (Dungeon.GetDungeonData("DifficultyInfo").XP * AMOUNT_FOR_NOT_BOSS) / DungeonState.NormalZombies
end
-- END XP

-- START STATS
function Zombie:GetScaling()
	if Dungeon.GetDungeonData("Gamemode") == "Boss" then
		return Dungeon.GetDungeonData("BossInfo").Stats[self.zombieType]
	else
		local campaignInfo = Dungeon.GetDungeonData("CampaignInfo")
		return assert(campaignInfo.Stats[self.zombieType])
	end
end

function Zombie:GetScale(key)
	local gamemode = Dungeon.GetDungeonData("Gamemode")

	if gamemode == "Arena" then
		local zombieData = assert(
			ArenaConstants.Zombies[self.zombieType],
			"Zombie constants not found for " .. self.zombieType
		)

		local stat = assert(zombieData[key], self.zombieType .. " did not have stat " .. key)
		if typeof(stat) == "number" then
			return stat
		else
			local function lerp(a, b, t)
				return a + (b - a) * t
			end

			if self.level >= ArenaConstants.StopBeingLinearLevel then
				return stat.Max * (ArenaConstants.PastCapMultiplier ^ (self.level - ArenaConstants.StopBeingLinearLevel))
			end

			return lerp(stat.Min, stat.Max, (self.level - 1) / (ArenaConstants.StopBeingLinearLevel - 1))
		end
	else
		local campaignInfo = Dungeon.GetDungeonData("CampaignInfo")

		local scale = assert(
			(self.Scaling or self:GetScaling())[key]
				or self:CustomScale(key),
			"no scale for " .. key
		)

		if scale.Base == nil then
			local number = assert(
				scale[Dungeon.GetDungeonData("Difficulty")],
				"difficulty locked scaling has no key for " .. key
			)

			return number
		end

		local scaleAmount = 1
		if Dungeon.GetDungeonData("Gamemode") ~= "Boss" then
			scaleAmount = self.level - campaignInfo.Difficulties[1].MinLevel
		end

		return scale.Base * scale.Scale ^ scaleAmount
	end
end

function Zombie:GetScaleSafe(key)
	local success, scale = pcall(function()
		return self:GetScale(key)
	end)

	return success and scale
end

function Zombie:GetHealth()
	if DungeonState.CurrentGamemode.Scales() then
		return 100
	else
		local health = self:GetScale("Health")
		health = health * (1 + (0.35 * (#Players:GetPlayers() - 1)))
		return health
	end
end

function Zombie:GetDamageAgainst(player)
	return self:GetDamageAgainstConstant(
		player,
		self:GetScale("Damage"),
		self:GetScaleSafe("MaxHealthDamage")
	)
end

function Zombie.GetDamageAgainstConstant(_, player, damage, maxHpDamage)
	if maxHpDamage then
		local character = player.Character
		if character then
			damage = damage + character.Humanoid.MaxHealth * (maxHpDamage / 100)
		end
	end

	return damage
end

function Zombie:GetDamageReceivedScale()
	local scale = self:GetScale("DamageReceivedScale")

	if Dungeon.GetDungeonData("Gamemode") ~= "Boss" then
		scale = scale * (DRS_PER_PLAYER ^ (#Players:GetPlayers() - 1))
	end

	return scale
end

function Zombie:GetAttackCooldown()
	return self.AttackCooldown
end

function Zombie:GetSpeed()
	local speed = self:GetScale("Speed")

	local buffMod = 1

	local speedBuffs = self.buffs.Speed
	if speedBuffs then
		for buff in pairs(speedBuffs) do
			buffMod = buffMod + buff.Amount
		end
	end

	return math.max(0, speed * buffMod)
end
-- END STATS

function Zombie:GetName()
	return self.Name
		or self:GetModel().ZombieName.Value
end

function Zombie:GetAsset(assetName)
	return GetAssetsFolder()[self.Model][assetName]
end

function Zombie:UpdateNametag()
	local nametag = Nametag(self.instance, self.level)

	if DungeonState.CurrentGamemode.Scales() then
		nametag.Level.Text = ""
		nametag.Health.HealthNumber.Visible = false
	end

	local campaignInfo = Dungeon.GetDungeonData("CampaignInfo")
	if campaignInfo and table.find(campaignInfo.SpecialZombies, self.Model) then
		nametag.EnemyName.TextColor3 = Color3.new(1, 1, 0.5)
		nametag.EnemyName.Text = "⭐" .. self:GetName()
	end

	return nametag
end

function Zombie.Disappeared()
	return false
end

function Zombie.ShouldSpawn()
	return true
end

-- START BASIC HOOKS
function Zombie.CustomScale() end
function Zombie.AfterDeath() end
function Zombie.AfterSpawn() end
function Zombie.AggroTargetChanged() end
-- END BASIC HOOKS

-- START SOUNDS
function Zombie.GetDeathSound()
	local soundsFolder

	if Dungeon.GetDungeonData("Gamemode") == "Boss" then
		soundsFolder = SoundService.ZombieSounds[Dungeon.GetDungeonData("BossInfo").RoomName]
	else
		soundsFolder = SoundService.ZombieSounds[Dungeon.GetDungeonData("Campaign")]
	end

	local sounds = soundsFolder.Death:GetChildren()
	return sounds[math.random(#sounds)]:Clone()
end

function Zombie:PlayDeathSound()
	local sound = self:GetDeathSound()
	sound.Parent = self.instance.PrimaryPart
	sound:Play()
	Debris:AddItem(sound)
end
-- END SOUNDS

function Zombie:GetModel()
	local folder

	if Dungeon.GetDungeonData("Gamemode") == "Boss" then
		folder = ServerStorage.Zombies[Dungeon.GetDungeonData("BossInfo").RoomName]
	else
		folder = ServerStorage.Zombies[Dungeon.GetDungeonData("Campaign")]
	end

	return folder[self.Model]:Clone()
end

function Zombie.GetZombies()
	local zombies = {}
	for zombie in pairs(allZombies) do
		table.insert(zombies, zombie)
	end
	return zombies
end

function Zombie.GetAliveZombies()
	local zombies = {}
	for zombie in pairs(allZombies) do
		if zombie.alive then
			table.insert(zombies, zombie)
		end
	end
	return zombies
end

function Zombie.new(zombieType, level, ...)
	assert(zombieType)
	local originalZombie = require(script.Parent[zombieType])
	assert(originalZombie)

	local zombie = originalZombie.new(level, ...)

	local instance = (zombie.GetModel or Zombie.GetModel)(zombie)

	local aliveMaid = Maid.new()

	local maid = Maid.new()
	maid:GiveTask(instance)
	maid:GiveTask(aliveMaid)

	local damagedEvent = Instance.new("BindableEvent")
	local diedEvent = Instance.new("BindableEvent")

	local zombieInstance = setmetatable({
		alive = true,
		aliveMaid = aliveMaid,
		aggroTick = 0,
		buffs = {},
		damagedEvent = damagedEvent,
		diedEvent = diedEvent,
		instance = instance,
		level = level,
		maid = maid,
		zombieType = zombieType,

		Damaged = damagedEvent.Event,
		Died = diedEvent.Event,
	}, {
		__index = function(_, key)
			return zombie[key]
				or Zombie[key]
		end,
	})

	maid:GiveTask(function()
		allZombies[zombieInstance] = nil
	end)

	allZombies[zombieInstance] = true

	return zombieInstance
end

return Zombie
