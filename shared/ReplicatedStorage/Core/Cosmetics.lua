local ReplicatedStorage = game:GetService("ReplicatedStorage")

local inspect = require(ReplicatedStorage.Core.inspect)
local t = require(ReplicatedStorage.Vendor.t)

local Items = ReplicatedStorage.Items

local cosmeticType = t.array(t.union(
	t.strictInterface({
		Index = t.number,
		Name = t.string,
		Type = t.literal("Face"),
		Instance = t.instanceIsA("Decal"),
	}),

	t.strictInterface({
		Index = t.number,
		Name = t.string,
		Type = t.literal("Particle"),
		Instance = t.instanceIsA("ParticleEmitter"),
		Image = t.instanceIsA("Decal"),
	}),

	t.strictInterface({
		Index = t.number,
		Name = t.string,
		Type = t.union(
			t.literal("LowTier"),
			t.literal("HighTier")
		),
		Instance = t.instanceIsA("Folder"),
	}),

	t.strictInterface({
		Index = t.number,
		Name = t.string,
		Type = t.literal("Armor"),
		Instance = t.union(t.instanceIsA("Folder")),
		ParentType = t.union(
			t.literal("LowTier"),
			t.literal("HighTier")
		),
	}),

	t.strictInterface({
		Index = t.number,
		Name = t.string,
		Type = t.literal("Helmet"),
		Instance = t.union(t.instanceIsA("Accessory"), t.instanceIsA("BasePart")),
		ParentType = t.union(
			t.literal("LowTier"),
			t.literal("HighTier")
		),
	})
))

local Cosmetics = {}

Cosmetics.Cosmetics = {
	{
		Name = "Chill",
		Type = "Face",
		Instance = Items.Face_Chill.Face,
	},

	{
		Name = "Doge",
		Type = "LowTier",
		Instance = Items.Bundle_Doge,
	},

	{
		Name = "Ud'zal",
		Type = "HighTier",
		Instance = Items.Bundle_Udzal,
	},

	{
		Name = "Fire",
		Type = "Particle",
		Instance = Items.Particle_Fire.Fire,
		Image = Items.Particle_Fire.Image,
	},

	{
		Name = "Oof",
		Type = "LowTier",
		Instance = Items.Bundle_Oof,
	},
}

for index, item in ipairs(Cosmetics.Cosmetics) do
	local itemType = item.Instance:FindFirstChild("ItemType")
	item.Index = index

	if itemType
		and (itemType.Value == "BundleSimple"
		or itemType.Value == "BundleComplex")
	then
		table.insert(Cosmetics.Cosmetics, index + 1, {
			Name = item.Name,
			Type = "Armor",
			Instance = item.Instance.Contents.Armor,
			ParentType = item.Type,
		})

		table.insert(Cosmetics.Cosmetics, index + 1, {
			Name = item.Name,
			Type = "Helmet",
			Instance = item.Instance.Contents.Helmet,
			ParentType = item.Type,
		})
	end
end

Cosmetics.Distribution = {
	-- Face = 2,
	-- Particle = 2,
	-- LowTier = 2,
	HighTier = {
		788904610,
	},

	LowTier = {
		789065538,
		789073931,
	},

	Face = {
		789066394,
	},

	Particle = {
		789066975,
	},
}

function Cosmetics.GetStoreItems()
	local date = os.date("!*t")
	local rng = Random.new(date.year + date.yday)

	local collated = {}

	for _, cosmetic in ipairs(Cosmetics.Cosmetics) do
		if Cosmetics.Distribution[cosmetic.Type] then
			if collated[cosmetic.Type] then
				table.insert(collated[cosmetic.Type], cosmetic)
			else
				collated[cosmetic.Type] = { cosmetic }
			end
		end
	end

	local contents = {}

	for key, passes in pairs(Cosmetics.Distribution) do
		local products = {}

		for _ = 1, #passes do
			table.insert(products, table.remove(collated[key], rng:NextInteger(1, #collated[key])))
		end

		contents[key] = products
	end

	return contents
end

assert(cosmeticType(Cosmetics.Cosmetics), inspect(Cosmetics.Cosmetics))

return Cosmetics