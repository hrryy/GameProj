--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- Wait for all remotes to be available first
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local JoinTeamRemote = Remotes:WaitForChild("JoinTeam") :: RemoteFunction
local TeamStateEvent = Remotes:WaitForChild("TeamState") :: RemoteEvent
local ShowTeamUIEvent = Remotes:WaitForChild("ShowTeamUI") :: RemoteEvent

local TeamConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TeamConfig"))

-- Types
type TeamState = {
    counts: { [TeamConfig.TeamId]: number }?,
    suggested: { TeamConfig.TeamId }?,
    allowed: { [TeamConfig.TeamId]: boolean }?
}

-- Constants
local PADDING = 20
local CELL_PADDING = 12
local CORNER_RADIUS = 12
local BUTTON_CORNER_RADIUS = 10
local BACKGROUND_COLOR = Color3.fromRGB(30, 30, 35)
local CARD_COLOR = Color3.fromRGB(38, 38, 40)
local AVAILABLE_ICON_COLOR = Color3.fromRGB(60, 200, 60)    -- Bright green
local UNAVAILABLE_ICON_COLOR = Color3.fromRGB(200, 60, 60)  -- Bright red
local SUCCESS_COLOR = Color3.fromRGB(60, 200, 60)

-- UI State
local cards: { [TeamConfig.TeamId]: Frame } = {}
local cooldownUntil = 0
local currentState: TeamState = {}

local function showConfirmationAndClose(team: TeamConfig.TeamId, gui: ScreenGui)
    local overlay = Instance.new("Frame")
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.BackgroundColor3 = Color3.new(0, 0, 0)
    overlay.BackgroundTransparency = 0.7
    overlay.Parent = gui

    local icon = Instance.new("ImageLabel")
    icon.Size = UDim2.fromOffset(64, 64)
    icon.Position = UDim2.fromScale(0.5, 0.5)
    icon.AnchorPoint = Vector2.new(0.5, 0.5)
    icon.BackgroundTransparency = 1
    icon.Image = "rbxassetid://9122619559"
    icon.ImageColor3 = SUCCESS_COLOR
    icon.Parent = overlay

    local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back)
    local iconTween = TweenService:Create(icon, tweenInfo, {
        Size = UDim2.fromOffset(96, 96),
        ImageTransparency = 1
    })

    iconTween:Play()
    iconTween.Completed:Connect(function()
        gui:Destroy()
    end)
end

local function createBaseGui(): ScreenGui
    local gui = Instance.new("ScreenGui")
    gui.Name = "TeamSelectUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = player:WaitForChild("PlayerGui")
    return gui
end

local function createMainFrame(parent: ScreenGui): Frame
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(0.45, 0.6)
    frame.Position = UDim2.fromScale(0.5, 0.5)
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.BackgroundColor3 = BACKGROUND_COLOR
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, CORNER_RADIUS)
    return frame
end

local function createTeamCard(team: TeamConfig.TeamId, container: Frame): Frame
    local color = TeamConfig.TeamColors[team]
    local card = Instance.new("TextButton")
    card.AutoButtonColor = true
    card.Text = ""
    card.BackgroundColor3 = CARD_COLOR
    card.BorderSizePixel = 0
    card.Parent = container
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, BUTTON_CORNER_RADIUS)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.6, -16, 0, 30)
    label.Position = UDim2.new(0, 8, 0, 10)
    label.Text = team .. " Team"
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.TextColor3 = Color3.new(1, 1, 1)
    label.BackgroundTransparency = 1
    label.Name = "TeamLabel"
    label.Parent = card

    local count = Instance.new("TextLabel")
    count.Size = UDim2.new(1, -16, 0, 28)
    count.Position = UDim2.new(0, 8, 0, 45)
    count.Text = "Players: 0"
    count.Font = Enum.Font.Gotham
    count.TextScaled = true
    count.TextColor3 = Color3.fromRGB(210, 210, 220)
    count.BackgroundTransparency = 1
    count.Name = "Count"
    count.Parent = card

    local pill = Instance.new("Frame")
    pill.Size = UDim2.fromOffset(80, 20)
    pill.AnchorPoint = Vector2.new(1, 0)
    pill.Position = UDim2.new(1, -8, 0, 8)
    pill.BackgroundColor3 = color
    pill.Visible = false
    pill.Name = "Pill"
    pill.Parent = card
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

    local pillText = Instance.new("TextLabel")
    pillText.Size = UDim2.fromScale(1, 1)
    pillText.Text = "Suggested"
    pillText.Font = Enum.Font.GothamSemibold
    pillText.TextSize = 12
    pillText.TextColor3 = Color3.new(1, 1, 1)
    pillText.BackgroundTransparency = 1
    pillText.Parent = pill

    local availabilityIcon = Instance.new("Frame")
    availabilityIcon.Size = UDim2.fromOffset(12, 12)
    availabilityIcon.Position = UDim2.new(0, 8, 1, -20)
    availabilityIcon.BackgroundColor3 = AVAILABLE_ICON_COLOR  -- Start with green
    availabilityIcon.Name = "AvailabilityIcon"
    availabilityIcon.Parent = card
    Instance.new("UICorner", availabilityIcon).CornerRadius = UDim.new(1, 0)

    local tooltip = Instance.new("TextLabel")
    tooltip.Size = UDim2.fromOffset(100, 20)
    tooltip.Position = UDim2.new(0, 24, 1, -20)
    tooltip.BackgroundTransparency = 1
    tooltip.TextColor3 = Color3.new(1, 1, 1)
    tooltip.TextXAlignment = Enum.TextXAlignment.Left
    tooltip.Font = Enum.Font.Gotham
    tooltip.TextSize = 12
    tooltip.Name = "AvailabilityText"
    tooltip.Text = "Available to join"  -- Start with available
    tooltip.Parent = card

    return card
