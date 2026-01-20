local IGNORE_FORBIDDEN = true
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local forbidden = {"#","!","_"}
local function containsForbidden(s)
	if not IGNORE_FORBIDDEN then return false end
	if not s then return true end
	for _,c in ipairs(forbidden) do
		if string.find(s, c, 1, true) then return true end
	end
	return false
end
local function normalize(s)
	if not s then return "" end
	local out = string.lower(s)
	out = string.gsub(out, "%s+", "")
	out = string.gsub(out, "[#_!]", "")
	return out
end
local function safeWaitForChild(parent, name)
	if not parent then return nil end
	local found = parent:FindFirstChild(name)
	while not found do
		found = parent:FindFirstChild(name)
		wait(0.1)
	end
	return found
end
local AssetsRoot = safeWaitForChild(ReplicatedStorage, "Assets")
local KillersRoot = safeWaitForChild(AssetsRoot, "Killers")
local SurvivorsRoot = safeWaitForChild(AssetsRoot, "Survivors")
local SkinsRoot = safeWaitForChild(AssetsRoot, "Skins")
local baseFolder = "SkinIndexer"
pcall(function() makefolder(baseFolder) end)
pcall(function() makefolder(baseFolder.."/killers") end)
pcall(function() makefolder(baseFolder.."/survivors") end)
local metaPath = baseFolder.."/meta.json"
local function readJson(path)
	local ok, c = pcall(function() return readfile(path) end)
	if not ok then return nil end
	local ok2, t = pcall(function() return HttpService:JSONDecode(c) end)
	if not ok2 then return nil end
	return t
end
local function writeJson(path, data)
	pcall(function() writefile(path, HttpService:JSONEncode(data)) end)
end
local meta = readJson(metaPath) or {skinpoints = 0, owned = {killers = {}, survivors = {}}, totalIndexed = 0}
local function recomputeMetaTotals()
	local total = 0
	meta.owned = meta.owned or {killers = {}, survivors = {}}
	for _,sideKey in ipairs({"killers","survivors"}) do
		local sideTable = meta.owned[sideKey] or {}
		for _,skins in pairs(sideTable) do
			for _ in pairs(skins) do total = total + 1 end
		end
	end
	meta.totalIndexed = total
	meta.skinpoints = (meta.totalIndexed or 0) * 5
end
recomputeMetaTotals()
local function saveMeta() writeJson(metaPath, meta) end
local function safeFileName(side, id)
	return baseFolder.."/"..side.."/"..HttpService:UrlEncode(id)..".json"
end
local function loadCharData(side, id)
	local path = safeFileName(side, id)
	local data = readJson(path) or {skins = {}}
	return data, path
end
local function saveCharData(path, data) writeJson(path, data) end
local function gatherCategories(root)
	local out = {}
	if not root then return out end
	for _,v in ipairs(root:GetChildren()) do
		if not containsForbidden(v.Name) then table.insert(out, v.Name) end
	end
	table.sort(out)
	return out
end
local function getSkinsForCategory(side, categoryName)
	if not SkinsRoot then return {} end
	local sideKey = side:sub(1,1):upper()..side:sub(2)
	local sideRoot = SkinsRoot:FindFirstChild(sideKey) or SkinsRoot:FindFirstChild(side)
	if not sideRoot then return {} end
	local cat = sideRoot:FindFirstChild(categoryName)
	if not cat then return {} end
	local out = {}
	for _,v in ipairs(cat:GetChildren()) do
		if not containsForbidden(v.Name) then table.insert(out, v.Name) end
	end
	table.sort(out)
	return out
end
local function findCategoryMatch(sideRoot, actorName)
	if not sideRoot then return nil end
	local norm = normalize(actorName)
	for _,v in ipairs(sideRoot:GetChildren()) do
		if (not containsForbidden(v.Name)) and normalize(v.Name) == norm then
			return v.Name
		end
	end
	return nil
end
local function countTotalSkinsInGame()
	local total = 0
	if not SkinsRoot then return 0 end
	for _,side in ipairs({"Killers","Survivors"}) do
		local sideRoot = SkinsRoot:FindFirstChild(side)
		if sideRoot then
			for _,cat in ipairs(sideRoot:GetChildren()) do
				if not containsForbidden(cat.Name) then
					for _,s in ipairs(cat:GetChildren()) do
						if not containsForbidden(s.Name) then total = total + 1 end
					end
				end
			end
		end
	end
	return total
