local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local gui = Instance.new("ScreenGui")
gui.Name = "TrajectoryUI"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 260, 0, 150)
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
frame.Visible = false
frame.Active = true
frame.Parent = gui

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 30, 0, 30)
closeButton.Position = UDim2.new(1, -30, 0, 0)
closeButton.Text = "X"
closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Font = Enum.Font.SourceSansBold
closeButton.TextSize = 18
closeButton.Parent = frame

local transLabel = Instance.new("TextLabel")
transLabel.Size = UDim2.new(0.9, 0, 0, 20)
transLabel.Position = UDim2.new(0.05, 0, 0, 35)
transLabel.Text = "Arch Transparency (0-1):"
transLabel.TextColor3 = Color3.new(1, 1, 1)
transLabel.BackgroundTransparency = 1
transLabel.TextXAlignment = Enum.TextXAlignment.Left
transLabel.Parent = frame

local transInput = Instance.new("TextBox")
transInput.Size = UDim2.new(0.9, 0, 0, 30)
transInput.Position = UDim2.new(0.05, 0, 0, 55)
transInput.Text = "0.5"
transInput.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
transInput.TextColor3 = Color3.new(1, 1, 1)
transInput.Parent = frame

local heightLabel = Instance.new("TextLabel")
heightLabel.Size = UDim2.new(0.9, 0, 0, 40)
heightLabel.Position = UDim2.new(0.05, 0, 0, 95)
heightLabel.Text = "Current Peak: 0\n45° Vacuum Peak: 0"
heightLabel.TextColor3 = Color3.new(1, 1, 1)
heightLabel.BackgroundTransparency = 1
heightLabel.TextXAlignment = Enum.TextXAlignment.Left
heightLabel.TextYAlignment = Enum.TextYAlignment.Top
heightLabel.Parent = frame

local archBase = Instance.new("Part")
archBase.Name = "TrajectoryArch"
archBase.Anchored = true
archBase.CanCollide = false
archBase.Transparency = 1
archBase.Size = Vector3.new(1, 1, 1)
archBase.Position = Vector3.zero
archBase.Parent = workspace

local hitBall = Instance.new("Part")
hitBall.Shape = Enum.PartType.Ball
hitBall.Size = Vector3.new(1.5, 1.5, 1.5)
hitBall.Color = Color3.fromRGB(255, 0, 0)
hitBall.Material = Enum.Material.Neon
hitBall.Transparency = 0
hitBall.Anchored = true
hitBall.CanCollide = false
hitBall.Parent = archBase

local isTrajectoryActive = false
local runConnection
local inputConnection
local uiInputConnection

local dragging
local dragInputEvent
local dragStart
local startPos

local attachmentPool = {}
local beamPool = {}
local activePoints = 0

local lastCalcPos = Vector3.zero
local lastCalcDir = Vector3.zero
local lastTrans = -1

local function enforceNumberInput(box)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local text = box.Text
		local filtered = string.gsub(text, "[^%d%.%-]", "")
		if text ~= filtered then
			box.Text = filtered
		end
	end)
end

enforceNumberInput(transInput)

frame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		dragStart = input.Position
		startPos = frame.Position

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

frame.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		dragInputEvent = input
	end
end)

uiInputConnection = UserInputService.InputChanged:Connect(function(input)
	if input == dragInputEvent and dragging then
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(
			startPos.X.Scale, 
			startPos.X.Offset + delta.X, 
			startPos.Y.Scale, 
			startPos.Y.Offset + delta.Y
		)
	end
end)

local function clearArch()
	for i = 1, #beamPool do
		beamPool[i].Enabled = false
	end
	hitBall.Position = Vector3.new(0, -10000, 0)
	lastCalcPos = Vector3.zero
end

local function getPoint(pos)
	activePoints = activePoints + 1
	local att = attachmentPool[activePoints]
	if not att then
		att = Instance.new("Attachment")
		att.Parent = archBase
		attachmentPool[activePoints] = att
	end
	att.WorldPosition = pos
	return att
end

local function connectBeams(points, trans)
	for i = 1, #points - 1 do
		local beam = beamPool[i]
		if not beam then
			beam = Instance.new("Beam")
			beam.FaceCamera = true
			beam.Width0 = 0.3
			beam.Width1 = 0.3
			beam.Color = ColorSequence.new(Color3.fromRGB(150, 150, 150))
			beam.LightEmission = 0.5
			beam.Parent = archBase
			beamPool[i] = beam
		end
		beam.Attachment0 = points[i]
		beam.Attachment1 = points[i + 1]
		beam.Transparency = NumberSequence.new(trans)
		beam.Enabled = true
	end
	for i = #points, #beamPool do
		beamPool[i].Enabled = false
	end
end

local function drawArch()
	if not isTrajectoryActive then
		clearArch()
		return
	end

	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local startPosVec = rootPart.Position
	local direction = camera.CFrame.LookVector
	local archTrans = tonumber(transInput.Text) or 0.5

	if startPosVec == lastCalcPos and direction == lastCalcDir and archTrans == lastTrans then
		return
	end

	lastCalcPos = startPosVec
	lastCalcDir = direction
	lastTrans = archTrans

	activePoints = 0

	local velocityMag = 40
	local simGravity = 10
	local airDrag = 0
	local velocityObj = direction * velocityMag

	local vy45 = velocityMag * math.sin(math.rad(45))
	local maxAt45 = (vy45 * vy45) / (2 * simGravity)

	local timeStep = 0.05
	local maxTime = 100
	local currentPos = startPosVec
	local currentVel = velocityObj
	local startY = startPosVec.Y
	local currentMaxHeight = 0

	local points = {}
	table.insert(points, getPoint(currentPos))

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {character, archBase}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	for t = 0, maxTime, timeStep do
		local heightDiff = currentPos.Y - startY
		if heightDiff > currentMaxHeight then
			currentMaxHeight = heightDiff
		end

		local nextPos = currentPos + (currentVel * timeStep)
		local raycastResult = workspace:Raycast(currentPos, nextPos - currentPos, raycastParams)

		if raycastResult then
			hitBall.Position = raycastResult.Position
			table.insert(points, getPoint(raycastResult.Position))
			break
		else
			table.insert(points, getPoint(nextPos))
			currentPos = nextPos
			currentVel = currentVel - Vector3.new(0, simGravity * timeStep, 0) - (currentVel * airDrag * timeStep)
		end
	end

	connectBeams(points, archTrans)
	heightLabel.Text = string.format("Current Peak: %.1f studs\n45° Vacuum Peak: %.1f studs", currentMaxHeight, maxAt45)
end

closeButton.MouseButton1Click:Connect(function()
	if runConnection then runConnection:Disconnect() end
	if inputConnection then inputConnection:Disconnect() end
	if uiInputConnection then uiInputConnection:Disconnect() end
	isTrajectoryActive = false
	archBase:Destroy()
	gui:Destroy()
end)

inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.J then
		frame.Visible = not frame.Visible
	elseif input.KeyCode == Enum.KeyCode.Q then
		isTrajectoryActive = not isTrajectoryActive
		if not isTrajectoryActive then
			clearArch()
			heightLabel.Text = "Current Peak: 0 studs\n45° Vacuum Peak: 0 studs"
		end
	end
end)

runConnection = RunService.RenderStepped:Connect(function()
	drawArch()
end)
