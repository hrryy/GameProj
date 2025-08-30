--!strict
local TeamConfig = {}

-- Type definitions
export type TeamId = "Red" | "Blue" | "Green" | "Yellow"
export type TeamCounts = { [TeamId]: number }
export type TeamAllowed = { [TeamId]: boolean }

-- Teams configuration (order matters for UI layout)
TeamConfig.Teams = { "Red", "Blue", "Green", "Yellow" } :: { TeamId }

-- UI colors for each team
TeamConfig.TeamColors = {
    Red = Color3.fromRGB(220, 60, 60),
    Blue = Color3.fromRGB(60, 100, 220),
    Green = Color3.fromRGB(60, 180, 90),
    Yellow = Color3.fromRGB(240, 210, 60),
} :: { [TeamId]: Color3 }

-- Server-enforced cooldown between switches (seconds)
TeamConfig.SwitchCooldownSeconds = 30

-- Helper function to get minimum team count
local function getMinTeamCount(counts: TeamCounts): number
    local minCount = math.huge
    for _, team in ipairs(TeamConfig.Teams) do
        local count = counts[team] or 0
        minCount = math.min(minCount, count)
    end
    return minCount
end

-- Balance rule:
-- A join is allowed only if, after joining, no team would be more than +1 over the smallest team size.
function TeamConfig.getAllowedTeams(counts: TeamCounts): TeamAllowed
    local minCount = getMinTeamCount(counts)
    
    local allowed: TeamAllowed = {}
    for _, team in ipairs(TeamConfig.Teams) do
        local currentCount = counts[team] or 0
        allowed[team] = (currentCount + 1) <= (minCount + 1)
    end
    return allowed
end

-- Suggest the currently smallest team(s)
function TeamConfig.getSuggestedTeams(counts: TeamCounts): { TeamId }
    local minCount = getMinTeamCount(counts)
    
    local suggested: { TeamId } = {}
    for _, team in ipairs(TeamConfig.Teams) do
        if (counts[team] or 0) == minCount then
            table.insert(suggested, team)
        end
    end
    return suggested
end

-- Get team difference from average
function TeamConfig.getTeamBalance(counts: TeamCounts): { [TeamId]: number }
    local total = 0
    local numTeams = #TeamConfig.Teams
    
    for _, count in counts do
        total += count
    end
    
    local average = total / numTeams
    local balance: { [TeamId]: number } = {}
    
    for _, team in ipairs(TeamConfig.Teams) do
        balance[team] = (counts[team] or 0) - average
    end
    
    return balance
end

return TeamConfig