-- tabs/auto_crates_tab.lua
-- Auto Open Crates Tab + Auto Delete Accessories (Clean Professional)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local Knit = require(ReplicatedStorage.Packages.Knit)
local ReplicaListener = Knit.GetController("ReplicaListener")

local SuccessLoadCrates, CratesInfo = pcall(function() 
    return require(ReplicatedStorage.GameInfo.CratesInfo) 
end)
if not SuccessLoadCrates then CratesInfo = {} end

local AutoCratesTab = {}
AutoCratesTab.__index = AutoCratesTab

-- Auto Delete Configuration
local AUTO_DELETE_CONFIG = {
    MAX_ACCESSORIES = 100,
    SAFE_THRESHOLD = 16,
    BATCH_SIZE = 8,
    EXCEPTION_LIST = {
        ["Meowl Head"] = true,
        ["Ashen Charm"] = true
    }
}

function AutoCratesTab.new(deps)
    local self = setmetatable({}, AutoCratesTab)
    
    self.UIFactory = deps.UIFactory
    self.StateManager = deps.StateManager
    self.InventoryManager = deps.InventoryManager
    self.Utils = deps.Utils
    self.Config = deps.Config
    self.StatusLabel = deps.StatusLabel
    self.InfoLabel = deps.InfoLabel
    
    self.Container = nil
    self.SelectedCrates = {}
    self.CrateCards = {}
    self.IsProcessing = false
    self.ShouldStop = false
    self.LockOverlay = nil
    
    self.FloatingButtons = {}
    
    self.AutoDeleteEnabled = true
    self.TrashNamesList = {}
    
    return self
end

