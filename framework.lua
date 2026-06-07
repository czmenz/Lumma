local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")

local Library = { Tabs = {} }
local FRAMEWORK_VERSION = "1.0.4"
local ClientSettings = {
	ClientColor = Color3.fromRGB(0, 170, 255)
}

local player = Players.LocalPlayer
local trackedConnections = {}
local activePopup
local activePopupAnchor
local activePopupArrow
local activePopupTween
local inlinePopupClosers = {}
local externalFadeRoots = {}
local menuFadeDriver = Instance.new("NumberValue")
local menuFadeTween
local mainRef = nil
local popupLayerRef = nil
local closeKeybind = Enum.KeyCode.Insert
local toggleKeybind = closeKeybind
local closeCallback
local allowedPlaceIds = nil

local function Create(className, properties, parent)
	local obj = Instance.new(className)
	for prop, val in pairs(properties) do
		obj[prop] = val
	end
	obj.Parent = parent
	return obj
end

local function TrackConnection(conn)
	if conn then
		table.insert(trackedConnections, conn)
	end
	return conn
end

local function GetMousePosition()
	local mouse = UserInputService:GetMouseLocation()
	return Vector2.new(mouse.X, mouse.Y)
end

local function NormalizeIconPath(iconID)
	if not iconID then
		return nil
	end
	if type(iconID) == "number" then
		return "rbxassetid://" .. tostring(iconID)
	end
	if type(iconID) ~= "string" then
		return nil
	end
	local cleaned = iconID:gsub("%s+", "")
	if cleaned == "" then
		return nil
	end
	if cleaned:match("^rbxassetid://") or cleaned:match("^rbxasset://") or cleaned:match("^https?://") then
		return cleaned
	end
	if cleaned:match("^%d+$") then
		return "rbxassetid://" .. cleaned
	end
	return cleaned
end

local function IsPointInsideGui(guiObject, point)
	if not guiObject or not guiObject.Visible then return false end
	local pos = guiObject.AbsolutePosition
	local size = guiObject.AbsoluteSize
	return point.X >= pos.X and point.X <= (pos.X + size.X) and point.Y >= pos.Y and point.Y <= (pos.Y + size.Y)
end

local function AnimatePopupClose(popupFrame)
	if not popupFrame then return end
	if activePopupTween then
		activePopupTween:Cancel()
		activePopupTween = nil
	end
	local width = popupFrame.AbsoluteSize.X > 0 and popupFrame.AbsoluteSize.X or popupFrame.Size.X.Offset
	activePopupTween = TweenService:Create(popupFrame, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.new(0, width, 0, 0)
	})
	activePopupTween:Play()
	activePopupTween.Completed:Connect(function()
		activePopupTween = nil
		if popupFrame then
			popupFrame.Visible = false
		end
	end)
end

local function SetPopup(anchor, popupFrame, arrowLabel, targetHeight)
	targetHeight = targetHeight or popupFrame:GetAttribute("TargetHeight") or popupFrame.Size.Y.Offset
	if activePopup and activePopup ~= popupFrame then
		AnimatePopupClose(activePopup)
		if activePopupArrow then activePopupArrow.Text = "v" end
	end

	if activePopup == popupFrame and popupFrame.Visible then
		AnimatePopupClose(popupFrame)
		if arrowLabel then arrowLabel.Text = "v" end
		activePopup = nil
		activePopupAnchor = nil
		activePopupArrow = nil
		return
	end

	local anchorPos = anchor.AbsolutePosition
	local anchorSize = anchor.AbsoluteSize
	local anchorHeight = math.max(anchorSize.Y, 24)
	local popupGap = 48
	popupFrame.Position = UDim2.fromOffset(anchorPos.X, anchorPos.Y + anchorHeight + popupGap)
	popupFrame:SetAttribute("TargetHeight", targetHeight)
	popupFrame.ClipsDescendants = true
	popupFrame.Visible = true
	local width = popupFrame.Size.X.Offset > 0 and popupFrame.Size.X.Offset or popupFrame.AbsoluteSize.X
	popupFrame.Size = UDim2.new(0, width, 0, 0)
	if activePopupTween then
		activePopupTween:Cancel()
		activePopupTween = nil
	end
	activePopupTween = TweenService:Create(popupFrame, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, width, 0, targetHeight)
	})
	activePopupTween:Play()
	activePopup = popupFrame
	activePopupAnchor = anchor
	activePopupArrow = arrowLabel
	if arrowLabel then arrowLabel.Text = "^" end
end

local function CloseActivePopup()
	if activePopup then
		AnimatePopupClose(activePopup)
		if activePopupArrow then activePopupArrow.Text = "v" end
		activePopup = nil
		activePopupAnchor = nil
		activePopupArrow = nil
	end
end

local function CloseInlinePopups()
	for _, closer in ipairs(inlinePopupClosers) do
		pcall(closer)
	end
end

local function RegisterInlinePopupCloser(closer)
	table.insert(inlinePopupClosers, closer)
end

local function applyObjFade(obj, alpha)
	if typeof(obj) ~= "Instance" then return end
	if obj:IsA("GuiObject") then
		if obj:GetAttribute("__base_bg") == nil then
			obj:SetAttribute("__base_bg", obj.BackgroundTransparency)
		end
		local base = obj:GetAttribute("__base_bg")
		obj.BackgroundTransparency = base + ((1 - base) * alpha)
	end
	if obj:IsA("TextLabel") or obj:IsA("TextButton") then
		if obj:GetAttribute("__base_text") == nil then
			obj:SetAttribute("__base_text", obj.TextTransparency)
		end
		local base = obj:GetAttribute("__base_text")
		obj.TextTransparency = base + ((1 - base) * alpha)
	end
	if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
		if obj:GetAttribute("__base_img") == nil then
			obj:SetAttribute("__base_img", obj.ImageTransparency)
		end
		local base = obj:GetAttribute("__base_img")
		obj.ImageTransparency = base + ((1 - base) * alpha)
	end
	if obj:IsA("UIStroke") then
		if obj:GetAttribute("__base_stroke") == nil then
			obj:SetAttribute("__base_stroke", obj.Transparency)
		end
		local base = obj:GetAttribute("__base_stroke")
		obj.Transparency = base + ((1 - base) * alpha)
	end
end

local function ApplyMenuFade(alpha)
	if typeof(mainRef) ~= "Instance" then return end
	applyObjFade(mainRef, alpha)
	for _, d in ipairs(mainRef:GetDescendants()) do
		applyObjFade(d, alpha)
	end
	if typeof(popupLayerRef) == "Instance" then
		applyObjFade(popupLayerRef, alpha)
		for _, d in ipairs(popupLayerRef:GetDescendants()) do
			applyObjFade(d, alpha)
		end
	end
	for i = #externalFadeRoots, 1, -1 do
		local root = externalFadeRoots[i]
		if typeof(root) ~= "Instance" or not root.Parent then
			table.remove(externalFadeRoots, i)
		else
			applyObjFade(root, alpha)
			for _, d in ipairs(root:GetDescendants()) do
				applyObjFade(d, alpha)
			end
		end
	end
end

local function RefreshFadeBases()
	if typeof(mainRef) ~= "Instance" then return end
	local function refreshObjBase(obj)
		if typeof(obj) ~= "Instance" then return end
		if obj:IsA("GuiObject") then
			obj:SetAttribute("__base_bg", obj.BackgroundTransparency)
		end
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			obj:SetAttribute("__base_text", obj.TextTransparency)
		end
		if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
			obj:SetAttribute("__base_img", obj.ImageTransparency)
		end
		if obj:IsA("UIStroke") then
			obj:SetAttribute("__base_stroke", obj.Transparency)
		end
	end
	refreshObjBase(mainRef)
	for _, d in ipairs(mainRef:GetDescendants()) do
		refreshObjBase(d)
	end
	if typeof(popupLayerRef) == "Instance" then
		refreshObjBase(popupLayerRef)
		for _, d in ipairs(popupLayerRef:GetDescendants()) do
			refreshObjBase(d)
		end
	end
	for i = #externalFadeRoots, 1, -1 do
		local root = externalFadeRoots[i]
		if typeof(root) ~= "Instance" or not root.Parent then
			table.remove(externalFadeRoots, i)
		else
			refreshObjBase(root)
			for _, d in ipairs(root:GetDescendants()) do
				refreshObjBase(d)
			end
		end
	end
end

