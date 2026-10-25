-- tabs/helper_tab.lua
-- Helper Tab - Ultimate Anti-Lag System (Fixed Animation Crash)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local RemoteFolder = ReplicatedStorage:WaitForChild("ReplicaRemoteEvents")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local HelperTab = {}
HelperTab.__index = HelperTab

function HelperTab.new(deps)
    local self = setmetatable({}, HelperTab)
    
    self.UIFactory = deps.UIFactory
    self.StateManager = deps.StateManager
    self.Utils = deps.Utils
    self.Config = deps.Config
    self.StatusLabel = deps.StatusLabel
    
    self.Container = nil
    self.AntiLagEnabled = false
    
    -- Backup Storage
    self.Replica = nil
    self.StoredListeners = {
        Table = {},
        Raw = {},
        Child = {}
    }
    
    -- [NEW] เก็บฟังก์ชันอนิเมชั่นตัวจริงไว้คืนค่า
    self.OriginalPlayRoll = nil 
    self.HasHooked = false
    
    return self
end

function HelperTab:Init(parent)
    local THEME = self.Config.THEME
    
    -- Header
    local headerFrame = Instance.new("Frame", parent)
    headerFrame.Size = UDim2.new(1, 0, 0, 42)
    headerFrame.BackgroundTransparency = 1
    
    self.UIFactory.CreateLabel({
        Parent = headerFrame,
        Text = "  HELPER & PERFORMANCE",
        Size = UDim2.new(1, -8, 0, 24),
        Position = UDim2.new(0, 8, 0, 0),
        TextColor = THEME.TextWhite,
        TextSize = 14,
        Font = Enum.Font.GothamBlack,
        TextXAlign = Enum.TextXAlignment.Left
    })
    
    self.UIFactory.CreateLabel({
        Parent = headerFrame,
        Text = "  Silence game UI to maximize speed",
        Size = UDim2.new(1, -8, 0, 14),
        Position = UDim2.new(0, 8, 0, 22),
        TextColor = THEME.TextDim,
        TextSize = 11,
        Font = Enum.Font.Gotham,
        TextXAlign = Enum.TextXAlignment.Left
    })
    
    self.Container = Instance.new("Frame", parent)
    self.Container.Size = UDim2.new(1, 0, 1, -48)
    self.Container.Position = UDim2.new(0, 0, 0, 48)
    self.Container.BackgroundTransparency = 1
    
    local padding = Instance.new("UIPadding", self.Container)
    padding.PaddingLeft = UDim.new(0, 12)
    padding.PaddingRight = UDim.new(0, 12)
    padding.PaddingTop = UDim.new(0, 8)
    
    self:CreateAntiLagCard()
end