end
local function indexSkins()
	local added = 0
	local function scanSide(folder, sideKey, sideRootSource)
		if not folder then return end
		for _,model in ipairs(folder:GetChildren()) do
			if model:IsA("Model") then
				local actor = model:GetAttribute("ActorDisplayName")
				local skin = model:GetAttribute("SkinName")
				if actor and skin and not containsForbidden(actor) and not containsForbidden(skin) then
					local matched = findCategoryMatch(sideRootSource, actor)
					if matched then
						local data, path = loadCharData(sideKey, matched)
						data.skins = data.skins or {}
						if not data.skins[skin] then
							data.skins[skin] = true
							saveCharData(path, data)
							meta.owned[sideKey] = meta.owned[sideKey] or {}
							meta.owned[sideKey][matched] = meta.owned[sideKey][matched] or {}
							meta.owned[sideKey][matched][skin] = true
							added = added + 1
						end
					end
				end
			end
		end
	end
	local playersFolder = Workspace:FindFirstChild("Players")
	if playersFolder and playersFolder:FindFirstChild("Killers") then
		scanSide(playersFolder.Killers, "killers", KillersRoot)
	end
	if playersFolder and playersFolder:FindFirstChild("Survivors") then
		scanSide(playersFolder.Survivors, "survivors", SurvivorsRoot)
	end
	recomputeMetaTotals()
	saveMeta()
	return added