function AutoCratesTab:Init(parent)
    local THEME = self.Config.THEME
    
    self:BuildTrashDatabase()
    
    local header = Instance.new("Frame", parent)
    header.Size = UDim2.new(1, 0, 0, 80)
    header.BackgroundTransparency = 1
    
    self.UIFactory.CreateLabel({
        Parent = header,
        Text = "  AUTO OPEN CRATES", -- เพิ่มเว้นวรรค 2 ที
        Size = UDim2.new(1, -8, 0, 28), -- ปรับความสูงเป็น 28
        Position = UDim2.new(0, 8, 0, 0),
        TextColor = THEME.TextWhite,
        TextSize = 14, -- ปรับขนาดเป็น 14
        Font = Enum.Font.GothamBlack,
        TextXAlign = Enum.TextXAlignment.Left
    })
    
    -- ปรับตำแหน่ง SubHeader นิดหน่อยเพื่อให้รับกับ Header ใหม่
    self.UIFactory.CreateLabel({
        Parent = header,
        Text = "  Select crates and open them automatically",
        Size = UDim2.new(1, -8, 0, 16),
        Position = UDim2.new(0, 8, 0, 28), -- ขยับลงมาที่ Y: 28
        TextColor = THEME.TextDim,
        TextSize = 10,
        Font = Enum.Font.Gotham,
        TextXAlign = Enum.TextXAlignment.Left
    })
    
    self.AccessoryStatusLabel = self.UIFactory.CreateLabel({
        Parent = header,
        Text = "Loading inventory...",
        Size = UDim2.new(1, -8, 0, 20),
        Position = UDim2.new(0, 8, 0, 48),
        TextColor = THEME.TextDim,
        TextSize = 11,
        Font = Enum.Font.GothamMedium,
        TextXAlign = Enum.TextXAlignment.Left
    })
    
    self.Container = self.UIFactory.CreateScrollingFrame({
        Parent = parent,
        Size = UDim2.new(1, 0, 1, -84),
        Position = UDim2.new(0, 0, 0, 82)
    })
    
    self.Container.ScrollBarThickness = 4
    self.Container.AutomaticCanvasSize = Enum.AutomaticSize.Y
    self.Container.CanvasSize = UDim2.new(0, 0, 0, 0)
    
    if self.Container:FindFirstChild("UIListLayout") then
        self.Container.UIListLayout:Destroy()
    end
    
    local padding = self.Container:FindFirstChild("UIPadding") or Instance.new("UIPadding", self.Container)
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingLeft = UDim.new(0, 4)
    padding.PaddingRight = UDim.new(0, 4)

    padding.PaddingBottom = UDim.new(0, 75)
    
    local layout = self.Container:FindFirstChild("UIGridLayout") or Instance.new("UIGridLayout", self.Container)
    layout.CellSize = UDim2.new(0, 90, 0, 100)
    layout.CellPadding = UDim2.new(0, 6, 0, 6)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    
    self:CreateFloatingButtons(parent)
    
    self:RefreshInventory()
    self:UpdateInfoLabel()
    self:UpdateSelectButton()
    self:UpdateAccessoryStatus()
    
    self.LockOverlay = Instance.new("Frame", parent)
    self.LockOverlay.Name = "LockOverlay"
    self.LockOverlay.Size = UDim2.new(1, 0, 1, -84)
    self.LockOverlay.Position = UDim2.new(0, 0, 0, 82)
    self.LockOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    self.LockOverlay.BackgroundTransparency = 0.6
    self.LockOverlay.BorderSizePixel = 0
    self.LockOverlay.ZIndex = 1000
    self.LockOverlay.Visible = false
    
    -- เก็บ LockLabel ไว้ใช้งานตอน StartAutoOpen
    self.LockLabel = self.UIFactory.CreateLabel({
        Parent = self.LockOverlay,
        Text = "[LOCKED]\nProcessing crates...",
        Size = UDim2.new(1, 0, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        TextColor = THEME.TextWhite,
        TextSize = 16,
        Font = Enum.Font.GothamBold
    })
    self.LockLabel.ZIndex = 1001
    self.LockLabel.TextWrapped = true
    
    task.spawn(function()
        while self.Container and self.Container.Parent do
            self:UpdateAccessoryStatus()
            task.wait(2)
        end
    end)
end

function AutoCratesTab:CreateFloatingButtons(parent)
    local THEME = self.Config.THEME
    
    local spacing = 6
    local btnWidth = 110
    local btnHeight = 32
    local startX = -8
    
    -- 1. Select All Button
    self.SelectAllBtn = self.UIFactory.CreateButton({
        Size = UDim2.new(0, btnWidth, 0, btnHeight),
        Position = UDim2.new(1, startX - btnWidth, 1, -38),
        Text = "SELECT ALL",
        BgColor = THEME.AccentBlue,  -- ✅ เปลี่ยนจาก CardBg
        TextColor = THEME.TextWhite,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        Parent = parent,
        OnClick = function() self:ToggleSelectAll() end
    })
    self.SelectAllBtn.ZIndex = 1500
    
    self.AutoOpenBtn = self.UIFactory.CreateButton({
        Size = UDim2.new(0, btnWidth + 10, 0, btnHeight),
        Position = UDim2.new(1, startX - btnWidth*2 - spacing - 10, 1, -38),
        Text = "START OPEN",
        BgColor = THEME.AccentBlue,  -- ✅ เปลี่ยนจาก CardBg
        TextColor = THEME.TextWhite,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        Parent = parent,
        OnClick = function() self:ToggleAutoOpen() end
    })
    self.AutoOpenBtn.ZIndex = 1500

    self.AutoDeleteBtn = self.UIFactory.CreateButton({
        Size = UDim2.new(0, btnWidth + 20, 0, btnHeight),
        Position = UDim2.new(1, startX - btnWidth*3 - spacing*2 - 30, 1, -38),
        Text = "AUTO DELETE: ON", 
        BgColor = THEME.AccentBlue,  -- ✅ เปลี่ยนจาก CardBg
        TextColor = THEME.TextWhite,
        TextSize = 11,
        Font = Enum.Font.GothamBold,
        Parent = parent,
        OnClick = function() self:ToggleAutoDelete() end
    })
    self.AutoDeleteBtn.ZIndex = 1500
end

function AutoCratesTab:BuildTrashDatabase()
    self.TrashNamesList = {}
    
    for crateName, crateData in pairs(CratesInfo) do
        if crateData.Rewards then
            local r = crateData.Rewards
            
            if r.ItemOne and r.ItemOne.Name then 
                self.TrashNamesList[r.ItemOne.Name] = true 
            end
            if r.ItemTwo and r.ItemTwo.Name then 
                self.TrashNamesList[r.ItemTwo.Name] = true 
            end
            if r.ItemThree and r.ItemThree.Name then 
                self.TrashNamesList[r.ItemThree.Name] = true 
            end
            if r.ItemFour and r.ItemFour.Name then 
                self.TrashNamesList[r.ItemFour.Name] = true 
            end
        end
    end
    
    for name, _ in pairs(AUTO_DELETE_CONFIG.EXCEPTION_LIST) do
        if self.TrashNamesList[name] then
            self.TrashNamesList[name] = nil
        end
    end
end

function AutoCratesTab:GetAccessorySpace()
    local replica = ReplicaListener:GetReplica()
    if not replica or not replica.Data then return 0, 0 end
    
    local accessories = replica.Data.AccessoryService.Accessories or {}
    local count = 0
    for _ in pairs(accessories) do count = count + 1 end
    
    local space = AUTO_DELETE_CONFIG.MAX_ACCESSORIES - count
    return count, space
end

function AutoCratesTab:UpdateAccessoryStatus()
    if not self.AccessoryStatusLabel then return end
    
    local count, space = self:GetAccessorySpace()
    local THEME = self.Config.THEME
    
    local color = THEME.TextDim
    if space <= AUTO_DELETE_CONFIG.SAFE_THRESHOLD then
        color = THEME.Fail
    elseif space <= 50 then
        color = THEME.Warning
    else
        color = THEME.TextGray
    end
    
    self.AccessoryStatusLabel.Text = string.format(
        "Accessories: %d/%d | Space: %d",
        count,
        AUTO_DELETE_CONFIG.MAX_ACCESSORIES,
        space
    )
    self.AccessoryStatusLabel.TextColor3 = color
end

function AutoCratesTab:ToggleAutoDelete()
    if self.IsProcessing then return end
    
    self.AutoDeleteEnabled = not self.AutoDeleteEnabled
    local THEME = self.Config.THEME
    
    if self.AutoDeleteEnabled then
        self.AutoDeleteBtn.Text = "AUTO DELETE: ON"
        self.AutoDeleteBtn.BackgroundColor3 = THEME.AccentBlue  -- ✅ สีฟ้า
    else
        self.AutoDeleteBtn.Text = "AUTO DELETE: OFF"
        self.AutoDeleteBtn.BackgroundColor3 = THEME.Fail  -- ✅ สีแดง
    end
end

function AutoCratesTab:AutoDeleteAccessories()
    local replica = ReplicaListener:GetReplica()
    if not replica or not replica.Data then return false end
    
    local accessories = replica.Data.AccessoryService.Accessories
    local equippedList = replica.Data.AccessoryService.EquippedAccessories
    
    local equippedSet = {}
    if equippedList then 
        for _, u in pairs(equippedList) do 
            equippedSet[u] = true 
        end 
    end
    
    local toDeleteList = {}
    
    for uuid, item in pairs(accessories) do
        local n = item.Name
        local shouldDelete = false
        
        if self.TrashNamesList[n] 
            and not AUTO_DELETE_CONFIG.EXCEPTION_LIST[n] 
            and not equippedSet[uuid] 
            and not item.Scroll then
            shouldDelete = true
        end

        if shouldDelete then
            table.insert(toDeleteList, uuid)
        end
    end
    
    if #toDeleteList == 0 then return true end
    
    local THEME = self.Config.THEME
    self.StateManager:SetStatus(
        string.format("[DELETING] %d accessories...", #toDeleteList),
        THEME.Warning,
        self.StatusLabel
    )
    
    local success, err = pcall(function()
        return ReplicatedStorage.Packages.Knit.Services.AccessoryService.RF.Delete:InvokeServer(toDeleteList)
    end)
    
    if success then
        self.StateManager:SetStatus(
            string.format("[DELETED] %d accessories", #toDeleteList),
            THEME.Success,
            self.StatusLabel
        )
        return true
    else
        self.StateManager:SetStatus(
            "[ERROR] Delete failed: " .. tostring(err),
            THEME.Fail,
            self.StatusLabel
        )
        return false
    end
end

function AutoCratesTab:RefreshInventory()
    for _, child in pairs(self.Container:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    self.CrateCards = {}
    
    local replica = ReplicaListener:GetReplica()
    local playerData = replica and replica.Data
    local inventoryCrates = (playerData and playerData.CratesService and playerData.CratesService.Crates) or {}
    
    local cratesList = {}
    for crateName, amount in pairs(inventoryCrates) do
        if amount > 0 then
            local info = CratesInfo[crateName]
            local image = info and info.Image or "0"
            table.insert(cratesList, {
                Name = crateName,
                Amount = amount,
                Image = image
            })
        end
    end
    
    table.sort(cratesList, function(a, b) return a.Name < b.Name end)
    
    for _, crate in ipairs(cratesList) do
        self:CreateCrateCard(crate)
    end
end

function AutoCratesTab:CreateCrateCard(crate)
    local THEME = self.Config.THEME
    local isSelected = self.SelectedCrates[crate.Name] ~= nil
    
    local currentSelectedAmount = self.SelectedCrates[crate.Name]
    local defaultAmount = currentSelectedAmount or math.min(500, crate.Amount)
    
    local Card = Instance.new("Frame", self.Container)
    Card.Name = crate.Name
    Card.BackgroundColor3 = THEME.CardBg
    Card.BackgroundTransparency = 0.2
    Card.BorderSizePixel = 0
    
    self.UIFactory.AddCorner(Card, 10)
    
    local Stroke = Instance.new("UIStroke", Card)
    Stroke.Thickness = 2
    Stroke.Color = THEME.AccentBlue
    Stroke.Transparency = 0.4
    Stroke.Enabled = isSelected  -- ✅ ถ้าไม่ select จะไม่มีกรอบ
    
    local CheckBox = Instance.new("Frame", Card)
    CheckBox.Size = UDim2.new(0, 16, 0, 16)
    CheckBox.Position = UDim2.new(0, 4, 0, 4)
    CheckBox.BackgroundColor3 = isSelected and THEME.AccentBlue or Color3.fromRGB(30, 30, 35)
    CheckBox.BorderSizePixel = 0
    CheckBox.ZIndex = 15
    
    self.UIFactory.AddCorner(CheckBox, 4)
    
    
    local CheckMark = self.UIFactory.CreateLabel({
        Parent = CheckBox,
        Text = isSelected and "✓" or "",
        Size = UDim2.new(1, 0, 1, 0),
        TextColor = THEME.TextWhite,
        TextSize = 10,
        Font = Enum.Font.GothamBold
    })
    CheckMark.ZIndex = 16
    
    local TotalLabel = self.UIFactory.CreateLabel({
        Parent = Card,
        Text = "x" .. tostring(crate.Amount),
        Size = UDim2.new(0, 40, 0, 20),
        Position = UDim2.new(1, -44, 0, 2),
        TextColor = Color3.fromRGB(180, 180, 180),
        TextSize = 11,
        Font = Enum.Font.GothamBold
    })
    TotalLabel.TextStrokeTransparency = 0.5
    TotalLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    TotalLabel.ZIndex = 20
    
    local Image = Instance.new("ImageLabel", Card)
    Image.Size = UDim2.new(0, 60, 0, 60)
    Image.Position = UDim2.new(0.5, -30, 0.5, -35)
    Image.BackgroundTransparency = 1
    local imgId = tostring(crate.Image)
    if not imgId:find("rbxassetid://") then imgId = "rbxassetid://" .. imgId end
    Image.Image = imgId
    Image.ScaleType = Enum.ScaleType.Fit
    
    local InputContainer = Instance.new("Frame", Card)
    InputContainer.Size = UDim2.new(1, -10, 0, 18)
    InputContainer.Position = UDim2.new(0, 5, 1, -22)
    InputContainer.BackgroundColor3 = Color3.fromRGB(18, 20, 25)
    InputContainer.BorderSizePixel = 0
    
    self.UIFactory.AddCorner(InputContainer, 4)
    
    
    local AmountInput = Instance.new("TextBox", InputContainer)
    AmountInput.Size = UDim2.new(1, -8, 1, -2)
    AmountInput.Position = UDim2.new(0, 4, 0, 1)
    AmountInput.BackgroundTransparency = 1
    AmountInput.Text = tostring(defaultAmount)
    AmountInput.TextColor3 = Color3.fromRGB(255, 255, 255)
    AmountInput.Font = Enum.Font.GothamBold
    AmountInput.TextSize = 11
    AmountInput.ClearTextOnFocus = false
    AmountInput.PlaceholderText = ""
    AmountInput.TextXAlignment = Enum.TextXAlignment.Center
    AmountInput.TextStrokeTransparency = 0.7
    AmountInput.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    
    local isFirstFocus = true
    local hasUserEdited = false
    local originalDefaultValue = tostring(defaultAmount)
    
    self.Utils.SanitizeNumberInput(AmountInput, crate.Amount, 1)
    
    local ClickBtn = Instance.new("TextButton", Card)
    ClickBtn.Size = UDim2.new(1, 0, 0, 85)
    ClickBtn.Position = UDim2.new(0, 0, 0, 0)
    ClickBtn.BackgroundTransparency = 1
    ClickBtn.Text = ""
    ClickBtn.ZIndex = 5
    
    ClickBtn.MouseButton1Click:Connect(function()
        if self.IsProcessing then return end
        
        local amount = tonumber(AmountInput.Text) or math.min(500, crate.Amount)
        
        if amount <= 0 then
            amount = math.min(500, crate.Amount)
            AmountInput.Text = tostring(amount)
        elseif amount > crate.Amount then
            amount = crate.Amount
            AmountInput.Text = tostring(amount)
        end
        
        if self.SelectedCrates[crate.Name] then
            -- ✅ ยกเลิกการเลือก
            self.SelectedCrates[crate.Name] = nil
            Stroke.Enabled = false
            CheckBox.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
            CheckMark.Text = ""
        else
            -- ✅ เลือก
            self.SelectedCrates[crate.Name] = amount
            Stroke.Enabled = true
            Stroke.Color = THEME.AccentBlue
            Stroke.Thickness = 2
            CheckBox.BackgroundColor3 = THEME.AccentBlue
            CheckMark.Text = "✓"
        end
        
        self:UpdateInfoLabel()
        self:UpdateSelectButton()  -- ✅ ต้องมีบรรทัดนี้!
    end)
    
    AmountInput.Focused:Connect(function()
        if self.IsProcessing then
            AmountInput:ReleaseFocus()
            return
        end
        
        -- ✅ ล้างค่าครั้งแรกที่คลิก
        if isFirstFocus then
            AmountInput.Text = ""
            isFirstFocus = false
        end
    end)

    AmountInput.FocusLost:Connect(function()
        local currentText = AmountInput.Text
        
        -- ถ้าไม่ได้แก้ไขหรือช่องว่าง → คืนค่าเริ่มต้น
        if currentText == "" or not hasUserEdited then
            AmountInput.Text = originalDefaultValue
            isFirstFocus = true
            hasUserEdited = false
        else
            hasUserEdited = true
        end
    end)

    AmountInput:GetPropertyChangedSignal("Text"):Connect(function()
        if self.IsProcessing then return end
        
        -- ✅ เพิ่มการตรวจจับการพิมพ์
        if not isFirstFocus and AmountInput.Text ~= originalDefaultValue and AmountInput.Text ~= "" then
            hasUserEdited = true
        end
        
        local amount = tonumber(AmountInput.Text) or 0
        
        if amount > crate.Amount then
            AmountInput.Text = tostring(crate.Amount)
            amount = crate.Amount
        elseif amount < 0 then
            AmountInput.Text = "1"
            amount = 1
        end
        
        if self.SelectedCrates[crate.Name] and amount > 0 then
            self.SelectedCrates[crate.Name] = amount
            self:UpdateInfoLabel()
        end
    end)
    
    self.CrateCards[crate.Name] = {
        CheckBox = CheckBox,
        CheckMark = CheckMark,
        Input = AmountInput,
        Stroke = Stroke,
        MaxAmount = crate.Amount,
        DefaultAmount = defaultAmount
    }
end

function AutoCratesTab:ToggleSelectAll()
    if self.IsProcessing then return end
    
    if self:AreAllSelected() then
        self:DeselectAll()
    else
        self:SelectAll()
    end
    self:UpdateSelectButton()
end

function AutoCratesTab:AreAllSelected()
    local totalCrates = 0
    local selectedCount = 0
    
    for _, data in pairs(self.CrateCards) do
        totalCrates = totalCrates + 1
        if self.SelectedCrates[_] then
            selectedCount = selectedCount + 1
        end
    end
    
    return totalCrates > 0 and totalCrates == selectedCount
end

function AutoCratesTab:UpdateSelectButton()
    local THEME = self.Config.THEME
    
    if self:AreAllSelected() then
        self.SelectAllBtn.Text = "UNSELECT ALL"
        self.SelectAllBtn.BackgroundColor3 = THEME.Fail  -- ✅ สีแดง
    else
        self.SelectAllBtn.Text = "SELECT ALL"
        self.SelectAllBtn.BackgroundColor3 = THEME.AccentBlue  -- ✅ สีฟ้า
    end

    -- ปรับความจางเมื่อกำลังทำงาน
    if self.IsProcessing then
        self.SelectAllBtn.TextTransparency = 0.6
        self.SelectAllBtn.BackgroundTransparency = 0.5  -- ✅ เพิ่มความจาง
    else
        self.SelectAllBtn.TextTransparency = 0
        self.SelectAllBtn.BackgroundTransparency = 0
    end
end

function AutoCratesTab:SelectAll()
    for crateName, data in pairs(self.CrateCards) do
        local amount = tonumber(data.Input.Text) or data.DefaultAmount
        if amount > 0 and amount <= data.MaxAmount then
            self.SelectedCrates[crateName] = amount
            data.Stroke.Enabled = true  -- ✅ แสดงกรอบ
            data.Stroke.Color = self.Config.THEME.AccentBlue
            data.Stroke.Thickness = 2
            data.CheckBox.BackgroundColor3 = self.Config.THEME.AccentBlue
            data.CheckMark.Text = "✓"
        end
    end
    self:UpdateInfoLabel()
    self:UpdateSelectButton()
end

function AutoCratesTab:DeselectAll()
    self.SelectedCrates = {}
    for _, data in pairs(self.CrateCards) do
        data.Stroke.Enabled = false  -- ✅ ซ่อนกรอบ
        data.CheckBox.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
        data.CheckMark.Text = ""
    end
    self:UpdateInfoLabel()
    self:UpdateSelectButton()
end

function AutoCratesTab:UpdateInfoLabel()
    if not self.InfoLabel then return end
    
    local count = 0
    local total = 0
    for crateName, amount in pairs(self.SelectedCrates) do
        count = count + 1
        total = total + amount
    end
    
    if count > 0 then
        self.InfoLabel.Text = string.format("Selected: %d types | Total: %d crates", count, total)
        self.InfoLabel.TextColor3 = self.Config.THEME.AccentBlue
    else
        self.InfoLabel.Text = ""
    end
end

function AutoCratesTab:ToggleAutoOpen()
    if self.IsProcessing then
        self.ShouldStop = true
        -- สถานะกำลังหยุด
        self.AutoOpenBtn.Text = "STOPPING..."
        self.AutoOpenBtn.TextColor3 = self.Config.THEME.TextWhite
        
        if self.AutoOpenBtnStroke then
            self.AutoOpenBtnStroke.Color = self.Config.THEME.Fail 
        end
    else
        self:StartAutoOpen()
    end
end

function AutoCratesTab:StartAutoOpen()
    if self.IsProcessing then return end
    
    local selectedList = {}
    for crateName, amount in pairs(self.SelectedCrates) do
        if amount > 0 then
            table.insert(selectedList, {Name = crateName, Amount = amount})
        end
    end
    
    if #selectedList == 0 then
        self.StateManager:SetStatus("[ERROR] No crates selected", self.Config.THEME.Warning, self.StatusLabel)
        return
    end
    
    self.IsProcessing = true
    self.ShouldStop = false
    
    local THEME = self.Config.THEME
    
    self.AutoOpenBtn.Text = "STOP OPEN"
    self.AutoOpenBtn.TextColor3 = THEME.TextWhite
    self.AutoOpenBtn.BackgroundColor3 = THEME.Fail  -- ✅ สีแดง
    
    if self.InfoLabel then
        self.InfoLabel.Text = "" 
    end
    
    if self.LockOverlay then
        self.LockOverlay.Visible = true
        if self.LockLabel then
             self.LockLabel.Text = "[STARTING]\nPreparing to open..."
             self.LockLabel.TextColor3 = THEME.TextWhite
        end
    end
    
    self.SelectAllBtn.TextTransparency = 0.6
    
    task.spawn(function()
        self:ProcessCrateOpening(selectedList)
    end)
end

function AutoCratesTab:ProcessCrateOpening(selectedList)
    local THEME = self.Config.THEME
    local CratesService = ReplicatedStorage.Packages.Knit.Services.CratesService
    local UseCrateRemote = CratesService.RF:FindFirstChild("UseCrateItem")
    
    if not UseCrateRemote then
        self.StateManager:SetStatus("[ERROR] Remote not found", THEME.Fail, self.StatusLabel)
        self:ResetButton()
        return
    end
    
    local totalOpened = 0
    local totalTypes = #selectedList
    
    for typeIndex, crateData in ipairs(selectedList) do
        if self.ShouldStop then
            self.StateManager:SetStatus("[STOPPED] Stopped by user", THEME.Warning, self.StatusLabel)
            break
        end
        
        local crateName = crateData.Name
        local targetAmount = crateData.Amount
        local opened = 0
        
        local cardData = self.CrateCards[crateName]
        if not cardData then continue end
        
        self.StateManager:SetStatus(
            string.format("[OPENING] %s... (%d/%d)", crateName, typeIndex, totalTypes),
            THEME.AccentBlue,
            self.StatusLabel
        )
        
        while opened < targetAmount do
            if self.ShouldStop then break end
            
            local count, space = self:GetAccessorySpace()
            self:UpdateAccessoryStatus()
            
            if space <= AUTO_DELETE_CONFIG.SAFE_THRESHOLD then
                if self.AutoDeleteEnabled then
                    self.StateManager:SetStatus(
                        string.format("[LOW SPACE] %d remaining - Deleting...", space),
                        THEME.Warning,
                        self.StatusLabel
                    )
                    
                    local deleteSuccess = self:AutoDeleteAccessories()
                    if deleteSuccess then
                        task.wait(0.5)
                        count, space = self:GetAccessorySpace()
                        self:UpdateAccessoryStatus()
                    else
                        self.StateManager:SetStatus("[ERROR] Delete failed - Stopping", THEME.Fail, self.StatusLabel)
                        self.ShouldStop = true
                        break
                    end
                else
                    self.StateManager:SetStatus(
                        string.format("[FULL] Inventory full (%d/%d)", count, AUTO_DELETE_CONFIG.MAX_ACCESSORIES),
                        THEME.Fail,
                        self.StatusLabel
                    )
                    self.ShouldStop = true
                    break
                end
            end
            
            count, space = self:GetAccessorySpace()
            if space < AUTO_DELETE_CONFIG.BATCH_SIZE then
                self.StateManager:SetStatus(
                    string.format("[ERROR] Not enough space (%d)", space),
                    THEME.Fail,
                    self.StatusLabel
                )
                self.ShouldStop = true
                break
            end
            
            local remaining = targetAmount - opened
            local batchSize = math.min(AUTO_DELETE_CONFIG.BATCH_SIZE, remaining)
            
            local success, err = pcall(function()
                return UseCrateRemote:InvokeServer(crateName, batchSize)
            end)
            
            if success then
                opened = opened + batchSize
                totalOpened = totalOpened + batchSize
                
                local remainingAmount = targetAmount - opened
                if cardData.Input then
                    cardData.Input.Text = tostring(remainingAmount)
                end
                
                if self.LockLabel then
                    local delStatus = self.AutoDeleteEnabled and "ON" or "OFF"
                    
                    self.LockLabel.Text = string.format(
                        "[OPENING] %s\n\n" ..
                        "Progress: %d / %d\n" ..
                        "Total Opened: %d\n\n" ..
                        "(Auto Delete: %s)",
                        crateName,         
                        opened,             
                        targetAmount,       
                        totalOpened,        
                        delStatus           
                    )
                    
                    -- เปลี่ยนสีตัวอักษรถ้าเปิด Auto Delete ให้เด่นหน่อย
                    if self.AutoDeleteEnabled then
                        self.LockLabel.TextColor3 = THEME.Warning
                    else
                        self.LockLabel.TextColor3 = THEME.TextWhite
                    end
                end
                
                local randomWait = math.random(100, 220) / 100 
                task.wait(randomWait)
            else
                warn("Failed to open " .. crateName .. ": " .. tostring(err))
                self.StateManager:SetStatus(
                    string.format("[ERROR] %s: %s", crateName, tostring(err)),
                    THEME.Warning,
                    self.StatusLabel
                )
                task.wait(2)
                break
            end
        end
        
        local remaining = targetAmount - opened

        if remaining > 0 then
            self.SelectedCrates[crateName] = remaining
            
            if cardData.Input then
                cardData.Input.Text = tostring(remaining)
            end
        else
            self.SelectedCrates[crateName] = nil
            
            local THEME = self.Config.THEME
            if cardData.Stroke then 
                cardData.Stroke.Color = THEME.GlassStroke 
                cardData.Stroke.Thickness = 1
            end
            if cardData.CheckBox then 
                cardData.CheckBox.BackgroundColor3 = Color3.fromRGB(30, 30, 35) 
            end
            if cardData.CheckMark then 
                cardData.CheckMark.Text = "" 
            end
            if cardData.CheckBoxStroke then 
                cardData.CheckBoxStroke.Color = THEME.GlassStroke 
            end
            
            if cardData.Input then
                cardData.Input.Text = tostring(cardData.DefaultAmount or 1)
            end
        end

        task.wait(0.2)
    end
    
    if self.ShouldStop then
        self.StateManager:SetStatus(
            string.format("[STOPPED] Opened %d crates", totalOpened),
            THEME.Warning,
            self.StatusLabel
        )
    else
        self.StateManager:SetStatus(
            string.format("[COMPLETE] Opened %d crates", totalOpened),
            THEME.Success,
            self.StatusLabel
        )
    end
    
    self:ResetButton()
    
    task.wait(1)
    self:RefreshInventory()
    self:UpdateInfoLabel()
    self:UpdateSelectButton()
    self:UpdateAccessoryStatus()
end

function AutoCratesTab:ResetButton()
    self.IsProcessing = false
    self.ShouldStop = false
    local THEME = self.Config.THEME
    
    self.AutoOpenBtn.Text = "START OPEN"
    self.AutoOpenBtn.TextColor3 = THEME.TextWhite
    self.AutoOpenBtn.BackgroundColor3 = THEME.AccentBlue  -- ✅ กลับเป็นสีฟ้า
    
    if self.LockOverlay then
        self.LockOverlay.Visible = false
    end
    
    self:UpdateSelectButton()
end

return AutoCratesTab