function HelperTab:CreateAntiLagCard()
    local THEME = self.Config.THEME
    
    local card = Instance.new("Frame", self.Container)
    card.BackgroundColor3 = THEME.CardBg
    -- [ปรับ 1] ลดความสูงการ์ดจาก 85 เหลือ 65 (กะทัดรัดขึ้น)
    card.Size = UDim2.new(1, -24, 0, 65)
    self.UIFactory.AddCorner(card, 8)
    self.UIFactory.AddStroke(card, THEME.GlassStroke, 1.5, 0)
    
    local indicator = Instance.new("Frame", card)
    indicator.Size = UDim2.new(0, 4, 1, -12) -- ปรับขนาดแถบข้างให้เข้ากับความสูงใหม่
    indicator.Position = UDim2.new(0, 6, 0, 6)
    indicator.BackgroundColor3 = THEME.BtnDisabled
    self.UIFactory.AddCorner(indicator, 2)
    
    local content = Instance.new("Frame", card)
    content.Size = UDim2.new(1, -95, 1, 0)
    content.Position = UDim2.new(0, 18, 0, 0)
    content.BackgroundTransparency = 1
    
    self.UIFactory.CreateLabel({
        Parent = content,
        Text = "DISBLE INVENTORY UPDATE",
        Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.new(0, 0, 0, 10), -- ขยับตำแหน่งหัวข้อ
        TextColor = THEME.TextWhite,
        TextSize = 13,
        Font = Enum.Font.GothamBold,
        TextXAlign = Enum.TextXAlignment.Left
    })
    
    self.UIFactory.CreateLabel({
        Parent = content,
        Text = "Disables animations for lag-free Craft Secert OpenCrates Upgrade Scorll", 
        Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.new(0, 0, 0, 28), -- ขยับขึ้นมาให้ชิดหัวข้อ
        TextColor = THEME.TextGray,
        -- [ปรับ 2] เพิ่มขนาดตัวหนังสือจาก 10 เป็น 12 (อ่านง่ายขึ้น)
        TextSize = 12,
        Font = Enum.Font.GothamMedium, -- เปลี่ยน Font ให้หนาขึ้นนิดนึง
        TextXAlign = Enum.TextXAlignment.Left,
        TextWrapped = true
    })
    
    local toggleBtn = self.UIFactory.CreateButton({
        Parent = card,
        Text = "OFF",
        -- [ปรับ 3] ปรับขนาดปุ่มให้เล็กลงนิดนึงเพื่อให้สมดุลกับการ์ด
        Size = UDim2.new(0, 70, 0, 28),
        Position = UDim2.new(1, -78, 0.5, -14),
        BgColor = THEME.BtnDefault,
        TextColor = THEME.TextGray,
        TextSize = 12,
        Font = Enum.Font.GothamBold
    })
    
    toggleBtn.MouseButton1Click:Connect(function()
        self.AntiLagEnabled = not self.AntiLagEnabled
        
        if self.AntiLagEnabled then
            toggleBtn.Text = "ON"
            toggleBtn.BackgroundColor3 = THEME.AccentBlue
            toggleBtn.TextColor3 = THEME.TextWhite
            indicator.BackgroundColor3 = THEME.AccentBlue
            self:SetAntiLag(true)
            self.StateManager:SetStatus("DISBLE INVENTORY MODE: ACTIVE", THEME.Info, self.StatusLabel)
        else
            toggleBtn.Text = "OFF"
            toggleBtn.BackgroundColor3 = THEME.BtnDefault
            toggleBtn.TextColor3 = THEME.TextGray
            indicator.BackgroundColor3 = THEME.BtnDisabled
            self:SetAntiLag(false)
            self.StateManager:SetStatus("RESTORED NORMAL UI", THEME.TextGray, self.StatusLabel)
        end
    end)
end

function HelperTab:SetupHooks()
    if self.HasHooked then return end
    self.HasHooked = true

    local remotes = {"Replica_ReplicaSetValue", "Replica_ReplicaSetValues", "Replica_ReplicaArrayInsert"}
    for _, name in pairs(remotes) do
        local remote = RemoteFolder:FindFirstChild(name)
        if remote then
            for _, conn in pairs(getconnections(remote.OnClientEvent)) do
                local oldFunc = conn.Function
                conn:Disable()
                remote.OnClientEvent:Connect(function(id, path, value, ...)
                    if self.AntiLagEnabled then
                        local pathStr = type(path) == "table" and table.concat(path, ".") or tostring(path)
                        if pathStr:find("Rewards") then
                            if name:find("ArrayInsert") then return end
                            value = {{Name = "System Cleaned", Amount = 1}}
                        end
                    end
                    pcall(oldFunc, id, path, value, ...)
                end)
            end
        end
    end
end