local function TweenMenuFade(target, duration, onDone)
	if menuFadeTween then
		menuFadeTween:Cancel()
		menuFadeTween = nil
	end
	menuFadeTween = TweenService:Create(menuFadeDriver, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Value = target})
	menuFadeTween:Play()
	if onDone then
		menuFadeTween.Completed:Connect(onDone)
	end
end

menuFadeDriver.Value = 1
menuFadeDriver:GetPropertyChangedSignal("Value"):Connect(function()
	ApplyMenuFade(menuFadeDriver.Value)
end)

local function EnforceUnlockedMouse()
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
end

Library.SetToggleKeybind = function(key)
 	if typeof(key) == "EnumItem" then
 		toggleKeybind = key
 	end
 end

Library.SetCloseCallback = function(cb)
	if type(cb) == "function" then
		closeCallback = cb
	end
end

Library.SetAllowedPlaceIds = function(ids)
	if type(ids) == "table" then
		allowedPlaceIds = ids
	end
end

function Library:Init(config)
	config = config or {}
	local scriptVersion = config.Version or FRAMEWORK_VERSION
	local menuFadeDuration = config.FadeDuration or 0.12

	if config.AllowedPlaceIds and type(config.AllowedPlaceIds) == "table" then
		allowedPlaceIds = config.AllowedPlaceIds
	end

	if allowedPlaceIds then
		local isAllowed = false
		for _, id in ipairs(allowedPlaceIds) do
			if game.PlaceId == id then
				isAllowed = true
				break
			end
		end
		if not isAllowed then
			return nil
		end
	end

	if config.CloseKey and typeof(config.CloseKey) == "EnumItem" then
		closeKeybind = config.CloseKey
		toggleKeybind = config.CloseKey
	end

	if config.ToggleKey and typeof(config.ToggleKey) == "EnumItem" then
		toggleKeybind = config.ToggleKey
	end

	local screenParent = player:WaitForChild("PlayerGui")

	if typeof(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and hui then
			screenParent = hui
		end
	end

	local screen = Create("ScreenGui", {
		Name = "LUMMA_V" .. scriptVersion:gsub("%.", "_"),
		ResetOnSpawn = false,
		DisplayOrder = 2147483647,
		Enabled = true,
		IgnoreGuiInset = true,
		OnTopOfCoreBlur = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	}, screenParent)

	local maxOrder = 2147483647
	TrackConnection(GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
		if screen and screen.Parent then
			screen.DisplayOrder = maxOrder
			maxOrder = maxOrder - 1
		end
	end))

	local main = Create("Frame", {
		Name = "Main",
		Size = UDim2.new(0, 750, 0, 500),
		Position = UDim2.new(0.5, -375, 0.5, -250),
		BackgroundColor3 = Color3.fromRGB(11, 11, 14),
		BorderSizePixel = 0,
		Active = true
	}, screen)

	Create("UICorner", {CornerRadius = UDim.new(0, 10)}, main)
	Create("UIStroke", {Color = Color3.fromRGB(40, 40, 45), Thickness = 1.5}, main)

	main.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			screen.DisplayOrder = 2147483647
		end
	end)

	local dragging, dragStart, startPos
	local dragHandle = Create("Frame", {Name = "DragHandle", Size = UDim2.new(1, -40, 0, 46), Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 1, ZIndex = 9}, main)
	dragHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
		end
	end)
	TrackConnection(UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))
	TrackConnection(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end))

	local resizeBtn = Create("TextButton", {Size = UDim2.new(0, 15, 0, 15), Position = UDim2.new(1, -18, 1, -18), BackgroundTransparency = 1, Text = "\u{25E2}", TextColor3 = Color3.fromRGB(40, 40, 45), TextSize = 12, ZIndex = 10, AutoButtonColor = false}, main)
	local resizing = false
	local rStartSize, rStartMouse
	resizeBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			resizing = true
			rStartSize = main.Size
			rStartMouse = input.Position
		end
	end)
	TrackConnection(UserInputService.InputChanged:Connect(function(input)
		if resizing and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - rStartMouse
			main.Size = UDim2.new(0, math.max(600, rStartSize.X.Offset + delta.X), 0, math.max(400, rStartSize.Y.Offset + delta.Y))
		end
	end))
	TrackConnection(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			resizing = false
		end
	end))

	local side = Create("Frame", {Size = UDim2.new(0, 180, 1, 0), BackgroundColor3 = Color3.fromRGB(14, 14, 17), BorderSizePixel = 0, ZIndex = 2}, main)
	Create("UICorner", {CornerRadius = UDim.new(0, 10)}, side)

	local tabHolder = Create("Frame", {Size = UDim2.new(1, 0, 1, -100), Position = UDim2.new(0, 0, 0, 70), BackgroundTransparency = 1, ZIndex = 3}, side)
	Create("UIListLayout", {Padding = UDim.new(0, 5), HorizontalAlignment = "Center"}, tabHolder)

	local container = Create("Frame", {Position = UDim2.new(0, 190, 0, 15), Size = UDim2.new(1, -200, 1, -30), BackgroundTransparency = 1, ZIndex = 2, ClipsDescendants = true}, main)
	local popupLayer = Create("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 200}, screen)
	mainRef = main
	popupLayerRef = popupLayer

	local subTabsCount = 0
	self.Tabs = {}
	local tabsWithSubTabs = {}

	local selectedTabBtn
	local selectedPage
	local pageTweenIn
	local pageTweenOut
	local menuVisible = false
	local unlockMouseRenderConn
	local unlockMouseHeartbeatConn
	local unlockMouseSteppedConn
	local unlockRenderStepName = "LUMMA_MouseUnlock_" .. tostring(player.UserId)
	local previousMouseBehavior
	local previousMouseIconEnabled

	local function StartMouseUnlock()
		previousMouseBehavior = UserInputService.MouseBehavior
		previousMouseIconEnabled = UserInputService.MouseIconEnabled
		UserInputService.MouseIconEnabled = true

		if not unlockMouseRenderConn then
			local ok = pcall(function()
				RunService:BindToRenderStep(unlockRenderStepName, Enum.RenderPriority.Last.Value + 10, function()
					if menuVisible then
						UserInputService.MouseIconEnabled = true
					end
				end)
			end)
			if ok then
				unlockMouseRenderConn = true
			end
		end

		if not unlockMouseHeartbeatConn then
			unlockMouseHeartbeatConn = RunService.Heartbeat:Connect(function()
				if menuVisible then
					UserInputService.MouseIconEnabled = true
				end
			end)
		end

		if not unlockMouseSteppedConn then
			unlockMouseSteppedConn = RunService.Stepped:Connect(function()
				if menuVisible then
					UserInputService.MouseIconEnabled = true
				end
			end)
		end
	end

	local function StopMouseUnlock()
		if unlockMouseRenderConn then
			pcall(function()
				RunService:UnbindFromRenderStep(unlockRenderStepName)
			end)
			unlockMouseRenderConn = nil
		end

		if unlockMouseHeartbeatConn then
			unlockMouseHeartbeatConn:Disconnect()
			unlockMouseHeartbeatConn = nil
		end

		if unlockMouseSteppedConn then
			unlockMouseSteppedConn:Disconnect()
			unlockMouseSteppedConn = nil
		end

		if previousMouseBehavior then
			UserInputService.MouseBehavior = previousMouseBehavior
		end
		if previousMouseIconEnabled ~= nil then
			UserInputService.MouseIconEnabled = previousMouseIconEnabled
		end
	end

	local function SetMenuVisible(isVisible)
		if typeof(mainRef) ~= "Instance" or typeof(popupLayerRef) ~= "Instance" then return end
		if menuVisible == isVisible then return end
		menuVisible = isVisible
		if not isVisible then
			CloseActivePopup()
			CloseInlinePopups()
		end

		if isVisible then
			mainRef.Visible = true
			popupLayerRef.Visible = true
			StartMouseUnlock()
			-- Ensure base transparencies are captured from visible state
			RefreshFadeBases()
			menuFadeDriver.Value = 1
			ApplyMenuFade(1)
			-- small yield to allow GUI to become visible before tween
			pcall(function()
				local ok, _ = pcall(function() wait(0.03) end)
			end)
			TweenMenuFade(0, menuFadeDuration, function()
				if menuVisible then
					menuFadeDriver.Value = 0
					ApplyMenuFade(0)
				end
			end)
		else
			TweenMenuFade(1, menuFadeDuration, function()
				if not menuVisible and typeof(mainRef) == "Instance" and typeof(popupLayerRef) == "Instance" then
					mainRef.Visible = false
					popupLayerRef.Visible = false
				end
			end)
			StopMouseUnlock()
		end
	end

	local function SelectTab(tabBtn, page, label, icon, fallbackLabel)
		CloseActivePopup()
		CloseInlinePopups()
		if pageTweenIn then
			pageTweenIn:Cancel()
			pageTweenIn = nil
		end
		if pageTweenOut then
			pageTweenOut:Cancel()
			pageTweenOut = nil
		end

		for _, b in pairs(tabHolder:GetChildren()) do
			if b:IsA("TextButton") and b ~= tabBtn then
				local bLabel = b:FindFirstChild("TabLabel")
				local bFallback = b:FindFirstChild("TabFallback")
				local bIcon = b:FindFirstChild("TabIcon")

				if bLabel then bLabel.TextColor3 = Color3.fromRGB(255, 255, 255) end
				if bFallback then bFallback.TextColor3 = Color3.fromRGB(255, 255, 255) end
				if bIcon then bIcon.ImageColor3 = Color3.fromRGB(255, 255, 255) end
				b.BackgroundTransparency = 1
			end
		end

		for _, v in pairs(container:GetChildren()) do
			v.Visible = false
			v.Position = UDim2.new(0, 0, 0, 0)
		end

		page.Visible = true
		page.Position = UDim2.new(0, 8, 0, 0)
		pageTweenIn = TweenService:Create(page, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, 0, 0, 0)
		})
		pageTweenIn:Play()
		label.TextColor3 = ClientSettings.ClientColor
		icon.ImageColor3 = ClientSettings.ClientColor
		fallbackLabel.TextColor3 = ClientSettings.ClientColor
		tabBtn.BackgroundTransparency = 0.95
		selectedTabBtn = tabBtn
		selectedPage = page
		screen.DisplayOrder = 2147483647
	end

	local closeBtn = Create("TextButton", {
		Name = "CloseButton",
		Size = UDim2.new(0, 22, 0, 22),
		Position = UDim2.new(1, -30, 0, 8),
		BackgroundTransparency = 1,
		Text = "X",
		Font = "GothamBold",
		TextSize = 18,
		TextColor3 = Color3.fromRGB(220, 220, 220),
		ZIndex = 30,
		AutoButtonColor = false
	}, main)
	closeBtn.MouseEnter:Connect(function()
		closeBtn.TextColor3 = Color3.fromRGB(255, 60, 60)
	end)
	closeBtn.MouseLeave:Connect(function()
		closeBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
	end)
	closeBtn.MouseButton1Click:Connect(function()
		if closeCallback then
			closeCallback()
		else
			self:Unload()
		end
	end)

	local titleWrap = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
		ZIndex = 3
	}, side)
	Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.new(0, 0, 0, 6),
		Text = "LUMMA",
		Font = "GothamBold",
		TextSize = 22,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3
	}, titleWrap)
	Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 0, 36),
		Text = "v" .. scriptVersion,
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		TextColor3 = Color3.fromRGB(150, 150, 160),
		BackgroundTransparency = 1,
		ZIndex = 3
	}, titleWrap)

	local userSeparator = Create("Frame", {
		Size = UDim2.new(1, -20, 0, 1),
		Position = UDim2.new(0, 10, 1, -71),
		BackgroundColor3 = Color3.fromRGB(35, 35, 40),
		BorderSizePixel = 0,
		ZIndex = 3
	}, side)

	local user = Create("Frame", {Size = UDim2.new(1, 0, 0, 60), Position = UDim2.new(0, 0, 1, -70), BackgroundTransparency = 1, ZIndex = 3}, side)
	local avatar = Create("ImageLabel", {Size = UDim2.new(0, 38, 0, 38), Position = UDim2.new(0, 15, 0.5, -19), Image = Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48), ZIndex = 4}, user)
	Create("UICorner", {CornerRadius = UDim.new(1, 0)}, avatar)
	Create("TextLabel", {Size = UDim2.new(1, -65, 1, 0), Position = UDim2.new(0, 65, 0, 0), Text = player.DisplayName, Font = "GothamMedium", TextSize = 13, TextColor3 = Color3.fromRGB(180, 180, 180), TextXAlignment = "Left", BackgroundTransparency = 1, ZIndex = 4}, user)

	self.Screen = screen
	self.Main = main

	self.RefreshBindButtonText = nil
	self.RefreshAimKeyBindText = nil
	self.RefreshTriggerKeyBindText = nil
	self.MenuFadeDriver = menuFadeDriver

	self.RegisterFadeRoot = function(root)
		if typeof(root) ~= "Instance" then
			return
		end
		for _, existing in ipairs(externalFadeRoots) do
			if existing == root then
				return
			end
		end
		table.insert(externalFadeRoots, root)
		RefreshFadeBases()
		ApplyMenuFade(menuFadeDriver.Value)
	end

	self.Unload = function()
		StopMouseUnlock()
		if unlockMouseRenderConn then
			unlockMouseRenderConn = nil
		end
		if screen and screen.Parent then
			pcall(function()
				screen:Destroy()
			end)
		end
		screen = nil
	end

	function Library:NewTab(name, iconID)
		local tabBtn = Create("TextButton", {Size = UDim2.new(0.9, 0, 0, 38), Text = "", BackgroundTransparency = 1, ZIndex = 4}, tabHolder)
		Create("UICorner", {CornerRadius = UDim.new(0, 6)}, tabBtn)

		local iconPath = NormalizeIconPath(iconID)
		local icon = Create("ImageLabel", {
			Name = "TabIcon",
			Size = UDim2.new(0, 20, 0, 20),
			Position = UDim2.new(0, 10, 0.5, -10),
			Image = iconPath or "",
			ImageColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			ZIndex = 5
		}, tabBtn)

		local fallbackLabel = Create("TextLabel", {
			Name = "TabFallback",
			Size = UDim2.new(0, 20, 0, 20),
			Position = UDim2.new(0, 10, 0.5, -10),
			Text = "\u{25C6}",
			Font = "GothamBold",
			TextSize = 12,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			ZIndex = 5,
			Visible = false
		}, tabBtn)

		local label = Create("TextLabel", {Name = "TabLabel", Size = UDim2.new(1, -40, 1, 0), Position = UDim2.new(0, 40, 0, 0), Text = name, Font = "GothamMedium", TextSize = 14, TextColor3 = Color3.fromRGB(255, 255, 255), TextXAlignment = "Left", BackgroundTransparency = 1, ZIndex = 5}, tabBtn)
		local page = Create("ScrollingFrame", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false, ScrollBarThickness = 0, CanvasSize = UDim2.new(0, 0, 0, 0)}, container)

		local pageLayout = Create("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = "LayoutOrder"}, page)
		pageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			page.CanvasSize = UDim2.new(0, 0, 0, pageLayout.AbsoluteContentSize.Y + 10)
		end)