end
local function tableCount(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end
local function countIndexedFor(sideKey, categoryName)
	if meta.owned and meta.owned[sideKey] and meta.owned[sideKey][categoryName] then
		return tableCount(meta.owned[sideKey][categoryName])
	end
	local data,_ = loadCharData(sideKey, categoryName)
	local owned = 0
	if data and data.skins then
		for _ in pairs(data.skins) do owned = owned + 1 end
	end
	return owned
end
local function countMaxFor(sideKey, categoryName)
	local side = sideKey == "killers" and "killers" or "survivors"
	local skins = getSkinsForCategory(side, categoryName)
	return #skins
end
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SkinIndexerUI"
screenGui.Parent = PlayerGui
screenGui.ResetOnSpawn = false
local centerButton = Instance.new("TextButton")
centerButton.Size = UDim2.new(0.08,0,0.08,0)
centerButton.Position = UDim2.new(0.5,0,0.92,0)
centerButton.AnchorPoint = Vector2.new(0.5,0.5)
centerButton.Text = ""
centerButton.Parent = screenGui
local cbCorner = Instance.new("UICorner")
cbCorner.CornerRadius = UDim.new(0.35,0)
cbCorner.Parent = centerButton
local cbIcon = Instance.new("ImageLabel")
cbIcon.Size = UDim2.new(0.6,0,0.6,0)
cbIcon.Position = UDim2.new(0.5,0,0.5,0)
cbIcon.AnchorPoint = Vector2.new(0.5,0.5)
cbIcon.BackgroundTransparency = 1
cbIcon.Image = "rbxassetid://6023426915"
cbIcon.Parent = centerButton
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0.6,0,0.65,0)
mainFrame.Position = UDim2.new(0.5,0,0.45,0)
mainFrame.AnchorPoint = Vector2.new(0.5,0.5)
mainFrame.Visible = false
mainFrame.Parent = screenGui
mainFrame.BackgroundColor3 = Color3.fromRGB(18,18,20)
local mfCorner = Instance.new("UICorner")
mfCorner.CornerRadius = UDim.new(0.03,0)
mfCorner.Parent = mainFrame
local mfAspect = Instance.new("UIAspectRatioConstraint")
mfAspect.Parent = mainFrame
mfAspect.AspectRatio = 1.5
local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1,0,0.12,0)
topBar.Position = UDim2.new(0,0,0,0)
topBar.Parent = mainFrame
topBar.BackgroundTransparency = 1
local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.6,0,1,0)
title.Position = UDim2.new(0.03,0,0,0)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Skin Indexer"
title.Font = Enum.Font.GothamSemibold
title.TextSize = 20
title.BackgroundTransparency = 1
title.TextColor3 = Color3.fromRGB(235,235,235)
title.Parent = topBar
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0.06,0,0.6,0)
closeBtn.Position = UDim2.new(0.94,0,0.2,0)
closeBtn.AnchorPoint = Vector2.new(0,0)
closeBtn.Text = "✕"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 18
closeBtn.BackgroundTransparency = 0.8
closeBtn.TextColor3 = Color3.fromRGB(220,220,220)
closeBtn.Parent = topBar
local skinPointsLabel = Instance.new("TextLabel")
skinPointsLabel.Size = UDim2.new(0.35,0,0.7,0)
skinPointsLabel.Position = UDim2.new(0.62,0,0.15,0)
skinPointsLabel.Text = "Indexed Points: "..tostring(meta.skinpoints or 0)
skinPointsLabel.Font = Enum.Font.Gotham
skinPointsLabel.TextSize = 14
skinPointsLabel.BackgroundTransparency = 1
skinPointsLabel.TextColor3 = Color3.fromRGB(210,210,210)
skinPointsLabel.Parent = topBar
local leftFrame = Instance.new("Frame")
leftFrame.Size = UDim2.new(0.22,0,0.75,0)
leftFrame.Position = UDim2.new(0.03,0,0.18,0)
leftFrame.Parent = mainFrame
leftFrame.BackgroundTransparency = 1
local sideSelector = Instance.new("Frame")
sideSelector.Size = UDim2.new(1,0,0.12,0)
sideSelector.Position = UDim2.new(0,0,0,0)
sideSelector.Parent = leftFrame
sideSelector.BackgroundTransparency = 1
local killersBtn = Instance.new("TextButton")
killersBtn.Size = UDim2.new(0.48,0,1,0)
killersBtn.Position = UDim2.new(0,0,0,0)
killersBtn.Text = "Killers"
killersBtn.Parent = sideSelector
killersBtn.Font = Enum.Font.GothamSemibold
killersBtn.TextSize = 14
killersBtn.TextColor3 = Color3.fromRGB(230,230,230)
local survivorsBtn = Instance.new("TextButton")
survivorsBtn.Size = UDim2.new(0.48,0,1,0)
survivorsBtn.Position = UDim2.new(0.52,0,0,0)
survivorsBtn.Text = "Survivors"
survivorsBtn.Parent = sideSelector
survivorsBtn.Font = Enum.Font.GothamSemibold
survivorsBtn.TextSize = 14
survivorsBtn.TextColor3 = Color3.fromRGB(230,230,230)
local catScroll = Instance.new("ScrollingFrame")
catScroll.Size = UDim2.new(1,0,0.88,0)
catScroll.Position = UDim2.new(0,0,0.12,0)
catScroll.Parent = leftFrame
catScroll.CanvasSize = UDim2.new(0,0,0,0)
catScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
catScroll.ScrollBarThickness = 8
catScroll.BackgroundTransparency = 1
local catLayout = Instance.new("UIListLayout")
catLayout.Parent = catScroll
catLayout.SortOrder = Enum.SortOrder.LayoutOrder
catLayout.Padding = UDim.new(0,8)
local rightFrame = Instance.new("Frame")
rightFrame.Size = UDim2.new(0.68,0,0.75,0)
rightFrame.Position = UDim2.new(0.27,0,0.18,0)
rightFrame.Parent = mainFrame
rightFrame.BackgroundTransparency = 1
local countsLabel = Instance.new("TextLabel")
countsLabel.Size = UDim2.new(1,0,0.06,0)
countsLabel.Position = UDim2.new(0,0,0,0)
countsLabel.Parent = rightFrame
countsLabel.BackgroundTransparency = 1
countsLabel.TextXAlignment = Enum.TextXAlignment.Left
countsLabel.Font = Enum.Font.Gotham
countsLabel.TextSize = 14
countsLabel.TextColor3 = Color3.fromRGB(200,200,200)
local skinsScroll = Instance.new("ScrollingFrame")
skinsScroll.Size = UDim2.new(1,0,0.94,0)
skinsScroll.Position = UDim2.new(0,0,0.06,0)
skinsScroll.Parent = rightFrame
skinsScroll.CanvasSize = UDim2.new(0,0,0,0)
skinsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
skinsScroll.ScrollBarThickness = 10
skinsScroll.BackgroundTransparency = 1
local skinsLayout = Instance.new("UIListLayout")
skinsLayout.Parent = skinsScroll
skinsLayout.SortOrder = Enum.SortOrder.LayoutOrder
skinsLayout.Padding = UDim.new(0,8)
local selectedSide = "killers"
local selectedCategory = nil
local function makeCategoryButton(name, order)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1,0,0.06,0)
	btn.Text = name
	btn.Font = Enum.Font.Gotham
	btn.TextSize = 14
	btn.BackgroundColor3 = Color3.fromRGB(28,28,30)
	btn.TextColor3 = Color3.fromRGB(230,230,230)
	btn.Parent = catScroll
	btn.LayoutOrder = order
	local uic = Instance.new("UICorner")
	uic.CornerRadius = UDim.new(0.18,0)
	uic.Parent = btn
	btn.MouseButton1Click:Connect(function()
		selectedCategory = name
		refreshSkins()
	end)
	return btn
