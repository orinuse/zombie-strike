local RunService = game:GetService("RunService")

local ROTATE_RATE = 1

local bases = {}
local rotators = {}
local totalDelta = 0

local function getKey(model)
	if model:FindFirstChild("UUID") then
		return model.UUID.Value
	else
		return model
	end
end

RunService.Heartbeat:connect(function(delta)
	totalDelta = totalDelta + delta

	for model in pairs(rotators) do
		model:SetPrimaryPartCFrame(
			CFrame.new(model.PrimaryPart.Position)
			* CFrame.Angles(0, bases[getKey(model)] + totalDelta * ROTATE_RATE, 0)
		)
	end
end)

return function(viewportFrame, model)
	local model = model:Clone()

	if viewportFrame.CurrentCamera then
		viewportFrame.CurrentCamera:Destroy()
	end

	local camera = Instance.new("Camera")
	model:SetPrimaryPartCFrame(CFrame.new())
	model.Parent = camera

	local modelCFrame, size = model:GetBoundingBox()
	model:TranslateBy(-modelCFrame.Position)

	local distance = size.Magnitude * 1.2
	local dir = Vector3.new(0.5, 0, 0.5).Unit
	camera.CFrame = CFrame.new(distance * dir, Vector3.new(0, 0, 0))

	camera.Parent = viewportFrame
	viewportFrame.CurrentCamera = camera

	if not bases[getKey(model)] then
		bases[getKey(model)] = math.random() * math.pi
	end

	rotators[model] = true

	model.AncestryChanged:connect(function()
		if not model:IsDescendantOf(game) then
			rotators[model] = nil
		else
			rotators[model] = true
		end
	end)

	return {
		UpdateScale = function(_, newScale)
			camera.CFrame = CFrame.new(distance * (1 / newScale) * dir, Vector3.new(0, 0, 0))
		end,
	}
end
