--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
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
local AVAILABLE_ICON_COLOR = Color3.fromRGB(60, 200, 60)
local UNAVAILABLE_ICON_COLOR = Color3.fromRGB(200, 60, 60)

-- Remote Events/Functions
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local JoinTeamRemote = Remotes:WaitForChild("JoinTeam") :: RemoteFunction
local TeamStateEvent = Remotes:WaitForChild("TeamState") :: RemoteEvent

-- UI State
local cards: { [TeamConfig.TeamId]: Frame } = {}
local cooldownUntil = 0
local currentState: TeamState = {}

-- UI Setup Functions
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
    card.AutoButtonColor = false
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
    availabilityIcon.BackgroundColor3 = UNAVAILABLE_ICON_COLOR
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
    tooltip.Text = "Unavailable"
    tooltip.Parent = card

    return card
end

local function handleTeamJoin(team: TeamConfig.TeamId)
    if os.clock() < cooldownUntil then return end

    if not (currentState.allowed and currentState.allowed[team]) then
        return
    end

    local success, result = pcall(function()
        return JoinTeamRemote:InvokeServer(team)
    end)

    if success and result and result.ok then
        cooldownUntil = os.clock() + TeamConfig.SwitchCooldownSeconds
        updateTeamCard(team, currentState)
        
        task.defer(function()
            task.wait(0.1)
            updateTeamCard(team, currentState)
        end)
    else
        warn("[TeamUI] Join failed:", if success then result.reason else result)
    end
end

local function updateTeamCard(team: TeamConfig.TeamId, state: TeamState)
    local card = cards[team]
    if not card then return end

    local countLbl = card:FindFirstChild("Count") :: TextLabel
    local pill = card:FindFirstChild("Pill") :: Frame
    local availabilityIcon = card:FindFirstChild("AvailabilityIcon") :: Frame
    local availabilityText = card:FindFirstChild("AvailabilityText") :: TextLabel

    local count = if state.counts then state.counts[team] else 0
    countLbl.Text = "Players: " .. tostring(count)

    local isAvailable = state.allowed and state.allowed[team]
    availabilityIcon.BackgroundColor3 = if isAvailable 
        then AVAILABLE_ICON_COLOR 
        else UNAVAILABLE_ICON_COLOR
    
    availabilityText.Text = if isAvailable 
        then "Available to join" 
        else "Team full"

    card.AutoButtonColor = isAvailable
    card.BackgroundColor3 = if isAvailable 
        then CARD_COLOR 
        else Color3.fromRGB(30, 30, 32)

    local isSuggested = false
    if state.suggested then
        for _, s in ipairs(state.suggested) do
            if s == team then
                isSuggested = true
                break
            end
        end
    end
    pill.Visible = isSuggested
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

init()