-- [NEW FUNCTION] แก้ปัญหา Error: attempt to index nil
function HelperTab:MuteCrateController(mute)
    local success, CrateController = pcall(function()
        return Knit.GetController("CrateController")
    end)
    
    if not success or not CrateController then return end

    if mute then
        -- ถ้ายังไม่เคยเก็บตัวจริง ให้เก็บไว้ก่อน
        if not self.OriginalPlayRoll and CrateController.PlayRollAnimation then
            self.OriginalPlayRoll = CrateController.PlayRollAnimation
        end
        
        -- ทับด้วยฟังก์ชันว่างเปล่า (ใบ้)
        if CrateController.PlayRollAnimation then
             CrateController.PlayRollAnimation = function() end
        end
        print("🚫 Muted Crate Animation")
    else
        -- คืนค่าตัวจริง
        if self.OriginalPlayRoll then
            CrateController.PlayRollAnimation = self.OriginalPlayRoll
            self.OriginalPlayRoll = nil
            print("✅ Restored Crate Animation")
        end
    end
end

function HelperTab:SetAntiLag(state)
    -- Toggle Effects UI
    pcall(function()
        local effectsGui = PlayerGui:FindFirstChild("Effects")
        if effectsGui then effectsGui.Enabled = not state end
    end)

    task.spawn(function()
        if not self.Replica then
            local controller = Knit.GetController("ReplicaListener")
            self.Replica = controller:GetReplica()
            while not self.Replica do task.wait(0.5) self.Replica = controller:GetReplica() end
        end

        self:SetupHooks()
        
        -- [เรียกใช้ฟังก์ชันแก้ Error]
        self:MuteCrateController(state)

        if state then
            -- [[ MUTE LISTENERS ]] --
            if self.Replica._table_listeners and self.Replica._table_listeners[1] then
                local listeners = self.Replica._table_listeners[1]
                
                if listeners["CratesService"] then
                    self.StoredListeners.Table["CratesService"] = listeners["CratesService"]
                    listeners["CratesService"] = nil
                end
                if listeners["AccessoryService"] then
                    self.StoredListeners.Table["AccessoryService"] = listeners["AccessoryService"]
                    listeners["AccessoryService"] = nil
                end
                if listeners["MonsterService"] then
                    self.StoredListeners.Table["MonsterService"] = listeners["MonsterService"]
                    listeners["MonsterService"] = nil
                    print("🔇 Muted MonsterService (Secrets)")
                end
            end

            
            -- Mute Raw
            if self.Replica._raw_listeners then
                for i, v in ipairs(self.Replica._raw_listeners) do
                    table.insert(self.StoredListeners.Raw, v)
                end
                table.clear(self.Replica._raw_listeners)
            end

            -- Mute Child
            if self.Replica._child_listeners then
                for id, listeners in pairs(self.Replica._child_listeners) do
                    self.StoredListeners.Child[id] = listeners
                    self.Replica._child_listeners[id] = nil
                end
            end

            self:NukeInventoryUI()

        else
            -- [[ RESTORE ]] --
            local listeners = self.Replica._table_listeners[1]
            for key, listenerData in pairs(self.StoredListeners.Table) do
                listeners[key] = listenerData
            end
            self.StoredListeners.Table = {}

            if self.Replica._raw_listeners then
                for _, v in ipairs(self.StoredListeners.Raw) do
                    table.insert(self.Replica._raw_listeners, v)
                end
            end
            self.StoredListeners.Raw = {}

            if self.Replica._child_listeners then
                for id, v in pairs(self.StoredListeners.Child) do
                    self.Replica._child_listeners[id] = v
                end
            end
            self.StoredListeners.Child = {}
        end
    end)
end

function HelperTab:NukeInventoryUI()
    pcall(function()
        local inventory = PlayerGui:FindFirstChild("Inventory", true)
        if inventory then
            local containers = {"Crates", "Accessories", "Items", "ScrollingFrame"}
            for _, name in pairs(containers) do
                local frame = inventory:FindFirstChild(name, true)
                if frame and frame:IsA("ScrollingFrame") then
                    for _, child in pairs(frame:GetChildren()) do
                        if child:IsA("Frame") then 
                            child.Visible = false 
                        end
                    end
                end
            end
        end
    end)
end

function HelperTab:Cleanup()
    if self.AntiLagEnabled then
        self:SetAntiLag(false)
    end
end

return HelperTab
