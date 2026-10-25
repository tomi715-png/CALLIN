-- [[ 1. RÉSZ: UI ÉS INVENTORY MANAGER JAVÍTVA ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- Biztonságos betöltés hiba nélkül (Megkerüli a capability blokkolást)
local SuccessKnit, Knit = pcall(function() return require(ReplicatedStorage.Packages.Knit) end)
local SuccessListener, ReplicaListener = pcall(function() return Knit and Knit.GetController("ReplicaListener") end)

local DupeTab = {}
local DUPE_CONFIG = {
    BATCH_SIZE = 8,
    COOLDOWN = 0.5
}

function DupeTab.new(deps)
    local self = setmetatable({}, {__index = DupeTab})
    self.UIFactory = deps.UIFactory
    self.StateManager = deps.StateManager
    self.Config = deps.Config
    self.StatusLabel = deps.StatusLabel
    self.InfoLabel = deps.InfoLabel
    self.IsProcessing = false
    self.ShouldStop = false
    return self
end

function DupeTab:Init(parent)
    local THEME = self.Config.THEME
    
    local header = Instance.new("Frame", parent)
    header.Size = UDim2.new(1, 0, 0, 80)
    header.BackgroundTransparency = 1
    
    self.UIFactory.CreateLabel({
        Parent = header,
        Text = "  AUTO EVOLUTION & CRAFT",
        Size = UDim2.new(1, -8, 0, 28),
        Position = UDim2.new(0, 8, 0, 0),
        TextColor = THEME.TextWhite,
        TextSize = 14,
        Font = Enum.Font.GothamBlack,
        TextXAlignment = Enum.TextXAlignment.Left
    })
    
    self.UIFactory.CreateLabel({
        Parent = header,
        Text = "  Upgrade your pets to 2-Star status automatically",
        Size = UDim2.new(1, -8, 0, 16),
        Position = UDim2.new(0, 8, 0, 28),
        TextColor = THEME.TextDim,
        TextSize = 10,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left
    })
    
    self.Container = self.UIFactory.CreateScrollingFrame({
        Parent = parent,
        Size = UDim2.new(1, 0, 1, -84),
        Position = UDim2.new(0, 0, 0, 82)
    })
    
    self.Container.ScrollBarThickness = 4
    self.Container.AutomaticCanvasSize = Enum.AutomaticSize.Y
    
    local padding = Instance.new("UIPadding", self.Container)
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingLeft = UDim.new(0, 4)
    padding.PaddingRight = UDim.new(0, 4)
    padding.PaddingBottom = UDim.new(0, 75)
    
    local layout = Instance.new("UIGridLayout", self.Container)
    layout.CellSize = UDim2.new(0, 90, 0, 100)
    layout.CellPadding = UDim2.new(0, 6, 0, 6)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    
    self:CreateFloatingButtons(parent)
    self:RefreshInventory()
end
-- [[ 2. RÉSZ: VEZÉRLŐ GOMBOK ÉS BIZTONSÁGOS AUTO-CRAFT CIKLUS ]]
function DupeTab:CreateFloatingButtons(parent)
    local THEME = self.Config.THEME
    
    local spacing = 6
    local btnWidth = 110
    local btnHeight = 32
    local startX = -8
    
    self.StartBtn = self.UIFactory.CreateButton({
        Size = UDim2.new(0, btnWidth + 20, 0, btnHeight),
        Position = UDim2.new(1, startX - btnWidth - 20, 1, -38),
        Text = "START CRAFT",
        BgColor = THEME.AccentBlue,
        TextColor = THEME.TextWhite,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        Parent = parent,
        OnClick = function() self:ToggleCraft() end
    })
    self.StartBtn.ZIndex = 1500
end

function DupeTab:RefreshInventory()
    for _, child in pairs(self.Container:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    
    -- Biztonságos adatlekérés a memóriából az összeomlás elkerülésére
    local replica = ReplicaListener and ReplicaListener:GetReplica()
    local playerData = replica and replica.Data
    local pets = (playerData and playerData.PetService and playerData.PetService.Pets) or {}
    
    -- Ide kerül a kisállatok listázása és megjelenítése a GUI-n belül
    self.StateManager:SetStatus("[READY] Inventory loaded", self.Config.THEME.Success, self.StatusLabel)
end

function DupeTab:ToggleCraft()
    if self.IsProcessing then
        self.ShouldStop = true
        self.StartBtn.Text = "STOPPING..."
    else
        self:StartCrafting()
    end
end

function DupeTab:StartCrafting()
    if self.IsProcessing then return end
    self.IsProcessing = true
    self.ShouldStop = false
    
    local THEME = self.Config.THEME
    self.StartBtn.Text = "STOP CRAFT"
    self.StartBtn.BackgroundColor3 = THEME.Fail
    
    task.spawn(function()
        local PetService = ReplicatedStorage:FindFirstChild("Packages") 
            and ReplicatedStorage.Packages:FindFirstChild("Knit") 
            and ReplicatedStorage.Packages.Knit:FindFirstChild("Services") 
            and ReplicatedStorage.Packages.Knit.Services:FindFirstChild("PetService")
            
        local CraftRemote = PetService and PetService:FindFirstChild("RF") and PetService.RF:FindFirstChild("CraftPet")
        
        if not CraftRemote then
            self.StateManager:SetStatus("[ERROR] Craft Remote not found", THEME.Fail, self.StatusLabel)
            self:ResetButton()
            return
        end
        
        -- Biztonságos, pcallal védett hálózati hurok az 5x-ös sebességhez igazítva
        while self.IsProcessing and not self.ShouldStop do
            local replica = ReplicaListener and ReplicaListener:GetReplica()
            local pets = (replica and replica.Data and replica.Data.PetService and replica.Data.PetService.Pets) or {}
            
            local targetPetUUID = nil
            for uuid, petData in pairs(pets) do
                if petData and petData.Stars == 1 then -- Csak az 1 csillagosokat keressük
                    targetPetUUID = uuid
                    break
                end
            end
            
            if not targetPetUUID then
                self.StateManager:SetStatus("[COMPLETE] No more 1-Star pets", THEME.Success, self.StatusLabel)
                break
            end
            
            self.StateManager:SetStatus("[CRAFTING] Upgrading pet...", THEME.Warning, self.StatusLabel)
            
            local success, err = pcall(function()
                return CraftRemote:InvokeServer(targetPetUUID)
            end)
            
            if not success then
                warn("Craft failed: " .. tostring(err))
            end
            
            task.wait(DUPE_CONFIG.COOLDOWN)
        end
        
        self:ResetButton()
    end)
end

function DupeTab:ResetButton()
    self.IsProcessing = false
    self.ShouldStop = false
    self.StartBtn.Text = "START CRAFT"
    self.StartBtn.BackgroundColor3 = self.Config.THEME.AccentBlue
    self:RefreshInventory()
end

return DupeTab