end
local function refreshCategories()
	for _,v in ipairs(catScroll:GetChildren()) do
		if v:IsA("TextButton") then v:Destroy() end
	end
	local root = selectedSide == "killers" and KillersRoot or SurvivorsRoot
	local cats = gatherCategories(root)
	for i,name in ipairs(cats) do
		makeCategoryButton(name, i)
	end
end
function refreshSkins()
	for _,v in ipairs(skinsScroll:GetChildren()) do
		if v:IsA("TextButton") then v:Destroy() end
	end
	if not selectedCategory then
		countsLabel.Text = "Select a category to see indexed skins"
		return
	end
	local sideKey = selectedSide
	local indexedCount = countIndexedFor(sideKey, selectedCategory)
	local maxCount = countMaxFor(sideKey, selectedCategory)
	local totalGame = countTotalSkinsInGame()
	countsLabel.Text = string.format("%s - Indexed: %d / %d    Indexed Total: %d / %d", selectedCategory, indexedCount, maxCount, meta.totalIndexed or 0, totalGame)
	local data,_ = loadCharData(sideKey, selectedCategory)
	local skinsList = {}
	if data and data.skins then
		for skinname,_ in pairs(data.skins) do table.insert(skinsList, skinname) end
	end
	table.sort(skinsList)
	for i,skinname in ipairs(skinsList) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1,0,0.07,0)
		btn.Text = skinname
		btn.Font = Enum.Font.Gotham
		btn.TextSize = 14
		btn.BackgroundColor3 = Color3.fromRGB(26,26,28)
		btn.TextColor3 = Color3.fromRGB(230,230,230)
		btn.Parent = skinsScroll
		btn.LayoutOrder = i
		local uc = Instance.new("UICorner")
		uc.CornerRadius = UDim.new(0.18,0)
		uc.Parent = btn
	end
end
local function openUI()
	mainFrame.Visible = true
end
local function closeUI()
	mainFrame.Visible = false
end
centerButton.MouseButton1Click:Connect(function()
	if mainFrame.Visible then
		closeUI()
	else
		openUI()
	end
end)
closeBtn.MouseButton1Click:Connect(function() closeUI() end)
killersBtn.MouseButton1Click:Connect(function()
	selectedSide = "killers"
	refreshCategories()
	refreshSkins()
end)
survivorsBtn.MouseButton1Click:Connect(function()
	selectedSide = "survivors"
	refreshCategories()
	refreshSkins()
end)
refreshCategories()
refreshSkins()
skinPointsLabel.Text = "Indexed Points: "..tostring(meta.skinpoints or 0)
local dragging = false
local dragStart, startPos, targetPos
mainFrame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		dragStart = input.Position
		startPos = mainFrame.Position
		targetPos = startPos
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)
mainFrame.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
		local delta = input.Position - dragStart
		local screenSize = workspace.CurrentCamera.ViewportSize
		local xScale = delta.X / screenSize.X
		local yScale = delta.Y / screenSize.Y
		targetPos = UDim2.new(startPos.X.Scale + xScale,0, startPos.Y.Scale + yScale,0)
	end
end)
RunService.RenderStepped:Connect(function(dt)
	if targetPos then
		mainFrame.Position = mainFrame.Position:Lerp(targetPos, math.clamp(12 * dt, 0, 1))
	end
end)
spawn(function()
	while true do
		local playersFolder = Workspace:FindFirstChild("Players")
		if not playersFolder then
			wait(1)
		else
			local added = indexSkins()
			if added > 0 then
				recomputeMetaTotals()
				skinPointsLabel.Text = "Indexed Points: "..tostring(meta.skinpoints or 0)
				refreshSkins()
			end
			wait(5)
		end
	end
end)