end

local function updateTeamCard(team: TeamConfig.TeamId, state: TeamState)
    local card = cards[team]
    if not card then return end

    local countLbl = card:FindFirstChild("Count") :: TextLabel
    local availabilityIcon = card:FindFirstChild("AvailabilityIcon") :: Frame
    local availabilityText = card:FindFirstChild("AvailabilityText") :: TextLabel

    -- Force available state
    availabilityIcon.BackgroundColor3 = AVAILABLE_ICON_COLOR
    availabilityText.Text = "Available to join"
    card.AutoButtonColor = true
    card.BackgroundColor3 = CARD_COLOR
    card.Active = true
    card.Selectable = true

    -- Update count
    local count = if state.counts then state.counts[team] else 0
    countLbl.Text = "Players: " .. tostring(count)

    print("[TeamUI] Team:", team, "Color:", availabilityIcon.BackgroundColor3)
end

local function handleTeamJoin(team: TeamConfig.TeamId)
    if os.clock() < cooldownUntil then return end

    local success, result = pcall(function()
        return JoinTeamRemote:InvokeServer(team)
    end)

    if success and result and result.ok then
        cooldownUntil = os.clock() + TeamConfig.SwitchCooldownSeconds
        
        local gui = cards[team]:FindFirstAncestorOfClass("ScreenGui")
        if gui then
            showConfirmationAndClose(team, gui)
        end
    else
        warn("[TeamUI] Join failed:", if success then result.reason else result)
    end
end

local function init()
    local gui = createBaseGui()
    local mainFrame = createMainFrame(gui)

    local layoutContainer = Instance.new("Frame")
    layoutContainer.Size = UDim2.new(1, -PADDING, 1, -PADDING)
    layoutContainer.Position = UDim2.fromOffset(PADDING/2, PADDING/2)
    layoutContainer.BackgroundTransparency = 1
    layoutContainer.Parent = mainFrame

    local layout = Instance.new("UIGridLayout")
    layout.CellPadding = UDim2.fromOffset(CELL_PADDING, CELL_PADDING)
    layout.CellSize = UDim2.new(0.45, 0, 0.4, 0)
    layout.FillDirectionMaxCells = 2
    layout.Parent = layoutContainer

    for _, team in ipairs(TeamConfig.Teams) do
        local card = createTeamCard(team, layoutContainer)
        cards[team] = card
        
        card.MouseButton1Click:Connect(function()
            handleTeamJoin(team)
        end)
    end

    TeamStateEvent.OnClientEvent:Connect(function(state: TeamState)
        currentState = state
        for _, team in ipairs(TeamConfig.Teams) do
            updateTeamCard(team, state)
        end
    end)
end

if game:IsLoaded() then
    task.spawn(init)
else
    game.Loaded:Wait()
    task.spawn(init)
end

ShowTeamUIEvent.OnClientEvent:Connect(function()
    local existing = player.PlayerGui:FindFirstChild("TeamSelectUI")
    if existing then
        existing:Destroy()
    end
    task.spawn(init)
end)