--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeamsService = game:GetService("Teams")

local TeamConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TeamConfig"))

-- Constants
local TEAM_COLORS = {
    Red = BrickColor.new("Bright red"),
    Blue = BrickColor.new("Bright blue"),
    Green = BrickColor.new("Bright green"),
    Yellow = BrickColor.new("New Yeller")
}

-- Initialize teams
for teamName, teamColor in pairs(TEAM_COLORS) do
    local team = TeamsService:FindFirstChild(teamName)
    if not team then
        team = Instance.new("Team")
        team.Name = teamName
        team.TeamColor = teamColor
        team.AutoAssignable = false
        team.Parent = TeamsService
    end
end

-- Setup remotes
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

local JoinTeamRemote = Remotes:FindFirstChild("JoinTeam") or Instance.new("RemoteFunction")
JoinTeamRemote.Name = "JoinTeam"
JoinTeamRemote.Parent = Remotes

local TeamStateEvent = Remotes:FindFirstChild("TeamState") or Instance.new("RemoteEvent")
TeamStateEvent.Name = "TeamState"
TeamStateEvent.Parent = Remotes

local ShowTeamUIEvent = Remotes:FindFirstChild("ShowTeamUI") or Instance.new("RemoteEvent")
ShowTeamUIEvent.Name = "ShowTeamUI"
ShowTeamUIEvent.Parent = Remotes

-- State
local lastSwitch: { [Player]: number } = {}

-- Team counting and state functions
local function getCounts(): { [TeamConfig.TeamId]: number }
    local counts = {}
    
    -- Initialize all teams to 0
    for _, team in ipairs(TeamConfig.Teams) do
        counts[team] = 0
    end
    
    -- Count players in each team
    for _, player in ipairs(Players:GetPlayers()) do
        local team = player.Team
        if team and counts[team.Name] ~= nil then
            counts[team.Name] += 1
        end
    end

    return counts
end

local function getAllowedTeams(counts: { [TeamConfig.TeamId]: number }): { [TeamConfig.TeamId]: boolean }
    local allowed = {}
    local totalPlayers = #Players:GetPlayers()
    
    print("[TeamService] Total players:", totalPlayers)
    print("[TeamService] Current counts:", counts)

    -- Always make all teams available
    for _, team in ipairs(TeamConfig.Teams) do
        allowed[team] = true
    end

    print("[TeamService] Final allowed teams:", allowed)
    return allowed
end

local function broadcastTeamState()
    local counts = getCounts()
    local allowed = getAllowedTeams(counts)
    local suggested = TeamConfig.getSuggestedTeams(counts)
    
    print("[TeamService] Broadcasting state:", counts, allowed)
    
    TeamStateEvent:FireAllClients({
        counts = counts,
        allowed = allowed,
        suggested = suggested,
        cooldown = TeamConfig.SwitchCooldownSeconds,
        serverTime = os.clock(),
    })
end

local function tryJoinTeam(player: Player, desired: TeamConfig.TeamId)
    local team = TeamsService:FindFirstChild(desired)
    if not team then
        warn("[TeamService] Invalid team requested:", desired)
        return { ok = false, reason = "InvalidTeam" }
    end

    local now = os.clock()
    local last = lastSwitch[player] or -1e9
    local remaining = TeamConfig.SwitchCooldownSeconds - (now - last)
    if remaining > 0 then
        return { 
            ok = false, 
            reason = "Cooldown", 
            remaining = math.ceil(remaining) 
        }
    end

    local counts = getCounts()
    local allowed = getAllowedTeams(counts)
    if not allowed[desired] then
        return { 
            ok = false, 
            reason = "Balance", 
            counts = counts, 
            allowed = allowed 
        }
    end

    print("[TeamService] Player joined team:", player.Name, "→", desired)
    player.Team = team
    lastSwitch[player] = now
    
    task.defer(function()
        task.wait(0.1)
        broadcastTeamState()
    end)
    
    return { ok = true, team = desired }
end

JoinTeamRemote.OnServerInvoke = function(player: Player, desired: any): { [string]: any }
    if typeof(desired) ~= "string" or not table.find(TeamConfig.Teams, desired) then
        return { ok = false, reason = "BadRequest" }
    end
    return tryJoinTeam(player, desired :: TeamConfig.TeamId)
end

Players.PlayerAdded:Connect(function(player: Player)
    lastSwitch[player] = -1e9
    task.spawn(broadcastTeamState)
    
    task.delay(1, function()
        ShowTeamUIEvent:FireClient(player)
    end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
    lastSwitch[player] = nil
    task.spawn(broadcastTeamState)
end)

TeamsService.ChildAdded:Connect(broadcastTeamState)
TeamsService.ChildRemoved:Connect(broadcastTeamState)