local pageHeaderSpacer = Create("Frame", {Name = "PageHeaderSpacer", Size = UDim2.new(1, -10, 0, 42), BackgroundTransparency = 1, LayoutOrder = 0}, page)
		if tabsWithSubTabs[page] then
			pageHeaderSpacer.Visible = false
		end
		table.insert(self.Tabs, {Button = tabBtn, Page = page})

		tabBtn.MouseButton1Click:Connect(function()
			SelectTab(tabBtn, page, label, icon, fallbackLabel)
		end)

		if not selectedTabBtn then
			SelectTab(tabBtn, page, label, icon, fallbackLabel)
		end

		return page
	end

	function Library:CreateSubTabs(page)
		subTabsCount = subTabsCount + 1
		local subPages = {}
		local subTabButtons = {}
		local selectedSubTab
		local selectedSubPage
		local subPageTweenIn
		local subPageTweenOut

		local tabsBar = Create("Frame", {
			Size = UDim2.new(1, -10, 0, 30),
			BackgroundTransparency = 1,
			LayoutOrder = 0
		}, page)
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Left
		}, tabsBar)
		Create("UIPadding", {
			PaddingRight = UDim.new(0, 6)
		}, tabsBar)

		local tabsContent = Create("Frame", {
			Size = UDim2.new(1, -10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 1
		}, page)

		local function updateLayoutForSubTabs()
			if subTabsCount == 1 then
				tabHolder.Position = UDim2.new(0, 0, 0, 48)
				tabHolder.Size = UDim2.new(1, 0, 1, -40)
				container.Position = UDim2.new(0, 190, 0, 48)
			end
		end

		page:SetAttribute("HasSubTabs", true)
		tabsWithSubTabs[page] = true
		local pageHeaderSpacer = page:FindFirstChild("PageHeaderSpacer")
		if pageHeaderSpacer then
			pageHeaderSpacer:Destroy()
		end
		subTabsCount = subTabsCount + 1
		updateLayoutForSubTabs()

		local function SelectSubTab(name)
			if selectedSubTab == name then return end
			if subPageTweenIn then
				subPageTweenIn:Cancel()
				subPageTweenIn = nil
			end
			if subPageTweenOut then
				subPageTweenOut:Cancel()
				subPageTweenOut = nil
			end
			selectedSubTab = name
			for tabName, btn in pairs(subTabButtons) do
				local active = tabName == name
				btn.BackgroundColor3 = active and ClientSettings.ClientColor or Color3.fromRGB(26, 26, 31)
				local lbl = btn:FindFirstChild("TabText")
				local ic = btn:FindFirstChild("TabIcon")
				if lbl then
					lbl.TextColor3 = active and Color3.fromRGB(15, 15, 18) or Color3.fromRGB(220, 220, 220)
				end
				if ic and ic:IsA("ImageLabel") then
					ic.ImageColor3 = active and Color3.fromRGB(15, 15, 18) or Color3.fromRGB(220, 220, 220)
				end
			end
			for _, pg in pairs(subPages) do
				pg.Visible = false
				pg.Position = UDim2.new(0, 0, 0, 0)
			end
			local newPage = subPages[name]
			if newPage then
				newPage.Visible = true
				newPage.Position = UDim2.new(0, 8, 0, 0)
				subPageTweenIn = TweenService:Create(newPage, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					Position = UDim2.new(0, 0, 0, 0)
				})
				subPageTweenIn:Play()
				selectedSubPage = newPage
			end
		end

		local mgr = {}
		mgr.bar = tabsBar
		mgr.container = tabsContent

		function mgr:AddTab(name, iconID)
			local pg = Create("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Visible = false
			}, tabsContent)
			Create("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, pg)
			subPages[name] = pg

			local btn = Create("TextButton", {
				Size = UDim2.new(0, 96, 1, 0),
				BackgroundColor3 = Color3.fromRGB(26, 26, 31),
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = false
			}, tabsBar)
			Create("UICorner", {CornerRadius = UDim.new(0, 5)}, btn)
			Create("ImageLabel", {
				Name = "TabIcon",
				Size = UDim2.new(0, 14, 0, 14),
				Position = UDim2.new(0, 8, 0.5, -7),
				BackgroundTransparency = 1,
				Image = NormalizeIconPath(iconID) or "",
				ImageColor3 = Color3.fromRGB(220, 220, 220),
				ZIndex = 3
			}, btn)
			Create("TextLabel", {
				Name = "TabText",
				Size = UDim2.new(1, -28, 1, 0),
				Position = UDim2.new(0, 24, 0, 0),
				BackgroundTransparency = 1,
				Text = name,
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				TextColor3 = Color3.fromRGB(220, 220, 220),
				ZIndex = 2
			}, btn)
			btn.MouseButton1Click:Connect(function()
				SelectSubTab(name)
			end)
			subTabButtons[name] = btn

			if not selectedSubTab then
				SelectSubTab(name)
			end

			return pg
		end

		function mgr:Select(name)
			SelectSubTab(name)
		end

		return mgr
	end

	function Library:AddToggle(parent, text, callback)
		local toggleFrame = Create("Frame", {Size = UDim2.new(1, -10, 0, 35), BackgroundColor3 = Color3.fromRGB(20, 20, 25), BackgroundTransparency = 0, ZIndex = 5}, parent)
		Create("UICorner", {CornerRadius = UDim.new(0, 6)}, toggleFrame)
		Create("UIStroke", {Color = Color3.fromRGB(45, 45, 50), Thickness = 1}, toggleFrame)

		local label = Create("TextLabel", {Size = UDim2.new(1, -50, 1, 0), Position = UDim2.new(0, 12, 0, 0), Text = text, Font = "GothamMedium", TextSize = 13, TextColor3 = Color3.fromRGB(200, 200, 200), TextXAlignment = "Left", BackgroundTransparency = 1, ZIndex = 6}, toggleFrame)

		local box = Create("Frame", {Size = UDim2.new(0, 35, 0, 18), Position = UDim2.new(1, -45, 0.5, -9), BackgroundColor3 = Color3.fromRGB(40, 40, 45), ZIndex = 6}, toggleFrame)
		Create("UICorner", {CornerRadius = UDim.new(1, 0)}, box)

		local indicator = Create("Frame", {Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 2, 0.5, -7), BackgroundColor3 = Color3.fromRGB(100, 100, 105), ZIndex = 7}, box)
		Create("UICorner", {CornerRadius = UDim.new(1, 0)}, indicator)

		local enabled = false
		local function update()
			local targetPos = enabled and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
			local targetColor = enabled and ClientSettings.ClientColor or Color3.fromRGB(100, 100, 105)
			local boxColor = enabled and Color3.fromRGB(30, 60, 80) or Color3.fromRGB(40, 40, 45)

			TweenService:Create(indicator, TweenInfo.new(0.2), {Position = targetPos, BackgroundColor3 = targetColor}):Play()
			TweenService:Create(box, TweenInfo.new(0.2), {BackgroundColor3 = boxColor}):Play()
			callback(enabled)
		end

		toggleFrame.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				enabled = not enabled
				update()
			end
		end)
	end

	function Library:AddSlider(parent, text, minValue, maxValue, defaultValue, callback)
		local holder = Create("Frame", {Size = UDim2.new(1, -10, 0, 52), BackgroundColor3 = Color3.fromRGB(20, 20, 25), BorderSizePixel = 0, ZIndex = 5}, parent)
		Create("UICorner", {CornerRadius = UDim.new(0, 6)}, holder)
		Create("UIStroke", {Color = Color3.fromRGB(45, 45, 50), Thickness = 1}, holder)

		Create("TextLabel", {Size = UDim2.new(0.6, 0, 0, 22), Position = UDim2.new(0, 12, 0, 6), Text = text, Font = "GothamMedium", TextSize = 13, TextColor3 = Color3.fromRGB(200, 200, 200), TextXAlignment = "Left", BackgroundTransparency = 1, ZIndex = 6}, holder)
		local valueLabel = Create("TextLabel", {Size = UDim2.new(0.35, -8, 0, 22), Position = UDim2.new(0.65, 0, 0, 6), Text = tostring(defaultValue), Font = "GothamMedium", TextSize = 13, TextColor3 = Color3.fromRGB(230, 230, 230), TextXAlignment = "Right", BackgroundTransparency = 1, ZIndex = 6}, holder)

		local bar = Create("Frame", {Size = UDim2.new(1, -24, 0, 8), Position = UDim2.new(0, 12, 0, 34), BackgroundColor3 = Color3.fromRGB(35, 35, 41), BorderSizePixel = 0, ZIndex = 6}, holder)
		Create("UICorner", {CornerRadius = UDim.new(1, 0)}, bar)
		local fill = Create("Frame", {Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = ClientSettings.ClientColor, BorderSizePixel = 0, ZIndex = 7}, bar)
		Create("UICorner", {CornerRadius = UDim.new(1, 0)}, fill)

		local dragging = false
		local currentValue = defaultValue
		local range = math.max(1, maxValue - minValue)

		local function setValue(v)
			local clamped = math.clamp(v, minValue, maxValue)
			currentValue = math.floor(clamped + 0.5)
			local alpha = (currentValue - minValue) / range
			fill.Size = UDim2.new(alpha, 0, 1, 0)
			valueLabel.Text = tostring(currentValue)
			if callback then callback(currentValue) end
		end

		local function updateFromMouse()
			local mouseX = GetMousePosition().X
			local rel = (mouseX - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X)
			setValue(minValue + (math.clamp(rel, 0, 1) * range))
		end

		bar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true
				updateFromMouse()
			end
		end)
		TrackConnection(UserInputService.InputChanged:Connect(function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				updateFromMouse()
			end
		end))
		TrackConnection(UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = false
			end
		end))

		setValue(defaultValue)
		return holder
	end

	function Library:AddKeybind(parent, text, defaultBind, callback)
		local button = Create("TextButton", {
			Size = UDim2.new(1, -10, 0, 35),
			BackgroundColor3 = Color3.fromRGB(20, 20, 25),
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 5
		}, parent)
		Create("UICorner", {CornerRadius = UDim.new(0, 6)}, button)
		Create("UIStroke", {Color = Color3.fromRGB(45, 45, 50), Thickness = 1}, button)

		local label = Create("TextLabel", {
			Size = UDim2.new(1, -24, 1, 0),
			Position = UDim2.new(0, 12, 0, 0),
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(230, 230, 230),
			ZIndex = 6
		}, button)

		local function GetBindText(bind)
			if not bind then return "None" end
			if bind.InputType == Enum.UserInputType.MouseButton2 then return "Right Click" end
			if bind.InputType == Enum.UserInputType.MouseButton1 then return "Left Click" end
			if bind.KeyCode then return bind.KeyCode.Name end
			return "Unknown"
		end

		local waiting = false
		local currentBind = defaultBind

		local function RefreshText()
			if waiting then
				label.Text = "Press key/mouse..."
			else
				label.Text = GetBindText(currentBind)
			end
		end

		RefreshText()

		button.MouseButton1Click:Connect(function()
			waiting = true
			RefreshText()
		end)

		TrackConnection(UserInputService.InputBegan:Connect(function(input)
			if not waiting then return end
			if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Escape then
				waiting = false
				RefreshText()
				return
			end
			if input.UserInputType == Enum.UserInputType.Keyboard then
				currentBind = {KeyCode = input.KeyCode}
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
				currentBind = {InputType = input.UserInputType}
			else
				return
			end
			waiting = false
			RefreshText()
			if callback then callback(currentBind) end
		end))

		if callback then callback(currentBind) end
		return button
	end

	function Library:AddDropdown(parent, text, options, defaultOption, callback)
		local holder = Create("TextButton", {Size = UDim2.new(1, -10, 0, 35), BackgroundColor3 = Color3.fromRGB(20, 20, 25), BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 5}, parent)
		Create("UICorner", {CornerRadius = UDim.new(0, 6)}, holder)
		Create("UIStroke", {Color = Color3.fromRGB(45, 45, 50), Thickness = 1}, holder)
		Create("TextLabel", {Size = UDim2.new(0.55, 0, 1, 0), Position = UDim2.new(0, 12, 0, 0), Text = text, Font = "GothamMedium", TextSize = 13, TextColor3 = Color3.fromRGB(200, 200, 200), TextXAlignment = "Left", BackgroundTransparency = 1, ZIndex = 6}, holder)
		local valueLabel = Create("TextLabel", {Size = UDim2.new(0.36, -10, 1, 0), Position = UDim2.new(0.6, 0, 0, 0), Text = tostring(defaultOption), Font = "GothamMedium", TextSize = 13, TextColor3 = Color3.fromRGB(230, 230, 230), TextXAlignment = "Right", BackgroundTransparency = 1, ZIndex = 6}, holder)
		local arrowLabel = Create("TextLabel", {Size = UDim2.new(0, 14, 1, 0), Position = UDim2.new(1, -18, 0, 0), Text = "v", Font = "GothamBold", TextSize = 12, TextColor3 = Color3.fromRGB(185, 185, 185), TextXAlignment = "Center", BackgroundTransparency = 1, ZIndex = 6}, holder)

		local popup = Create("Frame", {Size = UDim2.new(0, holder.AbsoluteSize.X, 0, (#options * 28) + 10), BackgroundColor3 = Color3.fromRGB(18, 18, 23), BorderSizePixel = 0, Visible = false, ZIndex = 210}, popupLayer)
		Create("UICorner", {CornerRadius = UDim.new(0, 6)}, popup)
		Create("UIStroke", {Color = Color3.fromRGB(45, 45, 50), Thickness = 1}, popup)
		local optionsContainer = Create("Frame", {Size = UDim2.new(1, -10, 1, -10), Position = UDim2.new(0, 5, 0, 5), BackgroundTransparency = 1, ZIndex = 211}, popup)
		Create("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = "LayoutOrder"}, optionsContainer)

		local selected = defaultOption
		for _, option in ipairs(options) do
			local optionBtn = Create("TextButton", {
				Size = UDim2.new(1, 0, 0, 24),
				BackgroundColor3 = Color3.fromRGB(26, 26, 31),
				Text = tostring(option),
				Font = "GothamMedium",
				TextSize = 13,
				TextColor3 = Color3.fromRGB(225, 225, 225),
				AutoButtonColor = false,
				ZIndex = 212
			}, optionsContainer)
			Create("UICorner", {CornerRadius = UDim.new(0, 4)}, optionBtn)
			optionBtn.MouseButton1Click:Connect(function()
				selected = option
				valueLabel.Text = tostring(option)
				CloseActivePopup()
				if callback then callback(selected) end
			end)
		end

		holder.MouseButton1Click:Connect(function()
			popup.Size = UDim2.new(0, holder.AbsoluteSize.X, 0, (#options * 28) + 10)
			SetPopup(holder, popup, arrowLabel)
		end)

		valueLabel.Text = tostring(defaultOption)
		if callback then callback(selected) end
		return holder
	end

	function Library:AddColorPicker(parent, text, defaultColor, callback)
		local holder = Create("TextButton", {Size = UDim2.new(1, -10, 0, 35), BackgroundColor3 = Color3.fromRGB(20, 20, 25), BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 5}, parent)
		Create("UICorner", {CornerRadius = UDim.new(0, 6)}, holder)
		Create("UIStroke", {Color = Color3.fromRGB(45, 45, 50), Thickness = 1}, holder)
		Create("TextLabel", {Size = UDim2.new(0.7, 0, 1, 0), Position = UDim2.new(0, 12, 0, 0), Text = text, Font = "GothamMedium", TextSize = 13, TextColor3 = Color3.fromRGB(200, 200, 200), TextXAlignment = "Left", BackgroundTransparency = 1, ZIndex = 6}, holder)
		local preview = Create("Frame", {Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(1, -30, 0.5, -11), BackgroundColor3 = defaultColor, BorderSizePixel = 0, ZIndex = 6}, holder)
		Create("UICorner", {CornerRadius = UDim.new(0, 4)}, preview)

		local popup = Create("Frame", {Size = UDim2.new(0, 220, 0, 132), BackgroundColor3 = Color3.fromRGB(18, 18, 23), BorderSizePixel = 0, Visible = false, ZIndex = 210}, popupLayer)
		Create("UICorner", {CornerRadius = UDim.new(0, 6)}, popup)
		Create("UIStroke", {Color = Color3.fromRGB(45, 45, 50), Thickness = 1}, popup)

		local current = defaultColor
		local channels = {
			{key = "R", value = math.floor(defaultColor.R * 255)},
			{key = "G", value = math.floor(defaultColor.G * 255)},
			{key = "B", value = math.floor(defaultColor.B * 255)}
		}

		local function applyColor()
			current = Color3.fromRGB(channels[1].value, channels[2].value, channels[3].value)
			preview.BackgroundColor3 = current
			if callback then callback(current) end
		end

		for i, channel in ipairs(channels) do
			local y = 8 + ((i - 1) * 40)
			Create("TextLabel", {Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 8, 0, y), Text = channel.key, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.fromRGB(220, 220, 220), BackgroundTransparency = 1, ZIndex = 211}, popup)
			local bar = Create("Frame", {Size = UDim2.new(0, 160, 0, 8), Position = UDim2.new(0, 26, 0, y + 3), BackgroundColor3 = Color3.fromRGB(35, 35, 41), BorderSizePixel = 0, ZIndex = 211}, popup)
			Create("UICorner", {CornerRadius = UDim.new(1, 0)}, bar)
			local fill = Create("Frame", {Size = UDim2.new(channel.value / 255, 0, 1, 0), BackgroundColor3 = ClientSettings.ClientColor, BorderSizePixel = 0, ZIndex = 212}, bar)
			Create("UICorner", {CornerRadius = UDim.new(1, 0)}, fill)
			local valueLabel = Create("TextLabel", {Size = UDim2.new(0, 26, 0, 14), Position = UDim2.new(0, 190, 0, y), Text = tostring(channel.value), Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Color3.fromRGB(220, 220, 220), BackgroundTransparency = 1, ZIndex = 211}, popup)

			local dragging = false
			local function updateChannel()
				local mouseX = GetMousePosition().X
				local alpha = math.clamp((mouseX - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
				channel.value = math.floor(alpha * 255 + 0.5)
				fill.Size = UDim2.new(channel.value / 255, 0, 1, 0)
				valueLabel.Text = tostring(channel.value)
				applyColor()
			end

			bar.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					dragging = true
					updateChannel()
				end
			end)
			TrackConnection(UserInputService.InputChanged:Connect(function(input)
				if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
					updateChannel()
				end
			end))
			TrackConnection(UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					dragging = false
				end
			end))
		end

		holder.MouseButton1Click:Connect(function()
			SetPopup(holder, popup)
		end)

		applyColor()
		return holder
	end

	function Library:AddCategory(parent, title)
		local section = Create("Frame", {
			Size = UDim2.new(1, -10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(18, 18, 23),
			BorderSizePixel = 0,
			ZIndex = 5
		}, parent)
		Create("UICorner", {CornerRadius = UDim.new(0, 7)}, section)
		Create("UIStroke", {Color = Color3.fromRGB(44, 44, 50), Thickness = 1}, section)
		Create("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8)
		}, section)

		Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Text = title,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(235, 235, 235),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
			LayoutOrder = 1
		}, section)

		local rows = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			ZIndex = 6
		}, section)
		Create("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, section)
		Create("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, rows)
		return rows
	end

	function Library:CreateCategoryCard(parent, title, position, size)
		local card = Create("Frame", {
			Size = UDim2.new(size.X.Scale, size.X.Offset, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = position,
			BackgroundColor3 = Color3.fromRGB(18, 18, 23),
			BorderSizePixel = 0,
			ZIndex = 5
		}, parent)
		Create("UICorner", {CornerRadius = UDim.new(0, 7)}, card)
		Create("UIStroke", {Color = Color3.fromRGB(44, 44, 50), Thickness = 1}, card)
		Create("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8)
		}, card)
		Create("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder
		}, card)

		Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Text = title,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(235, 235, 235),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
			LayoutOrder = 1
		}, card)

		local rows = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 6,
			LayoutOrder = 2
		}, card)
		Create("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, rows)
		return card, rows
	end

	function Library:AddCategoryRow(sectionRows, name)
		local row = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1
		}, sectionRows)
		Create("TextLabel", {
			Size = UDim2.new(0.55, 0, 0, 28),
			Position = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1,
			Text = name,
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(210, 210, 210),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 7
		}, row)
		local valueHolder = Create("Frame", {
			Size = UDim2.new(0.45, 0, 1, 0),
			Position = UDim2.new(0.55, 0, 0, 0),
			BackgroundTransparency = 1,
			ZIndex = 7
		}, row)
		return row, valueHolder
	end

	function Library:AddCategoryInfo(sectionRows, text)
		local row = Create("Frame", {Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1}, sectionRows)
		Create("TextLabel", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = text, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Color3.fromRGB(160, 160, 170), TextXAlignment = Enum.TextXAlignment.Left}, row)
	end

	function Library:AddCategoryToggle(sectionRows, name, defaultState, callback)
		local row, valueHolder = self:AddCategoryRow(sectionRows, name)
		local rowClick = Create("TextButton", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 6
		}, row)
		local button = Create("TextButton", {Size = UDim2.new(0, 16, 0, 16), Position = UDim2.new(1, -16, 0.5, -8), Text = "", BackgroundColor3 = Color3.fromRGB(31, 31, 37), BorderSizePixel = 0, AutoButtonColor = false}, valueHolder)
		button.ZIndex = 8
		Create("UICorner", {CornerRadius = UDim.new(0, 3)}, button)
		local stroke = Create("UIStroke", {Color = Color3.fromRGB(120, 120, 130), Thickness = 1}, button)
		local fill = Create("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = ClientSettings.ClientColor, BackgroundTransparency = 1, BorderSizePixel = 0}, button)
		fill.ZIndex = 9
		Create("UICorner", {CornerRadius = UDim.new(0, 3)}, fill)

		local enabled = defaultState and true or false
		local function refresh()
			local targetBg = enabled and Color3.fromRGB(24, 36, 48) or Color3.fromRGB(31, 31, 37)
			local targetStroke = enabled and ClientSettings.ClientColor or Color3.fromRGB(125, 125, 135)
			local targetFillTransparency = enabled and 0 or 1
			TweenService:Create(button, TweenInfo.new(0.15), {BackgroundColor3 = targetBg}):Play()
			TweenService:Create(stroke, TweenInfo.new(0.15), {Color = targetStroke}):Play()
			TweenService:Create(fill, TweenInfo.new(0.15), {BackgroundTransparency = targetFillTransparency}):Play()
			if callback then callback(enabled) end
		end

		local function toggle()
			enabled = not enabled
			refresh()
		end
		rowClick.MouseButton1Click:Connect(toggle)
		button.MouseButton1Click:Connect(toggle)
		refresh()
		return {
			Button = button,
			Get = function() return enabled end,
			Set = function(v)
				enabled = v and true or false
				refresh()
			end
		}
	end

	function Library:AddCategorySlider(sectionRows, name, minValue, maxValue, defaultValue, callback)
		local row, valueHolder = self:AddCategoryRow(sectionRows, name)
		row.Size = UDim2.new(1, 0, 0, 26)
		valueHolder.Size = UDim2.new(0.45, 0, 1, 0)
		local valueLabel = Create("TextLabel", {Size = UDim2.new(0, 34, 1, 0), Position = UDim2.new(1, -34, 0, 0), BackgroundTransparency = 1, Text = tostring(defaultValue), Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Color3.fromRGB(220, 220, 220), TextXAlignment = Enum.TextXAlignment.Right}, valueHolder)
		local bar = Create("Frame", {Size = UDim2.new(1, -40, 0, 6), Position = UDim2.new(0, 0, 0.5, -3), BackgroundColor3 = Color3.fromRGB(36, 36, 42), BorderSizePixel = 0}, valueHolder)
		Create("UICorner", {CornerRadius = UDim.new(1, 0)}, bar)
		local fill = Create("Frame", {Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = ClientSettings.ClientColor, BorderSizePixel = 0}, bar)
		Create("UICorner", {CornerRadius = UDim.new(1, 0)}, fill)

		local dragging = false
		local range = math.max(1, maxValue - minValue)
		local function setValue(v)
			local current = math.floor(math.clamp(v, minValue, maxValue) + 0.5)
			valueLabel.Text = tostring(current)
			fill.Size = UDim2.new((current - minValue) / range, 0, 1, 0)
			if callback then callback(current) end
		end
		local function fromMouse()
			local alpha = math.clamp((GetMousePosition().X - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
			setValue(minValue + (alpha * range))
		end

		bar.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; fromMouse() end end)
		TrackConnection(UserInputService.InputChanged:Connect(function(input) if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then fromMouse() end end))
		TrackConnection(UserInputService.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end))
		setValue(defaultValue)
		return row
	end

	function Library:AddCategoryKeybind(sectionRows, name, defaultBind, callback)
		local _, valueHolder = self:AddCategoryRow(sectionRows, name)
		local btn = Create("TextButton", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(26, 26, 31), BorderSizePixel = 0, Text = "", AutoButtonColor = false}, valueHolder)
		Create("UICorner", {CornerRadius = UDim.new(0, 4)}, btn)
		local label = Create("TextLabel", {Size = UDim2.new(1, -8, 1, 0), Position = UDim2.new(0, 4, 0, 0), BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Color3.fromRGB(220, 220, 220)}, btn)

		local function GetBindText(bind)
			if not bind then return "None" end
			if bind.InputType == Enum.UserInputType.MouseButton2 then return "Right Click" end
			if bind.InputType == Enum.UserInputType.MouseButton1 then return "Left Click" end
			if bind.KeyCode then return bind.KeyCode.Name end
			return "Unknown"
		end

		local waiting = false
		local currentBind = defaultBind

		local function RefreshText()
			if waiting then
				label.Text = "Press key..."
			else
				label.Text = GetBindText(currentBind)
			end
		end

		RefreshText()

		btn.MouseButton1Click:Connect(function()
			waiting = true
			RefreshText()
		end)

		TrackConnection(UserInputService.InputBegan:Connect(function(input)
			if not waiting then return end
			if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Escape then
				waiting = false
				RefreshText()
				return
			end
			if input.UserInputType == Enum.UserInputType.Keyboard then
				currentBind = {KeyCode = input.KeyCode}
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
				currentBind = {InputType = input.UserInputType}
			else
				return
			end
			waiting = false
			RefreshText()
			if callback then callback(currentBind) end
		end))

		if callback then callback(currentBind) end
		return btn
	end

	function Library:AddCategoryDropdown(sectionRows, name, options, defaultOption, callback)
		local row, valueHolder = self:AddCategoryRow(sectionRows, name)
		row.Size = UDim2.new(1, 0, 0, 28)
		local holder = Create("TextButton", {Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0, 0), BackgroundColor3 = Color3.fromRGB(26, 26, 31), BorderSizePixel = 0, Text = "", AutoButtonColor = false}, valueHolder)
		Create("UICorner", {CornerRadius = UDim.new(0, 4)}, holder)
		local valueLabel = Create("TextLabel", {Size = UDim2.new(1, -22, 1, 0), Position = UDim2.new(0, 6, 0, 0), BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Color3.fromRGB(220, 220, 220), Text = tostring(defaultOption)}, holder)
		local arrow = Create("TextLabel", {Size = UDim2.new(0, 14, 1, 0), Position = UDim2.new(1, -16, 0, -1), BackgroundTransparency = 1, Text = "v", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.fromRGB(185, 185, 185), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center}, holder)

		local popup = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			Position = UDim2.new(0, 0, 0, 32),
			BackgroundColor3 = Color3.fromRGB(26, 26, 31),
			BorderSizePixel = 0,
			Visible = false,
			ClipsDescendants = true
		}, valueHolder)
		Create("UICorner", {CornerRadius = UDim.new(0, 4)}, popup)
		local list = Create("Frame", {Size = UDim2.new(1, -10, 1, -10), Position = UDim2.new(0, 5, 0, 5), BackgroundTransparency = 1}, popup)
		Create("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, list)

		local selected = defaultOption
		local isOpen = false
		local optionHeight = 24
		local optionPad = 4
		local popupPadding = 10
		local popupHeight = (#options * optionHeight) + (math.max(0, #options - 1) * optionPad) + popupPadding
		local closedRowHeight = 28
		local openRowHeight = closedRowHeight + 4 + popupHeight

		for _, option in ipairs(options) do
			local opt = Create("TextButton", {Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = Color3.fromRGB(26, 26, 31), BorderSizePixel = 0, Text = tostring(option), Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Color3.fromRGB(225, 225, 225), AutoButtonColor = false}, list)
			Create("UICorner", {CornerRadius = UDim.new(0, 4)}, opt)
			opt.MouseButton1Click:Connect(function()
				selected = option
				valueLabel.Text = tostring(option)
				if isOpen then
					isOpen = false
					arrow.Text = "v"
					local closeTween = TweenService:Create(popup, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, 0)})
					closeTween:Play()
					closeTween.Completed:Connect(function()
						if not isOpen then
							popup.Visible = false
						end
					end)
					TweenService:Create(row, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, closedRowHeight)}):Play()
				end
				if callback then callback(selected) end
			end)
		end

		local function setOpen(state, instant)
			isOpen = state and true or false
			arrow.Text = isOpen and "^" or "v"
			local targetPopupHeight = isOpen and popupHeight or 0
			local targetRowHeight = isOpen and openRowHeight or closedRowHeight
			if isOpen then
				popup.Visible = true
			end
			if instant then
				popup.Size = UDim2.new(1, 0, 0, targetPopupHeight)
				row.Size = UDim2.new(1, 0, 0, targetRowHeight)
				if not isOpen then
					popup.Visible = false
				end
				return
			end
			local tween = TweenService:Create(popup, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, targetPopupHeight)})
			tween:Play()
			if not isOpen then
				tween.Completed:Connect(function()
					if not isOpen then
						popup.Visible = false
					end
				end)
			end
			TweenService:Create(row, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, targetRowHeight)}):Play()
		end

		holder.MouseButton1Click:Connect(function()
			setOpen(not isOpen, false)
		end)
		RegisterInlinePopupCloser(function()
			if isOpen then
				setOpen(false, true)
			end
		end)

		if callback then callback(selected) end
		return holder
	end

	function Library:AddCategoryMultiDropdown(sectionRows, name, options, defaultSelectedMap, callback)
		local row, valueHolder = self:AddCategoryRow(sectionRows, name)
		row.Size = UDim2.new(1, 0, 0, 28)
		local holder = Create("TextButton", {Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0, 0), BackgroundColor3 = Color3.fromRGB(26, 26, 31), BorderSizePixel = 0, Text = "", AutoButtonColor = false}, valueHolder)
		Create("UICorner", {CornerRadius = UDim.new(0, 4)}, holder)
		local valueLabel = Create("TextLabel", {Size = UDim2.new(1, -22, 1, 0), Position = UDim2.new(0, 6, 0, 0), BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Color3.fromRGB(220, 220, 220)}, holder)
		local arrow = Create("TextLabel", {Size = UDim2.new(0, 14, 1, 0), Position = UDim2.new(1, -16, 0, -1), BackgroundTransparency = 1, Text = "v", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.fromRGB(185, 185, 185), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center}, holder)

		local selected = {}
		for _, option in ipairs(options) do
			selected[option] = defaultSelectedMap and defaultSelectedMap[option] == true or false
		end

		local popup = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			Position = UDim2.new(0, 0, 0, 32),
			BackgroundColor3 = Color3.fromRGB(26, 26, 31),
			BorderSizePixel = 0,
			Visible = false,
			ClipsDescendants = true
		}, valueHolder)
		Create("UICorner", {CornerRadius = UDim.new(0, 4)}, popup)
		local list = Create("Frame", {Size = UDim2.new(1, -10, 1, -10), Position = UDim2.new(0, 5, 0, 5), BackgroundTransparency = 1}, popup)
		Create("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, list)
		local isOpen = false
		local optionHeight = 24
		local optionPad = 4
		local popupPadding = 10
		local popupHeight = (#options * optionHeight) + (math.max(0, #options - 1) * optionPad) + popupPadding
		local closedRowHeight = 28
		local openRowHeight = closedRowHeight + 4 + popupHeight

		local function getCount()
			local c = 0
			for _, option in ipairs(options) do
				if selected[option] then c = c + 1 end
			end
			return c
		end

		local function refreshLabel()
			local count = getCount()
			valueLabel.Text = count > 0 and (tostring(count) .. " selected") or "None"
		end

		local function cloneSelected()
			local out = {}
			for _, option in ipairs(options) do
				out[option] = selected[option] == true
			end
			return out
		end

		for _, option in ipairs(options) do
			local opt = Create("TextButton", {Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = Color3.fromRGB(26, 26, 31), BorderSizePixel = 0, Text = "", AutoButtonColor = false}, list)
			Create("UICorner", {CornerRadius = UDim.new(0, 4)}, opt)
			local text = Create("TextLabel", {Size = UDim2.new(1, -24, 1, 0), Position = UDim2.new(0, 8, 0, 0), BackgroundTransparency = 1, Text = option, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Color3.fromRGB(225, 225, 225), TextXAlignment = Enum.TextXAlignment.Left}, opt)
			local markBg = Create("Frame", {Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(1, -18, 0.5, -7), BackgroundColor3 = Color3.fromRGB(31, 31, 37), BorderSizePixel = 0}, opt)
			Create("UICorner", {CornerRadius = UDim.new(0, 3)}, markBg)
			local markStroke = Create("UIStroke", {Color = Color3.fromRGB(115, 115, 125), Thickness = 1}, markBg)
			local markFill = Create("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = ClientSettings.ClientColor, BackgroundTransparency = 1, BorderSizePixel = 0}, markBg)
			Create("UICorner", {CornerRadius = UDim.new(0, 3)}, markFill)

			local function refreshMark()
				local isOn = selected[option] and true or false
				TweenService:Create(markStroke, TweenInfo.new(0.12), {Color = isOn and ClientSettings.ClientColor or Color3.fromRGB(115, 115, 125)}):Play()
				TweenService:Create(markFill, TweenInfo.new(0.12), {BackgroundTransparency = isOn and 0 or 1}):Play()
			end

			opt.MouseButton1Click:Connect(function()
				selected[option] = not selected[option]
				refreshMark()
				refreshLabel()
				if callback then callback(cloneSelected()) end
			end)

			refreshMark()
		end

		local function setOpen(state, instant)
			isOpen = state and true or false
			arrow.Text = isOpen and "^" or "v"
			local targetPopupHeight = isOpen and popupHeight or 0
			local targetRowHeight = isOpen and openRowHeight or closedRowHeight
			if isOpen then
				popup.Visible = true
			end
			if instant then
				popup.Size = UDim2.new(1, 0, 0, targetPopupHeight)
				row.Size = UDim2.new(1, 0, 0, targetRowHeight)
				if not isOpen then
					popup.Visible = false
				end
				return
			end
			local tween = TweenService:Create(popup, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, targetPopupHeight)})
			tween:Play()
			if not isOpen then
				tween.Completed:Connect(function()
					if not isOpen then
						popup.Visible = false
					end
				end)
			end
			TweenService:Create(row, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, targetRowHeight)}):Play()
		end

		holder.MouseButton1Click:Connect(function()
			setOpen(not isOpen, false)
		end)
		RegisterInlinePopupCloser(function()
			if isOpen then
				setOpen(false, true)
			end
		end)

		refreshLabel()
		if callback then callback(cloneSelected()) end
		return holder
	end

	function Library:AddCategoryColorPicker(sectionRows, name, defaultColor, callback)
		local _, valueHolder = self:AddCategoryRow(sectionRows, name)
		local holder = Create("TextButton", {Size = UDim2.new(0, 26, 0, 16), Position = UDim2.new(1, -26, 0.5, -8), BackgroundTransparency = 1, BorderSizePixel = 0, Text = "", AutoButtonColor = false}, valueHolder)
		local preview = Create("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = defaultColor, BorderSizePixel = 0}, holder)
		Create("UICorner", {CornerRadius = UDim.new(0, 3)}, preview)

		local popup = Create("Frame", {Size = UDim2.new(0, 250, 0, 170), BackgroundColor3 = Color3.fromRGB(18, 18, 23), BorderSizePixel = 0, Visible = false, ZIndex = 210, Active = true}, popupLayer)
		Create("UICorner", {CornerRadius = UDim.new(0, 6)}, popup)
		Create("UIStroke", {Color = Color3.fromRGB(45, 45, 50), Thickness = 1}, popup)

		local h, s, v = Color3.toHSV(defaultColor)
		local opacity = 1

		local svBox = Create("Frame", {
			Size = UDim2.new(0, 160, 0, 150),
			Position = UDim2.new(0, 8, 0, 10),
			BackgroundColor3 = Color3.fromHSV(h, 1, 1),
			BorderSizePixel = 0
		}, popup)
		Create("UICorner", {CornerRadius = UDim.new(0, 4)}, svBox)

		local whiteGradient = Create("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0}, svBox)
		Create("UICorner", {CornerRadius = UDim.new(0, 4)}, whiteGradient)
		Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1))
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1)
			}),
			Rotation = 0
		}, whiteGradient)

		local blackGradient = Create("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0}, svBox)
		Create("UICorner", {CornerRadius = UDim.new(0, 4)}, blackGradient)
		Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)),
				ColorSequenceKeypoint.new(1, Color3.new(0, 0, 0))
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0)
			}),
			Rotation = 90
		}, blackGradient)

		local svCursor = Create("Frame", {
			Size = UDim2.new(0, 8, 0, 8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(s, 0, 1 - v, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0
		}, svBox)
		Create("UICorner", {CornerRadius = UDim.new(1, 0)}, svCursor)
		Create("UIStroke", {Color = Color3.new(0, 0, 0), Thickness = 1}, svCursor)

		local hueBar = Create("Frame", {
			Size = UDim2.new(0, 16, 0, 150),
			Position = UDim2.new(0, 176, 0, 10),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0
		}, popup)
		Create("UICorner", {CornerRadius = UDim.new(0, 4)}, hueBar)
		Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
				ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
				ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
				ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
				ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
				ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0))
			}),
			Rotation = 90
		}, hueBar)

		local hueCursor = Create("Frame", {
			Size = UDim2.new(1, 2, 0, 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, h, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0
		}, hueBar)
		Create("UIStroke", {Color = Color3.new(0, 0, 0), Thickness = 1}, hueCursor)

		local alphaBar = Create("Frame", {
			Size = UDim2.new(0, 16, 0, 150),
			Position = UDim2.new(0, 198, 0, 10),
			BackgroundColor3 = Color3.fromHSV(h, s, v),
			BorderSizePixel = 0
		}, popup)
		Create("UICorner", {CornerRadius = UDim.new(0, 4)}, alphaBar)
		Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1))
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0)
			}),
			Rotation = 90
		}, alphaBar)

		local alphaCursor = Create("Frame", {
			Size = UDim2.new(1, 2, 0, 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 1 - opacity, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0
		}, alphaBar)
		Create("UIStroke", {Color = Color3.new(0, 0, 0), Thickness = 1}, alphaCursor)

		local function apply()
			local c = Color3.fromHSV(h, s, v)
			preview.BackgroundColor3 = c
			svBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			alphaBar.BackgroundColor3 = c
			if callback then callback(c, opacity) end
		end

		local svDragging = false
		local hueDragging = false
		local alphaDragging = false

		local function getPickerMousePosition()
			local mouse = UserInputService:GetMouseLocation()
			local insetTopLeft = Vector2.new(0, 0)
			local okInset, topLeft = pcall(function()
				return select(1, GuiService:GetGuiInset())
			end)
			if okInset and typeof(topLeft) == "Vector2" then
				insetTopLeft = topLeft
			end
			return Vector2.new(mouse.X - insetTopLeft.X, mouse.Y - insetTopLeft.Y)
		end

		local function updateSVFromMouse()
			local mouse = getPickerMousePosition()
			local relX = math.clamp((mouse.X - svBox.AbsolutePosition.X) / math.max(1, svBox.AbsoluteSize.X), 0, 1)
			local relY = math.clamp((mouse.Y - svBox.AbsolutePosition.Y) / math.max(1, svBox.AbsoluteSize.Y), 0, 1)
			s = relX
			v = 1 - relY
			svCursor.Position = UDim2.new(s, 0, relY, 0)
			apply()
		end

		local function updateHueFromMouse()
			local mouse = getPickerMousePosition()
			local relY = math.clamp((mouse.Y - hueBar.AbsolutePosition.Y) / math.max(1, hueBar.AbsoluteSize.Y), 0, 1)
			h = relY
			hueCursor.Position = UDim2.new(0.5, 0, relY, 0)
			apply()
		end

		local function updateAlphaFromMouse()
			local mouse = getPickerMousePosition()
			local relY = math.clamp((mouse.Y - alphaBar.AbsolutePosition.Y) / math.max(1, alphaBar.AbsoluteSize.Y), 0, 1)
			opacity = 1 - relY
			alphaCursor.Position = UDim2.new(0.5, 0, relY, 0)
			apply()
		end

		svBox.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then svDragging = true; updateSVFromMouse() end end)
		hueBar.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then hueDragging = true; updateHueFromMouse() end end)
		alphaBar.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then alphaDragging = true; updateAlphaFromMouse() end end)
		TrackConnection(UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
			if svDragging then updateSVFromMouse() end
			if hueDragging then updateHueFromMouse() end
			if alphaDragging then updateAlphaFromMouse() end
		end))
		TrackConnection(UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				svDragging = false
				hueDragging = false
				alphaDragging = false
			end
		end))

		holder.MouseButton1Click:Connect(function()
			local targetHeight = 170
			popup.Size = UDim2.new(0, 250, 0, targetHeight)
			SetPopup(holder, popup, nil, targetHeight)
		end)
		apply()
		return holder
	end

	TrackConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == toggleKeybind then
			SetMenuVisible(not menuVisible)
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and menuVisible then
			local point = Vector2.new(input.Position.X, input.Position.Y)
			local inside = false
			if typeof(mainRef) == "Instance" and mainRef.Visible then
				if IsPointInsideGui(mainRef, point) then inside = true end
			end
			if typeof(popupLayerRef) == "Instance" then
				for _, popupObj in ipairs(popupLayerRef:GetChildren()) do
					if popupObj.Visible and IsPointInsideGui(popupObj, point) then
						inside = true
						break
					end
				end
			end
			if not inside then
				CloseActivePopup()
				CloseInlinePopups()
			end
		end
	end))

	TrackConnection(dragHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and menuVisible then
			CloseActivePopup()
			CloseInlinePopups()
		end
	end))

	self.SetMenuVisible = SetMenuVisible

	RefreshFadeBases()
	menuFadeDriver.Value = 1
	menuFadeDriver:GetPropertyChangedSignal("Value"):Connect(function()
		ApplyMenuFade(menuFadeDriver.Value)
	end)

	main.Visible = false
	popupLayer.Visible = false
	ApplyMenuFade(0)

	print("Loaded Lumma Framework - v1.0.4")
	return self
end

return Library
