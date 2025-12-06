--[[
    🔥 The Forge Script - النسخة المدمجة
    
    هذا السكربت يدمج جميع أجزاء السكربت الأصلي (Loader, Shared, Quests) في ملف واحد.
    
    الاستخدام: قم بتشغيل هذا السكربت في منفذ (Executor) اللعبة.
--]]

----------------------------------------------------------------
-- 📦 أدوات مساعدة مشتركة (Shared Utilities)
----------------------------------------------------------------

_G.Shared = _G.Shared or {}
local Shared = _G.Shared

-- 🎮 الخدمات (Services)
Shared.Services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    VirtualInputManager = game:GetService("VirtualInputManager"),
    GuiService = game:GetService("GuiService"),
    Workspace = game:GetService("Workspace"),
}

local Services = Shared.Services
local player = Services.Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 🔧 إدارة الحالة (State Management)
Shared.State = {
    currentTarget = nil,
    targetDestroyed = false,
    hpWatchConn = nil,
    noclipConn = nil,
    moveConn = nil,
    positionLockConn = nil,
    bodyVelocity = nil,
    bodyGyro = nil,
}

function Shared.cleanupState()
    local State = Shared.State
    if State.hpWatchConn then State.hpWatchConn:Disconnect() State.hpWatchConn = nil end
    if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.positionLockConn then State.positionLockConn:Disconnect() State.positionLockConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    State.currentTarget = nil
    State.targetDestroyed = false
end

-- 🔓 استعادة الاصطدام (Collision Restore)
function Shared.restoreCollisions()
    local char = player.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = true
        end
    end
end

-- 👻 نظام إزالة الاصطدام (Noclip System)
function Shared.enableNoclip()
    local State = Shared.State
    if State.noclipConn then return end
    
    local char = player.Character
    if not char then return end
    
    State.noclipConn = Services.RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
            return
        end
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

function Shared.disableNoclip()
    local State = Shared.State
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
    Shared.restoreCollisions()
end

-- 🚀 الحركة السلسة (BodyVelocity + BodyGyro)
function Shared.smoothMoveTo(targetPos, stopDistance, moveSpeed, callback)
    local State = Shared.State
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    stopDistance = stopDistance or 2
    moveSpeed = moveSpeed or 25
    
    -- تنظيف الحركة السابقة
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    Shared.enableNoclip()
    
    -- إنشاء BodyVelocity
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Velocity = Vector3.zero
    bv.Parent = hrp
    State.bodyVelocity = bv
    
    -- إنشاء BodyGyro
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.D = 500
    bg.Parent = hrp
    State.bodyGyro = bg
    
    print(string.format("   🚀 التحرك نحو (%.1f, %.1f, %.1f)...", targetPos.X, targetPos.Y, targetPos.Z))
    
    local reachedTarget = false
    
    State.moveConn = Services.RunService.Heartbeat:Connect(function()
        if reachedTarget then return end
        
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv and bv.Parent then bv:Destroy() end
            if bg and bg.Parent then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end
        
        local currentPos = hrp.Position
        local direction = (targetPos - currentPos)
        local distance = direction.Magnitude
        
        if distance < stopDistance then
            print(string.format("   ✅ تم الوصول إلى الهدف! (%.1f مسافة)", distance))
            
            reachedTarget = true
            
            bv.Velocity = Vector3.zero
            hrp.Velocity = Vector3.zero
            hrp.AssemblyLinearVelocity = Vector3.zero
            
            task.wait(0.1)
            
            if bv and bv.Parent then bv:Destroy() end
            if bg and bg.Parent then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            
            if callback then callback() end
            return
        end
        
        local speed = math.min(moveSpeed, distance * 10)
        local velocity = direction.Unit * speed
        
        bv.Velocity = velocity
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
    end)
    
    return true
end

-- 🔒 قفل الموقع (الاستلقاء)
function Shared.lockPositionLayingDown(targetPos, layingAngle)
    local State = Shared.State
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    layingAngle = layingAngle or 90
    
    if State.positionLockConn then
        State.positionLockConn:Disconnect()
        State.positionLockConn = nil
    end
    
    local angle = math.rad(layingAngle)
    local baseCFrame = CFrame.new(targetPos)
    local layingCFrame = baseCFrame * CFrame.Angles(angle, 0, 0)
    
    State.positionLockConn = Services.RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.positionLockConn then
                State.positionLockConn:Disconnect()
                State.positionLockConn = nil
            end
            return
        end
        
        hrp.CFrame = layingCFrame
        hrp.Velocity = Vector3.zero
        hrp.AssemblyLinearVelocity = Vector3.zero
    end)
    
    print("   🔒 تم قفل الموقع (وضع الاستلقاء)")
end

function Shared.unlockPosition()
    local State = Shared.State
    if State.positionLockConn then
        State.positionLockConn:Disconnect()
        State.positionLockConn = nil
        print("   🔓 تم إلغاء قفل الموقع")
    end
end

function Shared.SoftUnlockPosition()
    Shared.unlockPosition()
end

-- ⌨️ إدخال لوحة المفاتيح (Keyboard Input)
Shared.HOTKEY_MAP = {
    ["1"] = Enum.KeyCode.One, ["2"] = Enum.KeyCode.Two, ["3"] = Enum.KeyCode.Three,
    ["4"] = Enum.KeyCode.Four, ["5"] = Enum.KeyCode.Five, ["6"] = Enum.KeyCode.Six,
    ["7"] = Enum.KeyCode.Seven, ["8"] = Enum.KeyCode.Eight, ["9"] = Enum.KeyCode.Nine, 
    ["0"] = Enum.KeyCode.Zero
}

function Shared.pressKey(keyCode)
    if not keyCode then return end
    Services.VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait(0.05)
    Services.VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

-- 🔧 مساعدات الأدوات (Tool Helpers)
function Shared.findPickaxeSlotKey()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end
    local hotbar = gui:FindFirstChild("BackpackGui") 
        and gui.BackpackGui:FindFirstChild("Backpack") 
        and gui.BackpackGui.Backpack:FindFirstChild("Hotbar")
    if hotbar then
        for _, slotFrame in ipairs(hotbar:GetChildren()) do
            local frame = slotFrame:FindFirstChild("Frame")
            local label = frame and frame:FindFirstChild("ToolName")
            if label and label:IsA("TextLabel") and string.find(label.Text, "Pickaxe") then
                return Shared.HOTKEY_MAP[slotFrame.Name]
            end
        end
    end
    return nil
end

function Shared.findWeaponSlotKey()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil, nil end
    local hotbar = gui:FindFirstChild("BackpackGui") 
        and gui.BackpackGui:FindFirstChild("Backpack") 
        and gui.BackpackGui.Backpack:FindFirstChild("Hotbar")
    if hotbar then
        for _, slotFrame in ipairs(hotbar:GetChildren()) do
            local frame = slotFrame:FindFirstChild("Frame")
            local label = frame and frame:FindFirstChild("ToolName")
            if label and label:IsA("TextLabel") and not string.find(label.Text, "Pickaxe") and label.Text ~= "" then
                return Shared.HOTKEY_MAP[slotFrame.Name], label.Text
            end
        end
    end
    return nil, nil
end

-- 📊 مساعدات نقاط الحياة (HP Helpers)
function Shared.getRockHP(rock)
    if not rock or not rock.Parent then return 0 end
    local success, result = pcall(function()
        return rock:GetAttribute("Health") or 0
    end)
    return success and result or 0
end

function Shared.isRockValid(rock)
    if not rock or not rock.Parent then return false end
    if not rock:FindFirstChildWhichIsA("BasePart") then return false end
    return Shared.getRockHP(rock) > 0
end

function Shared.getZombieHP(zombie)
    if not zombie or not zombie.Parent then return 0 end
    local humanoid = zombie:FindFirstChild("Humanoid")
    if humanoid then return humanoid.Health or 0 end
    return 0
end

function Shared.isZombieValid(zombie)
    if not zombie or not zombie.Parent then return false end
    return Shared.getZombieHP(zombie) > 0
end

-- 📍 مساعدات الموقع (Position Helpers)
function Shared.getRockUndergroundPosition(rockModel, offset)
    offset = offset or 4
    if not rockModel or not rockModel.Parent then return nil end
    
    local pivotCFrame = nil
    pcall(function()
        if rockModel.GetPivot then
            pivotCFrame = rockModel:GetPivot()
        elseif rockModel.WorldPivot then
            pivotCFrame = rockModel.WorldPivot
        end
    end)
    
    if pivotCFrame then
        local pos = pivotCFrame.Position
        return Vector3.new(pos.X, pos.Y - offset, pos.Z)
    end
    
    if rockModel.PrimaryPart then
        local pos = rockModel.PrimaryPart.Position
        return Vector3.new(pos.X, pos.Y - offset, pos.Z)
    end
    
    local part = rockModel:FindFirstChildWhichIsA("BasePart")
    if part then
        local pos = part.Position
        return Vector3.new(pos.X, pos.Y - offset, pos.Z)
    end
    
    return nil
end

function Shared.getZombieUndergroundPosition(zombieModel, offset)
    offset = offset or 5
    if not zombieModel or not zombieModel.Parent then return nil end
    
    local hrp = zombieModel:FindFirstChild("HumanoidRootPart")
    if hrp then
        local pos = hrp.Position
        return Vector3.new(pos.X, pos.Y - offset, pos.Z)
    end
    
    return nil
end

-- ⚠️ فحص الأخطاء (Error Checking)
function Shared.checkMiningError()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return false end
    local notif = gui:FindFirstChild("Notifications")
    if notif and notif:FindFirstChild("Screen") and notif.Screen:FindFirstChild("NotificationsFrame") then
        for _, child in ipairs(notif.Screen.NotificationsFrame:GetChildren()) do
            local lbl = child:FindFirstChild("TextLabel", true)
            if lbl and string.find(lbl.Text, "Someone else is already mining") then 
                return true 
            end
        end
    end
    return false
end

-- 📋 مساعدات المهام (Quest Helpers)
function Shared.getQuestObjectives(questName)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil, nil end
    
    local list = gui:FindFirstChild("Main") 
        and gui.Main:FindFirstChild("Screen") 
        and gui.Main.Screen:FindFirstChild("Quests") 
        and gui.Main.Screen.Quests:FindFirstChild("List")
    if not list then return nil, nil end
    
    local questID = nil
    for _, child in ipairs(list:GetChildren()) do
        local id = string.match(child.Name, "^Introduction(%d+)Title$")
        if id and child:FindFirstChild("Frame") and child.Frame:FindFirstChild("TextLabel") then
            if child.Frame.TextLabel.Text == questName then
                questID = id
                break
            end
        end
    end
    
    if not questID then return nil, nil end
    
    local objList = list:FindFirstChild("Introduction" .. questID .. "List")
    return questID, objList
end

function Shared.isObjectiveComplete(item)
    if not item then return false end
    local check = item:FindFirstChild("Main") 
        and item.Main:FindFirstChild("Frame") 
        and item.Main.Frame:FindFirstChild("Check")
    return check and check.Visible
end

function Shared.getObjectiveText(item)
    local lbl = item:FindFirstChild("Main") and item.Main:FindFirstChild("TextLabel")
    return lbl and lbl.Text or ""
end

function Shared.isQuestComplete(questName)
    local questID, objList = Shared.getQuestObjectives(questName)
    if not questID or not objList then return true end
    
    for _, item in ipairs(objList:GetChildren()) do
        if item:IsA("Frame") and tonumber(item.Name) then
            if not Shared.isObjectiveComplete(item) then
                return false
            end
        end
    end
    
    return true
end

-- 🎭 مساعدات الحوار (Dialogue Helpers)
function Shared.invokeDialogueStart(npcModel)
    local remote = Services.ReplicatedStorage:WaitForChild("Shared")
        :WaitForChild("Packages"):WaitForChild("Knit")
        :WaitForChild("Services"):WaitForChild("ProximityService")
        :WaitForChild("RF"):WaitForChild("Dialogue")
    if remote then
        remote:InvokeServer(npcModel)
        print("📡 تم بدء الحوار")
    end
end

function Shared.invokeRunCommand(commandName)
    local remote = Services.ReplicatedStorage:WaitForChild("Shared")
        :WaitForChild("Packages"):WaitForChild("Knit")
        :WaitForChild("Services"):WaitForChild("DialogueService")
        :WaitForChild("RF"):WaitForChild("RunCommand")
    if remote then
        print("📡 اختيار الخيار: " .. commandName)
        pcall(function() remote:InvokeServer(commandName) end)
    end
end

function Shared.forceEndDialogue()
    print("🔧 فرض إنهاء الحوار...")
    
    local gui = player:FindFirstChild("PlayerGui")
    if gui then
        local dUI = gui:FindFirstChild("DialogueUI")
        if dUI then
            dUI.Enabled = false
            local bb = dUI:FindFirstChild("ResponseBillboard")
            if bb then bb.Visible = false end
        end
    end
    
    local cam = Services.Workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        cam.FieldOfView = 70
    end
    
    local char = player.Character
    if char then
        local status = char:FindFirstChild("Status")
        if status then
            for _, tag in ipairs(status:GetChildren()) do
                if tag.Name == "DisableBackpack" or tag.Name == "NoMovement" or tag.Name == "Talking" then
                    tag:Destroy()
                end
            end
        end
        
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
        end
    end
    
    if gui then
        local main = gui:FindFirstChild("Main")
        if main then main.Enabled = true end
        
        local backpack = gui:FindFirstChild("BackpackGui")
        if backpack then backpack.Enabled = true end
    end
    
    local dialogueRE = Services.ReplicatedStorage:FindFirstChild("Shared")
        and Services.ReplicatedStorage.Shared:FindFirstChild("Packages")
        and Services.ReplicatedStorage.Shared.Packages:FindFirstChild("Knit")
        and Services.ReplicatedStorage.Shared.Packages.Knit.Services:FindFirstChild("DialogueService")
        and Services.ReplicatedStorage.Shared.Packages.Knit.Services.DialogueService:FindFirstChild("RE")
        and Services.ReplicatedStorage.Shared.Packages.Knit.Services.DialogueService.RE:FindFirstChild("DialogueEvent")
    
    if dialogueRE then
        dialogueRE:FireServer("Closed")
    end
    
    print("✅ تم إنهاء الحوار بنجاح")
end

-- 🖱️ النقر الافتراضي (Virtual Click)
function Shared.virtualClick(guiObject)
    if not guiObject then 
        warn("❌ لم يتم العثور على كائن الواجهة الرسومية!")
        return false 
    end
    
    local clickSuccess = pcall(function()
        local conns = getconnections(guiObject.MouseButton1Click)
        for _, conn in pairs(conns) do
            conn:Fire()
        end
    end)
    
    local activatedSuccess = pcall(function()
        local conns = getconnections(guiObject.Activated)
        for _, conn in pairs(conns) do
            conn:Fire()
        end
    end)
    
    if clickSuccess or activatedSuccess then
        print("   ✅ تم تنفيذ النقر")
        return true
    end
    return false
end

-- 🛡️ نظام مكافحة الخمول (Anti-AFK)
function Shared.startAntiAfk(interval, clickCount)
    interval = interval or 120
    clickCount = clickCount or 5
    
    task.spawn(function()
        print("🛡️ [ANTI-AFK] تم البدء! النقر كل " .. interval .. " ثانية.")
        while true do
            task.wait(interval)
            pcall(function()
                local camera = Services.Workspace.CurrentCamera
                local viewportSize = camera.ViewportSize
                local guiInset = Services.GuiService:GetGuiInset()
                local centerX = viewportSize.X / 2
                local centerY = (viewportSize.Y / 2) + guiInset.Y
                
                print("🛡️ [ANTI-AFK] تنفيذ " .. clickCount .. " نقرة افتراضية...")
                
                for i = 1, clickCount do
                    Services.VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, true, game, 1)
                    task.wait(0.05)
                    Services.VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, false, game, 1)
                    
                    if i < clickCount then
                        task.wait(0.5)
                    end
                end
                
                print("🛡️ [ANTI-AFK] اكتمل النقر! التالي في " .. interval .. " ثانية.")
            end)
        end
    end)
end

-- 🔗 خدمات Knit (تحميل كسول)
Shared.Knit = nil
Shared.KnitServices = {}
Shared.KnitControllers = {}

function Shared.getKnit()
    if Shared.Knit then return Shared.Knit end
    
    pcall(function()
        local KnitPackage = Services.ReplicatedStorage:WaitForChild("Shared")
            :WaitForChild("Packages"):WaitForChild("Knit")
        Shared.Knit = require(KnitPackage)
        
        if not Shared.Knit.OnStart then 
            pcall(function() Shared.Knit.Start():await() end)
        end
    end)
    
    return Shared.Knit
end

function Shared.getService(serviceName)
    if Shared.KnitServices[serviceName] then
        return Shared.KnitServices[serviceName]
    end
    
    local Knit = Shared.getKnit()
    if Knit then
        pcall(function()
            Shared.KnitServices[serviceName] = Knit.GetService(serviceName)
        end)
    end
    
    return Shared.KnitServices[serviceName]
end

function Shared.getController(controllerName)
    if Shared.KnitControllers[controllerName] then
        return Shared.KnitControllers[controllerName]
    end
    
    local Knit = Shared.getKnit()
    if Knit then
        pcall(function()
            Shared.KnitControllers[controllerName] = Knit.GetController(controllerName)
        end)
    end
    
    return Shared.KnitControllers[controllerName]
end

-- 🔧 متحكم الأدوات (Tool Controller)
Shared.ToolController = nil
Shared.ToolActivatedFunc = nil
Shared.UIController = nil

function Shared.hookControllers()
    pcall(function()
        for _, v in pairs(getgc(true)) do
            if type(v) == "table" then
                if rawget(v, "Open") and rawget(v, "Modules") then
                    Shared.UIController = v
                end
                if rawget(v, "Name") == "ToolController" and rawget(v, "ToolActivated") then
                    Shared.ToolController = v
                    Shared.ToolActivatedFunc = v.ToolActivated
                end
            end
        end
    end)
    
    if Shared.UIController then print("✅ تم ربط UIController!") end
    if Shared.ToolController then print("✅ تم ربط ToolController!") end
end

-- الربط التلقائي عند التحميل
Shared.hookControllers()

print("✅ تم تحميل Shared Utilities بنجاح!")
print("   📦 متاح عبر: _G.Shared")

----------------------------------------------------------------
-- 🚀 محفز FPS (FPS Booster)
----------------------------------------------------------------
-- يتم تضمين وظيفة محفز FPS هنا مباشرة
local function FPSBooster()
    local RunService = game:GetService("RunService")
    local Lighting = game:GetService("Lighting")
    local Workspace = game:GetService("Workspace")
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    
    -- إعدادات الإضاءة
    Lighting.FogEnd = 100000
    Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
    Lighting.Ambient = Color3.new(0, 0, 0)
    Lighting.Brightness = 0
    Lighting.GlobalShadows = false
    Lighting.Technology = Enum.Technology.Compatibility
    
    -- إعدادات الكاميرا
    local camera = Workspace.CurrentCamera
    if camera then
        camera.FieldOfView = 70
    end
    
    -- إزالة التأثيرات
    for _, v in ipairs(Lighting:GetChildren()) do
        if v:IsA("BloomEffect") or v:IsA("ColorCorrectionEffect") or v:IsA("SunRaysEffect") or v:IsA("DepthOfFieldEffect") then
            v:Destroy()
        end
    end
    
    -- إزالة السماء
    if Lighting:FindFirstChild("Sky") then
        Lighting.Sky:Destroy()
    end
    
    -- إزالة الأجزاء غير الضرورية
    local function cleanup(instance)
        for _, child in ipairs(instance:GetChildren()) do
            if child:IsA("Part") or child:IsA("MeshPart") or child:IsA("UnionOperation") then
                if child.Name == "Water" or child.Name == "Cloud" or child.Name == "Foliage" then
                    child:Destroy()
                end
            elseif child:IsA("Decal") or child:IsA("Texture") then
                child:Destroy()
            elseif child:IsA("ParticleEmitter") or child:IsA("Fire") or child:IsA("Smoke") or child:IsA("Sparkles") then
                child:Destroy()
            elseif child:IsA("Sound") then
                child:Destroy()
            end
            -- لا تقم بالاستدعاء الذاتي هنا، سيتم التعامل معها بواسطة DescendantAdded
        end
    end
    
    -- تنظيف الأجزاء الموجودة
    cleanup(Workspace)
    
    -- إزالة الأجزاء الجديدة بشكل مستمر
    Workspace.DescendantAdded:Connect(function(descendant)
        cleanup(descendant)
    end)
    
    -- إعدادات الجودة
    settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    
    print("🚀 تم تفعيل FPS Booster!")
end

----------------------------------------------------------------
-- ⚙️ الإعدادات (Configuration)
----------------------------------------------------------------
local CONFIG = {
    -- ⏱️ التوقيت
    INITIAL_WAIT = 1,          -- انتظار البدء (ثواني)
    QUEST_CHECK_INTERVAL = 2,    -- فحص المهام الجديدة كل (ثواني)
    
    -- 🎮 نطاق المهام
    MIN_QUEST = 1,
    MAX_QUEST = 19,  -- تم التحديث: 1-18 للجزيرة 1، 19 للجزيرة 2
    
    -- 🔧 وضع التصحيح (Debug)
    DEBUG_MODE = true,
    
    -- 🚀 التحسين
    LOAD_FPS_BOOSTER = true,
    
    -- 🛡️ مكافحة الخمول (Anti-AFK)
    ANTI_AFK_ENABLED = true,
    ANTI_AFK_INTERVAL = 120,   -- كل 2 دقيقة
    ANTI_AFK_CLICK_COUNT = 5,  -- عدد النقرات في كل مرة
}

----------------------------------------------------------------
-- 📦 محمل المهام المعياري (Modular Quest Loader)
----------------------------------------------------------------

repeat task.wait(1) until game:IsLoaded()

print("=" .. string.rep("=", 59))
print("🔥 THE FORGE - محمل المهام المعياري")
print("=" .. string.rep("=", 59))

print("\n⏳ انتظار مبدئي: " .. CONFIG.INITIAL_WAIT .. " ثانية...")
task.wait(CONFIG.INITIAL_WAIT)

-- تفعيل محفز FPS
if CONFIG.LOAD_FPS_BOOSTER then
    print("\n🚀 تحميل محفز FPS...")
    pcall(FPSBooster)
    print("✅ تم تحميل محفز FPS!")
end

-- تفعيل نظام مكافحة الخمول
if CONFIG.ANTI_AFK_ENABLED then
    Shared.startAntiAfk(CONFIG.ANTI_AFK_INTERVAL, CONFIG.ANTI_AFK_CLICK_COUNT)
end

-- 🌍 نظام الكشف عن الجزيرة (Island Detection)
local FORGES_FOLDER = Services.Workspace:WaitForChild("Forges", 10)

local function getCurrentIsland()
    if not FORGES_FOLDER then
        return nil
    end
    
    for _, child in ipairs(FORGES_FOLDER:GetChildren()) do
        if child:IsA("Folder") or child:IsA("Model") then
            local islandMatch = string.match(child.Name, "Island(%d+)")
            if islandMatch then
                return "Island" .. islandMatch
            end
        end
    end
    return nil
end

-- 📊 نظام فحص المستوى (Level Check System)
local function getPlayerLevel()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end
    
    local levelLabel = gui:FindFirstChild("Main")
                      and gui.Main:FindFirstChild("Screen")
                      and gui.Main.Screen:FindFirstChild("Hud")
                      and gui.Main.Screen.Hud:FindFirstChild("Level")
    
    if not levelLabel or not levelLabel:IsA("TextLabel") then
        return nil
    end
    
    local levelText = levelLabel.Text
    local level = tonumber(string.match(levelText, "%d+"))
    return level
end

-- 📋 فحص قائمة المهام الفارغة (Quest List Empty Check)
local function isQuestListEmpty()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return false end
    
    local list = gui:FindFirstChild("Main") 
        and gui.Main:FindFirstChild("Screen") 
        and gui.Main.Screen:FindFirstChild("Quests") 
        and gui.Main.Screen.Quests:FindFirstChild("List")
    
    if not list then return false end
    
    -- فحص ما إذا كانت القائمة تحتوي فقط على UIListLayout و UIPadding (لا توجد مهام فعلية)
    for _, child in ipairs(list:GetChildren()) do
        if child.Name ~= "UIListLayout" and child.Name ~= "UIPadding" then
            return false  -- تم العثور على مهمة!
        end
    end
    
    return true  -- فقط UIListLayout و UIPadding = فارغة!
end

local function getActiveQuestNumber()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end
    
    local list = gui:FindFirstChild("Main") 
        and gui.Main:FindFirstChild("Screen") 
        and gui.Main.Screen:FindFirstChild("Quests") 
        and gui.Main.Screen.Quests:FindFirstChild("List")
    
    if not list then return nil end
    
    -- البحث عن المهمة النشطة
    for _, child in ipairs(list:GetChildren()) do
        local id = string.match(child.Name, "^Introduction(%d+)Title$")
        if id and child:FindFirstChild("Frame") and child.Frame:FindFirstChild("TextLabel") then
            local questName = child.Frame.TextLabel.Text
            local questNum = tonumber(id) + 1
            
            if questNum and questName ~= "" then
                -- فحص ما إذا كانت المهمة لم تكتمل بعد
                local objList = list:FindFirstChild("Introduction" .. id .. "List")
                if objList then
                    for _, item in ipairs(objList:GetChildren()) do
                        if item:IsA("Frame") and tonumber(item.Name) then
                            local check = item:FindFirstChild("Main") 
                                and item.Main:FindFirstChild("Frame") 
                                and item.Main.Frame:FindFirstChild("Check")
                            if check and not check.Visible then
                                -- تم العثور على هدف لم يكتمل
                                return questNum, questName
                            end
                        end
                    end
                end
            end
        end
    end
    
    return nil
end

local function isQuestComplete(questNum)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return true end
    
    local list = gui:FindFirstChild("Main") 
        and gui.Main:FindFirstChild("Screen") 
        and gui.Main.Screen:FindFirstChild("Quests") 
        and gui.Main.Screen.Quests:FindFirstChild("List")
    
    if not list then return true end
    
    -- تحويل رقم المهمة (1-based) إلى معرف واجهة المستخدم (0-based)
    local uiID = questNum - 1
    local objList = list:FindFirstChild("Introduction" .. uiID .. "List")
    if not objList then return true end
    
    for _, item in ipairs(objList:GetChildren()) do
        if item:IsA("Frame") and tonumber(item.Name) then
            local check = item:FindFirstChild("Main") 
                and item.Main:FindFirstChild("Frame") 
                and item.Main.Frame:FindFirstChild("Check")
            if check and not check.Visible then
                return false
            end
        end
    end
    
    return true
end

-- 📥 محمل المهام (Quest Loader)
local loadedQuests = {}

local function loadQuest(questNum)
    if loadedQuests[questNum] then
        print(string.format("   ⚠️ المهمة %02d محملة بالفعل.", questNum))
        return true
    end
    
    local questFunc = _G.QuestFunctions[questNum]
    if not questFunc then
        warn(string.format("❌ لم يتم العثور على وظيفة المهمة %02d في _G.QuestFunctions.", questNum))
        return false
    end
    
    print(string.format("   📥 تحميل المهمة %02d...", questNum))
    
    local success, err = pcall(function()
        loadedQuests[questNum] = questFunc()
    end)
    
    if success then
        print(string.format("   ✅ تم تحميل المهمة %02d بنجاح!", questNum))
        return true
    else
        warn(string.format("❌ فشل تحميل المهمة %02d: %s", questNum, tostring(err)))
        return false
    end
end

-- 🏃 مشغل المهام (Quest Runner)
local function runQuest(questNum, questName)
    local questModule = loadedQuests[questNum]
    if not questModule then
        warn(string.format("❌ لا يمكن تشغيل المهمة %02d: لم يتم تحميل الوحدة.", questNum))
        return
    end
    
    print(string.rep("-", 60))
    print(string.format("▶️ تشغيل المهمة %02d: %s", questNum, questName))
    print(string.rep("-", 60))
    
    Shared.cleanupState()
    
    local success, err = pcall(function()
        questModule.run()
    end)
    
    if not success then
        warn(string.format("❌ فشل تشغيل المهمة %02d: %s", questNum, tostring(err)))
    end
end

-- 🔄 حلقة المراقبة الرئيسية (Main Monitoring Loop)
local function mainLoop()
    while true do
        task.wait(CONFIG.QUEST_CHECK_INTERVAL)
        
        local currentIsland = getCurrentIsland()
        if not currentIsland then
            print("⚠️ لا يمكن الكشف عن الجزيرة. جاري الانتظار...")
            continue
        end
        
        local questNum, questName = getActiveQuestNumber()
        
        if questNum then
            if questNum < CONFIG.MIN_QUEST or questNum > CONFIG.MAX_QUEST then
                print(string.format("⚠️ المهمة %02d خارج النطاق المحدد (%d-%d). جاري التخطي.", questNum, CONFIG.MIN_QUEST, CONFIG.MAX_QUEST))
                continue
            end
            
            if not loadedQuests[questNum] then
                loadQuest(questNum)
            end
            
            if loadedQuests[questNum] then
                runQuest(questNum, questName)
            end
        else
            -- إذا كانت قائمة المهام فارغة، فحص ما إذا كانت المهمة الأخيرة قد اكتملت
            if isQuestListEmpty() then
                local lastQuest = CONFIG.MAX_QUEST
                if isQuestComplete(lastQuest) then
                    print(string.format("✅ جميع المهام (%d) مكتملة. جاري الانتظار...", lastQuest))
                else
                    print("⚠️ قائمة المهام فارغة، ولكن المهمة الأخيرة لم تكتمل. جاري الانتظار...")
                end
            else
                print("💤 لا توجد مهمة نشطة. جاري الانتظار...")
            end
        end
    end
end

-- 🏁 بدء التشغيل
task.spawn(mainLoop)

----------------------------------------------------------------
-- 📜 وظائف المهام (Quest Functions)
----------------------------------------------------------------
_G.QuestFunctions = {}

-- سيتم إدراج محتوى ملفات المهام هنا

-- 📜 وظائف المهام (Quest Functions)
-- تم استخراجها من ملفات QuestXX.lua
_G.QuestFunctions = {}

-- Quest 01
_G.QuestFunctions[1] = function()
--[[
    ⚔️ QUEST 01: Getting Started!
    📋 Talk to Sensei Moro
    📍 Extracted from 0.lua (lines 209-587)
--]]

-- Full Quest 1 Automation Script (Smooth Movement + UI Force Restore)
-- Features: Quest Check -> Smooth BodyMove -> Dialogue -> Force Restore ALL UI

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

----------------------------------------------------------------
-- CONFIGURATION
----------------------------------------------------------------
local QUEST_NAME = "Getting Started!"
local NPC_NAME = "Sensei Moro"
local QUEST_OPTION_ARG = "GiveIntroduction1"
local MOVE_SPEED = 25

----------------------------------------------------------------
-- STATE MANAGEMENT
----------------------------------------------------------------
local State = {
    noclipConn = nil,
    moveConn = nil,
    bodyVelocity = nil,
    bodyGyro = nil,
}

local function restoreCollisions()
    local char = player.Character
    if not char then return end

    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = true
        end
    end
end

local function cleanupState()
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
    if State.moveConn then
        State.moveConn:Disconnect()
        State.moveConn = nil
    end
    if State.bodyVelocity then
        State.bodyVelocity:Destroy()
        State.bodyVelocity = nil
    end
    if State.bodyGyro then
        State.bodyGyro:Destroy()
        State.bodyGyro = nil
    end

    -- ✅ สำคัญ: คืน CanCollide ให้ตัวละคร
    restoreCollisions()
end

----------------------------------------------------------------
-- NOCLIP
----------------------------------------------------------------
local function enableNoclip()
    if State.noclipConn then return end
    
    local char = player.Character
    if not char then return end
    
    State.noclipConn = RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
            return
        end
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
    -- ✅ ปิด noclip แล้วคืนการชนให้ตัวละคร
    restoreCollisions()
end

----------------------------------------------------------------
-- SMOOTH MOVEMENT
----------------------------------------------------------------
local function smoothMoveTo(targetPos, callback)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    -- Cleanup previous movement
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    -- Enable noclip
    enableNoclip()
    
    -- Create BodyVelocity
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = hrp
    State.bodyVelocity = bv
    
    -- Create BodyGyro
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.D = 500
    bg.Parent = hrp
    State.bodyGyro = bg
    
    print(string.format("   🚀 Moving to (%.1f, %.1f, %.1f)...", targetPos.X, targetPos.Y, targetPos.Z))
    
    State.moveConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv then bv:Destroy() end
            if bg then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end
        
        local currentPos = hrp.Position
        local direction = (targetPos - currentPos)
        local distance = direction.Magnitude
        
        if distance < 5 then  -- Stop at 5 studs (NPC proximity)
            print("   ✅ Reached NPC!")
            
            bv.Velocity = Vector3.zero
            task.wait(0.1)
            
            bv:Destroy()
            bg:Destroy()
            State.bodyVelocity = nil
            State.bodyGyro = nil
            
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            
            if callback then callback() end
            return
        end
        
        local speed = math.min(MOVE_SPEED, distance * 10)
        local velocity = direction.Unit * speed
        
        bv.Velocity = velocity
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
    end)
    
    return true
end

----------------------------------------------------------------
-- REMOTE FUNCTIONS
----------------------------------------------------------------
local function invokeDialogueStart(npcModel)
    local remote = ReplicatedStorage:WaitForChild("Shared")
        :WaitForChild("Packages"):WaitForChild("Knit")
        :WaitForChild("Services"):WaitForChild("ProximityService")
        :WaitForChild("RF"):WaitForChild("Dialogue")
    if remote then
        remote:InvokeServer(npcModel)
        print("📡 1. Started Dialogue")
    end
end

local function invokeRunCommand(commandName)
    local remote = ReplicatedStorage:WaitForChild("Shared")
        :WaitForChild("Packages"):WaitForChild("Knit")
        :WaitForChild("Services"):WaitForChild("DialogueService")
        :WaitForChild("RF"):WaitForChild("RunCommand")
    if remote then
        print("📡 2. Selecting Option: " .. commandName)
        pcall(function() remote:InvokeServer(commandName) end)
    end
end

----------------------------------------------------------------
-- HELPER: FORCE RESTORE (Fix Missing UI)
----------------------------------------------------------------
local function ForceEndDialogueAndRestore()
    print("🔧 3. Forcing Cleanup & UI Restore...")

    -- A. ปิด Dialogue & แก้ Camera
    local gui = player:FindFirstChild("PlayerGui")
    if gui then
        local dUI = gui:FindFirstChild("DialogueUI")
        if dUI then
            dUI.Enabled = false
            local bb = dUI:FindFirstChild("ResponseBillboard")
            if bb then bb.Visible = false end
        end
    end

    local cam = Workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        cam.FieldOfView = 70
    end

    -- B. ลบ Status ที่ทำให้ UI หาย
    local char = player.Character
    if char then
        local status = char:FindFirstChild("Status")
        if status then
            for _, tag in ipairs(status:GetChildren()) do
                if tag.Name == "DisableBackpack" or tag.Name == "NoMovement" or tag.Name == "Talking" then
                    tag:Destroy()
                    print("   - Removed Status Tag: " .. tag.Name)
                end
            end
        end
        
        -- คืนค่า Humanoid
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
        end
    end

    -- C. บังคับเปิด UI ที่สำคัญกลับมา
    if gui then
        local main = gui:FindFirstChild("Main")
        if main then 
            main.Enabled = true 
            print("   - Main UI (Quest) Restored")
        end
        
        local backpack = gui:FindFirstChild("BackpackGui")
        if backpack then 
            backpack.Enabled = true 
            print("   - Backpack Restored")
        end
        
        local compass = gui:FindFirstChild("Compass")
        if compass then compass.Enabled = true end
        
        local mobile = gui:FindFirstChild("MobileButtons")
        if mobile then mobile.Enabled = true end
    end

    -- D. บอก Server ว่าปิดแล้ว
    local remote = ReplicatedStorage:WaitForChild("Shared")
        :WaitForChild("Packages"):WaitForChild("Knit")
        :WaitForChild("Services"):WaitForChild("DialogueService")
        :WaitForChild("RE"):WaitForChild("DialogueEvent")
    if remote then
        remote:FireServer("Closed")
    end
    
    print("✅ Restore Complete")
end

----------------------------------------------------------------
-- HELPER: LEVEL CHECK
----------------------------------------------------------------
local function getPlayerLevel()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end
    
    local levelLabel = gui:FindFirstChild("Main")
                      and gui.Main:FindFirstChild("Screen")
                      and gui.Main.Screen:FindFirstChild("Hud")
                      and gui.Main.Screen.Hud:FindFirstChild("Level")
    
    if not levelLabel or not levelLabel:IsA("TextLabel") then
        return nil
    end
    
    local levelText = levelLabel.Text
    local level = tonumber(string.match(levelText, "%d+"))
    return level
end

----------------------------------------------------------------
-- HELPER: QUEST & MOVEMENT
----------------------------------------------------------------
local function getActiveQuestName()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end
    local list = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Screen") 
                 and gui.Main.Screen:FindFirstChild("Quests") and gui.Main.Screen.Quests:FindFirstChild("List")
    if not list then return nil end
    for _, child in ipairs(list:GetChildren()) do
        if string.match(child.Name, "^Introduction%d+Title$") then
            local frame = child:FindFirstChild("Frame")
            if frame then
                local label = frame:FindFirstChild("TextLabel")
                if label and label.Text ~= "" then return label.Text end
            end
        end
    end
    return nil
end

local function getNpcModel(name)
    local prox = Workspace:FindFirstChild("Proximity")
    return prox and prox:FindFirstChild(name)
end

----------------------------------------------------------------
-- FORCE COMPLETE (For recovery from disconnected dialogue)
-- Uses body move to fixed NPC position
-- Only runs if Quest List is EMPTY (no items)
----------------------------------------------------------------
local NPC_POSITION = Vector3.new(-200.07, 30.37, 158.41)

local function forceCompleteQuest1()
    print("\n🔧 Checking if force complete is needed...")
    
    -- ⚠️ เช็คก่อนว่า Quest List ว่างเปล่าจริงไหม
    local gui = player:FindFirstChild("PlayerGui")
    local isQuestListEmpty = true
    
    if gui then
        local list = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Screen") 
                     and gui.Main.Screen:FindFirstChild("Quests") and gui.Main.Screen.Quests:FindFirstChild("List")
        if list then
            for _, child in ipairs(list:GetChildren()) do
                -- มี Quest item อยู่ (ไม่ใช่แค่ UIListLayout หรือ UIPadding)
                if child.Name ~= "UIListLayout" and child.Name ~= "UIPadding" then
                    isQuestListEmpty = false
                    break
                end
            end
        end
    end
    
    -- ❌ ถ้ามี Quest items อยู่ → ไม่ทำ forceComplete
    if not isQuestListEmpty then
        print("   ⏭️  Quest List has items (not empty)")
        print("   → Skipping force complete (other quests active)")
        return false
    end
    
    -- ✅ Quest List ว่างเปล่า → ทำ forceComplete
    print("   ✅ Quest List is EMPTY! Proceeding with force complete...")
    print(string.format("   🎯 Moving to NPC position (%.1f, %.1f, %.1f)...", 
        NPC_POSITION.X, NPC_POSITION.Y, NPC_POSITION.Z))
    
    -- 1. Enable noclip & Move to NPC position
    enableNoclip()
    
    local moveComplete = false
    smoothMoveTo(NPC_POSITION, function()
        moveComplete = true
    end)
    
    -- Wait for movement (max 30 seconds)
    local timeout = 30
    local startTime = tick()
    while not moveComplete and tick() - startTime < timeout do
        task.wait(0.1)
    end
    
    -- Cleanup movement
    cleanupState()
    disableNoclip()
    
    if not moveComplete then
        warn("   ⚠️ Movement timeout, but trying remote anyway...")
    else
        print("   ✅ Arrived at NPC position!")
    end
    
    task.wait(0.5)
    
    -- 2. Try to find NPC and start dialogue
    local npcModel = getNpcModel(NPC_NAME)
    if npcModel then
        print("   📡 Found NPC, starting dialogue...")
        invokeDialogueStart(npcModel)
        task.wait(0.5)
    else
        print("   ⚠️ NPC not found at position, trying remote directly...")
    end
    
    -- 3. Send quest accept command
    print("   📡 Sending quest accept command...")
    pcall(function()
        invokeRunCommand(QUEST_OPTION_ARG)
    end)
    task.wait(0.5)
    
    -- 4. Cleanup UI
    ForceEndDialogueAndRestore()
    
    print("   ✅ Force complete done!")
    return true
end

----------------------------------------------------------------
-- MAIN EXECUTION
----------------------------------------------------------------
local function Run_Quest1()
    print(string.rep("=", 50))
    print("🚀 QUEST 1: " .. QUEST_NAME)
    print(string.rep("=", 50))
    
    -- ✅ เช็คว่ามี Introduction0Title (Quest 1 UI) หรือไม่
    local gui = player:FindFirstChild("PlayerGui")
    local hasQuest1UI = false
    
    if gui then
        local list = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Screen") 
                     and gui.Main.Screen:FindFirstChild("Quests") and gui.Main.Screen.Quests:FindFirstChild("List")
        if list and list:FindFirstChild("Introduction0Title") then
            hasQuest1UI = true
        end
    end
    
    if hasQuest1UI then
        -- ✅ มี Quest 1 UI → ทำงานปกติ
        print("✅ Quest 1 UI (Introduction0Title) found! Continuing normal flow...")
    else
        -- ⚠️ ไม่มี Quest 1 UI → forceCompleteQuest1
        print("\n⚠️ DETECTED: No Quest 1 UI (Introduction0Title)!")
        print("   → Quest 1 UI not visible")
        print("   → Player may have disconnected during dialogue")
        print("   → Attempting force recovery...")
        
        local success = forceCompleteQuest1()
        if success then
            cleanupState()
            disableNoclip()
            print("\n" .. string.rep("=", 50))
            print("🎉 Quest 1 Recovery Complete!")
            print(string.rep("=", 50))
            return
        end
    end

    local npcModel = getNpcModel(NPC_NAME)
    if not npcModel then 
        cleanupState()
        disableNoclip()
        return warn("❌ NPC Not Found") 
    end
    
    local targetPart = npcModel.PrimaryPart or npcModel:FindFirstChildWhichIsA("BasePart")
    if not targetPart then
        cleanupState()
        disableNoclip()
        return warn("❌ NPC has no valid part")
    end
    
    local targetPos = targetPart.Position
    
    print(string.format("\n🚶 Moving to NPC '%s' at (%.1f, %.1f, %.1f)...", 
        NPC_NAME, targetPos.X, targetPos.Y, targetPos.Z))
    
    -- Start smooth movement
    local moveComplete = false
    smoothMoveTo(targetPos, function()
        moveComplete = true
    end)
    
    -- Wait for movement to complete
    local timeout = 60
    local startTime = tick()
    while not moveComplete and tick() - startTime < timeout do
        task.wait(0.1)
    end
    
    -- Cleanup movement
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    if not moveComplete then
        cleanupState()
        disableNoclip()
        return warn("❌ Failed to reach NPC (timeout)")
    end
    
    print("\n📞 Starting Dialogue...")
    task.wait(0.5)
    invokeDialogueStart(npcModel)
    
    print("⏳ Waiting for dialogue to open...")
    task.wait(1.5)
    
    print("✅ Selecting quest option...")
    invokeRunCommand(QUEST_OPTION_ARG)
    
    print("⏳ Processing...")
    task.wait(0.5)
    
    ForceEndDialogueAndRestore()
    
    -- Final cleanup
    cleanupState()
    disableNoclip()
    
    print("\n" .. string.rep("=", 50))
    print("🎉 Quest 1 Sequence Finished!")
    print(string.rep("=", 50))
end

Run_Quest1()

end

-- Quest 02
_G.QuestFunctions[2] = function()
--[[
    ⚔️ QUEST 02: First Pickaxe!
    📋 Open Equipments → Equip Stone Pickaxe → Mine Pebbles
    📍 Extracted from 0.lua (lines 592-1548)
--]]

-- QUEST 2: "First Pickaxe!" (SMART SYSTEM: Priority-based + Flexible + smoothMoveTo)
-- Priority Order: 1) Open Equipments → 2) Equip Pickaxe → 3) Mine Pebbles

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest2Active = true
local QUEST_CONFIG = {
    QUEST_NAME = "First Pickaxe!",
    PICKAXE_NAME = "Stone Pickaxe",
    MINING_START_POSITION = Vector3.new(43.203, -3.717, -106.628),
    UNDERGROUND_OFFSET = 4,
    LAYING_ANGLE = 90,
    MOVE_SPEED = 25,
    STOP_DISTANCE = 2,
    PRIORITY_ORDER = {
        "Open",
        "Equip",
        "Mine",
    },
}

----------------------------------------------------------------
-- SERVICES & REMOTES
----------------------------------------------------------------
local SERVICES = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")
local CHAR_RF = SERVICES:WaitForChild("CharacterService"):WaitForChild("RF"):WaitForChild("EquipItem")
local TOOL_RF_BACKUP = SERVICES:WaitForChild("ToolService"):WaitForChild("RF"):WaitForChild("ToolActivated")

local MINING_FOLDER_PATH = nil
do
    local ok, rocks = pcall(function()
        return Workspace:FindFirstChild("Rocks")
    end)
    if ok and rocks then
        MINING_FOLDER_PATH = rocks:FindFirstChild("Island1CaveStart")
    end
    if not MINING_FOLDER_PATH then
        warn("[Quest2] Rocks/Island1CaveStart not found – skipping Quest 2 on this map.")
        return
    end
end

----------------------------------------------------------------
-- HOOK CONTROLLERS
----------------------------------------------------------------
local UIController = nil
local ToolController = nil
local ToolActivatedFunc = nil

pcall(function()
    for _, v in pairs(getgc(true)) do
        if type(v) == "table" then
            if rawget(v, "Open") and rawget(v, "Modules") then
                UIController = v
            end
            if rawget(v, "Name") == "ToolController" and rawget(v, "ToolActivated") then
                ToolController = v
                ToolActivatedFunc = v.ToolActivated
            end
        end
    end
end)

if UIController then print("✅ UIController Hooked!") else warn("⚠️ UIController not found") end
if ToolController then print("✅ ToolController Hooked!") else warn("⚠️ ToolController not found (using backup)") end

----------------------------------------------------------------
-- STATE MANAGEMENT
----------------------------------------------------------------
local State = {
    currentTarget = nil,
    targetDestroyed = false,
    moveConn = nil,
    hpWatchConn = nil,
    noclipConn = nil,
    bodyVelocity = nil,
    bodyGyro = nil,
    positionLockConn = nil, 
    currentObjectiveFrame = nil,
}

local function restoreCollisions()
    local char = player.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = true
        end
    end
end

local function cleanupState()
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.hpWatchConn then State.hpWatchConn:Disconnect() State.hpWatchConn = nil end
    if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
    if State.positionLockConn then State.positionLockConn:Disconnect() State.positionLockConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    State.currentTarget = nil
    State.targetDestroyed = false
    if ToolController then ToolController.holdingM1 = false end
end

----------------------------------------------------------------
-- QUEST SYSTEM
----------------------------------------------------------------
local function getQuestObjectives(questName)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil, nil end
    
    local list = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Screen") 
                 and gui.Main.Screen:FindFirstChild("Quests") and gui.Main.Screen.Quests:FindFirstChild("List")
    if not list then return nil, nil end
    
    local questID = nil
    for _, child in ipairs(list:GetChildren()) do
        local id = string.match(child.Name, "^Introduction(%d+)Title$")
        if id and child:FindFirstChild("Frame") and child.Frame:FindFirstChild("TextLabel") then
            if child.Frame.TextLabel.Text == questName then
                questID = id
                break
            end
        end
    end
    
    if not questID then return nil, nil end
    
    local objList = list:FindFirstChild("Introduction" .. questID .. "List")
    return questID, objList
end

local function isObjectiveComplete(item)
    if not item then return false end
    local check = item:FindFirstChild("Main") and item.Main:FindFirstChild("Frame") and item.Main.Frame:FindFirstChild("Check")
    return check and check.Visible
end

local function getObjectiveText(item)
    local lbl = item:FindFirstChild("Main") and item.Main:FindFirstChild("TextLabel")
    return lbl and lbl.Text or ""
end

local function isQuest2StillActive()
    if not Quest2Active then return false end
    
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)
    if not questID or not objList then
        print("🛑 Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' disappeared!")
        Quest2Active = false
        return false
    end
    
    return true
end

local function isCurrentObjectiveComplete()
    if State.currentObjectiveFrame then
        return isObjectiveComplete(State.currentObjectiveFrame)
    end
    return false
end

local function getObjectiveType(text)
    if string.find(text, "Open Equipments") or string.find(text, "Open") then
        return "Open"
    elseif string.find(text, "Equip") and string.find(text, "Pickaxe") then
        return "Equip"
    elseif string.find(text, "Get Ore") or string.find(text, "Mine") or string.find(text, "Pebble") then
        return "Mine"
    else
        return "Unknown"
    end
end

local function canDoObjective(objType)
    return true
end

----------------------------------------------------------------
-- NOCLIP & MOVEMENT
----------------------------------------------------------------
local function enableNoclip()
    if State.noclipConn then return end
    
    local char = player.Character
    if not char then return end
    
    State.noclipConn = RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
            return
        end
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
    restoreCollisions()
end

local function smoothMoveTo(targetPos, stopDistance, callback)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    enableNoclip()
    
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = hrp
    State.bodyVelocity = bv
    
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.D = 500
    bg.Parent = hrp
    State.bodyGyro = bg
    
    State.moveConn = RunService.Heartbeat:Connect(function()
        if State.targetDestroyed or not Quest2Active then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv then bv.Velocity = Vector3.zero bv:Destroy() end
            if bg then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end
        
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv then bv:Destroy() end
            if bg then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end
        
        local currentPos = hrp.Position
        local direction = (targetPos - currentPos)
        local distance = direction.Magnitude
        
        if distance < stopDistance then
            bv.Velocity = Vector3.zero
            if callback then callback() end
            return
        end
        
        local speed = math.min(QUEST_CONFIG.MOVE_SPEED, distance * 10)
        local velocity = direction.Unit * speed
        
        bv.Velocity = velocity
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
    end)
    
    return true
end

----------------------------------------------------------------
-- HELPER FUNCTIONS
----------------------------------------------------------------
local function getPebbleUndergroundPosition(pebbleModel)
    if not pebbleModel or not pebbleModel.Parent then 
        return nil 
    end
    
    local pivotCFrame = nil
    pcall(function()
        if pebbleModel.GetPivot then
            pivotCFrame = pebbleModel:GetPivot()
        elseif pebbleModel.WorldPivot then
            pivotCFrame = pebbleModel.WorldPivot
        end
    end)
    
    if pivotCFrame then
        local pos = pivotCFrame.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.UNDERGROUND_OFFSET, pos.Z)
    end
    
    if pebbleModel.PrimaryPart then
        local pos = pebbleModel.PrimaryPart.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.UNDERGROUND_OFFSET, pos.Z)
    end
    
    local part = pebbleModel:FindFirstChildWhichIsA("BasePart")
    if part then
        local pos = part.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.UNDERGROUND_OFFSET, pos.Z)
    end
    
    return nil
end

local HOTKEY_MAP = {
    ["1"] = Enum.KeyCode.One, ["2"] = Enum.KeyCode.Two, ["3"] = Enum.KeyCode.Three,
    ["4"] = Enum.KeyCode.Four, ["5"] = Enum.KeyCode.Five, ["6"] = Enum.KeyCode.Six,
    ["7"] = Enum.KeyCode.Seven, ["8"] = Enum.KeyCode.Eight, ["9"] = Enum.KeyCode.Nine, ["0"] = Enum.KeyCode.Zero
}

local function pressKey(keyCode)
    if not keyCode then return end
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

local function findPickaxeSlotKey()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end
    local hotbar = gui:FindFirstChild("BackpackGui") and gui.BackpackGui:FindFirstChild("Backpack") and gui.BackpackGui.Backpack:FindFirstChild("Hotbar")
    if hotbar then
        for _, slotFrame in ipairs(hotbar:GetChildren()) do
            local frame = slotFrame:FindFirstChild("Frame")
            local label = frame and frame:FindFirstChild("ToolName")
            if label and label:IsA("TextLabel") and string.find(label.Text, "Pickaxe") then
                return HOTKEY_MAP[slotFrame.Name]
            end
        end
    end
    return nil
end

local function checkMiningError()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return false end
    local notif = gui:FindFirstChild("Notifications")
    if notif and notif:FindFirstChild("Screen") and notif.Screen:FindFirstChild("NotificationsFrame") then
        for _, child in ipairs(notif.Screen.NotificationsFrame:GetChildren()) do
            local lbl = child:FindFirstChild("TextLabel", true)
            if lbl and string.find(lbl.Text, "Someone else is already mining") then return true end
        end
    end
    return false
end

local function getPebblePosition(pebbleModel)
    if not pebbleModel or not pebbleModel.Parent then 
        return nil 
    end
    
    if pebbleModel.PrimaryPart then
        return pebbleModel.PrimaryPart.Position
    end
    
    local part = pebbleModel:FindFirstChildWhichIsA("BasePart")
    return part and part.Position or nil
end

local function lockPositionLayingDown(targetPos)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    if State.positionLockConn then
        State.positionLockConn:Disconnect()
        State.positionLockConn = nil
    end
    
    local angle = math.rad(QUEST_CONFIG.LAYING_ANGLE)
    local baseCFrame = CFrame.new(targetPos)
    local layingCFrame = baseCFrame * CFrame.Angles(angle, 0, 0)
    
    State.positionLockConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.positionLockConn then
                State.positionLockConn:Disconnect()
                State.positionLockConn = nil
            end
            return
        end
        
        hrp.CFrame = layingCFrame
        hrp.Velocity = Vector3.zero
        hrp.AssemblyLinearVelocity = Vector3.zero
    end)
    
    print("   🔒 Position locked (laying down)")
end

local function unlockPosition()
    if State.positionLockConn then
        State.positionLockConn:Disconnect()
        State.positionLockConn = nil
        print("   🔓 Position unlocked")
    end
end

----------------------------------------------------------------
-- HP CHECKER
----------------------------------------------------------------
local function getPebbleHP(pebble)
    if not pebble or not pebble.Parent then return 0 end
    
    local success, result = pcall(function()
        return pebble:GetAttribute("Health") or 0
    end)
    
    return success and result or 0
end

local function isTargetValid(pebble)
    if not pebble or not pebble.Parent then return false end
    if not pebble:FindFirstChildWhichIsA("BasePart") then return false end
    
    local hp = getPebbleHP(pebble)
    return hp > 0
end

----------------------------------------------------------------
-- VIRTUAL CLICK
----------------------------------------------------------------
local function VirtualClick(guiObject)
    if not guiObject then 
        warn("❌ GUI Object not found!")
        return false 
    end
    
    local clickSuccess = pcall(function()
        local conns = getconnections(guiObject.MouseButton1Click)
        for _, conn in pairs(conns) do
            conn:Fire()
        end
    end)
    
    local activatedSuccess = pcall(function()
        local conns = getconnections(guiObject.Activated)
        for _, conn in pairs(conns) do
            conn:Fire()
        end
    end)
    
    if clickSuccess or activatedSuccess then
        print("   ✅ Click executed")
        return true
    end
    return false
end

----------------------------------------------------------------
-- TARGET FINDER
----------------------------------------------------------------
local function findNearestPebble()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local targetPebble, minDist = nil, math.huge
    
    for _, child in ipairs(MINING_FOLDER_PATH:GetChildren()) do
        if child:IsA("SpawnLocation") or child.Name == "SpawnLocation" then
            local pebble = child:FindFirstChild("Pebble")
            if isTargetValid(pebble) then
                local pos = getPebblePosition(pebble)
                if pos then
                    local dist = (pos - hrp.Position).Magnitude
                    if dist < minDist then
                        minDist = dist
                        targetPebble = pebble
                    end
                end
            end
        end
    end
    
    return targetPebble, minDist
end

----------------------------------------------------------------
-- MOVE TO STARTING POSITION
----------------------------------------------------------------
local function moveToStartPosition()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    local currentDist = (QUEST_CONFIG.MINING_START_POSITION - hrp.Position).Magnitude
    
    if currentDist > 50 then
        print(string.format("📍 Moving to starting position (%.1f studs away)...", currentDist))
        
        local moveComplete = false
        smoothMoveTo(QUEST_CONFIG.MINING_START_POSITION, 5, function()
            moveComplete = true
        end)
        
        local timeout = 60
        local startTime = tick()
        while not moveComplete and tick() - startTime < timeout do
            if not hrp or not hrp.Parent then break end
            local dist = (QUEST_CONFIG.MINING_START_POSITION - hrp.Position).Magnitude
            if dist < 8 then
                moveComplete = true
                break
            end
            task.wait(0.1)
        end
        
        if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
        if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
        if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
        
        print("   ✅ Reached starting position!")
        task.wait(0.3)
    else
        print("   ✅ Already near starting position!")
    end
    
    return true
end

----------------------------------------------------------------
-- WATCH HP
----------------------------------------------------------------
local function watchPebbleHP(pebble)
    if State.hpWatchConn then State.hpWatchConn:Disconnect() end
    if not pebble then return end
    
    State.hpWatchConn = pebble:GetAttributeChangedSignal("Health"):Connect(function()
        local hp = pebble:GetAttribute("Health") or 0
        print(string.format("   ⚡ [HP Changed!] New HP: %d", hp))
        
        if hp <= 0 then
            print("   💥 HP = 0 detected! Switching target...")
            State.targetDestroyed = true
            if ToolController then ToolController.holdingM1 = false end
        end
    end)
end

----------------------------------------------------------------
-- ACTIONS
----------------------------------------------------------------
local function doOpenEquipments()
    print("📦 Objective: Opening Equipments...")
    
    if not UIController then
        warn("   ❌ UIController not available")
        return false
    end
    
    if UIController.Modules["Inventory"] then
        pcall(function() UIController:Open("Inventory") end)
    end
    
    if UIController.Modules["Menu"] then
        pcall(function() UIController:Open("Menu") end)
        
        local menuModule = UIController.Modules["Menu"]
        if menuModule.OpenTab then
            pcall(function() menuModule:OpenTab("Inventory") end)
            pcall(function() menuModule:OpenTab("Equipments") end)
        elseif menuModule.SwitchTab then
            pcall(function() menuModule:SwitchTab("Inventory") end)
        end
    end
    
    print("   ⏳ Waiting for Menu...")
    task.wait(1)
    
    local toolsButton = nil
    pcall(function()
        toolsButton = playerGui.Menu.Frame.Frame.BottomBar.Buttons.Buttons.Tools
    end)
    
    if toolsButton then
        print("   🖱️ Clicking Tools...")
        VirtualClick(toolsButton)
        task.wait(0.5)
        
        print("   🚪 Closing Menu...")
        if UIController and UIController.Close then
            pcall(function() UIController:Close("Menu") end)
        end
        task.wait(0.3)
        return true
    else
        warn("   ❌ Tools button not found")
        return false
    end
end

local function doEquipPickaxe()
    print("⛏️ Objective: Equipping Stone Pickaxe...")
    
    local key = findPickaxeSlotKey()
    if key then
        print("   🔢 Using hotkey...")
        pressKey(key)
        task.wait(0.5)
    else
        print("   📡 Using remote...")
        pcall(function() 
            CHAR_RF:InvokeServer({Runes = {}, Name = QUEST_CONFIG.PICKAXE_NAME}) 
        end)
        task.wait(0.5)
    end
    
    local char = player.Character
    local tool = char and char:FindFirstChildWhichIsA("Tool")
    if tool and string.find(tool.Name, "Pickaxe") then
        print("   ✅ Pickaxe equipped!")
        return true
    else
        warn("   ⚠️ Pickaxe not in hand yet")
        return false
    end
end

local function doMinePebbles()
    print("🪨 Objective: Mining Pebbles...")
    print("\n" .. string.rep("-", 30))
    print("🚶 Step 1: Moving to starting position...")
    print(string.rep("-", 30))
    
    moveToStartPosition()
    
    print("\n" .. string.rep("-", 30))
    print("⛏️  Step 2: Starting mining loop...")
    print(string.rep("-", 30))
    
    while isQuest2StillActive() and not isCurrentObjectiveComplete() do
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        
        if not hrp then
            task.wait(1)
            continue
        end
        
        cleanupState()
        
        local targetPebble, dist = findNearestPebble()
        
        if not targetPebble then
            warn("   ❌ No Pebbles found, waiting...")
            task.wait(2)
            continue
        end
        
        State.currentTarget = targetPebble
        State.targetDestroyed = false
        
        local targetPos = getPebbleUndergroundPosition(targetPebble)
        if not targetPos then
            warn("   ❌ Cannot get pebble underground position!")
            task.wait(1)
            continue
        end
        
        local currentHP = getPebbleHP(targetPebble)
        local targetName = "Unknown"
        pcall(function()
            if targetPebble.Parent then
                targetName = targetPebble.Parent.Name or "Unknown"
            end
        end)

        print(string.format("   🎯 Target: %s (dist: %d, HP: %d)", 
            targetName, math.floor(dist), currentHP))
        
        watchPebbleHP(targetPebble)
        
        local moveStarted = false
        smoothMoveTo(targetPos, QUEST_CONFIG.STOP_DISTANCE, function()
            lockPositionLayingDown(targetPos)
            moveStarted = true
        end)
        
        local timeout = 60
        local startTime = tick()
        while not moveStarted and (tick() - startTime) < timeout do
            task.wait(0.1)
        end
        
        if not moveStarted then
            lockPositionLayingDown(targetPos)
        end
        
        task.wait(0.5)
        
        while not State.targetDestroyed and isQuest2StillActive() and not isCurrentObjectiveComplete() do
            if not char or not char.Parent then
                print("   💀 Character died!")
                break
            end
            
            if not targetPebble or not targetPebble.Parent then
                print("   💥 Target removed!")
                State.targetDestroyed = true
                break
            end
            
            if checkMiningError() then
                print("   ⚠️ Someone else mining!")
                State.targetDestroyed = true
                if ToolController then ToolController.holdingM1 = false end
                break
            end
            
            local toolInHand = char:FindFirstChildWhichIsA("Tool")
            local isPickaxeHeld = toolInHand and string.find(toolInHand.Name, "Pickaxe")
            
            if not isPickaxeHeld then
                if ToolController then ToolController.holdingM1 = false end
                local key = findPickaxeSlotKey()
                if key then
                    pressKey(key)
                    task.wait(0.3)
                else
                    pcall(function() CHAR_RF:InvokeServer({Runes = {}}, {Name = QUEST_CONFIG.PICKAXE_NAME}) end)
                    task.wait(0.5)
                end
            else
                if ToolController and ToolActivatedFunc then
                    ToolController.holdingM1 = true
                    pcall(function() ToolActivatedFunc(ToolController, toolInHand) end)
                else
                    pcall(function() TOOL_RF_BACKUP:InvokeServer(toolInHand.Name, true) end)
                end
            end
            
            task.wait(0.15)
        end
        
        if isCurrentObjectiveComplete() then
            print("✅ Objective (Mine Pebbles) Complete!")
            break
        end
        
        print("   🔄 Finding next target...")
        task.wait(0.5)
    end
    
    print("\n🛑 Mining ended")
    unlockPosition()
    cleanupState()
end

----------------------------------------------------------------
-- SMART QUEST RUNNER
----------------------------------------------------------------
local function RunQuest2_Smart()
    print(string.rep("=", 50))
    print("🚀 QUEST 2: " .. QUEST_CONFIG.QUEST_NAME)
    print("🎯 SMART SYSTEM: Priority-based + Flexible")
    print("📋 Priority Order: Open → Equip → Mine")
    print("🛡️  Noclip + smoothMoveTo enabled")
    print(string.rep("=", 50))
    
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)
    
    if not questID then
        warn("❌ Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not active")
        Quest2Active = false
        return
    end
    
    print("✅ Quest found (ID: " .. questID .. ")")
    
    local objectives = {}
    for _, item in ipairs(objList:GetChildren()) do
        if item:IsA("Frame") and tonumber(item.Name) then
            local text = getObjectiveText(item)
            local objType = getObjectiveType(text)
            
            table.insert(objectives, {
                order = tonumber(item.Name),
                frame = item,
                text = text,
                type = objType
            })
        end
    end
    
    table.sort(objectives, function(a, b)
        local function getPriority(type)
            for i, priorityType in ipairs(QUEST_CONFIG.PRIORITY_ORDER) do
                if string.find(type, priorityType) then
                    return i
                end
            end
            return 999
        end
        return getPriority(a.type) < getPriority(b.type)
    end)
    
    print("\n" .. string.rep("=", 50))
    print("⚙️  Quest Objectives (Priority Order):")
    for i, obj in ipairs(objectives) do
        local complete = isObjectiveComplete(obj.frame)
        print(string.format("   %d. [%s] %s [%s]", i, obj.type, obj.text, complete and "✅" or "⏳"))
    end
    print(string.rep("=", 50))
    
    local maxAttempts = 5
    local attempt = 0
    
    while isQuest2StillActive() and attempt < maxAttempts do
        attempt = attempt + 1
        print(string.format("\n🔄 Quest Cycle #%d", attempt))
        
        local allComplete = true
        local didSomething = false
        
        for _, obj in ipairs(objectives) do
            if not isQuest2StillActive() then
                print("🛑 Quest disappeared!")
                break
            end
            
            local complete = isObjectiveComplete(obj.frame)
            
            if not complete then
                allComplete = false
                
                if not canDoObjective(obj.type) then
                    print(string.format("   ⏭️  Skipping [%s] - Cannot do right now", obj.type))
                    continue
                end
                
                State.currentObjectiveFrame = obj.frame
                
                print(string.format("\n📋 Processing [%s]: %s", obj.type, obj.text))
                
                local success = false
                
                if obj.type == "Open" then
                    success = doOpenEquipments()
                    didSomething = true
                    task.wait(1)
                    
                elseif obj.type == "Equip" then
                    success = doEquipPickaxe()
                    didSomething = true
                    task.wait(1)
                    
                elseif obj.type == "Mine" then
                    doMinePebbles()
                    didSomething = true
                    
                else
                    warn("   ⚠️ Unknown objective type: " .. obj.type)
                end
                
                task.wait(1)
                if isObjectiveComplete(obj.frame) then
                    print(string.format("✅ [%s] Complete!", obj.type))
                else
                    print(string.format("⏳ [%s] Still in progress", obj.type))
                end
            end
        end
        
        if allComplete then
            print("\n🎉 All objectives complete!")
            break
        end
        
        if not didSomething then
            warn("\n⚠️ No objectives could be completed this cycle!")
            print("   Waiting 2s before retry...")
            task.wait(2)
        end
    end
    
    task.wait(1)
    
    local allComplete = true
    for _, obj in ipairs(objectives) do
        if not isObjectiveComplete(obj.frame) then
            allComplete = false
            warn(string.format("   ⚠️ [%s] incomplete: %s", obj.type, obj.text))
        end
    end
    
    if allComplete then
        print("\n" .. string.rep("=", 50))
        print("✅ Quest 2 Complete!")
        print(string.rep("=", 50))
    else
        warn("\n" .. string.rep("=", 50))
        warn("⚠️ Quest 2 incomplete after " .. attempt .. " cycles")
        warn(string.rep("=", 50))
    end
    
    Quest2Active = false
    disableNoclip()
    cleanupState()
end

----------------------------------------------------------------
-- START
----------------------------------------------------------------
RunQuest2_Smart()

end

-- Quest 03
_G.QuestFunctions[3] = function()
--[[
    ⚔️ QUEST 03: Learning to Forge!
    📋 Forge a Weapon at the Forge
    📍 Extracted from 0.lua (lines 1554-2240)
--]]

-- QUEST 3 ONLY: "Learning to Forge!" (FIXED: smoothMoveTo + Lock Position)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest3Active = true

local FORGE_CONFIG = {
    REQUIRED_ORE_COUNT = 3,
    ITEM_TYPE = "Weapon",
    FORGE_DELAY = 2,
    FORGE_POSITION = Vector3.new(-192.3, 29.5, 168.1),
    MOVE_SPEED = 25,  
}

----------------------------------------------------------------
-- SERVICES & REMOTES
----------------------------------------------------------------
local SERVICES = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")
local PROXIMITY_RF = SERVICES:WaitForChild("ProximityService"):WaitForChild("RF"):WaitForChild("Forge")

local FORGE_OBJECT = Workspace:WaitForChild("Proximity"):WaitForChild("Forge")

----------------------------------------------------------------
-- KNIT SETUP
----------------------------------------------------------------
local KnitPackage = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitPackage)

if not Knit.OnStart then 
    pcall(function() Knit.Start():await() end)
end

local ForgeController = nil
local ForgeService = nil
local PlayerController = nil
local UIController = nil

pcall(function()
    ForgeController = Knit.GetController("ForgeController")
    ForgeService = Knit.GetService("ForgeService")
    PlayerController = Knit.GetController("PlayerController")
end)

-- Hook UIController from getgc
pcall(function()
    for _, v in pairs(getgc(true)) do
        if type(v) == "table" then
            if rawget(v, "Open") and rawget(v, "Close") and rawget(v, "Modules") then
                UIController = v
                break
            end
        end
    end
end)

if ForgeService then print("✅ ForgeService Ready!") else warn("⚠️ ForgeService not found") end
if PlayerController then print("✅ PlayerController Ready!") else warn("⚠️ PlayerController not found") end
if UIController then print("✅ UIController Ready!") else warn("⚠️ UIController not found") end

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local State = {
    moveConn = nil,
    noclipConn = nil,
    bodyVelocity = nil,
    bodyGyro = nil,
}

local function restoreCollisions()
    local char = player.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = true
        end
    end
end

local function cleanupState()
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
end

----------------------------------------------------------------
-- NOCLIP & MOVEMENT
----------------------------------------------------------------
local function enableNoclip()
    if State.noclipConn then return end
    
    local char = player.Character
    if not char then return end
    
    State.noclipConn = RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
            return
        end
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
    restoreCollisions()
end

local function smoothMoveTo(targetPos, callback)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end

    enableNoclip()

    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = hrp
    State.bodyVelocity = bv

    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.D = 500
    bg.Parent = hrp
    State.bodyGyro = bg

    print(string.format("   🚀 Moving to (%.1f, %.1f, %.1f)...", targetPos.X, targetPos.Y, targetPos.Z))

    State.moveConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv then bv:Destroy() end
            if bg then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end

        local currentPos = hrp.Position
        local direction = (targetPos - currentPos)
        local distance = direction.Magnitude

        if distance < 2 then
            print("   ✅ Reached target!")

            bv.Velocity = Vector3.zero
            task.wait(0.1)

            bv:Destroy()
            bg:Destroy()
            State.bodyVelocity = nil
            State.bodyGyro = nil

            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end

            if callback then callback() end
            return
        end

        local speed = math.min(FORGE_CONFIG.MOVE_SPEED, distance * 10)
        local velocity = direction.Unit * speed

        bv.Velocity = velocity
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
    end)

    return true
end

----------------------------------------------------------------
-- UI MANAGEMENT
----------------------------------------------------------------
local function closeForgeUI()
    print("\n   🚪 Closing Forge UI...")
    
    local closed = false
    
    if UIController and UIController.Close then
        pcall(function()
            if UIController.Modules and UIController.Modules["Forge"] then
                UIController:Close("Forge")
                print("      ✅ Closed via UIController")
                closed = true
            end
        end)
    end
    
    if not closed and ForgeController then
        pcall(function()
            if ForgeController.Close then
                ForgeController:Close()
                print("      ✅ Closed via ForgeController")
                closed = true
            elseif ForgeController.CloseForge then
                ForgeController:CloseForge()
                print("      ✅ Closed via ForgeController.CloseForge")
                closed = true
            end
        end)
    end
    
    if not closed then
        pcall(function()
            local forgeGui = playerGui:FindFirstChild("Forge") or playerGui:FindFirstChild("ForgeUI")
            if forgeGui then
                forgeGui.Enabled = false
                print("      ✅ Closed via PlayerGui")
                closed = true
            end
        end)
    end
    
    if not closed then
        warn("      ⚠️ Could not close Forge UI (may already be closed)")
    end
    
    task.wait(0.5)
end

----------------------------------------------------------------
-- QUEST SYSTEM
----------------------------------------------------------------
local function getQuestObjectives(questName)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil, nil end
    
    local list = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Screen") 
                 and gui.Main.Screen:FindFirstChild("Quests") and gui.Main.Screen.Quests:FindFirstChild("List")
    if not list then return nil, nil end
    
    local questID = nil
    for _, child in ipairs(list:GetChildren()) do
        local id = string.match(child.Name, "^Introduction(%d+)Title$")
        if id and child:FindFirstChild("Frame") and child.Frame:FindFirstChild("TextLabel") then
            if child.Frame.TextLabel.Text == questName then
                questID = id
                break
            end
        end
    end
    
    if not questID then return nil, nil end
    
    local objList = list:FindFirstChild("Introduction" .. questID .. "List")
    return questID, objList
end

local function isQuestComplete(questName)
    local questID, objList = getQuestObjectives(questName)
    
    if not questID or not objList then
        return true
    end
    
    for _, item in ipairs(objList:GetChildren()) do
        if item:IsA("Frame") and tonumber(item.Name) then
            local check = item:FindFirstChild("Main") and item.Main:FindFirstChild("Frame") and item.Main.Frame:FindFirstChild("Check")
            if check and not check.Visible then
                return false
            end
        end
    end
    
    return true
end

local function isQuest3StillActive()
    if not Quest3Active then return false end
    
    if isQuestComplete("Learning to Forge!") then
        print("🛑 Quest 'Learning to Forge!' completed!")
        Quest3Active = false
        return false
    end
    
    local questID, objList = getQuestObjectives("Learning to Forge!")
    if not questID or not objList then
        print("🛑 Quest 'Learning to Forge!' not found!")
        Quest3Active = false
        return false
    end
    
    return true
end

----------------------------------------------------------------
-- INVENTORY SYSTEM
----------------------------------------------------------------
local function getPlayerInventory()
    local inventory = {}
    
    if not PlayerController then
        warn("   ⚠️ PlayerController not available!")
        return inventory
    end
    
    if not PlayerController.Replica then
        print("   ⏳ Waiting for Replica...")
        task.wait(2)
    end
    
    if not PlayerController.Replica then
        warn("   ❌ Replica still not available!")
        return inventory
    end
    
    local replica = PlayerController.Replica
    
    if replica and replica.Data and replica.Data.Inventory then
        print("   ✅ Reading from Replica.Data.Inventory")
        
        for itemName, amount in pairs(replica.Data.Inventory) do
            if type(amount) == "number" and amount > 0 then
                inventory[itemName] = amount
            end
        end
    else
        warn("   ❌ Replica.Data.Inventory not found!")
    end
    
    return inventory
end

local function getAvailableOres()
    local inventory = getPlayerInventory()
    local ores = {}
    
    local oreTypes = {"Copper","Stone", "Iron","Sand Stone", "Tin", "Cardboardite", "Silver", "Gold", "Bananite", "Mushroomite", "Platinum","Aite","Poopite"}
    
    for _, oreName in ipairs(oreTypes) do
        if inventory[oreName] and inventory[oreName] > 0 then
            table.insert(ores, {Name = oreName, Amount = inventory[oreName]})
        end
    end
    
    if #ores == 0 then
        print("   🔍 Scanning all items for ores...")
        for itemName, amount in pairs(inventory) do
            if string.find(itemName, "Ore") or string.find(itemName, "ore") then
                table.insert(ores, {Name = itemName, Amount = amount})
            end
        end
    end
    
    return ores
end

local function selectRandomOres(count)
    local availableOres = getAvailableOres()
    
    if #availableOres == 0 then
        return nil, "No ores found in inventory!"
    end
    
    local totalOres = 0
    for _, ore in ipairs(availableOres) do
        totalOres = totalOres + ore.Amount
    end
    
    if totalOres < count then
        return nil, string.format("Not enough ores! Need %d, have %d", count, totalOres)
    end
    
    local orePool = {}
    for _, ore in ipairs(availableOres) do
        for i = 1, ore.Amount do
            table.insert(orePool, ore.Name)
        end
    end
    
    local selected = {}
    for i = 1, count do
        if #orePool == 0 then break end
        
        local randomIndex = math.random(1, #orePool)
        local oreName = table.remove(orePool, randomIndex)
        
        selected[oreName] = (selected[oreName] or 0) + 1
    end
    
    return selected, nil
end

local function printInventorySummary()
    print("\n   📦 === INVENTORY CHECK ===")
    
    local ores = getAvailableOres()
    
    if #ores == 0 then
        warn("   ❌ No ores found in inventory!")
        return
    end
    
    print("   ✅ Available Ores:")
    local total = 0
    for _, ore in ipairs(ores) do
        print(string.format("      • %s: %d", ore.Name, ore.Amount))
        total = total + ore.Amount
    end
    print(string.format("      📊 Total: %d ores", total))
    print("   " .. string.rep("=", 28) .. "\n")
end

----------------------------------------------------------------
-- FORGE SYSTEM
----------------------------------------------------------------
getgenv().ForgeHookActive = getgenv().ForgeHookActive or false

local function setupForgeHook()
    if getgenv().ForgeHookActive then
        print("   ⚠️ Forge Hook already active")
        return
    end
    
    if not ForgeService then
        warn("   ❌ ForgeService not available!")
        return
    end
    
    print("   🪝 Installing Forge Hook...")
    local originalChangeSequence = ForgeService.ChangeSequence
    
    ForgeService.ChangeSequence = function(self, sequenceName, args)
        print("      🔄 Sequence: " .. sequenceName)
        
        local success, result = pcall(originalChangeSequence, self, sequenceName, args)
        
        task.spawn(function()
            if sequenceName == "Melt" then
                print("      ⏩ Auto: Pouring in 8s...")
                task.wait(8)
                self:ChangeSequence("Pour", {ClientTime = 8.5, InContact = true})
                
            elseif sequenceName == "Pour" then
                print("      ⏩ Auto: Hammering in 5s...")
                task.wait(5)
                self:ChangeSequence("Hammer", {ClientTime = 5.2})
                
            elseif sequenceName == "Hammer" then
                print("      ⏩ Auto: Watering in 6s...")
                task.wait(6)
                self:ChangeSequence("Water", {ClientTime = 6.5})
                
            elseif sequenceName == "Water" then
                print("      ⏩ Auto: Showcasing in 3s...")
                task.wait(3)
                self:ChangeSequence("Showcase", {})
                
            elseif sequenceName == "Showcase" then
                print("      ✅ Forge completed!")
            end
        end)
        
        return success, result
    end
    
    getgenv().ForgeHookActive = true
    print("   ✅ Forge Hook installed!")
end

local function moveToForge()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    local forgePos = FORGE_CONFIG.FORGE_POSITION
    local currentDist = (forgePos - hrp.Position).Magnitude
    
    print(string.format("   🚶 Moving to Forge at (%.1f, %.1f, %.1f) (%.1f studs away)...", 
        forgePos.X, forgePos.Y, forgePos.Z, currentDist))
    
    local moveComplete = false
    smoothMoveTo(forgePos, function()
        moveComplete = true
    end)
    
    local timeout = 60
    local startTime = tick()
    while not moveComplete and tick() - startTime < timeout do
        task.wait(0.1)
    end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    print("   ✅ Reached Forge!")
    
    print("   ⏸️  Waiting 1.5s before opening Forge UI...")
    task.wait(1.5)
    
    return true
end

local function startForge(oreSelection)
    print("   🔥 Starting Forge with:")
    for oreName, amount in pairs(oreSelection) do
        print(string.format("      • %s x%d", oreName, amount))
    end
    
    local success = pcall(function()
        PROXIMITY_RF:InvokeServer(FORGE_OBJECT)
    end)
    
    if not success then
        warn("   ❌ Failed to invoke Forge remote")
        return false
    end
    
    task.wait(1)
    
    if not ForgeService then
        warn("   ❌ ForgeService not available!")
        return false
    end
    
    local forgeSuccess = pcall(function()
        ForgeService:ChangeSequence("Melt", {
            Ores = oreSelection,
            ItemType = FORGE_CONFIG.ITEM_TYPE,
            FastForge = false
        })
    end)
    
    if forgeSuccess then
        print("   ✅ Forge Melt started!")
        return true
    else
        warn("   ⚠️ Could not start forge melt")
        return false
    end
end

local function doForgeLoop()
    print("🔥 Action: Auto Forging...")
    
    setupForgeHook()
    
    moveToForge()
    
    local forgeCount = 0
    local consecutiveFailures = 0
    
    while isQuest3StillActive() do
        forgeCount = forgeCount + 1
        print(string.format("\n   🔨 Forge Attempt #%d", forgeCount))
        
        printInventorySummary()
        
        local oreSelection, errorMsg = selectRandomOres(FORGE_CONFIG.REQUIRED_ORE_COUNT)
        
        if not oreSelection then
            warn(string.format("\n❌ ERROR: %s", errorMsg))
            consecutiveFailures = consecutiveFailures + 1
            
            if consecutiveFailures >= 3 then
                warn("❌ Failed 3 times in a row. Cannot continue forging!")
                warn("💡 Please mine more ores and try again.")
                Quest3Active = false
                break
            end
            
            warn(string.format("⏳ Waiting 5s before retry... (%d/3 failures)", consecutiveFailures))
            task.wait(5)
            continue
        end
        
        consecutiveFailures = 0
        
        local success = startForge(oreSelection)
        
        if success then
            print("   ⏳ Waiting for forge to complete...")
            task.wait(25)
        else
            warn("   ⚠️ Forge failed, retrying in 3s...")
            task.wait(3)
        end
        
        if not isQuest3StillActive() then
            print("   ✅ Quest complete!")
            break
        end
        
        print(string.format("   ⏸️ Cooling down for %ds...", FORGE_CONFIG.FORGE_DELAY))
        task.wait(FORGE_CONFIG.FORGE_DELAY)
    end
    
    print("\n🛑 Quest 3 forging ended")
end

----------------------------------------------------------------
-- MAIN RUNNER
----------------------------------------------------------------
local function Run_Quest3()
    print(string.rep("=", 50))
    print("🚀 QUEST 3: Learning to Forge!")
    print("🛡️  Noclip + Lock Position enabled")
    print("📍 Forge Position: (-192.3, 29.5, 168.1)")
    print("⏸️  Wait 1.5s before opening Forge UI")
    print(string.rep("=", 50))
    
    local questID, objList = getQuestObjectives("Learning to Forge!")
    
    if not questID then
        warn("❌ Quest 'Learning to Forge!' not found!")
        warn("💡 Make sure the quest is active in your quest log.")
        Quest3Active = false
        return
    end
    
    print("✅ Quest found (ID: " .. questID .. ")")
    
    print("\n" .. string.rep("=", 50))
    print("🔥 Starting Forge Sequence...")
    print(string.rep("=", 50))
    
    doForgeLoop()
    
    closeForgeUI()
    
    if Quest3Active == false and not isQuestComplete("Learning to Forge!") then
        warn("\n" .. string.rep("=", 50))
        warn("❌ Quest 3 Failed!")
        warn("Reason: Not enough ores to continue")
        warn(string.rep("=", 50))
    else
        print("\n" .. string.rep("=", 50))
        print("✅ Quest 3 Complete!")
        print(string.rep("=", 50))
    end
    
    Quest3Active = false
    disableNoclip()
    cleanupState()
end

----------------------------------------------------------------
-- START
----------------------------------------------------------------
Run_Quest3()

end

-- Quest 04
_G.QuestFunctions[4] = function()
--[[
    ⚔️ QUEST 04: Getting Equipped!
    📋 Equip Best Weapon → Sell Weakest Weapon
    📍 Extracted from 0.lua (lines 2245-3010)
--]]

-- QUEST 4: "Getting Equipped!" (SMART SYSTEM: Priority-based + Flexible + UI Damage Reading)
-- Priority Order: 1) Equip Best Weapon → 2) Sell Weakest Weapon

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest4Active = true

-- Weapon Types (ALL WEAPONS IN GAME - 23 Types)
local WEAPON_TYPES = {
    "Dagger", "Falchion Knife", "Gladius Dagger", "Hook",
    "Crusaders Sword", "Long Sword", "Falchion Sword", "Gladius Sword",
    "Cutlass", "Rapier", "Great Sword", "Uchigatana", "Tachi",
    "Double Battle Axe", "Hammer", "Skull Crusher", "Scythe",
    "Dragon Slayer", "Comically Large Spoon", "Chaos", "Ironhand",
    "Boxing Gloves", "Relevator"
}

-- Sell Config
local SELL_CONFIG = {
    NPC_NAME = "Marbles",
    KEEP_BEST_COUNT = 1
}

-- Priority Order
local PRIORITY_ORDER = {
    "Equip",   -- 1. ใส่อาวุธดีที่สุดก่อน
    "Sell",    -- 2. แล้วค่อยขายอาวุธแย่ที่สุด
}

----------------------------------------------------------------
-- KNIT SETUP
----------------------------------------------------------------
local KnitPackage = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitPackage)

if not Knit.OnStart then 
    pcall(function() Knit.Start():await() end)
end

local CharacterService = nil
local PlayerController = nil
local ProximityService = nil
local DialogueService = nil
local UIController = nil

pcall(function()
    CharacterService = Knit.GetService("CharacterService")
    PlayerController = Knit.GetController("PlayerController")
    ProximityService = Knit.GetService("ProximityService")
    DialogueService = Knit.GetService("DialogueService")
end)

pcall(function()
    for _, v in pairs(getgc(true)) do
        if type(v) == "table" then
            if rawget(v, "Open") and rawget(v, "Close") and rawget(v, "Modules") then
                UIController = v
                break
            end
        end
    end
end)

if CharacterService then print("✅ CharacterService Ready!") else warn("⚠️ CharacterService not found") end
if PlayerController then print("✅ PlayerController Ready!") else warn("⚠️ PlayerController not found") end
if ProximityService then print("✅ ProximityService Ready!") else warn("⚠️ ProximityService not found") end
if DialogueService then print("✅ DialogueService Ready!") else warn("⚠️ DialogueService not found") end
if UIController then print("✅ UIController Ready!") else warn("⚠️ UIController not found") end

----------------------------------------------------------------
-- QUEST SYSTEM
----------------------------------------------------------------
local function getQuestObjectives(questName)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil, nil end
    
    local list = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Screen") 
                 and gui.Main.Screen:FindFirstChild("Quests") and gui.Main.Screen.Quests:FindFirstChild("List")
    if not list then return nil, nil end
    
    local questID = nil
    for _, child in ipairs(list:GetChildren()) do
        local id = string.match(child.Name, "^Introduction(%d+)Title$")
        if id and child:FindFirstChild("Frame") and child.Frame:FindFirstChild("TextLabel") then
            if child.Frame.TextLabel.Text == questName then
                questID = id
                break
            end
        end
    end
    
    if not questID then return nil, nil end
    
    local objList = list:FindFirstChild("Introduction" .. questID .. "List")
    return questID, objList
end

local function isObjectiveComplete(item)
    if not item then return false end
    local check = item:FindFirstChild("Main") and item.Main:FindFirstChild("Frame") and item.Main.Frame:FindFirstChild("Check")
    return check and check.Visible
end

local function getObjectiveText(item)
    local lbl = item:FindFirstChild("Main") and item.Main:FindFirstChild("TextLabel")
    return lbl and lbl.Text or ""
end

local function isQuest4StillActive()
    if not Quest4Active then return false end
    
    local questID, objList = getQuestObjectives("Getting Equipped!")
    if not questID or not objList then
        print("🛑 Quest 'Getting Equipped!' not found!")
        Quest4Active = false
        return false
    end
    
    return true
end

local function getObjectiveType(text)
    if string.find(text, "Equip") and string.find(text, "Weapon") then
        return "Equip"
    elseif string.find(text, "Sell") and string.find(text, "Weapon") then
        return "Sell"
    else
        return "Unknown"
    end
end

----------------------------------------------------------------
-- UI MANAGEMENT
----------------------------------------------------------------
local function openToolsMenu()
    if not UIController then
        warn("   ⚠️ UIController not available, using fallback...")
        return false
    end
    
    if UIController.Modules["Menu"] then
        pcall(function() UIController:Open("Menu") end)
        task.wait(0.5)
        
        local menuModule = UIController.Modules["Menu"]
        if menuModule.OpenTab then
            pcall(function() menuModule:OpenTab("Tools") end)
        elseif menuModule.SwitchTab then
            pcall(function() menuModule:SwitchTab("Tools") end)
        end
        
        task.wait(0.5)
        return true
    end
    
    return false
end

local function closeToolsMenu()
    if UIController and UIController.Close then
        pcall(function() UIController:Close("Menu") end)
        task.wait(0.3)
    end
end

local function getDamageFromUI(guid)
    local menuGui = playerGui:FindFirstChild("Menu")
    if not menuGui then return 0 end
    
    local toolsFrame = menuGui:FindFirstChild("Frame") and menuGui.Frame:FindFirstChild("Frame") 
                       and menuGui.Frame.Frame:FindFirstChild("Menus") 
                       and menuGui.Frame.Frame.Menus:FindFirstChild("Tools")
                       and menuGui.Frame.Frame.Menus.Tools:FindFirstChild("Frame")
    
    if not toolsFrame then return 0 end
    
    local weaponFrame = toolsFrame:FindFirstChild(guid)
    if not weaponFrame then return 0 end
    
    local stats = weaponFrame:FindFirstChild("Stats")
    if not stats then return 0 end
    
    local dmgLabel = stats:FindFirstChild("DMG")
    if not dmgLabel or not dmgLabel:IsA("TextLabel") then return 0 end
    
    local text = dmgLabel.Text
    local damageValue = tonumber(string.match(text, "([%d%.]+)"))
    
    return damageValue or 0
end

----------------------------------------------------------------
-- WEAPON MANAGEMENT
----------------------------------------------------------------
local function isWeaponType(itemType)
    for _, weaponType in ipairs(WEAPON_TYPES) do
        if itemType == weaponType then
            return true
        end
    end
    return false
end

local function isWeaponEquippedFromUI(guid)
    local menuGui = playerGui:FindFirstChild("Menu")
    if not menuGui then return false end
    
    local toolsFrame = menuGui:FindFirstChild("Frame") and menuGui.Frame:FindFirstChild("Frame") 
                    and menuGui.Frame.Frame:FindFirstChild("Menus") 
                    and menuGui.Frame.Frame.Menus:FindFirstChild("Tools")
                    and menuGui.Frame.Frame.Menus.Tools:FindFirstChild("Frame")
    
    if not toolsFrame then return false end
    
    local weaponFrame = toolsFrame:FindFirstChild(guid)
    if not weaponFrame then return false end
    
    local equipButton = weaponFrame:FindFirstChild("Equip")
    if not equipButton then return false end
    
    local textLabel = equipButton:FindFirstChild("TextLabel")
    if not textLabel or not textLabel:IsA("TextLabel") then return false end
    
    return textLabel.Text == "Unequip"
end

local function getPlayerWeapons()
    if not PlayerController or not PlayerController.Replica then
        warn("   ⚠️ Replica not available!")
        return {}
    end
    
    local replica = PlayerController.Replica
    
    if not replica.Data or not replica.Data.Inventory or not replica.Data.Inventory.Equipments then
        warn("   ⚠️ Equipments not found in Replica!")
        return {}
    end
    
    print("   📂 Opening Tools menu to read damage...")
    openToolsMenu()
    
    local equipments = replica.Data.Inventory.Equipments
    local weapons = {}
    
    for id, item in pairs(equipments) do
        if type(item) == "table" and item.Type and isWeaponType(item.Type) then
            local guid = item.GUID
            local quality = item.Quality or 0
            local damage = getDamageFromUI(guid)
            local isEquipped = isWeaponEquippedFromUI(guid)
            
            table.insert(weapons, {
                ID = id,
                Type = item.Type,
                Damage = damage,
                Quality = quality,
                GUID = guid,
                Data = item,
                IsEquipped = isEquipped
            })
            
            print(string.format("      - %s | Dmg: %.2f | GUID: %s | Equipped: %s", 
                item.Type, damage, guid, tostring(isEquipped)))
        end
    end
    
    closeToolsMenu()
    
    return weapons
end

local function findBestWeapon()
    local weapons = getPlayerWeapons()
    
    if #weapons == 0 then
        return nil, "No weapons found in inventory!"
    end
    
    local bestWeapon = weapons[1]
    
    for _, weapon in ipairs(weapons) do
        if weapon.Damage > bestWeapon.Damage then
            bestWeapon = weapon
        elseif weapon.Damage == bestWeapon.Damage and weapon.Quality > bestWeapon.Quality then
            bestWeapon = weapon
        end
    end
    
    return bestWeapon, nil
end

local function findWeakestWeapon()
    local weapons = getPlayerWeapons()
    
    if #weapons == 0 then
        return nil, "No weapons found in inventory!"
    end
    
    if #weapons <= SELL_CONFIG.KEEP_BEST_COUNT then
        return nil, "Not enough weapons to sell!"
    end
    
    print("\n🔍 Finding weakest weapon to sell...")
    
    local weakestWeapon = nil
    for _, weapon in ipairs(weapons) do
        if not weapon.IsEquipped then
            if not weakestWeapon then
                weakestWeapon = weapon
            elseif weapon.Damage < weakestWeapon.Damage then
                weakestWeapon = weapon
            elseif weapon.Damage == weakestWeapon.Damage and weapon.Quality < weakestWeapon.Quality then
                weakestWeapon = weapon
            end
        else
            print(string.format("   ⚠️ Skipping equipped weapon: %s (Dmg: %.2f, Quality: %.1f)", 
                weapon.Type, weapon.Damage, weapon.Quality))
        end
    end
    
    if weakestWeapon then
        print(string.format("   ✅ Selected weakest (not equipped): %s | Dmg: %.2f | GUID: %s", 
            weakestWeapon.Type, weakestWeapon.Damage, weakestWeapon.GUID))
        return weakestWeapon, nil
    end
    
    print("   ⚠️ [FALLBACK] Weakest weapon is equipped! Selecting any sellable weapon...")
    for _, weapon in ipairs(weapons) do
        if not weapon.IsEquipped then
            print(string.format("   → Selected fallback: %s | Dmg: %.2f | GUID: %s", 
                weapon.Type, weapon.Damage, weapon.GUID))
            return weapon, nil
        end
    end
    
    return nil, "All weapons are equipped or no valid weapon to sell!"
end

local function canDoObjective(objType)
    if objType == "Sell" then
        local weapons = getPlayerWeapons()
        if #weapons <= 1 then
            print("   ⚠️ Cannot Sell: Need at least 2 weapons (have " .. #weapons .. ")")
            return false
        end
    end
    return true
end

local function printWeaponsSummary()
    print("\n   ⚔️  === WEAPONS INVENTORY ===")
    
    local weapons = getPlayerWeapons()
    
    if #weapons == 0 then
        warn("   ❌ No weapons found!")
        return
    end
    
    print(string.format("   ✅ Found %d weapon(s):", #weapons))
    
    table.sort(weapons, function(a, b)
        if a.Damage ~= b.Damage then
            return a.Damage > b.Damage
        else
            return a.Quality > b.Quality
        end
    end)
    
    for i, weapon in ipairs(weapons) do
        local marker = ""
        if i == 1 then marker = " 👑 BEST" end
        if i == #weapons and #weapons > 1 and not weapon.IsEquipped then 
            marker = " 🗑️ WORST" 
        end
        if weapon.IsEquipped then 
            marker = marker .. " ⚡ EQUIPPED" 
        end
        
        print(string.format("      %d. %s - Dmg: %.2f | Quality: %.1f%s", 
            i, weapon.Type, weapon.Damage, weapon.Quality, marker))
    end
    
    print("   " .. string.rep("=", 30) .. "\n")
end

----------------------------------------------------------------
-- FORCE RESTORE STATE
----------------------------------------------------------------
local function forceRestoreState()
    print("   🔧 Restoring Player State...")
    
    local char = player.Character
    if char then
        local status = char:FindFirstChild("Status")
        if status then
            for _, tag in ipairs(status:GetChildren()) do
                if tag.Name == "DisableBackpack" or tag.Name == "NoMovement" or tag.Name == "Talking" then
                    tag:Destroy()
                end
            end
        end
        
        if char:FindFirstChild("Humanoid") then
            char.Humanoid.WalkSpeed = 16
            char.Humanoid.JumpPower = 50
        end
    end
    
    local gui = player:FindFirstChild("PlayerGui")
    if gui then
        local dUI = gui:FindFirstChild("DialogueUI")
        if dUI then dUI.Enabled = false end
        
        local main = gui:FindFirstChild("Main")
        if main then main.Enabled = true end
        
        local backpack = gui:FindFirstChild("BackpackGui")
        if backpack then backpack.Enabled = true end
    end
    
    local cam = Workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
    end
    
    pcall(function()
        local dialogueRE = ReplicatedStorage.Shared.Packages.Knit.Services.DialogueService.RE.DialogueEvent
        dialogueRE:FireServer("Closed")
    end)
    
    print("   ✅ State restored!")
end

----------------------------------------------------------------
-- ACTIONS
----------------------------------------------------------------
local function doEquipBestWeapon()
    print("⚔️  Objective: Equipping Best Weapon...")
    
    printWeaponsSummary()
    
    local bestWeapon, errorMsg = findBestWeapon()
    
    if not bestWeapon then
        warn(string.format("   ❌ ERROR: %s", errorMsg))
        return false
    end
    
    print(string.format("   🎯 Selected: %s (Dmg: %.2f | Quality: %.1f)", bestWeapon.Type, bestWeapon.Damage, bestWeapon.Quality))
    
    if not CharacterService then
        warn("   ❌ CharacterService not available!")
        return false
    end
    
    local success, err = pcall(function()
        CharacterService:EquipItem(bestWeapon.Data)
    end)
    
    if success then
        print("   ✅ Equipped successfully!")
        return true
    else
        warn("   ❌ Failed to equip: " .. tostring(err))
        return false
    end
end

local function doSellWeakestWeapon()
    print("💰 Objective: Selling Weakest Weapon...")
    
    printWeaponsSummary()
    
    local weakestWeapon, errorMsg = findWeakestWeapon()
    
    if not weakestWeapon then
        warn(string.format("   ❌ ERROR: %s", errorMsg))
        return false
    end
    
    print(string.format("   🎯 Selected: %s (Dmg: %.2f | Quality: %.1f)", weakestWeapon.Type, weakestWeapon.Damage, weakestWeapon.Quality))
    
    local basket = {}
    basket[weakestWeapon.GUID] = true
    
    local proximity = Workspace:FindFirstChild("Proximity")
    local npc = proximity and (proximity:FindFirstChild(SELL_CONFIG.NPC_NAME) or proximity:FindFirstChild("Greedy Cey"))
    
    if not npc then
        warn("   ❌ NPC not found!")
        return false
    end
    
    if not ProximityService or not DialogueService then
        warn("   ❌ Services not available!")
        return false
    end
    
    print("   🔌 Opening dialogue...")
    local success1 = pcall(function()
        ProximityService:ForceDialogue(npc, "SellConfirm")
    end)
    
    if not success1 then
        warn("   ❌ Failed to open dialogue")
        return false
    end
    
    task.wait(0.2)
    
    print("   💸 Selling weapon...")
    local success2 = pcall(function()
        DialogueService:RunCommand("SellConfirm", { Basket = basket })
    end)
    
    if success2 then
        print("   ✅ Sold successfully!")
        task.wait(0.1)
        forceRestoreState()
        return true
    else
        warn("   ❌ Sell failed")
        forceRestoreState()
        return false
    end
end

----------------------------------------------------------------
-- SMART QUEST RUNNER
----------------------------------------------------------------
local function RunQuest4_Smart()
    print(string.rep("=", 50))
    print("🚀 QUEST 4: Getting Equipped!")
    print("🎯 SMART SYSTEM: Priority-based + Flexible")
    print("📋 Priority Order: Equip → Sell")
    print(string.rep("=", 50))
    
    local questID, objList = getQuestObjectives("Getting Equipped!")
    
    if not questID then
        warn("❌ Quest 'Getting Equipped!' not found!")
        Quest4Active = false
        return
    end
    
    print("✅ Quest found (ID: " .. questID .. ")")
    
    local objectives = {}
    for _, item in ipairs(objList:GetChildren()) do
        if item:IsA("Frame") and tonumber(item.Name) then
            local text = getObjectiveText(item)
            local objType = getObjectiveType(text)
            
            table.insert(objectives, {
                order = tonumber(item.Name),
                frame = item,
                text = text,
                type = objType
            })
        end
    end
    
    table.sort(objectives, function(a, b)
        local function getPriority(type)
            for i, priorityType in ipairs(PRIORITY_ORDER) do
                if string.find(type, priorityType) then
                    return i
                end
            end
            return 999
        end
        return getPriority(a.type) < getPriority(b.type)
    end)
    
    print("\n" .. string.rep("=", 50))
    print("⚙️  Quest Objectives (Priority Order):")
    for i, obj in ipairs(objectives) do
        local complete = isObjectiveComplete(obj.frame)
        print(string.format("   %d. [%s] %s [%s]", i, obj.type, obj.text, complete and "✅" or "⏳"))
    end
    print(string.rep("=", 50))
    
    local maxAttempts = 5
    local attempt = 0
    
    while isQuest4StillActive() and attempt < maxAttempts do
        attempt = attempt + 1
        print(string.format("\n🔄 Quest Cycle #%d", attempt))
        
        local allComplete = true
        local didSomething = false
        
        for _, obj in ipairs(objectives) do
            if not isQuest4StillActive() then
                print("🛑 Quest disappeared!")
                break
            end
            
            local complete = isObjectiveComplete(obj.frame)
            
            if not complete then
                allComplete = false
                
                if not canDoObjective(obj.type) then
                    print(string.format("   ⏭️  Skipping [%s] - Cannot do right now", obj.type))
                    continue
                end
                
                print(string.format("\n📋 Processing [%s]: %s", obj.type, obj.text))
                
                local success = false
                
                if obj.type == "Equip" then
                    success = doEquipBestWeapon()
                    didSomething = true
                    task.wait(1.5)
                    
                elseif obj.type == "Sell" then
                    success = doSellWeakestWeapon()
                    didSomething = true
                    task.wait(1.5)
                    
                else
                    warn("   ⚠️ Unknown objective type: " .. obj.type)
                end
                
                if success then
                    print(string.format("   ✅ Action completed!"))
                else
                    warn(string.format("   ⚠️ Action failed, will retry"))
                end
                
                task.wait(1)
                if isObjectiveComplete(obj.frame) then
                    print(string.format("✅ [%s] Complete!", obj.type))
                else
                    print(string.format("⏳ [%s] Still in progress", obj.type))
                end
            end
        end
        
        if allComplete then
            print("\n🎉 All objectives complete!")
            break
        end
        
        if not didSomething then
            warn("\n⚠️ No objectives could be completed this cycle!")
            print("   Waiting 2s before retry...")
            task.wait(2)
        end
    end
    
    task.wait(1)
    
    local allComplete = true
    for _, obj in ipairs(objectives) do
        if not isObjectiveComplete(obj.frame) then
            allComplete = false
            warn(string.format("   ⚠️ [%s] incomplete: %s", obj.type, obj.text))
        end
    end
    
    if allComplete then
        print("\n" .. string.rep("=", 50))
        print("✅ Quest 4 Complete!")
        print(string.rep("=", 50))
    else
        warn("\n" .. string.rep("=", 50))
        warn("⚠️ Quest 4 incomplete after " .. attempt .. " cycles")
        warn(string.rep("=", 50))
    end
    
    Quest4Active = false
end

----------------------------------------------------------------
-- START
----------------------------------------------------------------
RunQuest4_Smart()

end

-- Quest 05
_G.QuestFunctions[5] = function()
local Shared = _G.Shared

-- QUEST 5: "New Pickaxe!" (SMART SYSTEM: Priority-based + Flexible + Dynamic Zombie Tracking)
-- Priority Order: 1) Purchase → 2) Kill Zombies → 3) Mine Rocks

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest5Active = true
local IsMiningActive = false
local IsKillingActive = false

local QUEST_CONFIG = {
    QUEST_NAME = "New Pickaxe!",
    PICKAXE_NAME = "Bronze Pickaxe",
    PICKAXE_AMOUNT = 1,
    NPC_POSITION = Vector3.new(-81.03, 28.51, 84.68),
    MINING_PATH = "Island1CaveMid",
    ROCK_NAME = "Rock",
    STARTING_POSITION = Vector3.new(50, -10, -200),
    UNDERGROUND_OFFSET = 4,
    ZOMBIE_UNDERGROUND_OFFSET = 5,
    ZOMBIE_MAX_DISTANCE = 50,
    LAYING_ANGLE = 90,
    MOVE_SPEED = 25,  
    
    -- 🔥 NEW: Priority Order
    PRIORITY_ORDER = {
        "Purchase",   -- 1. ซื้อ Pickaxe ก่อน
        "Kill",       -- 2. ฆ่า Zombie
        "Mine",       -- 3. ขุดแร่ (สุดท้าย)
    }
}

----------------------------------------------------------------
-- KNIT SETUP
----------------------------------------------------------------
local KnitPackage = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitPackage)

if not Knit.OnStart then 
    pcall(function() Knit.Start():await() end)
end

local CharacterService = nil
local PlayerController = nil
local ProximityService = nil

pcall(function()
    CharacterService = Knit.GetService("CharacterService")
    PlayerController = Knit.GetController("PlayerController")
    ProximityService = Knit.GetService("ProximityService")
end)

local ToolController = nil
local ToolActivatedFunc = nil

pcall(function()
    for _, v in pairs(getgc(true)) do
        if type(v) == "table" then
            if rawget(v, "Name") == "ToolController" and rawget(v, "ToolActivated") then
                ToolController = v
                ToolActivatedFunc = v.ToolActivated
                break
            end
        end
    end
end)

local SERVICES = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")
local PURCHASE_RF = SERVICES:WaitForChild("ProximityService"):WaitForChild("RF"):WaitForChild("Purchase")
local CHAR_RF = SERVICES:WaitForChild("CharacterService"):WaitForChild("RF"):WaitForChild("EquipItem")
local TOOL_RF_BACKUP = SERVICES:WaitForChild("ToolService"):WaitForChild("RF"):WaitForChild("ToolActivated")

local MINING_FOLDER_PATH = Workspace:WaitForChild("Rocks")
local LIVING_FOLDER = Workspace:WaitForChild("Living")

if CharacterService then print("✅ CharacterService Ready!") else warn("⚠️ CharacterService not found") end
if PlayerController then print("✅ PlayerController Ready!") else warn("⚠️ PlayerController not found") end
if ProximityService then print("✅ ProximityService Ready!") else warn("⚠️ ProximityService not found") end
if ToolController then print("✅ ToolController Ready!") else warn("⚠️ ToolController not found") end
if PURCHASE_RF then print("✅ Purchase Remote Ready!") else warn("⚠️ Purchase Remote not found") end

----------------------------------------------------------------
-- STATE MANAGEMENT
----------------------------------------------------------------
local State = {
    currentTarget = nil,
    targetDestroyed = false,
    hpWatchConn = nil,
    noclipConn = nil,
    moveConn = nil,
    positionLockConn = nil,
    bodyVelocity = nil,
    bodyGyro = nil,
    currentObjectiveFrame = nil,
}

local function cleanupState()
    if State.hpWatchConn then State.hpWatchConn:Disconnect() State.hpWatchConn = nil end
    if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.positionLockConn then State.positionLockConn:Disconnect() State.positionLockConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    State.currentTarget = nil
    State.targetDestroyed = false
    if ToolController then ToolController.holdingM1 = false end
end

----------------------------------------------------------------
-- RESPAWN HANDLER
----------------------------------------------------------------
local function setupRespawnHandler()
    player.CharacterAdded:Connect(function(character)
        print("💀 Character respawned!")
        
        local hrp = character:WaitForChild("HumanoidRootPart", 5)
        if not hrp then return end
        
        task.wait(1)
        
        if (IsMiningActive or IsKillingActive) and Quest5Active then
            print("🔄 Returning to action after respawn...")
            task.wait(2)
        end
    end)
end

----------------------------------------------------------------
-- QUEST SYSTEM
----------------------------------------------------------------
local function getQuestObjectives(questName)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil, nil end
    
    local list = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Screen") 
                 and gui.Main.Screen:FindFirstChild("Quests") and gui.Main.Screen.Quests:FindFirstChild("List")
    if not list then return nil, nil end
    
    local questID = nil
    for _, child in ipairs(list:GetChildren()) do
        local id = string.match(child.Name, "^Introduction(%d+)Title$")
        if id and child:FindFirstChild("Frame") and child.Frame:FindFirstChild("TextLabel") then
            if child.Frame.TextLabel.Text == questName then
                questID = id
                break
            end
        end
    end
    
    if not questID then return nil, nil end
    
    local objList = list:FindFirstChild("Introduction" .. questID .. "List")
    return questID, objList
end

local function isObjectiveComplete(item)
    if not item then return false end
    local check = item:FindFirstChild("Main") and item.Main:FindFirstChild("Frame") and item.Main.Frame:FindFirstChild("Check")
    return check and check.Visible
end

local function getObjectiveText(item)
    local lbl = item:FindFirstChild("Main") and item.Main:FindFirstChild("TextLabel")
    return lbl and lbl.Text or ""
end

local function isQuest5StillActive()
    if not Quest5Active then return false end
    
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)
    if not questID or not objList then
        print("🛑 Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not found!")
        Quest5Active = false
        return false
    end
    
    return true
end

local function isCurrentObjectiveComplete()
    if State.currentObjectiveFrame then
        return isObjectiveComplete(State.currentObjectiveFrame)
    end
    return false
end

-- 🔥 NEW: Classify objective type
local function getObjectiveType(text)
    if string.find(text, "Purchase") or string.find(text, "Buy") or string.find(text, "Pickaxe") then
        return "Purchase"
    elseif string.find(text, "Kill") or string.find(text, "Zombie") or string.find(text, "Defeat") then
        return "Kill"
    elseif string.find(text, "Get Ore") or string.find(text, "Mine") or string.find(text, "Rock") then
        return "Mine"
    else
        return "Unknown"
    end
end

-- 🔥 NEW: Check if objective can be done now (Quest 5 has no dependencies)
local function canDoObjective(objType)
    -- Quest 5 ไม่มี dependency เหมือน Quest 7 (Forge ต้องการแร่)
    -- ทุก objective ทำได้เลย
    return true
end

----------------------------------------------------------------
-- HELPER FUNCTIONS
----------------------------------------------------------------
local HOTKEY_MAP = {
    ["1"] = Enum.KeyCode.One, ["2"] = Enum.KeyCode.Two, ["3"] = Enum.KeyCode.Three,
    ["4"] = Enum.KeyCode.Four, ["5"] = Enum.KeyCode.Five, ["6"] = Enum.KeyCode.Six,
    ["7"] = Enum.KeyCode.Seven, ["8"] = Enum.KeyCode.Eight, ["9"] = Enum.KeyCode.Nine, ["0"] = Enum.KeyCode.Zero
}

local function pressKey(keyCode)
    if not keyCode then return end
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

local function findPickaxeSlotKey()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end
    local hotbar = gui:FindFirstChild("BackpackGui") and gui.BackpackGui:FindFirstChild("Backpack") and gui.BackpackGui.Backpack:FindFirstChild("Hotbar")
    if hotbar then
        for _, slotFrame in ipairs(hotbar:GetChildren()) do
            local frame = slotFrame:FindFirstChild("Frame")
            local label = frame and frame:FindFirstChild("ToolName")
            if label and label:IsA("TextLabel") and string.find(label.Text, "Pickaxe") then
                return HOTKEY_MAP[slotFrame.Name]
            end
        end
    end
    return nil
end

local function findWeaponSlotKey()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end
    local hotbar = gui:FindFirstChild("BackpackGui") and gui.BackpackGui:FindFirstChild("Backpack") and gui.BackpackGui.Backpack:FindFirstChild("Hotbar")
    if hotbar then
        for _, slotFrame in ipairs(hotbar:GetChildren()) do
            local frame = slotFrame:FindFirstChild("Frame")
            local label = frame and frame:FindFirstChild("ToolName")
            if label and label:IsA("TextLabel") and not string.find(label.Text, "Pickaxe") and label.Text ~= "" then
                return HOTKEY_MAP[slotFrame.Name], label.Text
            end
        end
    end
    return nil, nil
end

local function checkMiningError()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return false end
    local notif = gui:FindFirstChild("Notifications")
    if notif and notif:FindFirstChild("Screen") and notif.Screen:FindFirstChild("NotificationsFrame") then
        for _, child in ipairs(notif.Screen.NotificationsFrame:GetChildren()) do
            local lbl = child:FindFirstChild("TextLabel", true)
            if lbl and string.find(lbl.Text, "Someone else is already mining") then return true end
        end
    end
    return false
end

local function getRockUndergroundPosition(rockModel)
    if not rockModel or not rockModel.Parent then return nil end
    
    local pivotCFrame = nil
    
    pcall(function()
        if rockModel.GetPivot then
            pivotCFrame = rockModel:GetPivot()
        elseif rockModel.WorldPivot then
            pivotCFrame = rockModel.WorldPivot
        end
    end)
    
    if pivotCFrame then
        local pos = pivotCFrame.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.UNDERGROUND_OFFSET, pos.Z)
    end
    
    if rockModel.PrimaryPart then
        local pos = rockModel.PrimaryPart.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.UNDERGROUND_OFFSET, pos.Z)
    end
    
    local part = rockModel:FindFirstChildWhichIsA("BasePart")
    if part then
        local pos = part.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.UNDERGROUND_OFFSET, pos.Z)
    end
    
    return nil
end

local function getZombieUndergroundPosition(zombieModel)
    if not zombieModel or not zombieModel.Parent then return nil end
    
    local hrp = zombieModel:FindFirstChild("HumanoidRootPart")
    if hrp then
        local pos = hrp.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.ZOMBIE_UNDERGROUND_OFFSET, pos.Z)
    end
    
    return nil
end

----------------------------------------------------------------
-- HP CHECKER
----------------------------------------------------------------
local function getRockHP(rock)
    if not rock or not rock.Parent then return 0 end
    
    local success, result = pcall(function()
        return rock:GetAttribute("Health") or 0
    end)
    
    return success and result or 0
end

local function isTargetValid(rock)
    if not rock or not rock.Parent then return false end
    if not rock:FindFirstChildWhichIsA("BasePart") then return false end
    
    local hp = getRockHP(rock)
    return hp > 0
end

local function getZombieHP(zombie)
    if not zombie or not zombie.Parent then return 0 end
    local humanoid = zombie:FindFirstChild("Humanoid")
    if humanoid then return humanoid.Health or 0 end
    return 0
end

local function isZombieValid(zombie)
    if not zombie or not zombie.Parent then return false end
    return getZombieHP(zombie) > 0
end

----------------------------------------------------------------
-- TARGET FINDER
----------------------------------------------------------------
local function findNearestRock()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local targetRock, minDist = nil, math.huge
    
    for _, folder in ipairs(MINING_FOLDER_PATH:GetChildren()) do
        if folder:IsA("Folder") or folder:IsA("Model") then
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("SpawnLocation") or child.Name == "SpawnLocation" then
                    local rock = child:FindFirstChild(QUEST_CONFIG.ROCK_NAME)
                    if isTargetValid(rock) then
                        local pos = getRockUndergroundPosition(rock)
                        if pos then
                            local dist = (pos - hrp.Position).Magnitude
                            if dist < minDist then
                                minDist = dist
                                targetRock = rock
                            end
                        end
                    end
                end
            end
        end
    end
    
    return targetRock, minDist
end

local function findNearestZombie()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local targetZombie, minDist = nil, math.huge
    
    for _, child in ipairs(LIVING_FOLDER:GetChildren()) do
        if string.match(child.Name, "^Zombie%d+$") then
            if isZombieValid(child) then
                local pos = getZombieUndergroundPosition(child)
                if pos then
                    local dist = (pos - hrp.Position).Magnitude
                    if dist < minDist then
                        minDist = dist
                        targetZombie = child
                    end
                end
            end
        end
    end
    
    return targetZombie, minDist
end

----------------------------------------------------------------
-- NOCLIP
----------------------------------------------------------------
local function enableNoclip()
    if State.noclipConn then return end
    
    local char = player.Character
    if not char then return end
    
    State.noclipConn = RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
            return
        end
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
    -- ✅ ปิด noclip แล้วคืนการชนให้ตัวละคร
    Shared.restoreCollisions()
end

----------------------------------------------------------------
-- SMOOTH BODY VELOCITY MOVEMENT
----------------------------------------------------------------
local function smoothMoveTo(targetPos, callback)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    enableNoclip()
    
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = hrp
    State.bodyVelocity = bv
    
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.D = 500
    bg.Parent = hrp
    State.bodyGyro = bg
    
    print(string.format("   🚀 Moving to (%.1f, %.1f, %.1f)...", targetPos.X, targetPos.Y, targetPos.Z))
    
    State.moveConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv then bv:Destroy() end
            if bg then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end
        
        local currentPos = hrp.Position
        local direction = (targetPos - currentPos)
        local distance = direction.Magnitude
        
        if distance < 2 then
            print("   ✅ Reached target!")
            
            bv.Velocity = Vector3.zero
            task.wait(0.1)
            
            bv:Destroy()
            bg:Destroy()
            State.bodyVelocity = nil
            State.bodyGyro = nil
            
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            
            if callback then callback() end
            return
        end
        
        local speed = math.min(QUEST_CONFIG.MOVE_SPEED, distance * 10)
        local velocity = direction.Unit * speed
        
        bv.Velocity = velocity
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
    end)
    
    return true
end

----------------------------------------------------------------
-- POSITION LOCK
----------------------------------------------------------------
local function lockPositionLayingDown(targetPos)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    if State.positionLockConn then State.positionLockConn:Disconnect() State.positionLockConn = nil end
    
    local angle = math.rad(QUEST_CONFIG.LAYING_ANGLE)
    local baseCFrame = CFrame.new(targetPos)
    local layingCFrame = baseCFrame * CFrame.Angles(angle, 0, 0)
    
    State.positionLockConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.positionLockConn then State.positionLockConn:Disconnect() State.positionLockConn = nil end
            return
        end
        
        hrp.CFrame = layingCFrame
        hrp.Velocity = Vector3.zero
        hrp.AssemblyLinearVelocity = Vector3.zero
    end)
    
    print("   🛏️ Position locked (laying down)")
end

local function lockPositionFollowTarget(targetModel)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not targetModel then return end
    
    if State.positionLockConn then State.positionLockConn:Disconnect() State.positionLockConn = nil end
    
    local angle = math.rad(QUEST_CONFIG.LAYING_ANGLE)
    
    State.positionLockConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.positionLockConn then State.positionLockConn:Disconnect() State.positionLockConn = nil end
            return
        end
        
        if not targetModel or not targetModel.Parent then
            if State.positionLockConn then State.positionLockConn:Disconnect() State.positionLockConn = nil end
            return
        end
        
        local targetPos = getZombieUndergroundPosition(targetModel)
        if targetPos then
            local baseCFrame = CFrame.new(targetPos)
            local layingCFrame = baseCFrame * CFrame.Angles(angle, 0, 0)
            
            hrp.CFrame = layingCFrame
            hrp.Velocity = Vector3.zero
            hrp.AssemblyLinearVelocity = Vector3.zero
        end
    end)
    
    print("   🎯 Position locked (following target)")
end

local function unlockPosition()
    Shared.SoftUnlockPosition()
end

----------------------------------------------------------------
-- WATCH HP
----------------------------------------------------------------
local function watchRockHP(rock)
    if State.hpWatchConn then State.hpWatchConn:Disconnect() end
    if not rock then return end
    
    State.hpWatchConn = rock:GetAttributeChangedSignal("Health"):Connect(function()
        local hp = rock:GetAttribute("Health") or 0
        print(string.format("   ⚡ [HP Changed!] New HP: %d", hp))
        
        if hp <= 0 then
            print("   💥 HP = 0 detected! Switching target...")
            State.targetDestroyed = true
            if ToolController then ToolController.holdingM1 = false end
            unlockPosition()
        end
    end)
end

local function watchZombieHP(zombie)
    if State.hpWatchConn then State.hpWatchConn:Disconnect() end
    if not zombie then return end
    
    local humanoid = zombie:FindFirstChild("Humanoid")
    if not humanoid then return end
    
    State.hpWatchConn = humanoid:GetPropertyChangedSignal("Health"):Connect(function()
        local hp = humanoid.Health or 0
        print(string.format("   ⚡ [HP Changed!] New HP: %.1f", hp))
        
        if hp <= 0 then
            print("   💀 Zombie died! Switching target...")
            State.targetDestroyed = true
            if ToolController then ToolController.holdingM1 = false end
            unlockPosition()
        end
    end)
end

----------------------------------------------------------------
-- WEAPON MANAGEMENT
----------------------------------------------------------------
local function getBestWeapon()
    if not PlayerController or not PlayerController.Replica then return nil end
    
    local replica = PlayerController.Replica
    if not replica.Data or not replica.Data.Inventory or not replica.Data.Inventory.Equipments then
        return nil
    end
    
    local equipments = replica.Data.Inventory.Equipments
    local bestWeapon = nil
    local highestDmg = 0
    
    for id, item in pairs(equipments) do
        if type(item) == "table" and item.Type then
            if not string.find(item.Type, "Pickaxe") then
                local dmg = item.Dmg or 0
                if dmg > highestDmg then
                    highestDmg = dmg
                    bestWeapon = item
                end
            end
        end
    end
    
    return bestWeapon
end

----------------------------------------------------------------
-- ACTIONS
----------------------------------------------------------------
local function doPurchaseBronzePickaxe()
    print("🛒 Objective: Purchasing Bronze Pickaxe...")
    
    if not PURCHASE_RF then
        warn("   ❌ Purchase Remote not available!")
        return false
    end
    
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    
    if hrp then
        local npcPos = QUEST_CONFIG.NPC_POSITION
        local currentDist = (npcPos - hrp.Position).Magnitude
        
        print(string.format("   🚶 Moving to NPC at (%.2f, %.2f, %.2f) (%.1f studs away)...", 
            npcPos.X, npcPos.Y, npcPos.Z, currentDist))
        
        local moveComplete = false
        smoothMoveTo(npcPos, function()
            moveComplete = true
        end)
        
        local timeout = 60
        local startTime = tick()
        while not moveComplete and tick() - startTime < timeout do
            task.wait(0.1)
        end
        
        if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
        if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
        if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
        
        print("   ✅ Reached NPC!")
        print("   ⏸️  Waiting 1.5s before purchase...")
        task.wait(1.5)
    end
    
    print(string.format("   💰 Purchasing: %s (Amount: %d)", QUEST_CONFIG.PICKAXE_NAME, QUEST_CONFIG.PICKAXE_AMOUNT))
    
    local args = {
        QUEST_CONFIG.PICKAXE_NAME,
        QUEST_CONFIG.PICKAXE_AMOUNT
    }
    
    local success, result = pcall(function()
        return PURCHASE_RF:InvokeServer(unpack(args))
    end)
    
    if success then
        print("   ✅ Purchase successful!")
        return true
    else
        warn("   ❌ Purchase failed: " .. tostring(result))
        return false
    end
end

local function doMineRocks()
    print("⛏️ Objective: Mining Rocks...")
    
    IsMiningActive = true
    
    print("\n" .. string.rep("-", 30))
    print("⛏️ Starting underground mining loop...")
    print(string.rep("-", 30))
    
    while isQuest5StillActive() and not isCurrentObjectiveComplete() do
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        
        if not hrp then
            warn("   ⚠️ Waiting for character...")
            task.wait(2)
            continue
        end
        
        cleanupState()
        
        local targetRock, dist = findNearestRock()
        
        if not targetRock then
            warn("   ❌ No Rocks found, waiting...")
            task.wait(2)
            continue
        end
        
        State.currentTarget = targetRock
        State.targetDestroyed = false
        
        local targetPos = getRockUndergroundPosition(targetRock)
        if not targetPos then
            warn("   ❌ Cannot get rock position!")
            task.wait(1)
            continue
        end
        
        local currentHP = getRockHP(targetRock)
        print(string.format("   🎯 Target: %s (dist: %d, HP: %d)", 
            targetRock.Parent.Name, math.floor(dist), currentHP))
        
        watchRockHP(targetRock)
        
        local moveStarted = false
        smoothMoveTo(targetPos, function()
            lockPositionLayingDown(targetPos)
            moveStarted = true
        end)
        
        local timeout = 60
        local startTime = tick()
        while not moveStarted and tick() - startTime < timeout do
            task.wait(0.1)
        end
        
        if not moveStarted then
            warn("   ⚠️ Move timeout, skip this rock to avoid teleport")
            State.targetDestroyed = true
            unlockPosition()
            -- ไม่ต้อง lockPositionLayingDown ที่นี่
            continue
        end
        
        task.wait(0.5)
        
        while not State.targetDestroyed and isQuest5StillActive() and not isCurrentObjectiveComplete() do
            if not char or not char.Parent then
                print("   💀 Character died!")
                break
            end
            
            if not targetRock or not targetRock.Parent then
                print("   💥 Target removed!")
                State.targetDestroyed = true
                break
            end
            
            if checkMiningError() then
                print("   ⚠️ Someone else mining!")
                State.targetDestroyed = true
                if ToolController then ToolController.holdingM1 = false end
                break
            end
            
            local toolInHand = char:FindFirstChildWhichIsA("Tool")
            local isPickaxeHeld = toolInHand and string.find(toolInHand.Name, "Pickaxe")
            
            if not isPickaxeHeld then
                if ToolController then ToolController.holdingM1 = false end
                local key = findPickaxeSlotKey()
                if key then 
                    pressKey(key) 
                    task.wait(0.3)
                else 
                    pcall(function() CHAR_RF:InvokeServer({Runes = {}, Name = QUEST_CONFIG.PICKAXE_NAME}) end)
                    task.wait(0.5) 
                end
            else
                if ToolController and ToolActivatedFunc then
                    ToolController.holdingM1 = true
                    pcall(function() ToolActivatedFunc(ToolController, toolInHand) end)
                else
                    pcall(function() TOOL_RF_BACKUP:InvokeServer(toolInHand.Name, true) end)
                end
            end
            
            task.wait(0.15)
        end
        
        --unlockPosition()
        
        if isCurrentObjectiveComplete() then
            print("✅ Objective (Mine Rocks) Complete!")
            break
        end
        
        print("   🔄 Finding next target...")
        task.wait(0.5)
    end
    
    print("\n🛑 Mining ended")
    IsMiningActive = false
    unlockPosition()
    disableNoclip()
    cleanupState()
end

local function doKillZombies()
    print("⚔️ Objective: Killing Zombies (Dynamic Tracking)...")
    
    IsKillingActive = true
    
    print("\n" .. string.rep("-", 30))
    print("⚔️ Starting zombie hunting with dynamic tracking...")
    print(string.rep("-", 30))
    
    while isQuest5StillActive() and not isCurrentObjectiveComplete() do
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        
        if not hrp then
            warn("   ⚠️ Waiting for character...")
            task.wait(2)
            continue
        end
        
        cleanupState()
        
        local targetZombie, dist = findNearestZombie()
        
        if not targetZombie then
            warn("   ❌ No Zombies found, waiting...")
            task.wait(2)
            continue
        end
        
        State.currentTarget = targetZombie
        State.targetDestroyed = false
        
        local targetPos = getZombieUndergroundPosition(targetZombie)
        if not targetPos then
            warn("   ❌ Cannot get zombie position!")
            task.wait(1)
            continue
        end
        
        local currentHP = getZombieHP(targetZombie)
        print(string.format("   🎯 Target: %s (dist: %d, HP: %.1f)", 
            targetZombie.Name, math.floor(dist), currentHP))
        
        watchZombieHP(targetZombie)
        
        local moveStarted = false
        smoothMoveTo(targetPos, function()
            lockPositionFollowTarget(targetZombie)
            moveStarted = true
        end)
        
        local timeout = 60
        local startTime = tick()
        while not moveStarted and tick() - startTime < timeout do
            task.wait(0.1)
        end
        
        -- ❌ อย่า hard-lock ถ้าไม่เคยเดินถึงเป้าหมาย
        if not moveStarted then
            warn("   ⚠️ Move timeout, skip this zombie to avoid teleport")
            State.targetDestroyed = true
            unlockPosition()
            continue
        end
        
        task.wait(0.5)
        
        while not State.targetDestroyed and isQuest5StillActive() and not isCurrentObjectiveComplete() do
            if not char or not char.Parent then
                print("   💀 Character died!")
                break
            end
            
            if not targetZombie or not targetZombie.Parent or not isZombieValid(targetZombie) then
                print("   💀 Zombie died or removed!")
                State.targetDestroyed = true
                unlockPosition() 
                break
            end
            
            local currentZombiePos = getZombieUndergroundPosition(targetZombie)
            if currentZombiePos and hrp then
                local distToZombie = (currentZombiePos - hrp.Position).Magnitude
                if distToZombie > QUEST_CONFIG.ZOMBIE_MAX_DISTANCE then
                    print(string.format("   ⚠️ Zombie moved too far! (%.1f studs) Switching target...", distToZombie))
                    State.targetDestroyed = true
                    unlockPosition()
                    break
                end
            end
            
            local toolInHand = char:FindFirstChildWhichIsA("Tool")
            local isWeaponHeld = toolInHand and not string.find(toolInHand.Name, "Pickaxe")
            
            if not isWeaponHeld then
                if ToolController then ToolController.holdingM1 = false end
                
                local bestWeapon = getBestWeapon()
                if bestWeapon then
                    print(string.format("   🗡️ Equipping weapon: %s", bestWeapon.Type))
                    pcall(function() 
                        CharacterService:EquipItem(bestWeapon)
                    end)
                    task.wait(0.5)
                else
                    local key, weaponName = findWeaponSlotKey()
                    if key then
                        print(string.format("   🗡️ Equipping via hotkey: %s", weaponName))
                        pressKey(key)
                        task.wait(0.3)
                    else
                        warn("   ⚠️ No weapon found!")
                        task.wait(1)
                    end
                end
            else
                if ToolController and ToolActivatedFunc then
                    ToolController.holdingM1 = true
                    pcall(function() ToolActivatedFunc(ToolController, toolInHand) end)
                else
                    pcall(function() TOOL_RF_BACKUP:InvokeServer(toolInHand.Name, true) end)
                end
            end
            
            task.wait(0.15)
        end
        
        --unlockPosition()
        
        if isCurrentObjectiveComplete() then
            print("✅ Objective (Kill Zombies) Complete!")
            break
        end
        
        print("   🔄 Finding next target...")
        task.wait(0.5)
    end
    
    print("\n🛑 Zombie hunting ended")
    IsKillingActive = false
    unlockPosition()
    disableNoclip()
    cleanupState()
end

----------------------------------------------------------------
-- 🔥 SMART QUEST RUNNER (Priority-based + Flexible)
----------------------------------------------------------------
print(string.rep("=", 50))
print("🚀 QUEST 5: " .. QUEST_CONFIG.QUEST_NAME)
print("🎯 SMART SYSTEM: Priority-based + Flexible")
print("📋 Priority Order: Purchase → Kill → Mine")
print(string.rep("=", 50))

setupRespawnHandler()

local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)

if not questID then
    warn("❌ Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not found!")
    Quest5Active = false
    return
end

print("✅ Quest found (ID: " .. questID .. ")")

-- Collect all objectives
local objectives = {}
for _, item in ipairs(objList:GetChildren()) do
    if item:IsA("Frame") and tonumber(item.Name) then
        local text = getObjectiveText(item)
        local objType = getObjectiveType(text)
        
        table.insert(objectives, {
            order = tonumber(item.Name),
            frame = item,
            text = text,
            type = objType
        })
    end
end

-- 🔥 Sort by priority instead of original order
table.sort(objectives, function(a, b)
    local function getPriority(type)
        for i, priorityType in ipairs(QUEST_CONFIG.PRIORITY_ORDER) do
            if string.find(type, priorityType) then
                return i
            end
        end
        return 999
    end
    return getPriority(a.type) < getPriority(b.type)
end)

print("\n" .. string.rep("=", 50))
print("⚙️  Quest Objectives (Priority Order):")
for i, obj in ipairs(objectives) do
    local complete = isObjectiveComplete(obj.frame)
    print(string.format("   %d. [%s] %s [%s]", i, obj.type, obj.text, complete and "✅" or "⏳"))
end
print(string.rep("=", 50))

local function hasIncompletePurchase()
    for _, obj in ipairs(objectives) do
        if obj.type == "Purchase" and not isObjectiveComplete(obj.frame) then
            return true
        end
    end
    return false
end

-- 🔥 Main loop: Process objectives by priority
local maxAttempts = 10
local attempt = 0

while isQuest5StillActive() and attempt < maxAttempts do
    attempt = attempt + 1
    print(string.format("\n🔄 Quest Cycle #%d", attempt))
    
    local allComplete = true
    local didSomething = false
    local purchasePending = hasIncompletePurchase()
    
    for _, obj in ipairs(objectives) do
        if not isQuest5StillActive() then
            print("🛑 Quest disappeared!")
            break
        end
        
        local complete = isObjectiveComplete(obj.frame)
        
        if not complete then
            allComplete = false

            -- ⛔ ถ้ายังมี Purchase ที่ไม่เสร็จ → ห้ามทำ objective อื่น
            if purchasePending and obj.type ~= "Purchase" then
                print(string.format("   ⏭️  Skipping [%s] (waiting for Purchase to finish)", obj.type))
                continue
            end
            
            -- 🔥 Check if we can do this objective now
            if not canDoObjective(obj.type) then
                print(string.format("   ⏭️  Skipping [%s] - Cannot do right now", obj.type))
                continue
            end
            
            State.currentObjectiveFrame = obj.frame
            
            print(string.format("\n📋 Processing [%s]: %s", obj.type, obj.text))
            
            -- Execute objective
            if obj.type == "Purchase" then
                doPurchaseBronzePickaxe()
                didSomething = true
                task.wait(2)
                
                -- 🆕 Re-check if Purchase is complete after running
                if isObjectiveComplete(obj.frame) then
                    purchasePending = false
                    print("   ✅ Purchase objective complete! Continuing to other objectives...")
                end
                
            elseif obj.type == "Kill" then
                doKillZombies()
                didSomething = true
                task.wait(1)
                
            elseif obj.type == "Mine" then
                doMineRocks()
                didSomething = true
                task.wait(1)
                
            else
                warn("   ⚠️ Unknown objective type: " .. obj.type)
            end
            
            -- Check if complete
            task.wait(1)
            if isObjectiveComplete(obj.frame) then
                print(string.format("✅ [%s] Complete!", obj.type))
            else
                print(string.format("⏳ [%s] Still in progress", obj.type))
            end
        end
    end
    
    if allComplete then
        print("\n🎉 All objectives complete!")
        break
    end
    
    if not didSomething then
        warn("\n⚠️ No objectives could be completed this cycle!")
        print("   Waiting 3s before retry...")
        task.wait(3)
    end
end

-- Final check
task.wait(2)

local allComplete = true
for _, obj in ipairs(objectives) do
    if not isObjectiveComplete(obj.frame) then
        allComplete = false
        warn(string.format("   ⚠️ [%s] incomplete: %s", obj.type, obj.text))
    end
end

if allComplete then
    print("\n" .. string.rep("=", 50))
    print("✅ Quest 5 Complete!")
    print(string.rep("=", 50))
else
    warn("\n" .. string.rep("=", 50))
    warn("⚠️ Quest 5 incomplete after " .. attempt .. " cycles")
    warn(string.rep("=", 50))
end

Quest5Active = false
IsMiningActive = false
IsKillingActive = false
unlockPosition()
disableNoclip()
cleanupState()

end

-- Quest 06
_G.QuestFunctions[6] = function()
local Shared = _G.Shared

-- QUEST 6 ONLY: "Preparing For Battle!" (FIXED: smoothMoveTo + Lock Position)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest6Active = true

local FORGE_CONFIG = {
    REQUIRED_ORE_COUNT = 3,
    ITEM_TYPE = "Armor",
    FORGE_DELAY = 2,
    FORGE_POSITION = Vector3.new(-192.3, 29.5, 168.1),  -- 🆕 Fixed position
    MOVE_SPEED = 25,  
}

----------------------------------------------------------------
-- SERVICES & REMOTES
----------------------------------------------------------------
local SERVICES = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")
local PROXIMITY_RF = SERVICES:WaitForChild("ProximityService"):WaitForChild("RF"):WaitForChild("Forge")

local FORGE_OBJECT = Workspace:WaitForChild("Proximity"):WaitForChild("Forge")

----------------------------------------------------------------
-- KNIT SETUP
----------------------------------------------------------------
local KnitPackage = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitPackage)

if not Knit.OnStart then 
    pcall(function() Knit.Start():await() end)
end

local ForgeController = nil
local ForgeService = nil
local PlayerController = nil
local UIController = nil

pcall(function()
    ForgeController = Knit.GetController("ForgeController")
    ForgeService = Knit.GetService("ForgeService")
    PlayerController = Knit.GetController("PlayerController")
end)

-- Hook UIController from getgc
pcall(function()
    for _, v in pairs(getgc(true)) do
        if type(v) == "table" then
            if rawget(v, "Open") and rawget(v, "Close") and rawget(v, "Modules") then
                UIController = v
                break
            end
        end
    end
end)

if ForgeService then print("✅ ForgeService Ready!") else warn("⚠️ ForgeService not found") end
if PlayerController then print("✅ PlayerController Ready!") else warn("⚠️ PlayerController not found") end
if UIController then print("✅ UIController Ready!") else warn("⚠️ UIController not found") end

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local State = {
    moveConn = nil,
    noclipConn = nil,
    bodyVelocity = nil,
    bodyGyro = nil,
}

local function cleanupState()
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
end

----------------------------------------------------------------
-- NOCLIP & MOVEMENT
----------------------------------------------------------------
local function enableNoclip()
    if State.noclipConn then return end
    
    local char = player.Character
    if not char then return end
    
    State.noclipConn = RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
            return
        end
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
    -- ✅ ปิด noclip แล้วคืนการชนให้ตัวละคร
    Shared.restoreCollisions()
end

-- 🆕 smoothMoveTo with BodyVelocity + BodyGyro
local function smoothMoveTo(targetPos, callback)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    -- Cleanup previous movement
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    -- Enable noclip
    enableNoclip()
    
    -- Create BodyVelocity
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = hrp
    State.bodyVelocity = bv
    
    -- Create BodyGyro
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.D = 500
    bg.Parent = hrp
    State.bodyGyro = bg
    
    print(string.format("   🚀 Moving to (%.1f, %.1f, %.1f)...", targetPos.X, targetPos.Y, targetPos.Z))
    
    local reachedTarget = false
    
    State.moveConn = RunService.Heartbeat:Connect(function()
        if reachedTarget then return end
        
        -- Check if character or BodyVelocity is destroyed
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv and bv.Parent then bv:Destroy() end
            if bg and bg.Parent then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end
        
        -- Check if BodyVelocity was destroyed by game/other script
        if not bv or not bv.Parent then
            warn("   ⚠️ BodyVelocity destroyed! Recreating...")
            
            -- Recreate BodyVelocity
            bv = Instance.new("BodyVelocity")
            bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bv.Parent = hrp
            State.bodyVelocity = bv
        end
        
        if not bg or not bg.Parent then
            bg = Instance.new("BodyGyro")
            bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
            bg.P = 10000
            bg.D = 500
            bg.Parent = hrp
            State.bodyGyro = bg
        end
        
        local currentPos = hrp.Position
        local direction = (targetPos - currentPos)
        local distance = direction.Magnitude
        
        if distance < 2 then
            print("   ✅ Reached target!")
            
            reachedTarget = true
            
            bv.Velocity = Vector3.zero
            hrp.Velocity = Vector3.zero
            hrp.AssemblyLinearVelocity = Vector3.zero
            
            task.wait(0.1)
            
            if bv and bv.Parent then bv:Destroy() end
            if bg and bg.Parent then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            
            if callback then callback() end
            return
        end
        
        local speed = math.min(FORGE_CONFIG.MOVE_SPEED, distance * 10)
        local velocity = direction.Unit * speed
        
        bv.Velocity = velocity
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
    end)
    
    return true
end

----------------------------------------------------------------
-- UI MANAGEMENT
----------------------------------------------------------------
local function closeForgeUI()
    print("\n   🚪 Closing Forge UI...")
    
    local closed = false
    
    -- Method 1: UIController.Close
    if UIController and UIController.Close then
        pcall(function()
            if UIController.Modules and UIController.Modules["Forge"] then
                UIController:Close("Forge")
                print("      ✅ Closed via UIController")
                closed = true
            end
        end)
    end
    
    -- Method 2: ForgeController
    if not closed and ForgeController then
        pcall(function()
            if ForgeController.Close then
                ForgeController:Close()
                print("      ✅ Closed via ForgeController")
                closed = true
            elseif ForgeController.CloseForge then
                ForgeController:CloseForge()
                print("      ✅ Closed via ForgeController.CloseForge")
                closed = true
            end
        end)
    end
    
    -- Method 3: PlayerGui (direct UI close)
    if not closed then
        pcall(function()
            local forgeGui = playerGui:FindFirstChild("Forge") or playerGui:FindFirstChild("ForgeUI")
            if forgeGui then
                forgeGui.Enabled = false
                print("      ✅ Closed via PlayerGui")
                closed = true
            end
        end)
    end
    
    if not closed then
        warn("      ⚠️ Could not close Forge UI (may already be closed)")
    end
    
    task.wait(0.5)
end

----------------------------------------------------------------
-- QUEST SYSTEM
----------------------------------------------------------------
local function getQuestObjectives(questName)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil, nil end
    
    local list = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Screen") 
                 and gui.Main.Screen:FindFirstChild("Quests") and gui.Main.Screen.Quests:FindFirstChild("List")
    if not list then return nil, nil end
    
    local questID = nil
    for _, child in ipairs(list:GetChildren()) do
        local id = string.match(child.Name, "^Introduction(%d+)Title$")
        if id and child:FindFirstChild("Frame") and child.Frame:FindFirstChild("TextLabel") then
            if child.Frame.TextLabel.Text == questName then
                questID = id
                break
            end
        end
    end
    
    if not questID then return nil, nil end
    
    local objList = list:FindFirstChild("Introduction" .. questID .. "List")
    return questID, objList
end

local function isQuestComplete(questName)
    local questID, objList = getQuestObjectives(questName)
    
    if not questID or not objList then
        return true
    end
    
    for _, item in ipairs(objList:GetChildren()) do
        if item:IsA("Frame") and tonumber(item.Name) then
            local check = item:FindFirstChild("Main") and item.Main:FindFirstChild("Frame") and item.Main.Frame:FindFirstChild("Check")
            if check and not check.Visible then
                return false
            end
        end
    end
    
    return true
end

local function isQuest6StillActive()
    if not Quest6Active then return false end
    
    if isQuestComplete("Preparing For Battle") then  -- ✅ แก้แล้ว
        print("🛑 Quest 'Preparing For Battle' completed!")  -- ✅ แก้แล้ว
        Quest6Active = false
        return false
    end
    
    local questID, objList = getQuestObjectives("Preparing For Battle")  -- ✅ แก้แล้ว
    if not questID or not objList then
        print("🛑 Quest 'Preparing For Battle' not found!")  -- ✅ แก้แล้ว
        Quest6Active = false
        return false
    end
    
    return true
end

----------------------------------------------------------------
-- INVENTORY SYSTEM
----------------------------------------------------------------
local function getPlayerInventory()
    local inventory = {}
    
    if not PlayerController then
        warn("   ⚠️ PlayerController not available!")
        return inventory
    end
    
    if not PlayerController.Replica then
        print("   ⏳ Waiting for Replica...")
        task.wait(2)
    end
    
    if not PlayerController.Replica then
        warn("   ❌ Replica still not available!")
        return inventory
    end
    
    local replica = PlayerController.Replica
    
    if replica and replica.Data and replica.Data.Inventory then
        print("   ✅ Reading from Replica.Data.Inventory")
        
        for itemName, amount in pairs(replica.Data.Inventory) do
            if type(amount) == "number" and amount > 0 then
                inventory[itemName] = amount
            end
        end
    else
        warn("   ❌ Replica.Data.Inventory not found!")
        
        if replica and replica.Data then
            print("   🔍 Available keys in Replica.Data:")
            for k, v in pairs(replica.Data) do
                print("      • " .. tostring(k) .. " = " .. tostring(type(v)))
            end
        end
    end
    
    return inventory
end

local function getAvailableOres()
    local inventory = getPlayerInventory()
    local ores = {}
    
    local oreTypes = {"Copper","Stone", "Iron","Sand Stone", "Tin", "Cardboardite", "Silver", "Gold", "Bananite", "Mushroomite", "Platinum","Aite","Poopite"}
    
    for _, oreName in ipairs(oreTypes) do
        if inventory[oreName] and inventory[oreName] > 0 then
            table.insert(ores, {Name = oreName, Amount = inventory[oreName]})
        end
    end
    
    if #ores == 0 then
        print("   🔍 Scanning all items for ores...")
        for itemName, amount in pairs(inventory) do
            if string.find(itemName, "Ore") or string.find(itemName, "ore") then
                table.insert(ores, {Name = itemName, Amount = amount})
            end
        end
    end
    
    return ores
end

local function selectRandomOres(count)
    local availableOres = getAvailableOres()
    
    if #availableOres == 0 then
        return nil, "No ores found in inventory!"
    end
    
    local totalOres = 0
    for _, ore in ipairs(availableOres) do
        totalOres = totalOres + ore.Amount
    end
    
    if totalOres < count then
        return nil, string.format("Not enough ores! Need %d, have %d", count, totalOres)
    end
    
    local orePool = {}
    for _, ore in ipairs(availableOres) do
        for i = 1, ore.Amount do
            table.insert(orePool, ore.Name)
        end
    end
    
    local selected = {}
    for i = 1, count do
        if #orePool == 0 then break end
        
        local randomIndex = math.random(1, #orePool)
        local oreName = table.remove(orePool, randomIndex)
        
        selected[oreName] = (selected[oreName] or 0) + 1
    end
    
    return selected, nil
end

local function printInventorySummary()
    print("\n   📦 === INVENTORY CHECK ===")
    
    local ores = getAvailableOres()
    
    if #ores == 0 then
        warn("   ❌ No ores found in inventory!")
        
        local inv = getPlayerInventory()
        if next(inv) then
            print("   📋 All items in inventory:")
            for item, amount in pairs(inv) do
                print(string.format("      • %s: %d", item, amount))
            end
        else
            warn("   ⚠️ Inventory is completely empty!")
        end
        return
    end
    
    print("   ✅ Available Ores:")
    local total = 0
    for _, ore in ipairs(ores) do
        print(string.format("      • %s: %d", ore.Name, ore.Amount))
        total = total + ore.Amount
    end
    print(string.format("      📊 Total: %d ores", total))
    print("   " .. string.rep("=", 28) .. "\n")
end

----------------------------------------------------------------
-- FORGE SYSTEM
----------------------------------------------------------------
getgenv().ForgeHookActive = getgenv().ForgeHookActive or false

local function setupForgeHook()
    if getgenv().ForgeHookActive then
        print("   ⚠️ Forge Hook already active")
        return
    end
    
    if not ForgeService then
        warn("   ❌ ForgeService not available!")
        return
    end
    
    print("   🪝 Installing Forge Hook...")
    local originalChangeSequence = ForgeService.ChangeSequence
    
    ForgeService.ChangeSequence = function(self, sequenceName, args)
        print("      🔄 Sequence: " .. sequenceName)
        
        local success, result = pcall(originalChangeSequence, self, sequenceName, args)
        
        task.spawn(function()
            if sequenceName == "Melt" then
                print("      ⏩ Auto: Pouring in 8s...")
                task.wait(8)
                self:ChangeSequence("Pour", {ClientTime = 8.5, InContact = true})
                
            elseif sequenceName == "Pour" then
                print("      ⏩ Auto: Hammering in 5s...")
                task.wait(5)
                self:ChangeSequence("Hammer", {ClientTime = 5.2})
                
            elseif sequenceName == "Hammer" then
                print("      ⏩ Auto: Watering in 6s...")
                task.wait(6)
                self:ChangeSequence("Water", {ClientTime = 6.5})
                
            elseif sequenceName == "Water" then
                print("      ⏩ Auto: Showcasing in 3s...")
                task.wait(3)
                self:ChangeSequence("Showcase", {})
                
            elseif sequenceName == "Showcase" then
                print("      ✅ Forge completed!")
            end
        end)
        
        return success, result
    end
    
    getgenv().ForgeHookActive = true
    print("   ✅ Forge Hook installed!")
end

-- 🆕 IMPROVED: Use smoothMoveTo with fixed position
local function moveToForge()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    local forgePos = FORGE_CONFIG.FORGE_POSITION
    local currentDist = (forgePos - hrp.Position).Magnitude
    
    print(string.format("   🚶 Moving to Forge at (%.1f, %.1f, %.1f) (%.1f studs away)...", 
        forgePos.X, forgePos.Y, forgePos.Z, currentDist))
    
    -- 🆕 Unlock position before moving
    Shared.SoftUnlockPosition()
    
    -- Use smoothMoveTo with noclip + lock position
    local moveComplete = false
    smoothMoveTo(forgePos, function()
        moveComplete = true
    end)
    
    -- Wait for movement to complete
    local timeout = 60
    local startTime = tick()
    while not moveComplete and tick() - startTime < timeout do
        task.wait(0.1)
    end
    
    if not moveComplete then
        warn("   ⚠️ Move timed out! Retrying...")
        if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
        if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
        if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
        return false
    end
    
    -- Cleanup movement
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    print("   ✅ Reached Forge!")
    
    -- Wait 1.5 seconds before opening UI
    print("   ⏸️  Waiting 1.5s before opening Forge UI...")
    task.wait(1.5)
    
    return true
end

local function startForge(oreSelection)
    print("   🔥 Starting Forge with:")
    for oreName, amount in pairs(oreSelection) do
        print(string.format("      • %s x%d", oreName, amount))
    end
    
    local success = pcall(function()
        PROXIMITY_RF:InvokeServer(FORGE_OBJECT)
    end)
    
    if not success then
        warn("   ❌ Failed to invoke Forge remote")
        return false
    end
    
    task.wait(1)
    
    if not ForgeService then
        warn("   ❌ ForgeService not available!")
        return false
    end
    
    local forgeSuccess = pcall(function()
        ForgeService:ChangeSequence("Melt", {
            Ores = oreSelection,
            ItemType = FORGE_CONFIG.ITEM_TYPE,
            FastForge = false
        })
    end)
    
    if forgeSuccess then
        print("   ✅ Forge Melt started!")
        return true
    else
        warn("   ⚠️ Could not start forge melt")
        return false
    end
end

local function doForgeLoop()
    print("🔥 Action: Auto Forging...")
    
    setupForgeHook()
    
    setupForgeHook()
    
    -- 🆕 Retry movement until successful
    while not moveToForge() do
        warn("   ⚠️ Failed to reach Forge, retrying in 2s...")
        task.wait(2)
    end
    
    local forgeCount = 0
    local consecutiveFailures = 0
    
    while isQuest6StillActive() do
        forgeCount = forgeCount + 1
        print(string.format("\n   🔨 Forge Attempt #%d", forgeCount))
        
        printInventorySummary()
        
        local oreSelection, errorMsg = selectRandomOres(FORGE_CONFIG.REQUIRED_ORE_COUNT)
        
        if not oreSelection then
            warn(string.format("\n❌ ERROR: %s", errorMsg))
            consecutiveFailures = consecutiveFailures + 1
            
            if consecutiveFailures >= 3 then
                warn("❌ Failed 3 times in a row. Cannot continue forging!")
                warn("💡 Please mine more ores and try again.")
                Quest6Active = false
                break
            end
            
            warn(string.format("⏳ Waiting 5s before retry... (%d/3 failures)", consecutiveFailures))
            task.wait(5)
            continue
        end
        
        consecutiveFailures = 0
        
        local success = startForge(oreSelection)
        
        if success then
            print("   ⏳ Waiting for forge to complete...")
            task.wait(25)
        else
            warn("   ⚠️ Forge failed, retrying in 3s...")
            task.wait(3)
        end
        
        if not isQuest6StillActive() then
            print("   ✅ Quest complete!")
            break
        end
        
        print(string.format("   ⏸️ Cooling down for %ds...", FORGE_CONFIG.FORGE_DELAY))
        task.wait(FORGE_CONFIG.FORGE_DELAY)
    end
    
    print("\n🛑 Quest 6 forging ended")
end

----------------------------------------------------------------
-- MAIN RUNNER
----------------------------------------------------------------
print(string.rep("=", 50))
print("🚀 QUEST 6: Preparing For Battle")  -- ✅ เอา ! ออก
print(string.rep("=", 50))

local questID, objList = getQuestObjectives("Preparing For Battle")  -- ✅ แก้แล้ว

if not questID then
    warn("❌ Quest 'Preparing For Battle' not found!")  -- ✅ แก้แล้ว

    warn("💡 Make sure the quest is active in your quest log.")
    Quest6Active = false
    return
end

print("✅ Quest found (ID: " .. questID .. ")")

print("\n" .. string.rep("=", 50))
print("🔥 Starting Forge Sequence...")
print(string.rep("=", 50))

doForgeLoop()

closeForgeUI()

if Quest6Active == false and not isQuestComplete("Preparing For Battle!") then
    warn("\n" .. string.rep("=", 50))
    warn("❌ Quest 6 Failed!")
    warn("Reason: Not enough ores to continue")
    warn(string.rep("=", 50))
else
    print("\n" .. string.rep("=", 50))
    print("✅ Quest 6 Complete!")
    print(string.rep("=", 50))
end

Quest6Active = false
disableNoclip()
cleanupState()

end

-- Quest 07
_G.QuestFunctions[7] = function()
local Shared = _G.Shared

-- QUEST 7: "Forging Under Pressure!" - SMART SYSTEM (FIXED VERSION)
-- ✅ Priority: Purchase → Kill → Mine → Forge
-- ✅ Sell System: Check from UI (supports Pickaxe Name + Weapon/Armor GUID)
-- ✅ Sell everything not Equipped (including Pickaxe)
-- ✅ FIXED: Close Forge UI after Forge is complete (like Quest 3)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest7Active = true
local IsMiningActive = false
local IsKillingActive = false
local IsForgingActive = false

local QUEST_CONFIG = {
    QUEST_NAME = "Forging Under Pressure",
    PICKAXE_NAME = "Iron Pickaxe",
    PICKAXE_AMOUNT = 1,
    NPC_POSITION = Vector3.new(-81.03, 28.51, 84.68),
    ZOMBIE_UNDERGROUND_OFFSET = 6,
    ZOMBIE_MAX_DISTANCE = 50,
    REQUIRED_ORE_COUNT = 3,
    ITEM_TYPE = "Armor",
    FORGE_DELAY = 2,
    FORGE_POSITION = Vector3.new(-192.3, 29.5, 168.1),
    ROCK_NAME = "Pebble",
    UNDERGROUND_OFFSET = 4,
    MIN_ORES_FOR_FORGE = 10,
    LAYING_ANGLE = 90,
    MOVE_SPEED = 25,  
    SELL_NPC_NAME = "Marbles",
    SELL_NPC_POSITION = Vector3.new(49.84, 29.17, 85.84),
    PRIORITY_ORDER = {"Purchase", "Kill", "Mine", "Forge"},
}

----------------------------------------------------------------
-- KNIT SETUP
----------------------------------------------------------------
local KnitPackage = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitPackage)

if not Knit.OnStart then 
    pcall(function() Knit.Start():await() end)
end

local CharacterService = nil
local PlayerController = nil
local ProximityService = nil
local ForgeService = nil
local DialogueService = nil
local UIController = nil

pcall(function()
    CharacterService = Knit.GetService("CharacterService")
    PlayerController = Knit.GetController("PlayerController")
    ProximityService = Knit.GetService("ProximityService")
    ForgeService = Knit.GetService("ForgeService")
    DialogueService = Knit.GetService("DialogueService")
end)

local ToolController = nil
local ToolActivatedFunc = nil

pcall(function()
    for _, v in pairs(getgc(true)) do
        if type(v) == "table" then
            if rawget(v, "Name") == "ToolController" and rawget(v, "ToolActivated") then
                ToolController = v
                ToolActivatedFunc = v.ToolActivated
                break
            end
        end
    end
end)

pcall(function()
    for _, v in pairs(getgc(true)) do
        if type(v) == "table" then
            if rawget(v, "Open") and rawget(v, "Close") and rawget(v, "Modules") then
                UIController = v
                break
            end
        end
    end
end)

local SERVICES = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")

local PURCHASE_RF = nil
pcall(function()
    PURCHASE_RF = SERVICES:WaitForChild("ProximityService", 5):WaitForChild("RF", 3):WaitForChild("Purchase", 3)
end)

local CHAR_RF = nil
pcall(function()
    CHAR_RF = SERVICES:WaitForChild("CharacterService", 5):WaitForChild("RF", 3):WaitForChild("EquipItem", 3)
end)

local TOOL_RF_BACKUP = nil
pcall(function()
    TOOL_RF_BACKUP = SERVICES:WaitForChild("ToolService", 5):WaitForChild("RF", 3):WaitForChild("ToolActivated", 3)
end)

local PROXIMITY_RF = nil
pcall(function()
    PROXIMITY_RF = SERVICES:WaitForChild("ProximityService", 5):WaitForChild("RF", 3):WaitForChild("Forge", 3)
end)

local MINING_FOLDER_PATH = Workspace:WaitForChild("Rocks")
local LIVING_FOLDER = Workspace:WaitForChild("Living")

local FORGE_OBJECT = nil
pcall(function()
    FORGE_OBJECT = Workspace:WaitForChild("Proximity", 5):WaitForChild("Forge", 3)
end)

if CharacterService then print("✅ CharacterService Ready!") else warn("⚠️ CharacterService not found") end
if PlayerController then print("✅ PlayerController Ready!") else warn("⚠️ PlayerController not found") end
if ToolController then print("✅ ToolController Ready!") else warn("⚠️ ToolController not found") end
if ForgeService then print("✅ ForgeService Ready!") else warn("⚠️ ForgeService not found") end
if DialogueService then print("✅ DialogueService Ready!") else warn("⚠️ DialogueService not found") end
if ProximityService then print("✅ ProximityService Ready!") else warn("⚠️ ProximityService not found") end
if UIController then print("✅ UIController Ready!") else warn("⚠️ UIController not found") end
if PURCHASE_RF then print("✅ Purchase Remote Ready!") else warn("⚠️ Purchase Remote not found") end
if FORGE_OBJECT then print("✅ Forge Object Ready!") else warn("⚠️ Forge Object not found") end

----------------------------------------------------------------
-- STATE MANAGEMENT
----------------------------------------------------------------
local State = {
    currentTarget = nil,
    targetDestroyed = false,
    hpWatchConn = nil,
    noclipConn = nil,
    moveConn = nil,
    positionLockConn = nil,
    bodyVelocity = nil,
    bodyGyro = nil,
    currentObjectiveFrame = nil,
}

local function cleanupState()
    if State.hpWatchConn then State.hpWatchConn:Disconnect() State.hpWatchConn = nil end
    if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.positionLockConn then State.positionLockConn:Disconnect() State.positionLockConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    State.currentTarget = nil
    State.targetDestroyed = false
    
    if ToolController then
        ToolController.holdingM1 = false
    end
end

----------------------------------------------------------------
-- QUEST SYSTEM
----------------------------------------------------------------
local function getQuestObjectives(questName)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil, nil end
    
    local list = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Screen") 
                 and gui.Main.Screen:FindFirstChild("Quests") and gui.Main.Screen.Quests:FindFirstChild("List")
    if not list then return nil, nil end
    
    local questID = nil
    for _, child in ipairs(list:GetChildren()) do
        local id = string.match(child.Name, "^Introduction(%d+)Title$")
        if id and child:FindFirstChild("Frame") and child.Frame:FindFirstChild("TextLabel") then
            if child.Frame.TextLabel.Text == questName then
                questID = id
                break
            end
        end
    end
    
    if not questID then return nil, nil end
    
    local objList = list:FindFirstChild("Introduction" .. questID .. "List")
    return questID, objList
end

local function isObjectiveComplete(item)
    if not item then return false end
    local check = item:FindFirstChild("Main") and item.Main:FindFirstChild("Frame") and item.Main.Frame:FindFirstChild("Check")
    return check and check.Visible
end

local function getObjectiveText(item)
    local lbl = item:FindFirstChild("Main") and item.Main:FindFirstChild("TextLabel")
    return lbl and lbl.Text or ""
end

local function isQuest7StillActive()
    if not Quest7Active then return false end
    
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)
    if not questID or not objList then
        print("🛑 Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not found!")
        Quest7Active = false
        return false
    end
    
    return true
end

local function isCurrentObjectiveComplete()
    if State.currentObjectiveFrame then
        return isObjectiveComplete(State.currentObjectiveFrame)
    end
    return false
end

local function getObjectiveType(text)
    if string.find(text, "Purchase") or string.find(text, "Buy") or string.find(text, "Pickaxe") then
        return "Purchase"
    elseif string.find(text, "Kill") or string.find(text, "Zombie") or string.find(text, "Defeat") then
        return "Kill"
    elseif string.find(text, "Get Ore") or string.find(text, "Mine") or string.find(text, "Pebble") then
        return "Mine"
    elseif string.find(text, "Forge") or string.find(text, "forge") or string.find(text, "Item") then
        return "Forge"
    else
        return "Unknown"
    end
end

----------------------------------------------------------------
-- INVENTORY SYSTEM
----------------------------------------------------------------
local function getPlayerInventory()
    local inventory = {}
    
    if not PlayerController or not PlayerController.Replica then
        warn("PlayerController/Replica not available!")
        return inventory
    end
    
    local replica = PlayerController.Replica
    if replica and replica.Data and replica.Data.Inventory then
        for itemName, amount in pairs(replica.Data.Inventory) do
            if type(amount) == "number" and amount > 0 then
                inventory[itemName] = amount
            end
        end
    end
    
    return inventory
end

local function getAvailableOres()
    local inventory = getPlayerInventory()
    local ores = {}
    
    local oreTypes = {"Copper", "Stone", "Iron", "Sand Stone", "Tin", "Cardboardite", "Silver", "Gold", "Bananite", "Mushroomite", "Platinum", "Aite","Poopite"}
    
    for _, oreName in ipairs(oreTypes) do
        if inventory[oreName] and inventory[oreName] > 0 then
            table.insert(ores, {Name = oreName, Amount = inventory[oreName]})
        end
    end
    
    if #ores == 0 then
        for itemName, amount in pairs(inventory) do
            if string.find(itemName, "Ore") or string.find(itemName, "ore") then
                table.insert(ores, {Name = itemName, Amount = amount})
            end
        end
    end
    
    return ores
end

function getTotalOreCount()
    local ores = getAvailableOres()
    local total = 0
    for _, ore in ipairs(ores) do
        total = total + ore.Amount
    end
    return total
end

local function selectRandomOres(count)
    local availableOres = getAvailableOres()
    
    if #availableOres == 0 then
        return nil, "No ores found in inventory!"
    end
    
    local totalOres = 0
    for _, ore in ipairs(availableOres) do
        totalOres = totalOres + ore.Amount
    end
    
    if totalOres < count then
        return nil, string.format("Not enough ores! Need %d, have %d", count, totalOres)
    end
    
    local orePool = {}
    for _, ore in ipairs(availableOres) do
        for i = 1, ore.Amount do
            table.insert(orePool, ore.Name)
        end
    end
    
    local selected = {}
    for i = 1, count do
        if #orePool == 0 then break end
        local randomIndex = math.random(1, #orePool)
        local oreName = table.remove(orePool, randomIndex)
        selected[oreName] = (selected[oreName] or 0) + 1
    end
    
    return selected, nil
end

local function printInventorySummary()
    print("📦 INVENTORY CHECK:")
    local ores = getAvailableOres()
    
    if #ores == 0 then
        warn("   ❌ No ores found in inventory!")
        local inv = getPlayerInventory()
        if next(inv) then
            print("   📋 All items in inventory:")
            for item, amount in pairs(inv) do
                print(string.format("      - %s: %d", item, amount))
            end
        else
            warn("   ⚠️ Inventory is completely empty!")
        end
        return
    end
    
    print("   💎 Available Ores:")
    local total = 0
    for _, ore in ipairs(ores) do
        print(string.format("      - %s: %d", ore.Name, ore.Amount))
        total = total + ore.Amount
    end
    print(string.format("   📊 Total: %d ores", total))
    print("   " .. string.rep("-", 28))
end

local function canDoObjective(objType)
    if objType == "Forge" then
        local totalOres = getTotalOreCount()
        if totalOres < QUEST_CONFIG.REQUIRED_ORE_COUNT then
            print(string.format("⏸️  Cannot Forge: Only %d/%d ores available", totalOres, QUEST_CONFIG.REQUIRED_ORE_COUNT))
            return false
        end
    end
    return true
end

----------------------------------------------------------------
-- HELPER FUNCTIONS
----------------------------------------------------------------
local HOTKEY_MAP = {
    ["1"] = Enum.KeyCode.One,
    ["2"] = Enum.KeyCode.Two,
    ["3"] = Enum.KeyCode.Three,
    ["4"] = Enum.KeyCode.Four,
    ["5"] = Enum.KeyCode.Five,
    ["6"] = Enum.KeyCode.Six,
    ["7"] = Enum.KeyCode.Seven,
    ["8"] = Enum.KeyCode.Eight,
    ["9"] = Enum.KeyCode.Nine,
    ["0"] = Enum.KeyCode.Zero
}

local function pressKey(keyCode)
    if not keyCode then return end
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

local function findPickaxeSlotKey()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end
    
    local hotbar = gui:FindFirstChild("BackpackGui") and gui.BackpackGui:FindFirstChild("Backpack") and gui.BackpackGui.Backpack:FindFirstChild("Hotbar")
    if hotbar then
        for _, slotFrame in ipairs(hotbar:GetChildren()) do
            local frame = slotFrame:FindFirstChild("Frame")
            local label = frame and frame:FindFirstChild("ToolName")
            if label and label:IsA("TextLabel") and string.find(label.Text, "Pickaxe") then
                return HOTKEY_MAP[slotFrame.Name]
            end
        end
    end
    
    return nil
end

local function findWeaponSlotKey()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end
    
    local hotbar = gui:FindFirstChild("BackpackGui") and gui.BackpackGui:FindFirstChild("Backpack") and gui.BackpackGui.Backpack:FindFirstChild("Hotbar")
    if hotbar then
        for _, slotFrame in ipairs(hotbar:GetChildren()) do
            local frame = slotFrame:FindFirstChild("Frame")
            local label = frame and frame:FindFirstChild("ToolName")
            if label and label:IsA("TextLabel") and not string.find(label.Text, "Pickaxe") and label.Text ~= "" then
                return HOTKEY_MAP[slotFrame.Name], label.Text
            end
        end
    end
    
    return nil, nil
end

local function checkMiningError()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return false end
    
    local notif = gui:FindFirstChild("Notifications")
    if notif and notif:FindFirstChild("Screen") and notif.Screen:FindFirstChild("NotificationsFrame") then
        for _, child in ipairs(notif.Screen.NotificationsFrame:GetChildren()) do
            local lbl = child:FindFirstChild("TextLabel", true)
            if lbl and string.find(lbl.Text, "Someone else is already mining") then
                return true
            end
        end
    end
    
    return false
end

----------------------------------------------------------------
-- ROCK HELPERS
----------------------------------------------------------------
local function getRockUndergroundPosition(rockModel)
    if not rockModel or not rockModel.Parent then return nil end
    
    local pivotCFrame = nil
    pcall(function()
        if rockModel.GetPivot then
            pivotCFrame = rockModel:GetPivot()
        elseif rockModel.WorldPivot then
            pivotCFrame = rockModel.WorldPivot
        end
    end)
    
    if pivotCFrame then
        local pos = pivotCFrame.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.UNDERGROUND_OFFSET, pos.Z)
    end
    
    if rockModel.PrimaryPart then
        local pos = rockModel.PrimaryPart.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.UNDERGROUND_OFFSET, pos.Z)
    end
    
    local part = rockModel:FindFirstChildWhichIsA("BasePart")
    if part then
        local pos = part.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.UNDERGROUND_OFFSET, pos.Z)
    end
    
    return nil
end

local function getRockHP(rock)
    if not rock or not rock.Parent then return 0 end
    local success, result = pcall(function()
        return rock:GetAttribute("Health") or 0
    end)
    return success and result or 0
end

local function isTargetValid(rock)
    if not rock or not rock.Parent then return false end
    if not rock:FindFirstChildWhichIsA("BasePart") then return false end
    local hp = getRockHP(rock)
    return hp > 0
end

local function findNearestRock()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local targetRock, minDist = nil, math.huge
    
    for _, folder in ipairs(MINING_FOLDER_PATH:GetChildren()) do
        if folder:IsA("Folder") or folder:IsA("Model") then
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("SpawnLocation") or child.Name == "SpawnLocation" then
                    local rock = child:FindFirstChild(QUEST_CONFIG.ROCK_NAME)
                    if isTargetValid(rock) then
                        local pos = getRockUndergroundPosition(rock)
                        if pos then
                            local dist = (pos - hrp.Position).Magnitude
                            if dist < minDist then
                                minDist = dist
                                targetRock = rock
                            end
                        end
                    end
                end
            end
        end
    end
    
    return targetRock, minDist
end

local function watchRockHP(rock)
    if State.hpWatchConn then State.hpWatchConn:Disconnect() end
    if not rock then return end
    
    State.hpWatchConn = rock:GetAttributeChangedSignal("Health"):Connect(function()
        local hp = rock:GetAttribute("Health") or 0
        print(string.format("💥 HP Changed! New HP: %d", hp))
        if hp == 0 then
            print("✅ HP = 0 detected! Switching target...")
            State.targetDestroyed = true
            if ToolController then ToolController.holdingM1 = false end
            Shared.SoftUnlockPosition()
        end
    end)
end

----------------------------------------------------------------
-- ZOMBIE HELPERS
----------------------------------------------------------------
local function getZombieUndergroundPosition(zombieModel)
    if not zombieModel or not zombieModel.Parent then return nil end
    
    local hrp = zombieModel:FindFirstChild("HumanoidRootPart")
    if hrp then
        local pos = hrp.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.ZOMBIE_UNDERGROUND_OFFSET, pos.Z)
    end
    
    return nil
end

local function getZombieHP(zombie)
    if not zombie or not zombie.Parent then return 0 end
    local humanoid = zombie:FindFirstChild("Humanoid")
    if humanoid then
        return humanoid.Health or 0
    end
    return 0
end

local function isZombieValid(zombie)
    if not zombie or not zombie.Parent then return false end
    return getZombieHP(zombie) > 0
end

local function findNearestZombie()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local targetZombie, minDist = nil, math.huge
    
    for _, child in ipairs(LIVING_FOLDER:GetChildren()) do
        -- ✅ เอาเฉพาะชื่อแนว "Zombie1234" เท่านั้น (ไม่เอา EliteZombie)
        if string.match(child.Name, "^Zombie%d+$") then
            if isZombieValid(child) then
                local pos = getZombieUndergroundPosition(child)
                if pos then
                    local dist = (pos - hrp.Position).Magnitude
                    if dist < minDist then
                        minDist = dist
                        targetZombie = child
                    end
                end
            end
        end
    end
    
    return targetZombie, minDist
end


local function watchZombieHP(zombie)
    if State.hpWatchConn then State.hpWatchConn:Disconnect() end
    if not zombie then return end
    
    local humanoid = zombie:FindFirstChild("Humanoid")
    if not humanoid then return end
    
    State.hpWatchConn = humanoid:GetPropertyChangedSignal("Health"):Connect(function()
        local hp = humanoid.Health or 0
        print(string.format("💥 HP Changed! New HP: %.1f", hp))
        if hp == 0 then
            print("✅ Zombie died! Switching target...")
            State.targetDestroyed = true
            if ToolController then ToolController.holdingM1 = false end
            Shared.SoftUnlockPosition()
        end
    end)
end

local function getBestWeapon()
    if not PlayerController or not PlayerController.Replica then return nil end
    
    local replica = PlayerController.Replica
    if not replica.Data or not replica.Data.Inventory or not replica.Data.Inventory.Equipments then
        return nil
    end
    
    local equipments = replica.Data.Inventory.Equipments
    local bestWeapon = nil
    local highestDmg = 0
    
    for id, item in pairs(equipments) do
        if type(item) == "table" and item.Type then
            if not string.find(item.Type, "Pickaxe") then
                local dmg = item.Dmg or 0
                if dmg > highestDmg then
                    highestDmg = dmg
                    bestWeapon = item
                end
            end
        end
    end
    
    return bestWeapon
end

----------------------------------------------------------------
-- NOCLIP & MOVEMENT
----------------------------------------------------------------
local function enableNoclip()
    if State.noclipConn then return end
    
    local char = player.Character
    if not char then return end
    
    State.noclipConn = RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
            return
        end
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
    Shared.restoreCollisions()
end

local function smoothMoveTo(targetPos, callback)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    enableNoclip()
    
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = hrp
    State.bodyVelocity = bv
    
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.D = 500
    bg.Parent = hrp
    State.bodyGyro = bg
    
    print(string.format("   🚀 Moving to (%.1f, %.1f, %.1f)...", targetPos.X, targetPos.Y, targetPos.Z))
    
    local reachedTarget = false
    
    State.moveConn = RunService.Heartbeat:Connect(function()
        if reachedTarget then return end
        
        -- Check if character or BodyVelocity is destroyed
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv and bv.Parent then bv:Destroy() end
            if bg and bg.Parent then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end
        
        -- Check if BodyVelocity was destroyed by game/other script
        if not bv or not bv.Parent then
            warn("   ⚠️ BodyVelocity destroyed! Recreating...")
            
            -- Recreate BodyVelocity
            bv = Instance.new("BodyVelocity")
            bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bv.Parent = hrp
            State.bodyVelocity = bv
        end
        
        if not bg or not bg.Parent then
            bg = Instance.new("BodyGyro")
            bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
            bg.P = 10000
            bg.D = 500
            bg.Parent = hrp
            State.bodyGyro = bg
        end
        
        local currentPos = hrp.Position
        local direction = (targetPos - currentPos)
        local distance = direction.Magnitude
        
        if distance < 2 then
            print("   ✅ Reached target!")
            
            reachedTarget = true
            
            bv.Velocity = Vector3.zero
            hrp.Velocity = Vector3.zero
            hrp.AssemblyLinearVelocity = Vector3.zero
            
            task.wait(0.1)
            
            if bv and bv.Parent then bv:Destroy() end
            if bg and bg.Parent then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            
            if callback then callback() end
            return
        end
        
        local speed = math.min(QUEST_CONFIG.MOVE_SPEED, distance * 10)
        local velocity = direction.Unit * speed
        
        bv.Velocity = velocity
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
    end)
    
    return true
end

----------------------------------------------------------------
-- POSITION LOCK
----------------------------------------------------------------
local function lockPositionLayingDown(targetPos)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    if State.positionLockConn then
        State.positionLockConn:Disconnect()
        State.positionLockConn = nil
    end
    
    local angle = math.rad(QUEST_CONFIG.LAYING_ANGLE)
    local baseCFrame = CFrame.new(targetPos)
    local layingCFrame = baseCFrame * CFrame.Angles(angle, 0, 0)
    
    State.positionLockConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.positionLockConn then
                State.positionLockConn:Disconnect()
                State.positionLockConn = nil
            end
            return
        end
        
        hrp.CFrame = layingCFrame
        hrp.Velocity = Vector3.zero
        hrp.AssemblyLinearVelocity = Vector3.zero
    end)
    
    print("🔒 Position locked (laying down)")
end

local function lockPositionFollowTarget(targetModel)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not targetModel then return end
    
    if State.positionLockConn then
        State.positionLockConn:Disconnect()
        State.positionLockConn = nil
    end
    
    local angle = math.rad(QUEST_CONFIG.LAYING_ANGLE)
    
    State.positionLockConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.positionLockConn then
                State.positionLockConn:Disconnect()
                State.positionLockConn = nil
            end
            return
        end
        
        if not targetModel or not targetModel.Parent then
            if State.positionLockConn then
                State.positionLockConn:Disconnect()
                State.positionLockConn = nil
            end
            return
        end
        
        local targetPos = getZombieUndergroundPosition(targetModel)
        if targetPos then
            local baseCFrame = CFrame.new(targetPos)
            local layingCFrame = baseCFrame * CFrame.Angles(angle, 0, 0)
            
            hrp.CFrame = layingCFrame
            hrp.Velocity = Vector3.zero
            hrp.AssemblyLinearVelocity = Vector3.zero
        end
    end)
    
    print("🔒 Position locked (following target)")
end

local function unlockPosition()
    Shared.SoftUnlockPosition()
end

----------------------------------------------------------------
-- SELL SYSTEM (FIXED - เช็คจาก UI แทน Replica)
----------------------------------------------------------------
local function getEquippedItemsFromUI()
    local equipped = {}
    
    print("   🔍 Checking equipped items from UI...")
    
    -- เช็คจาก PlayerGui.Menu.Frame.Frame.Menus.Tools.Frame
    local menuUI = playerGui:FindFirstChild("Menu")
                   and playerGui.Menu:FindFirstChild("Frame")
                   and playerGui.Menu.Frame:FindFirstChild("Frame")
                   and playerGui.Menu.Frame.Frame:FindFirstChild("Menus")
                   and playerGui.Menu.Frame.Frame.Menus:FindFirstChild("Tools")
                   and playerGui.Menu.Frame.Frame.Menus.Tools:FindFirstChild("Frame")
    
    if not menuUI then
        warn("   ⚠️ Menu UI not found!")
        return equipped
    end
    
    for _, child in ipairs(menuUI:GetChildren()) do
        local equipButton = child:FindFirstChild("Equip")
        local equipLabel = equipButton and equipButton:FindFirstChild("TextLabel")
        
        if equipLabel and equipLabel:IsA("TextLabel") then
            local isEquipped = (equipLabel.Text == "Unequip")
            
            if isEquipped then
                -- child.Name อาจเป็น GUID หรือ ชื่อ Pickaxe
                local identifier = child.Name
                equipped[identifier] = true
                
                print(string.format("      ✅ Equipped: %s (UI)", identifier))
            end
        end
    end
    
    return equipped
end

local function getSellableItems()
    if not PlayerController or not PlayerController.Replica then
        return {}
    end
    
    local replica = PlayerController.Replica
    if not replica.Data or not replica.Data.Inventory or not replica.Data.Inventory.Equipments then
        return {}
    end
    
    local sellable = {}
    
    -- ✅ เช็ค Equipped จาก UI แทน Replica
    local equippedItems = getEquippedItemsFromUI()
    
    for id, item in pairs(replica.Data.Inventory.Equipments) do
        if type(item) == "table" and item.Type then
            local isPickaxe = string.find(item.Type, "Pickaxe")
            
            -- ✅ เช็คจาก UI (ทั้ง GUID และ Type/Name)
            local isEquipped = false
            
            -- 1. เช็คจาก GUID
            if item.GUID and equippedItems[item.GUID] then
                isEquipped = true
            end
            
            -- 2. เช็คจาก Type (สำหรับ Pickaxe ที่ใช้ชื่อแทน GUID)
            if equippedItems[item.Type] then
                isEquipped = true
            end
            
            -- 3. เช็คจาก Name
            if item.Name and equippedItems[item.Name] then
                isEquipped = true
            end
            
            -- ✅ ขายทุกอย่างที่ไม่ได้ Equipped (รวม Pickaxe ด้วย)
            if not isEquipped then
                -- Identifier: Pickaxe ใช้ Type, อื่นๆใช้ GUID
                local identifier = isPickaxe and item.Type or item.GUID
                
                table.insert(sellable, {
                    ID = id,
                    Identifier = identifier,
                    Type = item.Type,
                    Name = item.Name or item.Type,
                    Dmg = item.Dmg or 0,
                    IsPickaxe = isPickaxe
                })
            end
        end
    end
    
    return sellable
end

local function doSellUnequippedItems()
    print("💰 Selling Unequipped Items...")
    
    local sellableItems = getSellableItems()
    
    if #sellableItems == 0 then
        print("   ✅ No items to sell (all equipped)")
        return true
    end
    
    print(string.format("   📋 Found %d unequipped items to sell:", #sellableItems))
    for i, item in ipairs(sellableItems) do
        local idType = item.IsPickaxe and "Name" or "GUID"
        print(string.format("      %d. %s (%s: %s, Dmg: %d)", 
            i, item.Name, idType, item.Identifier, item.Dmg))
    end
    
    -- หา Sell NPC
    local proximity = Workspace:FindFirstChild("Proximity")
    local npc = proximity and (proximity:FindFirstChild(QUEST_CONFIG.SELL_NPC_NAME) or proximity:FindFirstChild("Greedy Cey"))
    
    if not npc then
        warn("   ❌ Sell NPC not found!")
        return false
    end
    
    if not ProximityService or not DialogueService then
        warn("   ❌ Required services not available!")
        return false
    end
    
    local soldCount = 0
    
    for _, item in ipairs(sellableItems) do
        print(string.format("   💰 Selling %s...", item.Name))
        
        -- 1. เปิด Dialogue
        local success1 = pcall(function()
            ProximityService:ForceDialogue(npc, "SellConfirm")
        end)
        
        if not success1 then
            warn("      ❌ Failed to open dialogue")
            continue
        end
        
        task.wait(0.2)
        
        -- 2. ส่ง Basket (ใช้ Identifier)
        local basket = {[item.Identifier] = true}
        
        local success2 = pcall(function()
            DialogueService:RunCommand("SellConfirm", {Basket = basket})
        end)
        
        if success2 then
            soldCount = soldCount + 1
            print(string.format("      ✅ Sold!"))
            task.wait(0.3)
        else
            warn(string.format("      ❌ Failed to sell %s", item.Name))
        end
        
        -- 3. Force restore UI
        pcall(function()
            local char = player.Character
            if char then
                local status = char:FindFirstChild("Status")
                if status then
                    for _, tag in ipairs(status:GetChildren()) do
                        if tag.Name == "DisableBackpack" or tag.Name == "NoMovement" or tag.Name == "Talking" then
                            tag:Destroy()
                        end
                    end
                end
            end
            
            local gui = player:FindFirstChild("PlayerGui")
            if gui then
                local dUI = gui:FindFirstChild("DialogueUI")
                if dUI then dUI.Enabled = false end
            end
        end)
        
        task.wait(0.5)
    end
    
    print(string.format("   ✅ Sell complete! Sold %d/%d items", soldCount, #sellableItems))
    
    -- Final restore
    local gui = player:FindFirstChild("PlayerGui")
    if gui then
        local main = gui:FindFirstChild("Main")
        if main then main.Enabled = true end
        
        local backpack = gui:FindFirstChild("BackpackGui")
        if backpack then backpack.Enabled = true end
    end
    
    return true
end

----------------------------------------------------------------
-- UI MANAGEMENT
----------------------------------------------------------------
local function closeForgeUI()
    print("🔧 Closing Forge UI...")
    
    local closed = false
    
    if UIController and UIController.Close then
        pcall(function()
            if UIController.Modules and UIController.Modules.Forge then
                UIController:Close("Forge")
                print("   ✅ Closed via UIController")
                closed = true
            end
        end)
    end
    
    if not closed then
        pcall(function()
            local forgeGui = playerGui:FindFirstChild("Forge") or playerGui:FindFirstChild("ForgeUI")
            if forgeGui then
                forgeGui.Enabled = false
                print("   ✅ Closed via PlayerGui")
                closed = true
            end
        end)
    end
    
    if not closed then
        warn("   ⚠️ Could not close Forge UI (may already be closed)")
    end
    
    task.wait(0.3)
end

local function restoreUI()
    print("🔧 Restoring UI State...")
    
    local char = player.Character
    if char then
        local status = char:FindFirstChild("Status")
        if status then
            for _, tag in ipairs(status:GetChildren()) do
                if tag.Name == "DisableBackpack" or tag.Name == "NoMovement" or tag.Name == "Talking" then
                    pcall(function() tag:Destroy() end)
                end
            end
        end
        
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
        end
    end
    
    local gui = player:FindFirstChild("PlayerGui")
    if gui then
        local main = gui:FindFirstChild("Main")
        if main then main.Enabled = true end
        
        local backpack = gui:FindFirstChild("BackpackGui")
        if backpack then backpack.Enabled = true end
        
        local dialogueUI = gui:FindFirstChild("DialogueUI")
        if dialogueUI then dialogueUI.Enabled = false end
    end
    
    local cam = Workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
    end
    
    print("✅ UI State restored!")
end

----------------------------------------------------------------
-- FORGE SYSTEM
----------------------------------------------------------------
getgenv().ForgeHookActive = getgenv().ForgeHookActive or false

local function setupForgeHook()
    if getgenv().ForgeHookActive then
        print("⚙️  Forge Hook already active")
        return
    end
    
    if not ForgeService then
        warn("❌ ForgeService not available!")
        return
    end
    
    print("🔧 Installing Forge Hook...")
    
    local originalChangeSequence = ForgeService.ChangeSequence
    
    ForgeService.ChangeSequence = function(self, sequenceName, args)
        print("🔨 Sequence: " .. sequenceName)
        
        local success, result = pcall(originalChangeSequence, self, sequenceName, args)
        
        task.spawn(function()
            if sequenceName == "Melt" then
                print("   ⏳ Auto Pouring in 8s...")
                task.wait(8)
                self:ChangeSequence("Pour", {ClientTime = 8.5, InContact = true})
            elseif sequenceName == "Pour" then
                print("   ⏳ Auto Hammering in 5s...")
                task.wait(5)
                self:ChangeSequence("Hammer", {ClientTime = 5.2})
            elseif sequenceName == "Hammer" then
                print("   ⏳ Auto Watering in 6s...")
                task.wait(6)
                self:ChangeSequence("Water", {ClientTime = 6.5})
            elseif sequenceName == "Water" then
                print("   ⏳ Auto Showcasing in 3s...")
                task.wait(3)
                self:ChangeSequence("Showcase", {})
            elseif sequenceName == "Showcase" then
                print("   ✅ Forge completed!")
                -- ✅ ไม่ปิด UI ที่นี่ (ให้ doForge() จัดการ)
            end
        end)
        
        return success, result
    end
    
    getgenv().ForgeHookActive = true
    print("✅ Forge Hook installed!")
end

local function moveToForge()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local forgePos = QUEST_CONFIG.FORGE_POSITION
    local currentDist = (forgePos - hrp.Position).Magnitude

    print(string.format("🚶 Moving to Forge at (%.1f, %.1f, %.1f) (%.1f studs away)...", 
        forgePos.X, forgePos.Y, forgePos.Z, currentDist))

    -- 🆕 Unlock position before moving
    unlockPosition()

    local moveComplete = false
    smoothMoveTo(forgePos, function()
        moveComplete = true
    end)

    local timeout = 60
    local startTime = tick()
    while not moveComplete and tick() - startTime < timeout do
        task.wait(0.1)
    end
    
    if not moveComplete then
        warn("   ⚠️ Move timed out! Retrying...")
        if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
        if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
        if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
        return false
    end

    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end

    print("✅ Reached Forge!")
    print("   ⏳ Waiting 1.5s before opening Forge UI...")
    task.wait(1.5)

    return true
end


local function startForge(oreSelection)
    print("🔨 Starting Forge with:")
    for oreName, amount in pairs(oreSelection) do
        print(string.format("   - %s x%d", oreName, amount))
    end

    if not FORGE_OBJECT then
        warn("❌ Forge Object not found!")
        return false
    end

    pcall(function()
        PROXIMITY_RF:InvokeServer(FORGE_OBJECT)
    end)

    task.wait(1)

    if not ForgeService then return false end

    local forgeSuccess = pcall(function()
        ForgeService:ChangeSequence("Melt", {
            Ores = oreSelection,
            ItemType = QUEST_CONFIG.ITEM_TYPE,
            FastForge = false
        })
    end)

    if forgeSuccess then
        print("✅ Forge Melt started!")
        return true
    else
        return false
    end
end
----------------------------------------------------------------
-- OBJECTIVES
----------------------------------------------------------------
local function doPurchaseIronPickaxe()
    print("🛒 Objective 1: Purchasing Iron Pickaxe...")
    
    if not PURCHASE_RF then
        warn("   ❌ Purchase Remote not available!")
        return false
    end
    
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    
    if hrp then
        local npcPos = QUEST_CONFIG.NPC_POSITION
        local currentDist = (npcPos - hrp.Position).Magnitude
        
        print(string.format("   🚶 Moving to NPC at (%.2f, %.2f, %.2f) (%.1f studs away)...", 
            npcPos.X, npcPos.Y, npcPos.Z, currentDist))
        
        -- 🆕 Unlock position before moving
        unlockPosition()
        
        local moveComplete = false
        smoothMoveTo(npcPos, function()
            moveComplete = true
        end)
        
        local timeout = 60
        local startTime = tick()
        while not moveComplete and tick() - startTime < timeout do
            task.wait(0.1)
        end
        
        if not moveComplete then
            warn("   ⚠️ Move timed out! Retrying...")
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
            if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
            return false
        end
        
        if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
        if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
        if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
        
        print("   ✅ Reached NPC!")
        print("   ⏳ Waiting 1.5s before purchase...")
        task.wait(1.5)
    end
    
    print(string.format("   💰 Purchasing %s (Amount: %d)", QUEST_CONFIG.PICKAXE_NAME, QUEST_CONFIG.PICKAXE_AMOUNT))
    
    local args = {QUEST_CONFIG.PICKAXE_NAME, QUEST_CONFIG.PICKAXE_AMOUNT}
    local success, result = pcall(function()
        return PURCHASE_RF:InvokeServer(unpack(args))
    end)
    
    if success then
        print("   ✅ Purchase successful!")
        return true
    else
        warn("   ❌ Purchase failed: " .. tostring(result))
        return false
    end
end

local function doMinePebble()
    print("⛏️  Objective 4: Mining Pebble...")
    
    IsMiningActive = true
    
    print("   " .. string.rep("-", 30))
    print("   🔄 Starting Pebble mining loop...")
    print("   " .. string.rep("-", 30))
    
    while isQuest7StillActive() and not isCurrentObjectiveComplete() do
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        
        if not hrp then
            warn("   ⚠️ Waiting for character...")
            task.wait(2)
            continue
        end
        
        cleanupState()
        
        local targetRock, dist = findNearestRock()
        if not targetRock then
            warn("   ⚠️ No Pebble found, waiting...")
            task.wait(2)
            continue
        end
        
        State.currentTarget = targetRock
        State.targetDestroyed = false
        
        local targetPos = getRockUndergroundPosition(targetRock)
        if not targetPos then
            warn("   ⚠️ Cannot get pebble position!")
            task.wait(1)
            continue
        end
        
        local currentHP = getRockHP(targetRock)
        print(string.format("   🎯 Target: %s (dist: %d, HP: %d)", targetRock.Parent.Name, math.floor(dist), currentHP))
        
        watchRockHP(targetRock)
        
        -- 🆕 Unlock position before moving
        unlockPosition()
        
        local moveStarted = false
        smoothMoveTo(targetPos, function()
            lockPositionLayingDown(targetPos)
            moveStarted = true
        end)
        
        local timeout = 60
        local startTime = tick()
        while not moveStarted and tick() - startTime < timeout do
            task.wait(0.1)
        end
        
        if not moveStarted then
            lockPositionLayingDown(targetPos)
        end
        
        task.wait(0.5)
        
        while not State.targetDestroyed and isQuest7StillActive() and not isCurrentObjectiveComplete() do
            if not char or not char.Parent then
                print("   ⚠️ Character died!")
                break
            end
            
            if not targetRock or not targetRock.Parent then
                print("   ⚠️ Target removed!")
                State.targetDestroyed = true
                break
            end
            
            if checkMiningError() then
                print("   ⚠️ Someone else mining!")
                State.targetDestroyed = true
                if ToolController then ToolController.holdingM1 = false end
                break
            end
            
            local toolInHand = char:FindFirstChildWhichIsA("Tool")
            local isPickaxeHeld = toolInHand and string.find(toolInHand.Name, "Pickaxe")
            
            if not isPickaxeHeld then
                if ToolController then ToolController.holdingM1 = false end
                
                local key = findPickaxeSlotKey()
                if key then
                    pressKey(key)
                    task.wait(0.3)
                else
                    pcall(function()
                        CHAR_RF:InvokeServer({Runes = {}}, {Name = QUEST_CONFIG.PICKAXE_NAME})
                    end)
                    task.wait(0.5)
                end
            else
                if ToolController and ToolActivatedFunc then
                    ToolController.holdingM1 = true
                    pcall(function()
                        ToolActivatedFunc(ToolController, toolInHand)
                    end)
                else
                    pcall(function()
                        TOOL_RF_BACKUP:InvokeServer(toolInHand.Name, true)
                    end)
                end
            end
            
            task.wait(0.15)
        end
        
        --unlockPosition()
        
        if isCurrentObjectiveComplete() then
            print("   ✅ Objective 4 (Mine Pebble) Complete!")
            break
        end
        
        print("   🔄 Finding next target...")
        task.wait(0.5)
    end
    
    print("   ⛏️  Mining ended")
    IsMiningActive = false
    unlockPosition()
    disableNoclip()
    cleanupState()
end

local function doKillZombies()
    print("⚔️  Objective 2: Killing Zombies...")
    
    IsKillingActive = true
    
    print("   " .. string.rep("-", 30))
    print("   🔄 Starting Zombie hunting loop...")
    print("   " .. string.rep("-", 30))
    
    while isQuest7StillActive() and not isCurrentObjectiveComplete() do
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        
        if not hrp then
            warn("   ⚠️ Waiting for character...")
            task.wait(2)
            continue
        end
        
        cleanupState()
        
        local targetZombie, dist = findNearestZombie()
        if not targetZombie then
            warn("   ⚠️ No Zombies found, waiting...")
            task.wait(2)
            continue
        end
        
        State.currentTarget = targetZombie
        State.targetDestroyed = false
        
        local targetPos = getZombieUndergroundPosition(targetZombie)
        if not targetPos then
            warn("   ⚠️ Cannot get zombie position!")
            task.wait(1)
            continue
        end
        
        local currentHP = getZombieHP(targetZombie)
        print(string.format("   🎯 Target: %s (dist: %d, HP: %.1f)", targetZombie.Name, math.floor(dist), currentHP))
        
        watchZombieHP(targetZombie)
        
        -- 🆕 Unlock position before moving
        unlockPosition()
        
        local moveStarted = false
        smoothMoveTo(targetPos, function()
            lockPositionFollowTarget(targetZombie)
            moveStarted = true
        end)
        
        local timeout = 60
        local startTime = tick()
        while not moveStarted and tick() - startTime < timeout do
            task.wait(0.1)
        end
        
        -- ❌ อย่า hard-lock ถ้าไม่เคยเดินถึงเป้าหมาย
        if not moveStarted then
            warn("   ⚠️ Move timeout, skip this zombie to avoid teleport")
            State.targetDestroyed = true
            unlockPosition()
            continue
        end
        
        task.wait(0.5)
        
        while not State.targetDestroyed and isQuest7StillActive() and not isCurrentObjectiveComplete() do
            if not char or not char.Parent then
                print("   ⚠️ Character died!")
                break
            end
            
            if not targetZombie or not targetZombie.Parent or not isZombieValid(targetZombie) then
                print("   ⚠️ Target removed or died!")
                State.targetDestroyed = true
                unlockPosition()  
                break
            end
            
            local currentZombiePos = getZombieUndergroundPosition(targetZombie)
            if currentZombiePos and hrp then
                local distToZombie = (currentZombiePos - hrp.Position).Magnitude
                if distToZombie > QUEST_CONFIG.ZOMBIE_MAX_DISTANCE then
                    print(string.format("   ⚠️ Zombie moved too far! (%.1f studs) Switching target...", distToZombie))
                    State.targetDestroyed = true
                    unlockPosition()
                    break
                end
            end
            
            local toolInHand = char:FindFirstChildWhichIsA("Tool")
            local isWeaponHeld = toolInHand and not string.find(toolInHand.Name, "Pickaxe")
            
            if not isWeaponHeld then
                if ToolController then ToolController.holdingM1 = false end
                
                local bestWeapon = getBestWeapon()
                if bestWeapon then
                    print(string.format("   ⚔️  Equipping weapon: %s", bestWeapon.Type))
                    pcall(function()
                        CharacterService:EquipItem(bestWeapon)
                    end)
                    task.wait(0.5)
                else
                    local key, weaponName = findWeaponSlotKey()
                    if key then
                        print(string.format("   ⚔️  Equipping via hotkey: %s", weaponName))
                        pressKey(key)
                        task.wait(0.3)
                    else
                        warn("   ❌ No weapon found!")
                        task.wait(1)
                    end
                end
            else
                if ToolController and ToolActivatedFunc then
                    ToolController.holdingM1 = true
                    pcall(function()
                        ToolActivatedFunc(ToolController, toolInHand)
                    end)
                else
                    pcall(function()
                        TOOL_RF_BACKUP:InvokeServer(toolInHand.Name, true)
                    end)
                end
            end
            
            task.wait(0.15)
        end
        
        --unlockPosition()
        
        if isCurrentObjectiveComplete() then
            print("   ✅ Objective 2 (Kill Zombies) Complete!")
            break
        end
        
        print("   🔄 Finding next target...")
        task.wait(0.5)
    end
    
    print("   ⚔️  Zombie hunting ended")
    IsKillingActive = false
    unlockPosition()
    disableNoclip()
    cleanupState()
end

local function doForge()
    print("🔨 Objective 3: Forging Armor...")
    
    IsForgingActive = true
    
    print("\n" .. string.rep("=", 50))
    print("📋 Step 1: Selling Unequipped Items")
    print(string.rep("=", 50))
    
    doSellUnequippedItems()
    
    print("\n" .. string.rep("=", 50))
    print("🔨 Step 2: Starting Forge")
    print(string.rep("=", 50))
    
    setupForgeHook()
    moveToForge()
    
    local forgeAttempts = 0
    
    while isQuest7StillActive() and not isCurrentObjectiveComplete() do
        forgeAttempts = forgeAttempts + 1
        print(string.format("\n🔨 Forge Attempt #%d", forgeAttempts))
        
        printInventorySummary()
        
        local totalOres = getTotalOreCount()
        if totalOres < QUEST_CONFIG.REQUIRED_ORE_COUNT then
            warn(string.format("❌ Not enough ores! Have %d, need %d", totalOres, QUEST_CONFIG.REQUIRED_ORE_COUNT))
            warn("⚠️ This shouldn't happen - Mine objective should be done first!")
            break
        end
        
        local oreSelection, errorMsg = selectRandomOres(QUEST_CONFIG.REQUIRED_ORE_COUNT)
        if not oreSelection then
            warn(string.format("❌ ERROR: %s", errorMsg))
            break
        end
        
        local success = startForge(oreSelection)
        if success then
            print("   ⏳ Waiting for forge to complete...")
            task.wait(27)
        else
            warn("   ❌ Forge failed, retrying in 3s...")
            task.wait(3)
        end
        
        if isCurrentObjectiveComplete() then
            print("   ✅ Objective 3 (Forge) Complete!")
            break
        end
        
        print(string.format("   ⏸️  Cooling down for %ds...", QUEST_CONFIG.FORGE_DELAY))
        task.wait(QUEST_CONFIG.FORGE_DELAY)
    end
    
    -- ✅ FIXED: เพิ่มการปิด UI (เหมือน Quest 3)
    print("\n🚪 Closing Forge UI...")
    closeForgeUI()
    task.wait(0.5)
    restoreUI()
    
    print("   🔨 Forging ended")
    IsForgingActive = false
    disableNoclip()
    cleanupState()
end

----------------------------------------------------------------
-- SMART QUEST RUNNER
----------------------------------------------------------------
print(string.rep("=", 50))
print("🚀 QUEST 7: " .. QUEST_CONFIG.QUEST_NAME)
print("⚙️  SMART SYSTEM: Priority-based + Flexible")
print("📋 Priority Order: Purchase → Kill → Mine → Forge")
print("💰 Sell System: เช็คจาก UI (Pickaxe Name + Weapon/Armor GUID)")
print(string.rep("=", 50))

local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)

if not questID then
    warn("❌ Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not found!")
    Quest7Active = false
    return
end

print("✅ Quest found (ID: " .. questID .. ")\n")

local objectives = {}
for _, item in ipairs(objList:GetChildren()) do
    if item:IsA("Frame") and tonumber(item.Name) then
        local text = getObjectiveText(item)
        local objType = getObjectiveType(text)
        table.insert(objectives, {
            order = tonumber(item.Name),
            frame = item,
            text = text,
            type = objType
        })
    end
end

table.sort(objectives, function(a, b)
    local function getPriority(type)
        for i, priorityType in ipairs(QUEST_CONFIG.PRIORITY_ORDER) do
            if string.find(type, priorityType) then
                return i
            end
        end
        return 999
    end
    return getPriority(a.type) < getPriority(b.type)
end)

print(string.rep("=", 50))
print("📋 Quest Objectives (Priority Order):")
for i, obj in ipairs(objectives) do
    local complete = isObjectiveComplete(obj.frame)
    print(string.format("   %d. [%s] %s %s", i, obj.type, obj.text, complete and "✅" or "⏳"))
end
print(string.rep("=", 50))


-- 🆕 helper: เช็คว่ามี Purchase ที่ยังไม่ complete อยู่ไหม
local function hasIncompletePurchase()
    for _, obj in ipairs(objectives) do
        if obj.type == "Purchase" and not isObjectiveComplete(obj.frame) then
            return true
        end
    end
    return false
end

local maxAttempts = 10
local attempt = 0

while isQuest7StillActive() and attempt < maxAttempts do
    attempt = attempt + 1
    print(string.format("\n🔄 Quest Cycle #%d", attempt))
    
    local allComplete = true
    local didSomething = false
    local purchasePending = hasIncompletePurchase()
    
    for _, obj in ipairs(objectives) do
        if not isQuest7StillActive() then
            print("🛑 Quest disappeared!")
            break
        end
        
        local complete = isObjectiveComplete(obj.frame)
        
        if not complete then
            allComplete = false

            -- ⛔ ถ้า Purchase ยังไม่เสร็จ → ห้ามทำ Kill / Mine / Forge
            if purchasePending and obj.type ~= "Purchase" then
                print(string.format("⏭️  Skipping [%s] (waiting for Purchase to finish)", obj.type))
                continue
            end
            
            if not canDoObjective(obj.type) then
                print(string.format("⏸️  Skipping [%s] - Cannot do right now", obj.type))
                continue
            end
            
            State.currentObjectiveFrame = obj.frame
            
            print(string.format("\n▶️  Processing [%s]: %s", obj.type, obj.text))
            
            if obj.type == "Purchase" then
                doPurchaseIronPickaxe()
                didSomething = true
                task.wait(2)
                
                -- 🆕 Re-check if Purchase is complete after running
                if isObjectiveComplete(obj.frame) then
                    purchasePending = false
                    print("   ✅ Purchase objective complete! Continuing to other objectives...")
                end
            elseif obj.type == "Kill" then
                doKillZombies()
                didSomething = true
                task.wait(1)
            elseif obj.type == "Mine" then
                doMinePebble()
                didSomething = true
                task.wait(1)
            elseif obj.type == "Forge" then
                doForge()
                didSomething = true
                task.wait(1)
            else
                warn("❌ Unknown objective type: " .. obj.type)
            end
            
            task.wait(1)
            
            if isObjectiveComplete(obj.frame) then
                print(string.format("✅ [%s] Complete!", obj.type))
            else
                print(string.format("⏳ [%s] Still in progress", obj.type))
            end
        end
    end
    
    if allComplete then
        print("\n🎉 All objectives complete!")
        break
    end
    
    if not didSomething then
        warn("⚠️ No objectives could be completed this cycle!")
        print("   ⏳ Waiting 3s before retry...")
        task.wait(3)
    end
end

task.wait(2)

local allComplete = true
for _, obj in ipairs(objectives) do
    if not isObjectiveComplete(obj.frame) then
        allComplete = false
        warn(string.format("❌ [%s] incomplete: %s", obj.type, obj.text))
    end
end

if allComplete then
    print("\n" .. string.rep("=", 50))
    print("🏆 Quest 7 Complete!")
    print(string.rep("=", 50))
else
    warn("\n" .. string.rep("=", 50))
    warn("⚠️ Quest 7 incomplete after " .. attempt .. " cycles")
    warn(string.rep("=", 50))
end

Quest7Active = false
IsMiningActive = false
IsKillingActive = false
IsForgingActive = false
unlockPosition()
disableNoclip()
cleanupState()

end

-- Quest 08
_G.QuestFunctions[8] = function()
local Shared = _G.Shared

-- QUEST 8: "Reporting In!" (Body Move + Dialogue with Sensei Moro)
-- Objective: Go to Sensei Moro and click CheckQuest

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest8Active = true

local QUEST_CONFIG = {
    QUEST_NAME = "Reporting In",
    NPC_NAME = "Sensei Moro",
    QUEST_OPTION_ARG = "CheckQuest",
    MOVE_SPEED = 25,  
    NPC_STOP_DISTANCE = 5,  -- Stop 5 studs away from NPC
}

----------------------------------------------------------------
-- KNIT SETUP
----------------------------------------------------------------
local KnitPackage = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitPackage)

if not Knit.OnStart then 
    pcall(function() Knit.Start():await() end)
end

local ProximityService = nil
local DialogueService = nil

pcall(function()
    ProximityService = Knit.GetService("ProximityService")
    DialogueService = Knit.GetService("DialogueService")
end)

local SERVICES = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")

local DIALOGUE_RF = nil
pcall(function()
    DIALOGUE_RF = SERVICES:WaitForChild("ProximityService", 5):WaitForChild("RF", 3):WaitForChild("Dialogue", 3)
end)

local RUNCOMMAND_RF = nil
pcall(function()
    RUNCOMMAND_RF = SERVICES:WaitForChild("DialogueService", 5):WaitForChild("RF", 3):WaitForChild("RunCommand", 3)
end)

local DIALOGUE_RE = nil
pcall(function()
    DIALOGUE_RE = SERVICES:WaitForChild("DialogueService", 5):WaitForChild("RE", 3):WaitForChild("DialogueEvent", 3)
end)

if ProximityService then print("✅ ProximityService Ready!") else warn("⚠️ ProximityService not found") end
if DialogueService then print("✅ DialogueService Ready!") else warn("⚠️ DialogueService not found") end
if DIALOGUE_RF then print("✅ Dialogue Remote Ready!") else warn("⚠️ Dialogue Remote not found") end
if RUNCOMMAND_RF then print("✅ RunCommand Remote Ready!") else warn("⚠️ RunCommand Remote not found") end

----------------------------------------------------------------
-- STATE MANAGEMENT
----------------------------------------------------------------
local State = {
    noclipConn = nil,
    moveConn = nil,
    bodyVelocity = nil,
    bodyGyro = nil,
}

local function cleanupState()
    if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
end

----------------------------------------------------------------
-- QUEST SYSTEM
----------------------------------------------------------------
local function getQuestObjectives(questName)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil, nil end
    
    local list = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Screen") 
                 and gui.Main.Screen:FindFirstChild("Quests") and gui.Main.Screen.Quests:FindFirstChild("List")
    if not list then return nil, nil end
    
    local questID = nil
    for _, child in ipairs(list:GetChildren()) do
        local id = string.match(child.Name, "^Introduction(%d+)Title$")
        if id and child:FindFirstChild("Frame") and child.Frame:FindFirstChild("TextLabel") then
            if child.Frame.TextLabel.Text == questName then
                questID = id
                break
            end
        end
    end
    
    if not questID then return nil, nil end
    
    local objList = list:FindFirstChild("Introduction" .. questID .. "List")
    return questID, objList
end

local function isObjectiveComplete(item)
    if not item then return false end
    local check = item:FindFirstChild("Main") and item.Main:FindFirstChild("Frame") and item.Main.Frame:FindFirstChild("Check")
    return check and check.Visible
end

local function getObjectiveText(item)
    local lbl = item:FindFirstChild("Main") and item.Main:FindFirstChild("TextLabel")
    return lbl and lbl.Text or ""
end

local function isQuest8StillActive()
    if not Quest8Active then return false end
    
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)
    if not questID or not objList then
        print("🛑 Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not found!")
        Quest8Active = false
        return false
    end
    
    return true
end

local function areAllObjectivesComplete()
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)
    if not questID or not objList then return true end
    
    for _, item in ipairs(objList:GetChildren()) do
        if item:IsA("Frame") and tonumber(item.Name) then
            if not isObjectiveComplete(item) then
                return false
            end
        end
    end
    
    return true
end

----------------------------------------------------------------
-- NPC HELPERS
----------------------------------------------------------------
local function getNpcModel(name)
    local prox = Workspace:FindFirstChild("Proximity")
    return prox and prox:FindFirstChild(name)
end

local function getNpcPosition(npcModel)
    if not npcModel then return nil end
    
    local targetPart = npcModel.PrimaryPart or npcModel:FindFirstChildWhichIsA("BasePart")
    if not targetPart then return nil end
    
    return targetPart.Position
end

----------------------------------------------------------------
-- NOCLIP & MOVEMENT
----------------------------------------------------------------
local function enableNoclip()
    if State.noclipConn then return end
    
    local char = player.Character
    if not char then return end
    
    State.noclipConn = RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
            return
        end
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
end

local function smoothMoveTo(targetPos, callback)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    enableNoclip()
    
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = hrp
    State.bodyVelocity = bv
    
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.D = 500
    bg.Parent = hrp
    State.bodyGyro = bg
    
    print(string.format("   🚀 Moving to (%.1f, %.1f, %.1f)...", targetPos.X, targetPos.Y, targetPos.Z))
    
    State.moveConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv then bv:Destroy() end
            if bg then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end
        
        local currentPos = hrp.Position
        local direction = (targetPos - currentPos)
        local distance = direction.Magnitude
        
        if distance < QUEST_CONFIG.NPC_STOP_DISTANCE then
            print("   ✅ Reached NPC!")
            
            bv.Velocity = Vector3.zero
            task.wait(0.1)
            
            bv:Destroy()
            bg:Destroy()
            State.bodyVelocity = nil
            State.bodyGyro = nil
            
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            
            if callback then callback() end
            return
        end
        
        local speed = math.min(QUEST_CONFIG.MOVE_SPEED, distance * 10)
        local velocity = direction.Unit * speed
        
        bv.Velocity = velocity
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
    end)
    
    return true
end

----------------------------------------------------------------
-- UI RESTORE
----------------------------------------------------------------
local function forceRestoreUI()
    print("🔧 Forcing UI Restore...")
    
    local char = player.Character
    if char then
        local status = char:FindFirstChild("Status")
        if status then
            for _, tag in ipairs(status:GetChildren()) do
                if tag.Name == "DisableBackpack" or tag.Name == "NoMovement" or tag.Name == "Talking" then
                    pcall(function() tag:Destroy() end)
                    print("   - Removed Status Tag: " .. tag.Name)
                end
            end
        end
        
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
        end
    end
    
    local gui = player:FindFirstChild("PlayerGui")
    if gui then
        local dUI = gui:FindFirstChild("DialogueUI")
        if dUI then
            dUI.Enabled = false
            local bb = dUI:FindFirstChild("ResponseBillboard")
            if bb then bb.Visible = false end
        end
        
        local main = gui:FindFirstChild("Main")
        if main then 
            main.Enabled = true 
            print("   - Main UI Restored")
        end
        
        local backpack = gui:FindFirstChild("BackpackGui")
        if backpack then 
            backpack.Enabled = true 
            print("   - Backpack Restored")
        end
        
        local compass = gui:FindFirstChild("Compass")
        if compass then compass.Enabled = true end
        
        local mobile = gui:FindFirstChild("MobileButtons")
        if mobile then mobile.Enabled = true end
    end
    
    local cam = Workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        cam.FieldOfView = 70
    end
    
    if DIALOGUE_RE then
        pcall(function() DIALOGUE_RE:FireServer("Closed") end)
    end
    
    print("✅ UI Restore Complete")
end

----------------------------------------------------------------
-- DIALOGUE SYSTEM
----------------------------------------------------------------
local function startDialogue(npcModel)
    if not DIALOGUE_RF then
        warn("   ❌ Dialogue Remote not available!")
        return false
    end
    
    print("📞 Starting Dialogue with " .. QUEST_CONFIG.NPC_NAME .. "...")
    
    local success = pcall(function()
        DIALOGUE_RF:InvokeServer(npcModel)
    end)
    
    if success then
        print("   ✅ Dialogue started!")
        return true
    else
        warn("   ❌ Failed to start dialogue")
        return false
    end
end

local function selectQuestOption(optionName)
    if not RUNCOMMAND_RF then
        warn("   ❌ RunCommand Remote not available!")
        return false
    end
    
    print("✅ Selecting Option: " .. optionName)
    
    local success = pcall(function()
        RUNCOMMAND_RF:InvokeServer(optionName)
    end)
    
    if success then
        print("   ✅ Option selected!")
        return true
    else
        warn("   ❌ Failed to select option")
        return false
    end
end

----------------------------------------------------------------
-- MAIN QUEST EXECUTION
----------------------------------------------------------------
local function doReportToSenseiMoro()
    print("📋 Objective: Report to Sensei Moro...")
    
    local npcModel = getNpcModel(QUEST_CONFIG.NPC_NAME)
    if not npcModel then
        warn("   ❌ NPC not found: " .. QUEST_CONFIG.NPC_NAME)
        return false
    end
    
    local targetPos = getNpcPosition(npcModel)
    if not targetPos then
        warn("   ❌ Cannot get NPC position!")
        return false
    end
    
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local currentDist = (targetPos - hrp.Position).Magnitude
        print(string.format("   🚶 Moving to %s at (%.1f, %.1f, %.1f) (%.1f studs away)...", 
            QUEST_CONFIG.NPC_NAME, targetPos.X, targetPos.Y, targetPos.Z, currentDist))
    end
    
    local moveComplete = false
    smoothMoveTo(targetPos, function()
        moveComplete = true
    end)
    
    local timeout = 60
    local startTime = tick()
    while not moveComplete and tick() - startTime < timeout do
        task.wait(0.1)
    end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    if not moveComplete then
        warn("   ❌ Failed to reach NPC (timeout)")
        return false
    end
    
    print("\n📞 Interacting with Sensei Moro...")
    task.wait(0.5)
    
    local dialogueSuccess = startDialogue(npcModel)
    if not dialogueSuccess then
        warn("   ❌ Dialogue failed!")
        return false
    end
    
    print("   ⏳ Waiting for dialogue to open...")
    task.wait(1.5)
    
    local optionSuccess = selectQuestOption(QUEST_CONFIG.QUEST_OPTION_ARG)
    if not optionSuccess then
        warn("   ❌ Option selection failed!")
    end
    
    print("   ⏳ Processing...")
    task.wait(1)
    
    forceRestoreUI()
    
    print("   ✅ Dialogue complete!")
    return true
end

----------------------------------------------------------------
-- SMART QUEST RUNNER
----------------------------------------------------------------
print(string.rep("=", 50))
print("🚀 QUEST 8: " .. QUEST_CONFIG.QUEST_NAME)
print("🎯 Objective: Report to Sensei Moro")
print(string.rep("=", 50))

local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)

if not questID then
    warn("❌ Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not found!")
    Quest8Active = false
    cleanupState()
    disableNoclip()
    return
end

print("✅ Quest found (ID: " .. questID .. ")")

print("\n" .. string.rep("=", 50))
print("⚙️  Quest Objectives:")
local objectiveCount = 0
for _, item in ipairs(objList:GetChildren()) do
    if item:IsA("Frame") and tonumber(item.Name) then
        objectiveCount = objectiveCount + 1
        local text = getObjectiveText(item)
        local complete = isObjectiveComplete(item)
        print(string.format("   %d. %s [%s]", objectiveCount, text, complete and "✅" or "⏳"))
    end
end
print(string.rep("=", 50))

if areAllObjectivesComplete() then
    print("\n✅ Quest already complete!")
    cleanupState()
    disableNoclip()
    return
end

local maxAttempts = 3
local attempt = 0

while isQuest8StillActive() and not areAllObjectivesComplete() and attempt < maxAttempts do
    attempt = attempt + 1
    print(string.format("\n🔄 Attempt #%d", attempt))
    
    local success = doReportToSenseiMoro()
    
    if success then
        print("   ✅ Reporting complete!")
        task.wait(2)
        
        if areAllObjectivesComplete() then
            print("\n🎉 All objectives complete!")
            break
        else
            print("   ⚠️ Quest not marked complete, retrying...")
            task.wait(2)
        end
    else
        warn("   ❌ Reporting failed, retrying in 3s...")
        task.wait(3)
    end
end

task.wait(1)

if areAllObjectivesComplete() then
    print("\n" .. string.rep("=", 50))
    print("✅ Quest 8 Complete!")
    print(string.rep("=", 50))
else
    warn("\n" .. string.rep("=", 50))
    warn("⚠️ Quest 8 incomplete after " .. attempt .. " attempts")
    warn(string.rep("=", 50))
end

Quest8Active = false
cleanupState()
disableNoclip()

end

-- Quest 09
_G.QuestFunctions[9] = function()
local Shared = _G.Shared

-- QUEST 9: "The First Upgrade!" (Auto Enhance to +3)
-- ✅ No need to Move to NPC
-- ✅ Use Enhance Equipment Remote directly
-- ✅ Loop Enhance until Quest is complete

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest9Active = true

local QUEST_CONFIG = {
    QUEST_NAME = "The First Upgrade",
    TARGET_UPGRADE_LEVEL = 3,  -- Must enhance to +3
    ENHANCE_DELAY = 1.0,       -- Wait 1s between enhances
    MAX_ENHANCE_ATTEMPTS = 50, -- Prevent infinite loop
}

----------------------------------------------------------------
-- KNIT SETUP
----------------------------------------------------------------
local KnitPackage = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitPackage)

if not Knit.OnStart then 
    pcall(function() Knit.Start():await() end)
end

local PlayerController = nil
local EnhanceService = nil

pcall(function()
    PlayerController = Knit.GetController("PlayerController")
    EnhanceService = Knit.GetService("EnhanceService")
end)

local SERVICES = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")

local ENHANCE_RF = nil
pcall(function()
    ENHANCE_RF = SERVICES:WaitForChild("EnhanceService", 5):WaitForChild("RF", 3):WaitForChild("EnhanceEquipment", 3)
end)

local FIND_EQUIPMENT_RF = nil
pcall(function()
    FIND_EQUIPMENT_RF = SERVICES:WaitForChild("EnhanceService", 5):WaitForChild("RF", 3):WaitForChild("FindEquipmentByGUID", 3)
end)

if PlayerController then print("✅ PlayerController Ready!") else warn("⚠️ PlayerController not found") end
if EnhanceService then print("✅ EnhanceService Ready!") else warn("⚠️ EnhanceService not found") end
if ENHANCE_RF then print("✅ Enhance Remote Ready!") else warn("⚠️ Enhance Remote not found") end
if FIND_EQUIPMENT_RF then print("✅ FindEquipment Remote Ready!") else warn("⚠️ FindEquipment Remote not found") end

----------------------------------------------------------------
-- QUEST SYSTEM
----------------------------------------------------------------
local function getQuestObjectives(questName)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil, nil end
    
    local list = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Screen") 
                 and gui.Main.Screen:FindFirstChild("Quests") and gui.Main.Screen.Quests:FindFirstChild("List")
    if not list then return nil, nil end
    
    local questID = nil
    for _, child in ipairs(list:GetChildren()) do
        local id = string.match(child.Name, "^Introduction(%d+)Title$")
        if id and child:FindFirstChild("Frame") and child.Frame:FindFirstChild("TextLabel") then
            if child.Frame.TextLabel.Text == questName then
                questID = id
                break
            end
        end
    end
    
    if not questID then return nil, nil end
    
    local objList = list:FindFirstChild("Introduction" .. questID .. "List")
    return questID, objList
end

local function isObjectiveComplete(item)
    if not item then return false end
    local check = item:FindFirstChild("Main") and item.Main:FindFirstChild("Frame") and item.Main.Frame:FindFirstChild("Check")
    return check and check.Visible
end

local function getObjectiveText(item)
    local lbl = item:FindFirstChild("Main") and item.Main:FindFirstChild("TextLabel")
    return lbl and lbl.Text or ""
end

local function isQuest9StillActive()
    if not Quest9Active then return false end
    
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)
    if not questID or not objList then
        print("🛑 Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not found!")
        Quest9Active = false
        return false
    end
    
    return true
end

local function areAllObjectivesComplete()
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)
    if not questID or not objList then return true end
    
    for _, item in ipairs(objList:GetChildren()) do
        if item:IsA("Frame") and tonumber(item.Name) then
            if not isObjectiveComplete(item) then
                return false
            end
        end
    end
    
    return true
end

----------------------------------------------------------------
-- UI CONTROLLER (from Quest04)
----------------------------------------------------------------
local UIController = nil
pcall(function()
    for _, v in pairs(getgc(true)) do
        if type(v) == "table" then
            if rawget(v, "Open") and rawget(v, "Close") and rawget(v, "Modules") then
                UIController = v
                break
            end
        end
    end
end)

if UIController then print("✅ UIController Ready!") else warn("⚠️ UIController not found") end

local function openToolsMenu()
    if not UIController then return false end
    
    if UIController.Modules["Menu"] then
        pcall(function() UIController:Open("Menu") end)
        task.wait(0.5)
        
        local menuModule = UIController.Modules["Menu"]
        if menuModule.OpenTab then
            pcall(function() menuModule:OpenTab("Tools") end)
        elseif menuModule.SwitchTab then
            pcall(function() menuModule:SwitchTab("Tools") end)
        end
        
        task.wait(0.5)
        return true
    end
    
    return false
end

local function closeToolsMenu()
    if UIController and UIController.Close then
        pcall(function() UIController:Close("Menu") end)
        task.wait(0.3)
    end
end

----------------------------------------------------------------
-- FIND EQUIPPED WEAPON (via UI "Unequip" text)
----------------------------------------------------------------
local function findEquippedWeapon()
    print("   📂 Opening Tools menu to find equipped weapon...")
    openToolsMenu()
    task.wait(0.5)
    
    local menuGui = playerGui:FindFirstChild("Menu")
    if not menuGui then 
        warn("   ❌ Menu GUI not found!")
        closeToolsMenu()
        return nil, "Menu GUI not found"
    end
    
    local toolsFrame = menuGui:FindFirstChild("Frame") 
                    and menuGui.Frame:FindFirstChild("Frame") 
                    and menuGui.Frame.Frame:FindFirstChild("Menus") 
                    and menuGui.Frame.Frame.Menus:FindFirstChild("Tools")
                    and menuGui.Frame.Frame.Menus.Tools:FindFirstChild("Frame")
    
    if not toolsFrame then 
        warn("   ❌ Tools Frame not found!")
        closeToolsMenu()
        return nil, "Tools Frame not found"
    end
    
    print("   🔍 Scanning for equipped weapon (Unequip button)...")
    
    local equippedWeapon = nil
    
    -- Scan all items in Tools frame
    for _, weaponFrame in ipairs(toolsFrame:GetChildren()) do
        if weaponFrame:IsA("Frame") then
            local equipButton = weaponFrame:FindFirstChild("Equip")
            if equipButton then
                local textLabel = equipButton:FindFirstChild("TextLabel")
                if textLabel and textLabel:IsA("TextLabel") then
                    -- Check if text is "Unequip" = currently equipped
                    if textLabel.Text == "Unequip" then
                        local guid = weaponFrame.Name
                        
                        -- Skip Pickaxe
                        local itemName = weaponFrame:FindFirstChild("TextLabel")
                        local itemType = itemName and itemName.Text or ""
                        
                        if string.find(itemType, "Pickaxe") then
                            print(string.format("      ⏭️  Skipping Pickaxe: %s", itemType))
                            continue
                        end
                        
                        -- Get Upgrade level from UI
                        local upgradeLevel = 0
                        local stats = weaponFrame:FindFirstChild("Stats")
                        if stats then
                            -- Try to find upgrade text
                            for _, stat in ipairs(stats:GetChildren()) do
                                if stat:IsA("TextLabel") then
                                    local upgradeMatch = string.match(stat.Text, "%+(%d+)")
                                    if upgradeMatch then
                                        upgradeLevel = tonumber(upgradeMatch) or 0
                                    end
                                end
                            end
                        end
                        
                        equippedWeapon = {
                            GUID = guid,
                            Name = itemType,
                            Type = itemType,
                            Upgrade = upgradeLevel,
                        }
                        
                        print(string.format("      ✅ Found equipped weapon: %s (GUID: %s, +%d)", 
                            itemType, guid, upgradeLevel))
                        break
                    end
                end
            end
        end
    end
    
    closeToolsMenu()
    
    if not equippedWeapon then
        return nil, "No equipped weapon found (no Unequip button)"
    end
    
    return equippedWeapon, nil
end

local function getItemCurrentUpgrade(guid)
    if not FIND_EQUIPMENT_RF then return nil end
    
    local success, result = pcall(function()
        return FIND_EQUIPMENT_RF:InvokeServer(guid)
    end)
    
    if success and result and type(result) == "table" then
        return result.Upgrade or 0
    end
    
    return nil
end

----------------------------------------------------------------
-- ENHANCE SYSTEM
----------------------------------------------------------------
local function enhanceItem(guid)
    if not ENHANCE_RF then
        warn("   ❌ Enhance Remote not available!")
        return false, "Remote not available"
    end
    
    local success, result = pcall(function()
        return ENHANCE_RF:InvokeServer(guid)
    end)
    
    if success then
        if result == true or (type(result) == "table" and result.Success) then
            return true, "Success"
        elseif type(result) == "table" and result.Error then
            return false, result.Error
        else
            return false, "Unknown result"
        end
    else
        return false, tostring(result)
    end
end

local function printItemInfo(item)
    print(string.format("   🎯 Selected Item: %s", item.Name or item.Type))
    print(string.format("      - Type: %s", item.Type or "Unknown"))
    print(string.format("      - Current Upgrade: +%d", item.Upgrade or 0))
    print(string.format("      - GUID: %s", item.GUID))
end

----------------------------------------------------------------
-- MAIN QUEST EXECUTION
----------------------------------------------------------------
local function doEnhanceToPlus3()
    print("⚡ Objective: Enhance EQUIPPED weapon to +3...")
    
    -- Find currently equipped weapon (not lowest upgrade)
    local targetItem, errorMsg = findEquippedWeapon()
    
    if not targetItem then
        warn("   ❌ ERROR: " .. errorMsg)
        return false
    end
    
    printItemInfo(targetItem)
    
    if targetItem.Upgrade >= QUEST_CONFIG.TARGET_UPGRADE_LEVEL then
        print(string.format("   ✅ Item already at +%d or higher!", targetItem.Upgrade))
        return true
    end
    
    print(string.format("\n   🔨 Starting Enhancement Loop (Target: +%d)...\n", QUEST_CONFIG.TARGET_UPGRADE_LEVEL))
    
    local enhanceCount = 0
    local successCount = 0
    local failCount = 0
    
    while isQuest9StillActive() and not areAllObjectivesComplete() do
        enhanceCount = enhanceCount + 1
        
        if enhanceCount > QUEST_CONFIG.MAX_ENHANCE_ATTEMPTS then
            warn(string.format("   ⚠️ Max attempts reached (%d)! Stopping...", QUEST_CONFIG.MAX_ENHANCE_ATTEMPTS))
            break
        end
        
        -- Check current level
        local currentUpgrade = getItemCurrentUpgrade(targetItem.GUID)
        
        if currentUpgrade then
            print(string.format("   📊 Current Status: +%d / +%d", currentUpgrade, QUEST_CONFIG.TARGET_UPGRADE_LEVEL))
            
            if currentUpgrade >= QUEST_CONFIG.TARGET_UPGRADE_LEVEL then
                print(string.format("   🎉 Target reached! Item is now +%d", currentUpgrade))
                break
            end
        end
        
        -- Try Enhance
        print(string.format("   ⚡ Enhance Attempt #%d...", enhanceCount))
        
        local success, result = enhanceItem(targetItem.GUID)
        
        if success then
            successCount = successCount + 1
            print(string.format("      ✅ Enhancement SUCCESS! (+%d successful)", successCount))
        else
            failCount = failCount + 1
            print(string.format("      ❌ Enhancement FAILED! (%s) (+%d failed)", result, failCount))
        end
        
        -- Check if quest is complete
        task.wait(0.5)
        if areAllObjectivesComplete() then
            print("\n   🎉 Quest objective completed!")
            break
        end
        
        -- Wait before next attempt
        print(string.format("   ⏸️  Waiting %.1fs before next attempt...\n", QUEST_CONFIG.ENHANCE_DELAY))
        task.wait(QUEST_CONFIG.ENHANCE_DELAY)
    end
    
    print("\n   📊 Enhancement Summary:")
    print(string.format("      - Total Attempts: %d", enhanceCount))
    print(string.format("      - Successful: %d", successCount))
    print(string.format("      - Failed: %d", failCount))
    
    -- Check final level
    local finalUpgrade = getItemCurrentUpgrade(targetItem.GUID)
    if finalUpgrade then
        print(string.format("      - Final Upgrade: +%d", finalUpgrade))
        
        if finalUpgrade >= QUEST_CONFIG.TARGET_UPGRADE_LEVEL then
            print("   ✅ Enhancement complete!")
            return true
        else
            warn(string.format("   ⚠️ Failed to reach +%d (current: +%d)", QUEST_CONFIG.TARGET_UPGRADE_LEVEL, finalUpgrade))
            return false
        end
    end
    
    return false
end

----------------------------------------------------------------
-- SMART QUEST RUNNER
----------------------------------------------------------------
print(string.rep("=", 50))
print("🚀 QUEST 9: " .. QUEST_CONFIG.QUEST_NAME)
print("🎯 Objective: Enhance Item to +" .. QUEST_CONFIG.TARGET_UPGRADE_LEVEL)
print("✅ Strategy: Remote-based Enhancement (No Movement)")
print(string.rep("=", 50))

local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)

if not questID then
    warn("❌ Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not found!")
    Quest9Active = false
    return
end

print("✅ Quest found (ID: " .. questID .. ")")

print("\n" .. string.rep("=", 50))
print("⚙️  Quest Objectives:")
local objectiveCount = 0
for _, item in ipairs(objList:GetChildren()) do
    if item:IsA("Frame") and tonumber(item.Name) then
        objectiveCount = objectiveCount + 1
        local text = getObjectiveText(item)
        local complete = isObjectiveComplete(item)
        print(string.format("   %d. %s [%s]", objectiveCount, text, complete and "✅" or "⏳"))
    end
end
print(string.rep("=", 50))

if areAllObjectivesComplete() then
    print("\n✅ Quest already complete!")
    return
end

print("\n" .. string.rep("=", 50))
print("⚡ Starting Enhancement Process...")
print(string.rep("=", 50))

local success = doEnhanceToPlus3()

task.wait(1)

if areAllObjectivesComplete() then
    print("\n" .. string.rep("=", 50))
    print("✅ Quest 9 Complete!")
    print(string.rep("=", 50))
else
    if success then
        print("\n   ⚠️ Enhancement complete but quest not marked done")
        print("   💡 Try checking quest status manually")
    else
        warn("\n" .. string.rep("=", 50))
        warn("⚠️ Quest 9 incomplete - Enhancement failed")
        warn(string.rep("=", 50))
    end
end

Quest9Active = false

end

-- Quest 10
_G.QuestFunctions[10] = function()
local Shared = _G.Shared

-- QUEST 10: "Runes of Power!" (FIXED - Find Rune from Stash UI)
-- ✅ Find Rune from PlayerGui.Menu.Frame.Menus.Stash.Background
-- ✅ Find ItemName = "Flame Spark" or "Blast Chip"
-- ✅ Use GUID to Attach Rune
-- ✅ No need to open Rune UI first!

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest10Active = true
local DEBUG_MODE = true

local QUEST_CONFIG = {
    QUEST_NAME = "Runes of Power",
    NPC_NAME = "Runemaker",
    NPC_POSITION = Vector3.new(-271.7, 20.3, 141.9),
    MOVE_SPEED = 25,  
    NPC_STOP_DISTANCE = 5,
    
    -- Runes to look for (pick one)
    ALLOWED_RUNE_NAMES = {
        "Flame Spark",
        "Blast Chip",
    },
}

----------------------------------------------------------------
-- KNIT SETUP
----------------------------------------------------------------
local KnitPackage = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitPackage)

if not Knit.OnStart then 
    pcall(function() Knit.Start():await() end)
end

local PlayerController = nil
local ProximityService = nil
local RuneService = nil

pcall(function()
    PlayerController = Knit.GetController("PlayerController")
    ProximityService = Knit.GetService("ProximityService")
    RuneService = Knit.GetService("RuneService")
end)

local SERVICES = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")

local PURCHASE_ATTACH_RF = nil
pcall(function()
    PURCHASE_ATTACH_RF = SERVICES:WaitForChild("RuneService", 5):WaitForChild("RF", 3):WaitForChild("PurchaseAttach", 3)
end)

local GET_PRICE_INFO_RF = nil
pcall(function()
    GET_PRICE_INFO_RF = SERVICES:WaitForChild("RuneService", 5):WaitForChild("RF", 3):WaitForChild("GetPriceInfo", 3)
end)

if PlayerController then print("✅ PlayerController Ready!") else warn("⚠️ PlayerController not found") end
if ProximityService then print("✅ ProximityService Ready!") else warn("⚠️ ProximityService not found") end
if RuneService then print("✅ RuneService Ready!") else warn("⚠️ RuneService not found") end
if PURCHASE_ATTACH_RF then print("✅ PurchaseAttach Remote Ready!") else warn("⚠️ PurchaseAttach Remote not found") end

----------------------------------------------------------------
-- STATE MANAGEMENT
----------------------------------------------------------------
local State = {
    noclipConn = nil,
    moveConn = nil,
    bodyVelocity = nil,
    bodyGyro = nil,
}

local function cleanupState()
    if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
end

----------------------------------------------------------------
-- QUEST SYSTEM
----------------------------------------------------------------
local function getQuestObjectives(questName)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil, nil end
    
    local list = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Screen") 
                 and gui.Main.Screen:FindFirstChild("Quests") and gui.Main.Screen.Quests:FindFirstChild("List")
    if not list then return nil, nil end
    
    local questID = nil
    for _, child in ipairs(list:GetChildren()) do
        local id = string.match(child.Name, "^Introduction(%d+)Title$")
        if id and child:FindFirstChild("Frame") and child.Frame:FindFirstChild("TextLabel") then
            if child.Frame.TextLabel.Text == questName then
                questID = id
                break
            end
        end
    end
    
    if not questID then return nil, nil end
    
    local objList = list:FindFirstChild("Introduction" .. questID .. "List")
    return questID, objList
end

local function isObjectiveComplete(item)
    if not item then return false end
    local check = item:FindFirstChild("Main") and item.Main:FindFirstChild("Frame") and item.Main.Frame:FindFirstChild("Check")
    return check and check.Visible
end

local function getObjectiveText(item)
    local lbl = item:FindFirstChild("Main") and item.Main:FindFirstChild("TextLabel")
    return lbl and lbl.Text or ""
end

local function isQuest10StillActive()
    if not Quest10Active then return false end
    
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)
    if not questID or not objList then
        print("🛑 Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not found!")
        Quest10Active = false
        return false
    end
    
    return true
end

local function areAllObjectivesComplete()
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)
    if not questID or not objList then return true end
    
    for _, item in ipairs(objList:GetChildren()) do
        if item:IsA("Frame") and tonumber(item.Name) then
            if not isObjectiveComplete(item) then
                return false
            end
        end
    end
    
    return true
end

----------------------------------------------------------------
-- EQUIPMENT HELPERS
----------------------------------------------------------------
local function getEquippedWeaponGUID()
    print("   🔍 Checking equipped items from UI...")
    
    local menuUI = playerGui:FindFirstChild("Menu")
                   and playerGui.Menu:FindFirstChild("Frame")
                   and playerGui.Menu.Frame:FindFirstChild("Frame")
                   and playerGui.Menu.Frame.Frame:FindFirstChild("Menus")
                   and playerGui.Menu.Frame.Frame.Menus:FindFirstChild("Tools")
                   and playerGui.Menu.Frame.Frame.Menus.Tools:FindFirstChild("Frame")
    
    if menuUI then
        for _, child in ipairs(menuUI:GetChildren()) do
            if string.match(child.Name, "^%x+%-%x+%-%x+%-%x+%-%x+$") then
                local equipButton = child:FindFirstChild("Equip")
                local equipLabel = equipButton and equipButton:FindFirstChild("TextLabel")
                
                if equipLabel and equipLabel:IsA("TextLabel") then
                    local isEquipped = (equipLabel.Text == "Unequip")
                    
                    if PlayerController and PlayerController.Replica then
                        local replica = PlayerController.Replica
                        if replica.Data and replica.Data.Inventory and replica.Data.Inventory.Equipments then
                            for id, item in pairs(replica.Data.Inventory.Equipments) do
                                if type(item) == "table" and item.GUID == child.Name then
                                    local isPickaxe = string.find(item.Type or "", "Pickaxe")
                                    
                                    if DEBUG_MODE then
                                        print(string.format("      - %s: UI_Equipped=%s, Pickaxe=%s, GUID=%s", 
                                            item.Type or "Unknown", 
                                            tostring(isEquipped), 
                                            tostring(isPickaxe), 
                                            item.GUID))
                                    end
                                    
                                    if not isPickaxe and isEquipped then
                                        return item.GUID, item.Type
                                    end
                                    
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    else
        warn("   ⚠️ Menu UI not found!")
    end
    
    print("   🔍 Fallback: Checking from Replica...")
    
    if not PlayerController or not PlayerController.Replica then
        warn("   ⚠️ PlayerController/Replica not available!")
        return nil
    end
    
    local replica = PlayerController.Replica
    if not replica.Data or not replica.Data.Inventory or not replica.Data.Inventory.Equipments then
        warn("   ⚠️ Equipments not found in Replica!")
        return nil
    end
    
    local equipments = replica.Data.Inventory.Equipments
    
    for id, item in pairs(equipments) do
        if type(item) == "table" and item.Type and item.GUID then
            local isPickaxe = string.find(item.Type, "Pickaxe")
            local isEquipped = (item.Equipped == true)
            
            if DEBUG_MODE then
                print(string.format("      - %s: Replica_Equipped=%s, Pickaxe=%s, GUID=%s", 
                    item.Type, tostring(isEquipped), tostring(isPickaxe), item.GUID))
            end
            
            if not isPickaxe and isEquipped then
                return item.GUID, item.Type
            end
        end
    end
    
    warn("   ❌ No equipped weapon found (excluding Pickaxe)!")
    return nil
end

----------------------------------------------------------------
-- RUNE HELPERS (FIXED - Find from Stash UI)
----------------------------------------------------------------
local function getRunesFromStash()
    local runes = {}
    
    print("   🔍 Searching for Runes in Stash UI...")
    
    -- Path: PlayerGui.Menu.Frame.Frame.Menus.Stash.Background
    local stashBackground = playerGui:FindFirstChild("Menu")
                           and playerGui.Menu:FindFirstChild("Frame")
                           and playerGui.Menu.Frame:FindFirstChild("Frame")
                           and playerGui.Menu.Frame.Frame:FindFirstChild("Menus")
                           and playerGui.Menu.Frame.Frame.Menus:FindFirstChild("Stash")
                           and playerGui.Menu.Frame.Frame.Menus.Stash:FindFirstChild("Background")
    
    if not stashBackground then
        warn("   ❌ Stash Background not found!")
        warn("   💡 Path: PlayerGui.Menu.Frame.Frame.Menus.Stash.Background")
        return runes
    end
    
    print("   ✅ Found Stash Background!")
    print(string.format("   📊 Total children: %d", #stashBackground:GetChildren()))
    
    -- Loop through all children to find GUIDs
    for _, child in ipairs(stashBackground:GetChildren()) do
        -- Check if name is GUID pattern (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
        if string.match(child.Name, "^%x+%-%x+%-%x+%-%x+%-%x+$") then
            local main = child:FindFirstChild("Main")
            if main then
                local itemNameLabel = main:FindFirstChild("ItemName")
                if itemNameLabel and itemNameLabel:IsA("TextLabel") then
                    local itemName = itemNameLabel.Text
                    local itemGUID = child.Name
                    
                    if DEBUG_MODE then
                        print(string.format("      - Found Item: %s (GUID: %s)", itemName, itemGUID))
                    end
                    
                    table.insert(runes, {
                        GUID = itemGUID,
                        Name = itemName,
                        Frame = child,
                    })
                end
            end
        end
    end
    
    print(string.format("   📊 Total items found in Stash: %d", #runes))
    
    return runes
end

local function findAllowedRuneFromStash()
    local allItems = getRunesFromStash()
    
    if #allItems == 0 then
        return nil, "No items found in Stash!"
    end
    
    print(string.format("   📋 Found %d item(s) in Stash:", #allItems))
    
    -- Filter runes matching ALLOWED_RUNE_NAMES
    local allowedRunes = {}
    
    for _, item in ipairs(allItems) do
        for _, allowedName in ipairs(QUEST_CONFIG.ALLOWED_RUNE_NAMES) do
            if item.Name == allowedName then
                table.insert(allowedRunes, item)
                print(string.format("      ✅ Matched: %s (GUID: %s)", item.Name, item.GUID))
            end
        end
    end
    
    if #allowedRunes == 0 then
        warn(string.format("   ❌ No allowed runes found!"))
        warn(string.format("   💡 Looking for: %s", table.concat(QUEST_CONFIG.ALLOWED_RUNE_NAMES, ", ")))
        
        -- Debug: Show all available items
        if DEBUG_MODE then
            print("   📋 Available items in Stash:")
            for i, item in ipairs(allItems) do
                print(string.format("      %d. %s (GUID: %s)", i, item.Name, item.GUID))
            end
        end
        
        return nil, string.format("No allowed runes found! (Looking for: %s)", table.concat(QUEST_CONFIG.ALLOWED_RUNE_NAMES, ", "))
    end
    
    -- Randomly select one
    local selectedRune = allowedRunes[math.random(1, #allowedRunes)]
    
    return selectedRune, nil
end

----------------------------------------------------------------
-- NOCLIP & MOVEMENT
----------------------------------------------------------------
local function enableNoclip()
    if State.noclipConn then return end
    
    local char = player.Character
    if not char then return end
    
    State.noclipConn = RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
            return
        end
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
end

local function smoothMoveTo(targetPos, callback)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    enableNoclip()
    
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = hrp
    State.bodyVelocity = bv
    
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.D = 500
    bg.Parent = hrp
    State.bodyGyro = bg
    
    print(string.format("   🚀 Moving to (%.1f, %.1f, %.1f)...", targetPos.X, targetPos.Y, targetPos.Z))
    
    State.moveConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv then bv:Destroy() end
            if bg then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end
        
        local currentPos = hrp.Position
        local direction = (targetPos - currentPos)
        local distance = direction.Magnitude
        
        if distance < QUEST_CONFIG.NPC_STOP_DISTANCE then
            print("   ✅ Reached NPC!")
            
            bv.Velocity = Vector3.zero
            task.wait(0.1)
            
            bv:Destroy()
            bg:Destroy()
            State.bodyVelocity = nil
            State.bodyGyro = nil
            
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            
            if callback then callback() end
            return
        end
        
        local speed = math.min(QUEST_CONFIG.MOVE_SPEED, distance * 10)
        local velocity = direction.Unit * speed
        
        bv.Velocity = velocity
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
    end)
    
    return true
end

----------------------------------------------------------------
-- NPC INTERACTION
----------------------------------------------------------------
local function getNpcModel(name)
    local prox = Workspace:FindFirstChild("Proximity")
    return prox and prox:FindFirstChild(name)
end

----------------------------------------------------------------
-- RUNE ATTACHMENT
----------------------------------------------------------------
local function attachRuneToWeapon(weaponGUID, runeGUID)
    if not PURCHASE_ATTACH_RF then
        warn("   ❌ PurchaseAttach Remote not available!")
        return false
    end
    
    print(string.format("🔮 Attaching Rune to Weapon..."))
    print(string.format("   - Weapon GUID: %s", weaponGUID))
    print(string.format("   - Rune GUID: %s", runeGUID))
    
    -- Call GetPriceInfo first (if available)
    if GET_PRICE_INFO_RF then
        local success = pcall(function()
            GET_PRICE_INFO_RF:InvokeServer(weaponGUID, runeGUID, "Attach")
        end)
        
        if success then
            print("   ✅ GetPriceInfo called")
        end
        
        task.wait(0.3)
    end
    
    -- Call PurchaseAttach
    local success, result = pcall(function()
        return PURCHASE_ATTACH_RF:InvokeServer(weaponGUID, runeGUID)
    end)
    
    if success then
        print("   ✅ Rune attached successfully!")
        return true
    else
        warn("   ❌ Failed to attach rune: " .. tostring(result))
        return false
    end
end

----------------------------------------------------------------
-- MAIN QUEST EXECUTION
----------------------------------------------------------------
local function doAttachRune()
    print("🔮 Objective: Attach Rune to Weapon...")
    
    -- 1. Move to NPC
    local npcModel = getNpcModel(QUEST_CONFIG.NPC_NAME)
    if not npcModel then
        warn("   ❌ NPC not found: " .. QUEST_CONFIG.NPC_NAME)
        return false
    end
    
    local npcPos = QUEST_CONFIG.NPC_POSITION
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    
    if hrp then
        local currentDist = (npcPos - hrp.Position).Magnitude
        print(string.format("   🚶 Moving to %s at (%.1f, %.1f, %.1f) (%.1f studs away)...", 
            QUEST_CONFIG.NPC_NAME, npcPos.X, npcPos.Y, npcPos.Z, currentDist))
    end
    
    local moveComplete = false
    smoothMoveTo(npcPos, function()
        moveComplete = true
    end)
    
    local timeout = 60
    local startTime = tick()
    while not moveComplete and tick() - startTime < timeout do
        task.wait(0.1)
    end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    if not moveComplete then
        warn("   ⚠️ Failed to reach NPC")
        return false
    end
    
    print("   ✅ Reached NPC!")
    task.wait(1)
    
    -- 2. Find Equipped Weapon
    print("\n🔍 Finding equipped weapon...")
    local weaponGUID, weaponType = getEquippedWeaponGUID()
    
    if not weaponGUID then
        warn("   ❌ No weapon equipped!")
        warn("   💡 Please equip a weapon (not pickaxe) and try again")
        return false
    end
    
    print(string.format("   ✅ Found equipped weapon: %s (GUID: %s)", weaponType or "Unknown", weaponGUID))
    
    -- 3. Find Rune from Stash UI
    print("\n🔍 Finding suitable rune from Stash UI...")
    local selectedRune, errorMsg = findAllowedRuneFromStash()
    
    if not selectedRune then
        warn("   ❌ ERROR: " .. errorMsg)
        return false
    end
    
    print(string.format("   ✅ Selected Rune: %s (GUID: %s)", selectedRune.Name, selectedRune.GUID))
    
    -- 4. Attach Rune
    print("\n⚡ Attaching rune to weapon...")
    local attachSuccess = attachRuneToWeapon(weaponGUID, selectedRune.GUID)
    
    if attachSuccess then
        print("   ✅ Rune attachment complete!")
        return true
    else
        warn("   ❌ Rune attachment failed!")
        return false
    end
end

----------------------------------------------------------------
-- SMART QUEST RUNNER
----------------------------------------------------------------
print(string.rep("=", 50))
print("🚀 QUEST 10: " .. QUEST_CONFIG.QUEST_NAME)
print("🎯 Objective: Attach Rune to Weapon")
print("✅ Strategy: Move to NPC → Find Rune from Stash → Attach")
print(string.rep("=", 50))

local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)

if not questID then
    warn("❌ Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not found!")
    Quest10Active = false
    cleanupState()
    disableNoclip()
    return
end

print("✅ Quest found (ID: " .. questID .. ")")

print("\n" .. string.rep("=", 50))
print("⚙️  Quest Objectives:")
local objectiveCount = 0
for _, item in ipairs(objList:GetChildren()) do
    if item:IsA("Frame") and tonumber(item.Name) then
        objectiveCount = objectiveCount + 1
        local text = getObjectiveText(item)
        local complete = isObjectiveComplete(item)
        print(string.format("   %d. %s [%s]", objectiveCount, text, complete and "✅" or "⏳"))
    end
end
print(string.rep("=", 50))

if areAllObjectivesComplete() then
    print("\n✅ Quest already complete!")
    cleanupState()
    disableNoclip()
    return
end

local maxAttempts = 3
local attempt = 0

while isQuest10StillActive() and not areAllObjectivesComplete() and attempt < maxAttempts do
    attempt = attempt + 1
    print(string.format("\n🔄 Attempt #%d", attempt))
    
    local success = doAttachRune()
    
    if success then
        print("   ✅ Rune attachment complete!")
        task.wait(2)
        
        if areAllObjectivesComplete() then
            print("\n🎉 All objectives complete!")
            break
        else
            print("   ⚠️ Quest not marked complete, retrying...")
            task.wait(2)
        end
    else
        warn("   ❌ Rune attachment failed, retrying in 3s...")
        task.wait(3)
    end
end

task.wait(1)

if areAllObjectivesComplete() then
    print("\n" .. string.rep("=", 50))
    print("✅ Quest 10 Complete!")
    print(string.rep("=", 50))
else
    warn("\n" .. string.rep("=", 50))
    warn("⚠️ Quest 10 incomplete after " .. attempt .. " attempts")
    warn(string.rep("=", 50))
end

Quest10Active = false
cleanupState()
disableNoclip()

end

-- Quest 11
_G.QuestFunctions[11] = function()
local Shared = _G.Shared

-- QUEST 11: "End of the Beginning!" (Report to Sensei Moro - Final Quest)
-- ✅ Body Move to Sensei Moro
-- ✅ Dialogue + CheckQuest
-- ✅ Force Restore UI

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest11Active = true

local QUEST_CONFIG = {
    QUEST_NAME = "End of the Beginning",
    NPC_NAME = "Sensei Moro",
    QUEST_OPTION_ARG = "CheckQuest",
    MOVE_SPEED = 25,  
    NPC_STOP_DISTANCE = 5,
}

----------------------------------------------------------------
-- KNIT SETUP
----------------------------------------------------------------
local KnitPackage = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitPackage)

if not Knit.OnStart then 
    pcall(function() Knit.Start():await() end)
end

local ProximityService = nil
local DialogueService = nil

pcall(function()
    ProximityService = Knit.GetService("ProximityService")
    DialogueService = Knit.GetService("DialogueService")
end)

local SERVICES = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")

local DIALOGUE_RF = nil
pcall(function()
    DIALOGUE_RF = SERVICES:WaitForChild("ProximityService", 5):WaitForChild("RF", 3):WaitForChild("Dialogue", 3)
end)

local RUNCOMMAND_RF = nil
pcall(function()
    RUNCOMMAND_RF = SERVICES:WaitForChild("DialogueService", 5):WaitForChild("RF", 3):WaitForChild("RunCommand", 3)
end)

local DIALOGUE_RE = nil
pcall(function()
    DIALOGUE_RE = SERVICES:WaitForChild("DialogueService", 5):WaitForChild("RE", 3):WaitForChild("DialogueEvent", 3)
end)

if ProximityService then print("✅ ProximityService Ready!") else warn("⚠️ ProximityService not found") end
if DialogueService then print("✅ DialogueService Ready!") else warn("⚠️ DialogueService not found") end
if DIALOGUE_RF then print("✅ Dialogue Remote Ready!") else warn("⚠️ Dialogue Remote not found") end
if RUNCOMMAND_RF then print("✅ RunCommand Remote Ready!") else warn("⚠️ RunCommand Remote not found") end

----------------------------------------------------------------
-- STATE MANAGEMENT
----------------------------------------------------------------
local State = {
    noclipConn = nil,
    moveConn = nil,
    bodyVelocity = nil,
    bodyGyro = nil,
}

local function cleanupState()
    if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
end

----------------------------------------------------------------
-- QUEST SYSTEM
----------------------------------------------------------------
local function getQuestObjectives(questName)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil, nil end
    
    local list = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Screen") 
                 and gui.Main.Screen:FindFirstChild("Quests") and gui.Main.Screen.Quests:FindFirstChild("List")
    if not list then return nil, nil end
    
    local questID = nil
    for _, child in ipairs(list:GetChildren()) do
        local id = string.match(child.Name, "^Introduction(%d+)Title$")
        if id and child:FindFirstChild("Frame") and child.Frame:FindFirstChild("TextLabel") then
            if child.Frame.TextLabel.Text == questName then
                questID = id
                break
            end
        end
    end
    
    if not questID then return nil, nil end
    
    local objList = list:FindFirstChild("Introduction" .. questID .. "List")
    return questID, objList
end

local function isObjectiveComplete(item)
    if not item then return false end
    local check = item:FindFirstChild("Main") and item.Main:FindFirstChild("Frame") and item.Main.Frame:FindFirstChild("Check")
    return check and check.Visible
end

local function getObjectiveText(item)
    local lbl = item:FindFirstChild("Main") and item.Main:FindFirstChild("TextLabel")
    return lbl and lbl.Text or ""
end

local function isQuest11StillActive()
    if not Quest11Active then return false end
    
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)
    if not questID or not objList then
        print("🛑 Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not found!")
        Quest11Active = false
        return false
    end
    
    return true
end

local function areAllObjectivesComplete()
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)
    if not questID or not objList then return true end
    
    for _, item in ipairs(objList:GetChildren()) do
        if item:IsA("Frame") and tonumber(item.Name) then
            if not isObjectiveComplete(item) then
                return false
            end
        end
    end
    
    return true
end

----------------------------------------------------------------
-- NPC HELPERS
----------------------------------------------------------------
local function getNpcModel(name)
    local prox = Workspace:FindFirstChild("Proximity")
    return prox and prox:FindFirstChild(name)
end

local function getNpcPosition(npcModel)
    if not npcModel then return nil end
    
    local targetPart = npcModel.PrimaryPart or npcModel:FindFirstChildWhichIsA("BasePart")
    if not targetPart then return nil end
    
    return targetPart.Position
end

----------------------------------------------------------------
-- NOCLIP & MOVEMENT
----------------------------------------------------------------
local function enableNoclip()
    if State.noclipConn then return end
    
    local char = player.Character
    if not char then return end
    
    State.noclipConn = RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
            return
        end
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
end

local function smoothMoveTo(targetPos, callback)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    enableNoclip()
    
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = hrp
    State.bodyVelocity = bv
    
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.D = 500
    bg.Parent = hrp
    State.bodyGyro = bg
    
    print(string.format("   🚀 Moving to (%.1f, %.1f, %.1f)...", targetPos.X, targetPos.Y, targetPos.Z))
    
    State.moveConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv then bv:Destroy() end
            if bg then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end
        
        local currentPos = hrp.Position
        local direction = (targetPos - currentPos)
        local distance = direction.Magnitude
        
        if distance < QUEST_CONFIG.NPC_STOP_DISTANCE then
            print("   ✅ Reached NPC!")
            
            bv.Velocity = Vector3.zero
            task.wait(0.1)
            
            bv:Destroy()
            bg:Destroy()
            State.bodyVelocity = nil
            State.bodyGyro = nil
            
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            
            if callback then callback() end
            return
        end
        
        local speed = math.min(QUEST_CONFIG.MOVE_SPEED, distance * 10)
        local velocity = direction.Unit * speed
        
        bv.Velocity = velocity
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
    end)
    
    return true
end

----------------------------------------------------------------
-- UI RESTORE
----------------------------------------------------------------
local function forceRestoreUI()
    print("🔧 Forcing UI Restore...")
    
    local char = player.Character
    if char then
        local status = char:FindFirstChild("Status")
        if status then
            for _, tag in ipairs(status:GetChildren()) do
                if tag.Name == "DisableBackpack" or tag.Name == "NoMovement" or tag.Name == "Talking" then
                    pcall(function() tag:Destroy() end)
                    print("   - Removed Status Tag: " .. tag.Name)
                end
            end
        end
        
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
        end
    end
    
    local gui = player:FindFirstChild("PlayerGui")
    if gui then
        local dUI = gui:FindFirstChild("DialogueUI")
        if dUI then
            dUI.Enabled = false
            local bb = dUI:FindFirstChild("ResponseBillboard")
            if bb then bb.Visible = false end
        end
        
        local main = gui:FindFirstChild("Main")
        if main then 
            main.Enabled = true 
            print("   - Main UI Restored")
        end
        
        local backpack = gui:FindFirstChild("BackpackGui")
        if backpack then 
            backpack.Enabled = true 
            print("   - Backpack Restored")
        end
        
        local compass = gui:FindFirstChild("Compass")
        if compass then compass.Enabled = true end
        
        local mobile = gui:FindFirstChild("MobileButtons")
        if mobile then mobile.Enabled = true end
    end
    
    local cam = Workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        cam.FieldOfView = 70
    end
    
    if DIALOGUE_RE then
        pcall(function() DIALOGUE_RE:FireServer("Closed") end)
    end
    
    print("✅ UI Restore Complete")
end

----------------------------------------------------------------
-- DIALOGUE SYSTEM
----------------------------------------------------------------
local function startDialogue(npcModel)
    if not DIALOGUE_RF then
        warn("   ❌ Dialogue Remote not available!")
        return false
    end
    
    print("📞 Starting Dialogue with " .. QUEST_CONFIG.NPC_NAME .. "...")
    
    local success = pcall(function()
        DIALOGUE_RF:InvokeServer(npcModel)
    end)
    
    if success then
        print("   ✅ Dialogue started!")
        return true
    else
        warn("   ❌ Failed to start dialogue")
        return false
    end
end

local function selectQuestOption(optionName)
    if not RUNCOMMAND_RF then
        warn("   ❌ RunCommand Remote not available!")
        return false
    end
    
    print("✅ Selecting Option: " .. optionName)
    
    local success = pcall(function()
        RUNCOMMAND_RF:InvokeServer(optionName)
    end)
    
    if success then
        print("   ✅ Option selected!")
        return true
    else
        warn("   ❌ Failed to select option")
        return false
    end
end

----------------------------------------------------------------
-- MAIN QUEST EXECUTION
----------------------------------------------------------------
local function doReportToSenseiMoro()
    print("📋 Objective: Report to Sensei Moro (Final Quest)...")
    
    local npcModel = getNpcModel(QUEST_CONFIG.NPC_NAME)
    if not npcModel then
        warn("   ❌ NPC not found: " .. QUEST_CONFIG.NPC_NAME)
        return false
    end
    
    local targetPos = getNpcPosition(npcModel)
    if not targetPos then
        warn("   ❌ Cannot get NPC position!")
        return false
    end
    
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local currentDist = (targetPos - hrp.Position).Magnitude
        print(string.format("   🚶 Moving to %s at (%.1f, %.1f, %.1f) (%.1f studs away)...", 
            QUEST_CONFIG.NPC_NAME, targetPos.X, targetPos.Y, targetPos.Z, currentDist))
    end
    
    local moveComplete = false
    smoothMoveTo(targetPos, function()
        moveComplete = true
    end)
    
    local timeout = 60
    local startTime = tick()
    while not moveComplete and tick() - startTime < timeout do
        task.wait(0.1)
    end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    if not moveComplete then
        warn("   ❌ Failed to reach NPC (timeout)")
        return false
    end
    
    print("\n📞 Interacting with Sensei Moro...")
    task.wait(0.5)
    
    local dialogueSuccess = startDialogue(npcModel)
    if not dialogueSuccess then
        warn("   ❌ Dialogue failed!")
        return false
    end
    
    print("   ⏳ Waiting for dialogue to open...")
    task.wait(1.5)
    
    local optionSuccess = selectQuestOption(QUEST_CONFIG.QUEST_OPTION_ARG)
    if not optionSuccess then
        warn("   ❌ Option selection failed!")
    end
    
    print("   ⏳ Processing...")
    task.wait(1)
    
    forceRestoreUI()
    
    print("   ✅ Dialogue complete!")
    return true
end

----------------------------------------------------------------
-- SMART QUEST RUNNER
----------------------------------------------------------------
print(string.rep("=", 50))
print("🚀 QUEST 11: " .. QUEST_CONFIG.QUEST_NAME)
print("🎯 Objective: Report to Sensei Moro (FINAL QUEST)")
print("🏆 Completing Introduction Quest Line!")
print(string.rep("=", 50))

local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)

if not questID then
    warn("❌ Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not found!")
    Quest11Active = false
    cleanupState()
    disableNoclip()
    return
end

print("✅ Quest found (ID: " .. questID .. ")")

print("\n" .. string.rep("=", 50))
print("⚙️  Quest Objectives:")
local objectiveCount = 0
for _, item in ipairs(objList:GetChildren()) do
    if item:IsA("Frame") and tonumber(item.Name) then
        objectiveCount = objectiveCount + 1
        local text = getObjectiveText(item)
        local complete = isObjectiveComplete(item)
        print(string.format("   %d. %s [%s]", objectiveCount, text, complete and "✅" or "⏳"))
    end
end
print(string.rep("=", 50))

if areAllObjectivesComplete() then
    print("\n✅ Quest already complete!")
    cleanupState()
    disableNoclip()
    return
end

local maxAttempts = 3
local attempt = 0

while isQuest11StillActive() and not areAllObjectivesComplete() and attempt < maxAttempts do
    attempt = attempt + 1
    print(string.format("\n🔄 Attempt #%d", attempt))
    
    local success = doReportToSenseiMoro()
    
    if success then
        print("   ✅ Reporting complete!")
        task.wait(2)
        
        if areAllObjectivesComplete() then
            print("\n🎉 All objectives complete!")
            break
        else
            print("   ⚠️ Quest not marked complete, retrying...")
            task.wait(2)
        end
    else
        warn("   ❌ Reporting failed, retrying in 3s...")
        task.wait(3)
    end
end

task.wait(1)

if areAllObjectivesComplete() then
    print("\n" .. string.rep("=", 50))
    print("🏆 QUEST 11 COMPLETE!")
    print("🎉 INTRODUCTION QUEST LINE FINISHED!")
    print("✨ Congratulations!")
    print(string.rep("=", 50))
else
    warn("\n" .. string.rep("=", 50))
    warn("⚠️ Quest 11 incomplete after " .. attempt .. " attempts")
    warn(string.rep("=", 50))
end

Quest11Active = false
cleanupState()
disableNoclip()

end

-- Quest 12
_G.QuestFunctions[12] = function()
local Shared = _G.Shared

-- QUEST 12: "Everything starts now!" (Talk to Wizard - Auto Complete)
-- ✅ Smooth Body Move to Wizard
-- ✅ Auto Dialogue → CheckQuest → FinishQuest
-- ✅ Force Restore UI

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest12Active = true

local QUEST_CONFIG = {
    QUEST_NAME = "Everything starts now.",
    NPC_NAME = "Wizard",
    NPC_POSITION = Vector3.new(-24.1, 80.9, -358.5),
    MOVE_SPEED = 25,  
    NPC_STOP_DISTANCE = 5,
}

----------------------------------------------------------------
-- STATE MANAGEMENT
----------------------------------------------------------------
local State = {
    noclipConn = nil,
    moveConn = nil,
    bodyVelocity = nil,
    bodyGyro = nil,
}

local function cleanupState()
    if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
end

----------------------------------------------------------------
-- QUEST SYSTEM
----------------------------------------------------------------
local function getQuestObjectives(questName)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil, nil end
    
    local list = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Screen") 
                 and gui.Main.Screen:FindFirstChild("Quests") and gui.Main.Screen.Quests:FindFirstChild("List")
    if not list then return nil, nil end
    
    local questID = nil
    for _, child in ipairs(list:GetChildren()) do
        local id = string.match(child.Name, "^Introduction(%d+)Title$")
        if id and child:FindFirstChild("Frame") and child.Frame:FindFirstChild("TextLabel") then
            if child.Frame.TextLabel.Text == questName then
                questID = id
                break
            end
        end
    end
    
    if not questID then return nil, nil end
    
    local objList = list:FindFirstChild("Introduction" .. questID .. "List")
    return questID, objList
end

local function isObjectiveComplete(item)
    if not item then return false end
    local check = item:FindFirstChild("Main") and item.Main:FindFirstChild("Frame") and item.Main.Frame:FindFirstChild("Check")
    return check and check.Visible
end

local function getObjectiveText(item)
    local lbl = item:FindFirstChild("Main") and item.Main:FindFirstChild("TextLabel")
    return lbl and lbl.Text or ""
end

local function isQuest12StillActive()
    if not Quest12Active then return false end
    
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)
    if not questID or not objList then
        print("🛑 Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not found!")
        Quest12Active = false
        return false
    end
    
    return true
end

local function areAllObjectivesComplete()
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)
    if not questID or not objList then return true end
    
    for _, item in ipairs(objList:GetChildren()) do
        if item:IsA("Frame") and tonumber(item.Name) then
            if not isObjectiveComplete(item) then
                return false
            end
        end
    end
    
    return true
end

----------------------------------------------------------------
-- NPC HELPERS
----------------------------------------------------------------
local function getNpcModel(name)
    local prox = Workspace:FindFirstChild("Proximity")
    return prox and prox:FindFirstChild(name)
end

----------------------------------------------------------------
-- NOCLIP & MOVEMENT
----------------------------------------------------------------
local function enableNoclip()
    if State.noclipConn then return end
    
    local char = player.Character
    if not char then return end
    
    State.noclipConn = RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
            return
        end
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
end

local function smoothMoveTo(targetPos, callback)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    enableNoclip()
    
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = hrp
    State.bodyVelocity = bv
    
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.D = 500
    bg.Parent = hrp
    State.bodyGyro = bg
    
    print(string.format("   🚀 Moving to (%.1f, %.1f, %.1f)...", targetPos.X, targetPos.Y, targetPos.Z))
    
    State.moveConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv then bv:Destroy() end
            if bg then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end
        
        local currentPos = hrp.Position
        local direction = (targetPos - currentPos)
        local distance = direction.Magnitude
        
        if distance < QUEST_CONFIG.NPC_STOP_DISTANCE then
            print("   ✅ Reached NPC!")
            
            bv.Velocity = Vector3.zero
            task.wait(0.1)
            
            bv:Destroy()
            bg:Destroy()
            State.bodyVelocity = nil
            State.bodyGyro = nil
            
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            
            if callback then callback() end
            return
        end
        
        local speed = math.min(QUEST_CONFIG.MOVE_SPEED, distance * 10)
        local velocity = direction.Unit * speed
        
        bv.Velocity = velocity
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
    end)
    
    return true
end

----------------------------------------------------------------
-- REMOTE FUNCTIONS
----------------------------------------------------------------
local function invokeDialogueStart(npcModel)
    local remote = ReplicatedStorage:WaitForChild("Shared")
        :WaitForChild("Packages"):WaitForChild("Knit")
        :WaitForChild("Services"):WaitForChild("ProximityService")
        :WaitForChild("RF"):WaitForChild("Dialogue")
    if remote then
        pcall(function() remote:InvokeServer(npcModel) end)
        print("📡 1. Started Dialogue")
    end
end

local function invokeRunCommand(commandName)
    local remote = ReplicatedStorage:WaitForChild("Shared")
        :WaitForChild("Packages"):WaitForChild("Knit")
        :WaitForChild("Services"):WaitForChild("DialogueService")
        :WaitForChild("RF"):WaitForChild("RunCommand")
    if remote then
        print("📡 2. Executing Command: " .. commandName)
        pcall(function() remote:InvokeServer(commandName) end)
    end
end

----------------------------------------------------------------
-- UI RESTORE
----------------------------------------------------------------
local function forceEndDialogueAndRestore()
    print("🔧 3. Forcing Cleanup & UI Restore...")
    
    -- A. Close Dialogue & Fix Camera
    local gui = player:FindFirstChild("PlayerGui")
    if gui then
        local dUI = gui:FindFirstChild("DialogueUI")
        if dUI then
            dUI.Enabled = false
            local bb = dUI:FindFirstChild("ResponseBillboard")
            if bb then bb.Visible = false end
        end
    end
    
    local cam = Workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        cam.FieldOfView = 70
    end
    
    -- B. Remove Status Tags
    local char = player.Character
    if char then
        local status = char:FindFirstChild("Status")
        if status then
            for _, tag in ipairs(status:GetChildren()) do
                if tag.Name == "DisableBackpack" or tag.Name == "NoMovement" or tag.Name == "Talking" then
                    pcall(function() tag:Destroy() end)
                    print("   - Removed Status Tag: " .. tag.Name)
                end
            end
        end
        
        -- Restore Humanoid
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
        end
    end
    
    -- C. Restore Main UI
    if gui then
        local main = gui:FindFirstChild("Main")
        if main then 
            main.Enabled = true 
            print("   - Main UI (Quest) Restored")
        end
        
        local backpack = gui:FindFirstChild("BackpackGui")
        if backpack then 
            backpack.Enabled = true 
            print("   - Backpack Restored")
        end
        
        local compass = gui:FindFirstChild("Compass")
        if compass then compass.Enabled = true end
        
        local mobile = gui:FindFirstChild("MobileButtons")
        if mobile then mobile.Enabled = true end
    end
    
    -- D. Tell Server Closed
    local dialogueEvent = ReplicatedStorage:WaitForChild("Shared")
        :WaitForChild("Packages"):WaitForChild("Knit")
        :WaitForChild("Services"):WaitForChild("DialogueService")
        :WaitForChild("RE"):WaitForChild("DialogueEvent")
    if dialogueEvent then
        pcall(function() dialogueEvent:FireServer("Closed") end)
    end
    
    print("✅ Restore Complete")
end

----------------------------------------------------------------
-- MAIN QUEST EXECUTION
----------------------------------------------------------------
local function doTalkToWizard()
    print("📋 Objective: Talk to Wizard...")
    
    local npcModel = getNpcModel(QUEST_CONFIG.NPC_NAME)
    if not npcModel then
        warn("   ❌ NPC not found: " .. QUEST_CONFIG.NPC_NAME)
        warn("   💡 Trying to use static position instead...")
    end
    
    local targetPos = QUEST_CONFIG.NPC_POSITION
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    
    if hrp then
        local currentDist = (targetPos - hrp.Position).Magnitude
        print(string.format("   🚶 Moving to %s at (%.1f, %.1f, %.1f) (%.1f studs away)...", 
            QUEST_CONFIG.NPC_NAME, targetPos.X, targetPos.Y, targetPos.Z, currentDist))
    end
    
    local moveComplete = false
    smoothMoveTo(targetPos, function()
        moveComplete = true
    end)
    
    local timeout = 60
    local startTime = tick()
    while not moveComplete and tick() - startTime < timeout do
        task.wait(0.1)
    end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    if not moveComplete then
        warn("   ⚠️ Failed to reach NPC, continuing anyway...")
    end
    
    -- Check NPC again
    if not npcModel then
        npcModel = getNpcModel(QUEST_CONFIG.NPC_NAME)
    end
    
    if not npcModel then
        warn("   ❌ Cannot find NPC model!")
        return false
    end
    
    print("\n📞 Starting Dialogue with Wizard...")
    task.wait(0.5)
    invokeDialogueStart(npcModel)
    
    print("⏳ Waiting for dialogue to open...")
    task.wait(1.5)
    
    print("✅ Selecting CheckQuest option...")
    invokeRunCommand("CheckQuest")
    
    print("⏳ Processing CheckQuest...")
    task.wait(0.8)
    
    print("✅ Sending FinishQuest command...")
    invokeRunCommand("FinishQuest")
    
    print("⏳ Processing FinishQuest...")
    task.wait(0.5)
    
    forceEndDialogueAndRestore()
    
    print("   ✅ Quest dialogue complete!")
    return true
end

----------------------------------------------------------------
-- SMART QUEST RUNNER
----------------------------------------------------------------
print(string.rep("=", 50))
print("🚀 QUEST 12: " .. QUEST_CONFIG.QUEST_NAME)
print("🎯 Objective: Talk to Wizard")
print("✅ Strategy: Auto CheckQuest + FinishQuest")
print(string.rep("=", 50))

local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)

if not questID then
    warn("❌ Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not found!")
    Quest12Active = false
    cleanupState()
    disableNoclip()
    return
end

print("✅ Quest found (ID: " .. questID .. ")")

print("\n" .. string.rep("=", 50))
print("⚙️  Quest Objectives:")
local objectiveCount = 0
for _, item in ipairs(objList:GetChildren()) do
    if item:IsA("Frame") and tonumber(item.Name) then
        objectiveCount = objectiveCount + 1
        local text = getObjectiveText(item)
        local complete = isObjectiveComplete(item)
        print(string.format("   %d. %s [%s]", objectiveCount, text, complete and "✅" or "⏳"))
    end
end
print(string.rep("=", 50))

if areAllObjectivesComplete() then
    print("\n✅ Quest already complete!")
    cleanupState()
    disableNoclip()
    return
end

local maxAttempts = 3
local attempt = 0

while isQuest12StillActive() and not areAllObjectivesComplete() and attempt < maxAttempts do
    attempt = attempt + 1
    print(string.format("\n🔄 Attempt #%d", attempt))
    
    local success = doTalkToWizard()
    
    if success then
        print("   ✅ Dialogue sequence complete!")
        task.wait(2)
        
        if areAllObjectivesComplete() then
            print("\n🎉 All objectives complete!")
            break
        else
            print("   ⚠️ Quest not marked complete, retrying...")
            task.wait(2)
        end
    else
        warn("   ❌ Dialogue failed, retrying in 3s...")
        task.wait(3)
    end
end

task.wait(1)

if areAllObjectivesComplete() then
    print("\n" .. string.rep("=", 50))
    print("✅ Quest 12 Complete!")
    print("🎉 Everything Starts Now!")
    print(string.rep("=", 50))
else
    warn("\n" .. string.rep("=", 50))
    warn("⚠️ Quest 12 incomplete after " .. attempt .. " attempts")
    warn(string.rep("=", 50))
end

Quest12Active = false
cleanupState()
disableNoclip()

end

-- Quest 13
_G.QuestFunctions[13] = function()
local Shared = _G.Shared

-- QUEST 13: Bard Quest (Level-based Auto Quest)
-- ✅ Check Level from PlayerGui.Main.Screen.Hud.Level
-- ✅ If Level < 10 → Move to Bard NPC
-- ✅ Open Dialogue → CheckQuest → GiveBardQuest
-- ✅ Auto accept quest and complete it

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest13Active = true
local DEBUG_MODE = true

local QUEST_CONFIG = {
    QUEST_NAME = "Bard Quest",  -- Quest Name (if not found, check Level)
    NPC_NAME = "Bard",
    NPC_POSITION = Vector3.new(-130.9, 27.8, 109.8),
    MIN_LEVEL = 10,  -- Minimum level required (actually max level for this quest?)
    MOVE_SPEED = 25,  
    NPC_STOP_DISTANCE = 5,
}

----------------------------------------------------------------
-- KNIT SETUP
----------------------------------------------------------------
local KnitPackage = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitPackage)

if not Knit.OnStart then 
    pcall(function() Knit.Start():await() end)
end

local PlayerController = nil
local ProximityService = nil
local DialogueService = nil

pcall(function()
    PlayerController = Knit.GetController("PlayerController")
    ProximityService = Knit.GetService("ProximityService")
    DialogueService = Knit.GetService("DialogueService")
end)

local SERVICES = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")

local DIALOGUE_RF = nil
pcall(function()
    DIALOGUE_RF = SERVICES:WaitForChild("ProximityService", 5):WaitForChild("RF", 3):WaitForChild("Dialogue", 3)
end)

local DIALOGUE_COMMAND_RF = nil
pcall(function()
    DIALOGUE_COMMAND_RF = SERVICES:WaitForChild("DialogueService", 5):WaitForChild("RF", 3):WaitForChild("RunCommand", 3)
end)

if PlayerController then print("✅ PlayerController Ready!") else warn("⚠️ PlayerController not found") end
if ProximityService then print("✅ ProximityService Ready!") else warn("⚠️ ProximityService not found") end
if DialogueService then print("✅ DialogueService Ready!") else warn("⚠️ DialogueService not found") end
if DIALOGUE_RF then print("✅ Dialogue Remote Ready!") else warn("⚠️ Dialogue Remote not found") end
if DIALOGUE_COMMAND_RF then print("✅ DialogueCommand Remote Ready!") else warn("⚠️ DialogueCommand Remote not found") end

----------------------------------------------------------------
-- STATE MANAGEMENT
----------------------------------------------------------------
local State = {
    noclipConn = nil,
    moveConn = nil,
    bodyVelocity = nil,
    bodyGyro = nil,
}

local function cleanupState()
    if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
end

----------------------------------------------------------------
-- LEVEL SYSTEM
----------------------------------------------------------------
local function getPlayerLevel()
    print("   🔍 Checking player level...")
    
    -- Path: PlayerGui.Main.Screen.Hud.Level
    local levelLabel = playerGui:FindFirstChild("Main")
                      and playerGui.Main:FindFirstChild("Screen")
                      and playerGui.Main.Screen:FindFirstChild("Hud")
                      and playerGui.Main.Screen.Hud:FindFirstChild("Level")
    
    if not levelLabel then
        warn("   ❌ Level Label not found!")
        warn("   💡 Path: PlayerGui.Main.Screen.Hud.Level")
        return nil
    end
    
    if not levelLabel:IsA("TextLabel") then
        warn("   ❌ Level is not a TextLabel!")
        return nil
    end
    
    local levelText = levelLabel.Text
    print(string.format("   📊 Level Text: '%s'", levelText))
    
    -- Extract Level from text (e.g., "Level 7" → 7)
    local level = tonumber(string.match(levelText, "%d+"))
    
    if level then
        print(string.format("   ✅ Player Level: %d", level))
        return level
    else
        warn("   ❌ Failed to parse level from text!")
        return nil
    end
end

local function shouldDoQuest()
    local level = getPlayerLevel()
    
    if not level then
        warn("   ❌ Cannot determine player level!")
        return false
    end
    
    if level < QUEST_CONFIG.MIN_LEVEL then
        print(string.format("   ✅ Level %d < %d - Quest available!", level, QUEST_CONFIG.MIN_LEVEL))
        return true
    else
        print(string.format("   ⏸️  Level %d >= %d - Quest not available", level, QUEST_CONFIG.MIN_LEVEL))
        return false
    end
end

----------------------------------------------------------------
-- QUEST SYSTEM (Fallback - if quest name exists)
----------------------------------------------------------------
local function getQuestObjectives(questName)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil, nil end
    
    local list = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Screen") 
                 and gui.Main.Screen:FindFirstChild("Quests") and gui.Main.Screen.Quests:FindFirstChild("List")
    if not list then return nil, nil end
    
    local questID = nil
    for _, child in ipairs(list:GetChildren()) do
        local id = string.match(child.Name, "^Introduction(%d+)Title$")
        if id and child:FindFirstChild("Frame") and child.Frame:FindFirstChild("TextLabel") then
            if child.Frame.TextLabel.Text == questName then
                questID = id
                break
            end
        end
    end
    
    if not questID then return nil, nil end
    
    local objList = list:FindFirstChild("Introduction" .. questID .. "List")
    return questID, objList
end

local function isObjectiveComplete(item)
    if not item then return false end
    local check = item:FindFirstChild("Main") and item.Main:FindFirstChild("Frame") and item.Main.Frame:FindFirstChild("Check")
    return check and check.Visible
end

local function getObjectiveText(item)
    local lbl = item:FindFirstChild("Main") and item.Main:FindFirstChild("TextLabel")
    return lbl and lbl.Text or ""
end

local function areAllObjectivesComplete()
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)
    if not questID or not objList then return false end
    
    for _, item in ipairs(objList:GetChildren()) do
        if item:IsA("Frame") and tonumber(item.Name) then
            if not isObjectiveComplete(item) then
                return false
            end
        end
    end
    
    return true
end

----------------------------------------------------------------
-- NOCLIP & MOVEMENT
----------------------------------------------------------------
local function enableNoclip()
    if State.noclipConn then return end
    
    local char = player.Character
    if not char then return end
    
    State.noclipConn = RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
            return
        end
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
end

local function smoothMoveTo(targetPos, callback)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    enableNoclip()
    
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = hrp
    State.bodyVelocity = bv
    
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.D = 500
    bg.Parent = hrp
    State.bodyGyro = bg
    
    print(string.format("   🚀 Moving to (%.1f, %.1f, %.1f)...", targetPos.X, targetPos.Y, targetPos.Z))
    
    State.moveConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv then bv:Destroy() end
            if bg then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end
        
        local currentPos = hrp.Position
        local direction = (targetPos - currentPos)
        local distance = direction.Magnitude
        
        if distance < QUEST_CONFIG.NPC_STOP_DISTANCE then
            print("   ✅ Reached target!")
            
            bv.Velocity = Vector3.zero
            task.wait(0.1)
            
            bv:Destroy()
            bg:Destroy()
            State.bodyVelocity = nil
            State.bodyGyro = nil
            
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            
            if callback then callback() end
            return
        end
        
        local speed = math.min(QUEST_CONFIG.MOVE_SPEED, distance * 10)
        local velocity = direction.Unit * speed
        
        bv.Velocity = velocity
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
    end)
    
    return true
end

----------------------------------------------------------------
-- NPC INTERACTION
----------------------------------------------------------------
local function getNpcModel(name)
    local prox = Workspace:FindFirstChild("Proximity")
    return prox and prox:FindFirstChild(name)
end

local function openDialogue(npcModel)
    if not DIALOGUE_RF then
        warn("   ❌ Dialogue Remote not available!")
        return false
    end
    
    print("   📞 Opening Dialogue with " .. QUEST_CONFIG.NPC_NAME .. "...")
    
    local success = pcall(function()
        DIALOGUE_RF:InvokeServer(npcModel)
    end)
    
    if success then
        print("   ✅ Dialogue opened!")
        return true
    else
        warn("   ❌ Failed to open dialogue")
        return false
    end
end

local function runDialogueCommand(command)
    if not DIALOGUE_COMMAND_RF then
        warn("   ❌ DialogueCommand Remote not available!")
        return false
    end
    
    print(string.format("   💬 Running command: '%s'", command))
    
    local success, result = pcall(function()
        return DIALOGUE_COMMAND_RF:InvokeServer(command)
    end)
    
    if success then
        print(string.format("   ✅ Command '%s' executed successfully!", command))
        if DEBUG_MODE and result then
            print(string.format("   📊 Result: %s", tostring(result)))
        end
        return true
    else
        warn(string.format("   ❌ Failed to execute command '%s': %s", command, tostring(result)))
        return false
    end
end

----------------------------------------------------------------
-- UI RESTORE
----------------------------------------------------------------
local function forceRestoreUI()
    print("🔧 Forcing UI Restore...")
    
    local gui = player:FindFirstChild("PlayerGui")
    if gui then
        local dUI = gui:FindFirstChild("DialogueUI")
        if dUI then
            dUI.Enabled = false
            local bb = dUI:FindFirstChild("ResponseBillboard")
            if bb then bb.Visible = false end
        end
    end
    
    local cam = Workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        cam.FieldOfView = 70
    end
    
    local char = player.Character
    if char then
        local status = char:FindFirstChild("Status")
        if status then
            for _, tag in ipairs(status:GetChildren()) do
                if tag.Name == "DisableBackpack" or tag.Name == "NoMovement" or tag.Name == "Talking" then
                    pcall(function() tag:Destroy() end)
                    print("   - Removed Status Tag: " .. tag.Name)
                end
            end
        end
        
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
        end
    end
    
    if gui then
        local main = gui:FindFirstChild("Main")
        if main then 
            main.Enabled = true 
            print("   - Main UI Restored")
        end
        
        local backpack = gui:FindFirstChild("BackpackGui")
        if backpack then 
            backpack.Enabled = true 
            print("   - Backpack Restored")
        end
    end
    
    print("✅ UI Restore Complete")
end

----------------------------------------------------------------
-- MAIN QUEST EXECUTION
----------------------------------------------------------------
local function doAcceptQuest()
    print("📜 Objective: Accept Bard Quest...")
    
    -- 1. Check Level
    print("\n🔍 Checking if quest is available...")
    if not shouldDoQuest() then
        warn("   ❌ Quest not available (Level too high)")
        return false
    end
    
    -- 2. Find NPC
    local npcModel = getNpcModel(QUEST_CONFIG.NPC_NAME)
    if not npcModel then
        warn("   ❌ NPC not found: " .. QUEST_CONFIG.NPC_NAME)
        return false
    end
    
    -- 3. Move to NPC
    local npcPos = QUEST_CONFIG.NPC_POSITION
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    
    if hrp then
        local currentDist = (npcPos - hrp.Position).Magnitude
        print(string.format("   🚶 Moving to %s at (%.1f, %.1f, %.1f) (%.1f studs away)...", 
            QUEST_CONFIG.NPC_NAME, npcPos.X, npcPos.Y, npcPos.Z, currentDist))
    end
    
    local moveComplete = false
    smoothMoveTo(npcPos, function()
        moveComplete = true
    end)
    
    local timeout = 60
    local startTime = tick()
    while not moveComplete and tick() - startTime < timeout do
        task.wait(0.1)
    end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    if not moveComplete then
        warn("   ⚠️ Failed to reach NPC")
        return false
    end
    
    print("   ✅ Reached NPC!")
    task.wait(1)
    
    -- 4. Open Dialogue
    print("\n📞 Opening Dialogue...")
    local dialogueOpened = openDialogue(npcModel)
    
    if not dialogueOpened then
        warn("   ❌ Failed to open dialogue")
        return false
    end
    
    task.wait(1.5)
    
    -- 5. Check Quest (CheckQuest)
    print("\n🔍 Checking quest availability...")
    local checkSuccess = runDialogueCommand("CheckQuest")
    
    if not checkSuccess then
        warn("   ❌ Failed to check quest")
        return false
    end
    
    task.wait(1)
    
    -- 6. Accept Quest (GiveBardQuest)
    print("\n✅ Accepting quest...")
    local giveSuccess = runDialogueCommand("GiveBardQuest")
    
    if not giveSuccess then
        warn("   ❌ Failed to accept quest")
        return false
    end
    
    print("   ✅ Quest accepted!")
    
    -- 7. Restore UI
    task.wait(1)
    forceRestoreUI()
    
    return true
end

----------------------------------------------------------------
-- SMART QUEST RUNNER
----------------------------------------------------------------
print(string.rep("=", 50))
print("🚀 QUEST 13: " .. QUEST_CONFIG.QUEST_NAME)
print("🎯 Objective: Accept Bard Quest (Level-based)")
print(string.format("✅ Strategy: Check Level → Move to NPC → Accept Quest"))
print(string.rep("=", 50))

-- Check Level First
print("\n🔍 Pre-check: Verifying level requirement...")
if not shouldDoQuest() then
    print("\n✅ Quest not available (Level too high)")
    print(string.rep("=", 50))
    cleanupState()
    disableNoclip()
    return
end

local maxAttempts = 3
local attempt = 0

while Quest13Active and attempt < maxAttempts do
    attempt = attempt + 1
    print(string.format("\n🔄 Attempt #%d", attempt))
    
    local success = doAcceptQuest()
    
    if success then
        print("   ✅ Quest accepted successfully!")
        task.wait(2)
        
        -- Check if quest is in UI
        local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_NAME)
        if questID then
            print("\n🎉 Quest found in Quest Log!")
            
            print("\n" .. string.rep("=", 50))
            print("⚙️  Quest Objectives:")
            local objectiveCount = 0
            for _, item in ipairs(objList:GetChildren()) do
                if item:IsA("Frame") and tonumber(item.Name) then
                    objectiveCount = objectiveCount + 1
                    local text = getObjectiveText(item)
                    local complete = isObjectiveComplete(item)
                    print(string.format("   %d. %s [%s]", objectiveCount, text, complete and "✅" or "⏳"))
                end
            end
            print(string.rep("=", 50))
            
            break
        else
            print("   ⚠️ Quest not found in Quest Log, but accepted")
            break
        end
    else
        warn("   ❌ Failed to accept quest, retrying in 3s...")
        task.wait(3)
    end
end

task.wait(1)

print("\n" .. string.rep("=", 50))
print("✅ Quest 13 Complete!")
print(string.rep("=", 50))

Quest13Active = false
cleanupState()
disableNoclip()

end

-- Quest 14
_G.QuestFunctions[14] = function()
local Shared = _G.Shared

-- QUEST 14: "Lost Guitar" (FIXED - Change Quest Viewing)
-- ✅ Move to Guitar (-46.2, -26.6, -63.4)
-- ✅ Collect Guitar via Functionals Remote
-- ✅ Move back to Bard NPC (-130.9, 27.8, 109.8)
-- ✅ Talk to NPC → CheckQuest → FinishQuest
-- ✅ Auto Complete Quest

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest14Active = true
local DEBUG_MODE = true

local QUEST_CONFIG = {
    QUEST_NAME = "Lost Guitar!",
    QUEST_ID = "BardQuest",  -- Use instead of Introduction{N}
    
    -- Guitar Location
    GUITAR_OBJECT_NAME = "BardGuitar",
    GUITAR_POSITION = Vector3.new(-46.2, -26.6, -63.4),
    
    -- Bard NPC
    NPC_NAME = "Bard",
    NPC_POSITION = Vector3.new(-130.9, 27.8, 109.8),
    
    MOVE_SPEED = 25,  
    STOP_DISTANCE = 5,
}

----------------------------------------------------------------
-- KNIT SETUP
----------------------------------------------------------------
local KnitPackage = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitPackage)

if not Knit.OnStart then 
    pcall(function() Knit.Start():await() end)
end

local PlayerController = nil
local ProximityService = nil
local DialogueService = nil

pcall(function()
    PlayerController = Knit.GetController("PlayerController")
    ProximityService = Knit.GetService("ProximityService")
    DialogueService = Knit.GetService("DialogueService")
end)

local SERVICES = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")

local DIALOGUE_RF = nil
pcall(function()
    DIALOGUE_RF = SERVICES:WaitForChild("ProximityService", 5):WaitForChild("RF", 3):WaitForChild("Dialogue", 3)
end)

local FUNCTIONALS_RF = nil
pcall(function()
    FUNCTIONALS_RF = SERVICES:WaitForChild("ProximityService", 5):WaitForChild("RF", 3):WaitForChild("Functionals", 3)
end)

local DIALOGUE_COMMAND_RF = nil
pcall(function()
    DIALOGUE_COMMAND_RF = SERVICES:WaitForChild("DialogueService", 5):WaitForChild("RF", 3):WaitForChild("RunCommand", 3)
end)

if PlayerController then print("✅ PlayerController Ready!") else warn("⚠️ PlayerController not found") end
if ProximityService then print("✅ ProximityService Ready!") else warn("⚠️ ProximityService not found") end
if DialogueService then print("✅ DialogueService Ready!") else warn("⚠️ DialogueService not found") end
if DIALOGUE_RF then print("✅ Dialogue Remote Ready!") else warn("⚠️ Dialogue Remote not found") end
if FUNCTIONALS_RF then print("✅ Functionals Remote Ready!") else warn("⚠️ Functionals Remote not found") end
if DIALOGUE_COMMAND_RF then print("✅ DialogueCommand Remote Ready!") else warn("⚠️ DialogueCommand Remote not found") end

----------------------------------------------------------------
-- STATE MANAGEMENT
----------------------------------------------------------------
local State = {
    noclipConn = nil,
    moveConn = nil,
    bodyVelocity = nil,
    bodyGyro = nil,
}

local function cleanupState()
    if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
end

----------------------------------------------------------------
-- QUEST SYSTEM (FIXED - No Introduction{N})
----------------------------------------------------------------
local function getQuestObjectives(questID)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil, nil end
    
    local list = gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Screen") 
                 and gui.Main.Screen:FindFirstChild("Quests") and gui.Main.Screen.Quests:FindFirstChild("List")
    if not list then return nil, nil end
    
    -- Find Title (e.g. "BardQuestTitle")
    local titleFrame = list:FindFirstChild(questID .. "Title")
    if not titleFrame then
        if DEBUG_MODE then
            warn(string.format("   ❌ Quest Title not found: %sTitle", questID))
        end
        return nil, nil
    end
    
    -- Check if Title matches Quest Name
    if titleFrame:FindFirstChild("Frame") and titleFrame.Frame:FindFirstChild("TextLabel") then
        local questName = titleFrame.Frame.TextLabel.Text
        if DEBUG_MODE then
            print(string.format("   ✅ Found Quest: %s", questName))
        end
    end
    
    -- Find List (e.g. "BardQuestList")
    local objList = list:FindFirstChild(questID .. "List")
    if not objList then
        if DEBUG_MODE then
            warn(string.format("   ❌ Quest List not found: %sList", questID))
        end
        return nil, nil
    end
    
    return questID, objList
end

local function isObjectiveComplete(item)
    if not item then return false end
    local check = item:FindFirstChild("Main") and item.Main:FindFirstChild("Frame") and item.Main.Frame:FindFirstChild("Check")
    return check and check.Visible
end

local function getObjectiveText(item)
    local lbl = item:FindFirstChild("Main") and item.Main:FindFirstChild("TextLabel")
    return lbl and lbl.Text or ""
end

local function isQuest14StillActive()
    if not Quest14Active then return false end
    
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_ID)
    if not questID or not objList then
        print("🛑 Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not found!")
        Quest14Active = false
        return false
    end
    
    return true
end

local function areAllObjectivesComplete()
    local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_ID)
    if not questID or not objList then return true end
    
    for _, item in ipairs(objList:GetChildren()) do
        if item:IsA("Frame") and tonumber(item.Name) then
            if not isObjectiveComplete(item) then
                return false
            end
        end
    end
    
    return true
end

----------------------------------------------------------------
-- NOCLIP & MOVEMENT
----------------------------------------------------------------
local function enableNoclip()
    if State.noclipConn then return end
    
    local char = player.Character
    if not char then return end
    
    State.noclipConn = RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
            return
        end
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
end

local function smoothMoveTo(targetPos, callback)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    enableNoclip()
    
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = hrp
    State.bodyVelocity = bv
    
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.D = 500
    bg.Parent = hrp
    State.bodyGyro = bg
    
    print(string.format("   🚀 Moving to (%.1f, %.1f, %.1f)...", targetPos.X, targetPos.Y, targetPos.Z))
    
    State.moveConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv then bv:Destroy() end
            if bg then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end
        
        local currentPos = hrp.Position
        local direction = (targetPos - currentPos)
        local distance = direction.Magnitude
        
        if distance < QUEST_CONFIG.STOP_DISTANCE then
            print("   ✅ Reached target!")
            
            bv.Velocity = Vector3.zero
            task.wait(0.1)
            
            bv:Destroy()
            bg:Destroy()
            State.bodyVelocity = nil
            State.bodyGyro = nil
            
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            
            if callback then callback() end
            return
        end
        
        local speed = math.min(QUEST_CONFIG.MOVE_SPEED, distance * 10)
        local velocity = direction.Unit * speed
        
        bv.Velocity = velocity
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
    end)
    
    return true
end

----------------------------------------------------------------
-- OBJECT HELPERS
----------------------------------------------------------------
local function getProximityObject(name)
    local prox = Workspace:FindFirstChild("Proximity")
    return prox and prox:FindFirstChild(name)
end

----------------------------------------------------------------
-- GUITAR PICKUP
----------------------------------------------------------------
local function pickupGuitar()
    if not FUNCTIONALS_RF then
        warn("   ❌ Functionals Remote not available!")
        return false
    end
    
    local guitarObject = getProximityObject(QUEST_CONFIG.GUITAR_OBJECT_NAME)
    if not guitarObject then
        warn("   ❌ Guitar object not found: " .. QUEST_CONFIG.GUITAR_OBJECT_NAME)
        return false
    end
    
    print("   🎸 Picking up guitar...")
    
    local success, result = pcall(function()
        return FUNCTIONALS_RF:InvokeServer(guitarObject)
    end)
    
    if success then
        print("   ✅ Guitar picked up!")
        return true
    else
        warn("   ❌ Failed to pickup guitar: " .. tostring(result))
        return false
    end
end

----------------------------------------------------------------
-- NPC INTERACTION
----------------------------------------------------------------
local function openDialogue(npcModel)
    if not DIALOGUE_RF then
        warn("   ❌ Dialogue Remote not available!")
        return false
    end
    
    print("   📞 Opening Dialogue with " .. QUEST_CONFIG.NPC_NAME .. "...")
    
    local success = pcall(function()
        DIALOGUE_RF:InvokeServer(npcModel)
    end)
    
    if success then
        print("   ✅ Dialogue opened!")
        return true
    else
        warn("   ❌ Failed to open dialogue")
        return false
    end
end

local function runDialogueCommand(command)
    if not DIALOGUE_COMMAND_RF then
        warn("   ❌ DialogueCommand Remote not available!")
        return false
    end
    
    print(string.format("   💬 Running command: '%s'", command))
    
    local success, result = pcall(function()
        return DIALOGUE_COMMAND_RF:InvokeServer(command)
    end)
    
    if success then
        print(string.format("   ✅ Command '%s' executed successfully!", command))
        if DEBUG_MODE and result then
            print(string.format("   📊 Result: %s", tostring(result)))
        end
        return true
    else
        warn(string.format("   ❌ Failed to execute command '%s': %s", command, tostring(result)))
        return false
    end
end

----------------------------------------------------------------
-- UI RESTORE
----------------------------------------------------------------
local function forceRestoreUI()
    print("🔧 Forcing UI Restore...")
    
    local gui = player:FindFirstChild("PlayerGui")
    if gui then
        local dUI = gui:FindFirstChild("DialogueUI")
        if dUI then
            dUI.Enabled = false
            local bb = dUI:FindFirstChild("ResponseBillboard")
            if bb then bb.Visible = false end
        end
    end
    
    local cam = Workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        cam.FieldOfView = 70
    end
    
    local char = player.Character
    if char then
        local status = char:FindFirstChild("Status")
        if status then
            for _, tag in ipairs(status:GetChildren()) do
                if tag.Name == "DisableBackpack" or tag.Name == "NoMovement" or tag.Name == "Talking" then
                    pcall(function() tag:Destroy() end)
                    print("   - Removed Status Tag: " .. tag.Name)
                end
            end
        end
        
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
        end
    end
    
    if gui then
        local main = gui:FindFirstChild("Main")
        if main then 
            main.Enabled = true 
            print("   - Main UI Restored")
        end
        
        local backpack = gui:FindFirstChild("BackpackGui")
        if backpack then 
            backpack.Enabled = true 
            print("   - Backpack Restored")
        end
    end
    
    print("✅ UI Restore Complete")
end

----------------------------------------------------------------
-- MAIN QUEST EXECUTION
----------------------------------------------------------------
local function doCollectGuitar()
    print("🎸 Step 1: Collecting Guitar...")
    
    -- 1. Move to Guitar
    local guitarPos = QUEST_CONFIG.GUITAR_POSITION
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    
    if hrp then
        local currentDist = (guitarPos - hrp.Position).Magnitude
        print(string.format("   🚶 Moving to Guitar at (%.1f, %.1f, %.1f) (%.1f studs away)...", 
            guitarPos.X, guitarPos.Y, guitarPos.Z, currentDist))
    end
    
    local moveComplete = false
    smoothMoveTo(guitarPos, function()
        moveComplete = true
    end)
    
    local timeout = 60
    local startTime = tick()
    while not moveComplete and tick() - startTime < timeout do
        task.wait(0.1)
    end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    if not moveComplete then
        warn("   ⚠️ Failed to reach Guitar")
        return false
    end
    
    print("   ✅ Reached Guitar!")
    task.wait(1)
    
    -- 2. Pickup Guitar
    local pickupSuccess = pickupGuitar()
    
    if not pickupSuccess then
        warn("   ❌ Failed to pickup guitar")
        return false
    end
    
    task.wait(1)
    return true
end

local function doReturnGuitar()
    print("\n🎸 Step 2: Returning Guitar to Bard...")
    
    -- 1. Move to Bard NPC
    local npcPos = QUEST_CONFIG.NPC_POSITION
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    
    if hrp then
        local currentDist = (npcPos - hrp.Position).Magnitude
        print(string.format("   🚶 Moving to %s at (%.1f, %.1f, %.1f) (%.1f studs away)...", 
            QUEST_CONFIG.NPC_NAME, npcPos.X, npcPos.Y, npcPos.Z, currentDist))
    end
    
    local moveComplete = false
    smoothMoveTo(npcPos, function()
        moveComplete = true
    end)
    
    local timeout = 60
    local startTime = tick()
    while not moveComplete and tick() - startTime < timeout do
        task.wait(0.1)
    end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    if not moveComplete then
        warn("   ⚠️ Failed to reach NPC")
        return false
    end
    
    print("   ✅ Reached NPC!")
    task.wait(1)
    
    -- 2. Find NPC Model
    local npcModel = getProximityObject(QUEST_CONFIG.NPC_NAME)
    if not npcModel then
        warn("   ❌ NPC not found: " .. QUEST_CONFIG.NPC_NAME)
        return false
    end
    
    -- 3. Open Dialogue
    print("\n📞 Opening Dialogue...")
    local dialogueOpened = openDialogue(npcModel)
    
    if not dialogueOpened then
        warn("   ❌ Failed to open dialogue")
        return false
    end
    
    task.wait(1.5)
    
    -- 4. CheckQuest
    print("\n🔍 Checking quest status...")
    local checkSuccess = runDialogueCommand("CheckQuest")
    
    if not checkSuccess then
        warn("   ❌ Failed to check quest")
        return false
    end
    
    task.wait(1)
    
    -- 5. FinishQuest (Return Guitar)
    print("\n✅ Returning guitar to Bard...")
    local finishSuccess = runDialogueCommand("FinishQuest")
    
    if not finishSuccess then
        warn("   ❌ Failed to finish quest")
        return false
    end
    
    print("   ✅ Quest completed!")
    
    -- 6. Restore UI
    task.wait(1)
    forceRestoreUI()
    
    return true
end

----------------------------------------------------------------
-- SMART QUEST RUNNER
----------------------------------------------------------------
print(string.rep("=", 50))
print("🚀 QUEST 14: " .. QUEST_CONFIG.QUEST_NAME)
print("🎯 Objective: Find and Return Guitar to Bard")
print("✅ Strategy: Collect Guitar → Return to NPC → Finish Quest")
print(string.rep("=", 50))

local questID, objList = getQuestObjectives(QUEST_CONFIG.QUEST_ID)

if not questID then
    warn("❌ Quest '" .. QUEST_CONFIG.QUEST_NAME .. "' not found!")
    warn(string.format("   💡 Looking for: %sTitle", QUEST_CONFIG.QUEST_ID))
    Quest14Active = false
    cleanupState()
    disableNoclip()
    return
end

print("✅ Quest found (ID: " .. questID .. ")")

print("\n" .. string.rep("=", 50))
print("⚙️  Quest Objectives:")
local objectiveCount = 0
for _, item in ipairs(objList:GetChildren()) do
    if item:IsA("Frame") and tonumber(item.Name) then
        objectiveCount = objectiveCount + 1
        local text = getObjectiveText(item)
        local complete = isObjectiveComplete(item)
        print(string.format("   %d. %s [%s]", objectiveCount, text, complete and "✅" or "⏳"))
    end
end
print(string.rep("=", 50))

if areAllObjectivesComplete() then
    print("\n✅ Quest already complete!")
    cleanupState()
    disableNoclip()
    return
end

local maxAttempts = 3
local attempt = 0

while isQuest14StillActive() and not areAllObjectivesComplete() and attempt < maxAttempts do
    attempt = attempt + 1
    print(string.format("\n🔄 Attempt #%d", attempt))
    
    -- Step 1: Collect Guitar
    local collectSuccess = doCollectGuitar()
    
    if not collectSuccess then
        warn("   ❌ Failed to collect guitar, retrying in 3s...")
        task.wait(3)
        continue
    end
    
    -- Step 2: Return Guitar
    local returnSuccess = doReturnGuitar()
    
    if returnSuccess then
        print("   ✅ Quest completed successfully!")
        task.wait(2)
        
        if areAllObjectivesComplete() then
            print("\n🎉 All objectives complete!")
            break
        else
            print("   ⚠️ Quest not marked complete, retrying...")
            task.wait(2)
        end
    else
        warn("   ❌ Failed to return guitar, retrying in 3s...")
        task.wait(3)
    end
end

task.wait(1)

if areAllObjectivesComplete() then
    print("\n" .. string.rep("=", 50))
    print("✅ Quest 14 Complete!")
    print(string.rep("=", 50))
else
    warn("\n" .. string.rep("=", 50))
    warn("⚠️ Quest 14 incomplete after " .. attempt .. " attempts")
    warn(string.rep("=", 50))
end

Quest14Active = false
cleanupState()
disableNoclip()

end

-- Quest 15
_G.QuestFunctions[15] = function()
local Shared = _G.Shared
-- Silent load (no console spam)

-- QUEST 15: Auto Claim Index (Codex System)
-- ✅ Scans UI for claimable items (Matches TestClaim.lua logic)
-- ✅ Claims Ores, Enemies, Equipments
-- ✅ Only claims items that have Claim button

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest15Active = true
local DEBUG_MODE = false -- Set to true for verbose output

local QUEST_CONFIG = {
    QUEST_NAME = "Auto Claim Index",
    CLAIM_DELAY = 0.3,
}

----------------------------------------------------------------
-- KNIT SETUP
----------------------------------------------------------------
local SERVICES = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")

local CLAIM_ORE_RF = nil
pcall(function()
    CLAIM_ORE_RF = SERVICES:WaitForChild("CodexService", 5):WaitForChild("RF", 3):WaitForChild("ClaimOre", 3)
end)

local CLAIM_ENEMY_RF = nil
pcall(function()
    CLAIM_ENEMY_RF = SERVICES:WaitForChild("CodexService", 5):WaitForChild("RF", 3):WaitForChild("ClaimEnemy", 3)
end)

local CLAIM_EQUIPMENT_RF = nil
pcall(function()
    CLAIM_EQUIPMENT_RF = SERVICES:WaitForChild("CodexService", 5):WaitForChild("RF", 3):WaitForChild("ClaimEquipment", 3)
end)

if DEBUG_MODE then
    print("📡 ClaimOre: " .. (CLAIM_ORE_RF and "✅" or "❌"))
    print("📡 ClaimEnemy: " .. (CLAIM_ENEMY_RF and "✅" or "❌"))
    print("📡 ClaimEquipment: " .. (CLAIM_EQUIPMENT_RF and "✅" or "❌"))
end

----------------------------------------------------------------
-- GET INDEX UI
----------------------------------------------------------------
local function getIndexUI()
    local indexUI = playerGui:FindFirstChild("Menu")
                   and playerGui.Menu:FindFirstChild("Frame")
                   and playerGui.Menu.Frame:FindFirstChild("Frame")
                   and playerGui.Menu.Frame.Frame:FindFirstChild("Menus")
                   and playerGui.Menu.Frame.Frame.Menus:FindFirstChild("Index")
    
    if indexUI then
        return indexUI
    else
        -- Fallback check (from TestClaim.lua)
        if DEBUG_MODE then
            print("   ❌ Index UI NOT FOUND! Checking path...")
            local menu = playerGui:FindFirstChild("Menu")
            print("   - Menu: " .. (menu and "✅" or "❌"))
            if menu then
                local frame1 = menu:FindFirstChild("Frame")
                print("   - Menu.Frame: " .. (frame1 and "✅" or "❌"))
                if frame1 then
                    local frame2 = frame1:FindFirstChild("Frame")
                    print("   - Menu.Frame.Frame: " .. (frame2 and "✅" or "❌"))
                    if frame2 then
                        local menus = frame2:FindFirstChild("Menus")
                        print("   - Menu.Frame.Frame.Menus: " .. (menus and "✅" or "❌"))
                        if menus then
                            local index = menus:FindFirstChild("Index")
                            print("   - Menu.Frame.Frame.Menus.Index: " .. (index and "✅" or "❌"))
                        end
                    end
                end
            end
        end
        return nil
    end
end

----------------------------------------------------------------
-- CLAIM FUNCTIONS
----------------------------------------------------------------
local function claimOre(oreName)
    if not CLAIM_ORE_RF then return false end
    
    local success, result = pcall(function()
        return CLAIM_ORE_RF:InvokeServer(oreName)
    end)
    
    if success then
        print(string.format("   🪨 Claimed: %s | Result: %s", oreName, tostring(result)))
        return true
    else
        warn(string.format("   ❌ Failed to claim %s: %s", oreName, tostring(result)))
    end
    return false
end

local function claimEnemy(enemyName)
    if not CLAIM_ENEMY_RF then return false end
    
    local success, result = pcall(function()
        return CLAIM_ENEMY_RF:InvokeServer(enemyName)
    end)
    
    if success then
        print(string.format("   👹 Claimed: %s | Result: %s", enemyName, tostring(result)))
        return true
    else
        warn(string.format("   ❌ Failed to claim %s: %s", enemyName, tostring(result)))
    end
    return false
end

local function claimEquipment(equipmentName)
    if not CLAIM_EQUIPMENT_RF then return false end
    
    local success, result = pcall(function()
        return CLAIM_EQUIPMENT_RF:InvokeServer(equipmentName)
    end)
    
    if success then
        print(string.format("   ⚔️ Claimed: %s | Result: %s", equipmentName, tostring(result)))
        return true
    else
        warn(string.format("   ❌ Failed to claim %s: %s", equipmentName, tostring(result)))
    end
    return false
end

----------------------------------------------------------------
-- MAIN CLAIM FUNCTION (UI SCANNING)
----------------------------------------------------------------
local function claimAllIndex()
    local totalClaimed = 0
    
    local indexUI = getIndexUI()
    if not indexUI then
        if DEBUG_MODE then warn("❌ Index UI not found!") end
        return false
    end
    
    local pages = indexUI:FindFirstChild("Pages")
    if not pages then
        if DEBUG_MODE then warn("❌ Pages not found!") end
        return false
    end
    
    if DEBUG_MODE then
        print("\n📂 PAGES FOUND:")
        for _, page in ipairs(pages:GetChildren()) do
            print("   - " .. page.Name)
        end
    end
    
    -- 1. CLAIM ORES
    local oresPage = pages:FindFirstChild("Ores")
    if oresPage then
        if DEBUG_MODE then print("\n🪨 CHECKING ORES PAGE...") end
        local oreCount = 0
        for _, child in ipairs(oresPage:GetChildren()) do
            if string.find(child.Name, "List$") then
                for _, oreItem in ipairs(child:GetChildren()) do
                    if oreItem:IsA("Frame") or oreItem:IsA("GuiObject") then
                        oreCount = oreCount + 1
                        local main = oreItem:FindFirstChild("Main")
                        if main then
                            local claim = main:FindFirstChild("Claim")
                            if claim then
                                if DEBUG_MODE then print("      ✅ CLAIMABLE: " .. oreItem.Name) end
                                if claimOre(oreItem.Name) then
                                    totalClaimed = totalClaimed + 1
                                end
                                task.wait(QUEST_CONFIG.CLAIM_DELAY)
                            end
                        end
                    end
                end
            end
        end
        if DEBUG_MODE then print("   📊 Scanned " .. oreCount .. " ores.") end
    else
        if DEBUG_MODE then warn("   ❌ Ores Page NOT found") end
    end
    
    -- 2. CLAIM ENEMIES
    local enemiesPage = pages:FindFirstChild("Enemies")
    if enemiesPage then
        local scrollFrame = enemiesPage:FindFirstChild("ScrollingFrame")
        if scrollFrame then
            if DEBUG_MODE then print("\n👹 CHECKING ENEMIES PAGE...") end
            local enemyCount = 0
            for _, child in ipairs(scrollFrame:GetChildren()) do
                if string.find(child.Name, "List$") then
                    for _, enemyItem in ipairs(child:GetChildren()) do
                        if enemyItem:IsA("Frame") or enemyItem:IsA("GuiObject") then
                            enemyCount = enemyCount + 1
                            local main = enemyItem:FindFirstChild("Main")
                            if main then
                                local claim = main:FindFirstChild("Claim")
                                if claim then
                                    if DEBUG_MODE then print("      ✅ CLAIMABLE: " .. enemyItem.Name) end
                                    if claimEnemy(enemyItem.Name) then
                                        totalClaimed = totalClaimed + 1
                                    end
                                    task.wait(QUEST_CONFIG.CLAIM_DELAY)
                                end
                            end
                        end
                    end
                end
            end
            if DEBUG_MODE then print("   📊 Scanned " .. enemyCount .. " enemies.") end
        else
             if DEBUG_MODE then warn("   ❌ Enemies ScrollingFrame NOT found") end
        end
    else
        if DEBUG_MODE then warn("   ❌ Enemies Page NOT found") end
    end
    
    -- 3. CLAIM EQUIPMENTS
    local equipPage = pages:FindFirstChild("Equipments")
    if equipPage then
        local scrollFrame = equipPage:FindFirstChild("ScrollingFrame")
        if scrollFrame then
            if DEBUG_MODE then print("\n⚔️ CHECKING EQUIPMENTS PAGE...") end
            local equipCount = 0
            for _, child in ipairs(scrollFrame:GetChildren()) do
                if string.find(child.Name, "List$") then
                    for _, equipItem in ipairs(child:GetChildren()) do
                        if equipItem:IsA("Frame") or equipItem:IsA("GuiObject") then
                            equipCount = equipCount + 1
                            local main = equipItem:FindFirstChild("Main")
                            if main then
                                local claim = main:FindFirstChild("Claim")
                                if claim then
                                    if DEBUG_MODE then print("      ✅ CLAIMABLE: " .. equipItem.Name) end
                                    if claimEquipment(equipItem.Name) then
                                        totalClaimed = totalClaimed + 1
                                    end
                                    task.wait(QUEST_CONFIG.CLAIM_DELAY)
                                end
                            end
                        end
                    end
                end
            end
            if DEBUG_MODE then print("   📊 Scanned " .. equipCount .. " equipments.") end
        else
            if DEBUG_MODE then warn("   ❌ Equipments ScrollingFrame NOT found") end
        end
    else
        if DEBUG_MODE then warn("   ❌ Equipments Page NOT found") end
    end
    
    return totalClaimed > 0
end

----------------------------------------------------------------
-- EXECUTE
----------------------------------------------------------------
-- Execute silently (no console spam)
local success = claimAllIndex()
Quest15Active = false

end

-- Quest 16
_G.QuestFunctions[16] = function()
local Shared = _G.Shared

-- QUEST 16: Auto Buy Pickaxe (Gold-based)
-- ✅ Check Gold > 3340
-- ✅ Move to Shop (-32.6, -2.0, -269.3)
-- ✅ Buy "Stonewake's Pickaxe" x1
-- ✅ Auto Purchase

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest16Active = true
local DEBUG_MODE = true

local QUEST_CONFIG = {
    QUEST_NAME = "Auto Buy Pickaxe",
    MIN_GOLD = 3340,  -- Must have Gold >= 3340
    
    -- Shop Location
    SHOP_POSITION = Vector3.new(-32.6, -2.0, -269.3),
    
    -- Purchase Item
    ITEM_NAME = "Stonewake's Pickaxe",
    ITEM_QUANTITY = 1,
    
    MOVE_SPEED = 25,  
    STOP_DISTANCE = 5,
}

----------------------------------------------------------------
-- KNIT SETUP
----------------------------------------------------------------
local KnitPackage = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitPackage)

if not Knit.OnStart then 
    pcall(function() Knit.Start():await() end)
end

local PlayerController = nil
local ProximityService = nil

pcall(function()
    PlayerController = Knit.GetController("PlayerController")
    ProximityService = Knit.GetService("ProximityService")
end)

local SERVICES = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")

local PURCHASE_RF = nil
pcall(function()
    PURCHASE_RF = SERVICES:WaitForChild("ProximityService", 5):WaitForChild("RF", 3):WaitForChild("Purchase", 3)
end)

if PlayerController then print("✅ PlayerController Ready!") else warn("⚠️ PlayerController not found") end
if ProximityService then print("✅ ProximityService Ready!") else warn("⚠️ ProximityService not found") end
if PURCHASE_RF then print("✅ Purchase Remote Ready!") else warn("⚠️ Purchase Remote not found") end

----------------------------------------------------------------
-- STATE MANAGEMENT
----------------------------------------------------------------
local State = {
    noclipConn = nil,
    moveConn = nil,
    bodyVelocity = nil,
    bodyGyro = nil,
}

local function cleanupState()
    if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
end

----------------------------------------------------------------
-- LEVEL SYSTEM
----------------------------------------------------------------
local function getPlayerLevel()
    print("   🔍 Checking player level...")

    -- Path: PlayerGui.Main.Screen.Hud.Level
    local levelLabel = playerGui:FindFirstChild("Main")
                    and playerGui.Main:FindFirstChild("Screen")
                    and playerGui.Main.Screen:FindFirstChild("Hud")
                    and playerGui.Main.Screen.Hud:FindFirstChild("Level")

    if not levelLabel then
        warn("   ❌ Level Label not found!")
        return nil
    end

    if not levelLabel:IsA("TextLabel") then
        warn("   ❌ Level is not a TextLabel!")
        return nil
    end

    local levelText = levelLabel.Text
    local level = tonumber(string.match(levelText, "%d+"))
    
    if level then
        print(string.format("   ✅ Player Level: %d", level))
        return level
    else
        warn("   ❌ Failed to parse level from text!")
        return nil
    end
end

----------------------------------------------------------------
-- GOLD SYSTEM
----------------------------------------------------------------
local function getPlayerGold()
    print("   🔍 Checking player gold...")
    
    -- Path: PlayerGui.Main.Screen.Hud.Gold
    local goldLabel = playerGui:FindFirstChild("Main")
                     and playerGui.Main:FindFirstChild("Screen")
                     and playerGui.Main.Screen:FindFirstChild("Hud")
                     and playerGui.Main.Screen.Hud:FindFirstChild("Gold")
    
    if not goldLabel then
        warn("   ❌ Gold Label not found!")
        return nil
    end
    
    if not goldLabel:IsA("TextLabel") then
        warn("   ❌ Gold is not a TextLabel!")
        return nil
    end
    
    local goldText = goldLabel.Text
    
    -- Extract Gold from text (e.g., "$3,722.72" → 3722.72)
    local goldString = string.gsub(goldText, "[$,]", "")
    local gold = tonumber(goldString)
    
    if gold then
        print(string.format("   ✅ Player Gold: $%.2f", gold))
        return gold
    else
        warn("   ❌ Failed to parse gold from text!")
        return nil
    end
end

local function hasEnoughGold()
    local gold = getPlayerGold()
    
    if not gold then
        warn("   ❌ Cannot determine player gold!")
        return false
    end
    
    if gold >= QUEST_CONFIG.MIN_GOLD then
        print(string.format("   ✅ Gold $%.2f >= $%d - Can purchase!", gold, QUEST_CONFIG.MIN_GOLD))
        return true
    else
        print(string.format("   ⏸️  Gold $%.2f < $%d - Not enough gold", gold, QUEST_CONFIG.MIN_GOLD))
        return false
    end
end

----------------------------------------------------------------
-- NOCLIP & MOVEMENT
----------------------------------------------------------------
local function enableNoclip()
    if State.noclipConn then return end
    
    local char = player.Character
    if not char then return end
    
    State.noclipConn = RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
            return
        end
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
end

local function smoothMoveTo(targetPos, callback)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    enableNoclip()
    
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = hrp
    State.bodyVelocity = bv
    
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.D = 500
    bg.Parent = hrp
    State.bodyGyro = bg
    
    print(string.format("   🚀 Moving to (%.1f, %.1f, %.1f)...", targetPos.X, targetPos.Y, targetPos.Z))
    
    State.moveConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv then bv:Destroy() end
            if bg then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end
        
        local currentPos = hrp.Position
        local direction = (targetPos - currentPos)
        local distance = direction.Magnitude
        
        if distance < QUEST_CONFIG.STOP_DISTANCE then
            print("   ✅ Reached target!")
            
            bv.Velocity = Vector3.zero
            task.wait(0.1)
            
            bv:Destroy()
            bg:Destroy()
            State.bodyVelocity = nil
            State.bodyGyro = nil
            
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            
            if callback then callback() end
            return
        end
        
        local speed = math.min(QUEST_CONFIG.MOVE_SPEED, distance * 10)
        local velocity = direction.Unit * speed
        
        bv.Velocity = velocity
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
    end)
    
    return true
end

----------------------------------------------------------------
-- PURCHASE SYSTEM
----------------------------------------------------------------
local function purchaseItem(itemName, quantity)
    if not PURCHASE_RF then
        warn("   ❌ Purchase Remote not available!")
        return false
    end
    
    print(string.format("   🛒 Purchasing: %s x%d", itemName, quantity))
    
    local success, result = pcall(function()
        return PURCHASE_RF:InvokeServer(itemName, quantity)
    end)
    
    if success then
        print(string.format("   ✅ Purchased: %s x%d", itemName, quantity))
        return true
    else
        warn(string.format("   ❌ Failed to purchase %s: %s", itemName, tostring(result)))
        return false
    end
end

----------------------------------------------------------------
-- INVENTORY CHECK
----------------------------------------------------------------
local function hasPickaxe(pickaxeName)
    if not PlayerController or not PlayerController.Replica then
        warn("   ❌ PlayerController/Replica not available!")
        return false
    end
    
    local replica = PlayerController.Replica
    if not replica.Data or not replica.Data.Inventory or not replica.Data.Inventory.Equipments then
        warn("   ❌ Equipments not found in Replica!")
        return false
    end
    
    local equipments = replica.Data.Inventory.Equipments
    
    for id, item in pairs(equipments) do
        if type(item) == "table" and item.Type then
            if item.Type == pickaxeName then
                print(string.format("   ✅ Already have: %s", pickaxeName))
                return true
            end
        end
    end
    
    return false
end

----------------------------------------------------------------
-- MAIN QUEST EXECUTION
----------------------------------------------------------------
local function doBuyPickaxe()
    print("🛒 Objective: Buy Pickaxe...")
    
    -- 1. Check Gold
    print("\n💰 Checking gold...")
    if not hasEnoughGold() then
        warn("   ❌ Not enough gold to purchase!")
        return false
    end
    
    -- 2. Check Inventory
    print("\n🔍 Checking inventory...")
    if hasPickaxe(QUEST_CONFIG.ITEM_NAME) then
        print("   ✅ Already have the pickaxe!")
        return true
    end
    
    -- 3. Move to Shop
    local shopPos = QUEST_CONFIG.SHOP_POSITION
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    
    if hrp then
        local currentDist = (shopPos - hrp.Position).Magnitude
        print(string.format("   🚶 Moving to Shop at (%.1f, %.1f, %.1f) (%.1f studs away)...", 
            shopPos.X, shopPos.Y, shopPos.Z, currentDist))
    end
    
    local moveComplete = false
    smoothMoveTo(shopPos, function()
        moveComplete = true
    end)
    
    local timeout = 60
    local startTime = tick()
    while not moveComplete and tick() - startTime < timeout do
        task.wait(0.1)
    end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    if not moveComplete then
        warn("   ⚠️ Failed to reach Shop")
        return false
    end
    
    print("   ✅ Reached Shop!")
    task.wait(1)
    
    -- 4. Purchase Pickaxe
    print("\n🛒 Purchasing pickaxe...")
    local purchaseSuccess = purchaseItem(QUEST_CONFIG.ITEM_NAME, QUEST_CONFIG.ITEM_QUANTITY)
    
    if not purchaseSuccess then
        warn("   ❌ Failed to purchase pickaxe")
        return false
    end
    
    print("   ✅ Purchase complete!")
    
    -- 5. Check Gold after purchase
    task.wait(1)
    local newGold = getPlayerGold()
    if newGold then
        print(string.format("\n💰 Gold after purchase: $%.2f", newGold))
    end
    
    -- 6. Check Inventory again
    task.wait(1)
    if hasPickaxe(QUEST_CONFIG.ITEM_NAME) then
        print(string.format("   ✅ Successfully obtained: %s", QUEST_CONFIG.ITEM_NAME))
        return true
    else
        warn("   ⚠️ Purchase successful but item not found in inventory")
        return true  -- Assume success if remote worked
    end
end

----------------------------------------------------------------
-- SMART QUEST RUNNER
----------------------------------------------------------------
print(string.rep("=", 50))
print("🚀 QUEST 16: " .. QUEST_CONFIG.QUEST_NAME)
print("🎯 Objective: Buy Pickaxe")
print("✅ Strategy: Check Gold → Move to Shop → Purchase")
print(string.rep("=", 50))

-- Pre-check: Gold >= 3340 AND Level < 10
print("\n🔍 Pre-check: Verifying gold and level requirement...")

-- 1) Check Gold >= MIN_GOLD
local goldOk = hasEnoughGold()

-- 2) Check Level < 10
local level = getPlayerLevel()
if not level then
    warn("\n❌ Cannot determine player level – skipping Quest 16")
    print(string.rep("=", 50))
    cleanupState()
    disableNoclip()
    return
end

if (not goldOk) or level >= 10 then
    print(string.format(
        "\n❌ Condition not met (Gold ≥ %d AND Level < 10). Current: GoldOK=%s, Level=%d",
        QUEST_CONFIG.MIN_GOLD,
        tostring(goldOk),
        level
    ))
    print(string.rep("=", 50))
    cleanupState()
    disableNoclip()
    return
end

print(string.format(
    "   ✅ Condition passed! Gold ≥ %d AND Level < 10 (Level = %d)",
    QUEST_CONFIG.MIN_GOLD,
    level
))

-- Check if already have Pickaxe
print("\n🔍 Pre-check: Checking if already have pickaxe...")
if hasPickaxe(QUEST_CONFIG.ITEM_NAME) then
    print("\n✅ Already have the pickaxe!")
    print(string.rep("=", 50))
    cleanupState()
    disableNoclip()
    return
end

print("   ❌ Don't have pickaxe yet – proceeding to purchase...")

-- Purchase Pickaxe
local buySuccess = doBuyPickaxe()

if buySuccess then
    print("\n" .. string.rep("=", 50))
    print("✅ Quest 16 Complete! Pickaxe purchased successfully!")
    print(string.rep("=", 50))
else
    warn("\n" .. string.rep("=", 50))
    warn("❌ Quest 16 Failed! Could not purchase pickaxe.")
    warn(string.rep("=", 50))
end

Quest16Active = false
cleanupState()
disableNoclip()

end

-- Quest 17
_G.QuestFunctions[17] = function()
local Shared = _G.Shared

-- QUEST 17: Auto Mining Until Level 10 (FIXED - Smooth Movement)
-- ✅ Check Level < 10
-- ✅ Find all Boulders in workspace.Rocks
-- ✅ Smooth transition between rocks (No falling off map)
-- ✅ Loop until Level = 10

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest17Active = true
local IsMiningActive = false
local DEBUG_MODE = true

local QUEST_CONFIG = {
    QUEST_NAME = "Auto Mining Until Level 10",
    TARGET_LEVEL = 10,  -- Mine until Level = 10
    
    -- Rock Settings
    ROCK_NAME = "Boulder",
    
    UNDERGROUND_OFFSET = 4,
    LAYING_ANGLE = 90,
    MOVE_SPEED = 25,  
    
    -- Smooth Movement Settings
    HOLD_POSITION_AFTER_MINE = true,  -- Hold position after mining
    RESPAWN_WAIT_TIME = 3,  -- Wait for respawn (seconds)
}

----------------------------------------------------------------
-- KNIT SETUP
----------------------------------------------------------------
local KnitPackage = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitPackage)

if not Knit.OnStart then 
    pcall(function() Knit.Start():await() end)
end

local CharacterService = nil
local PlayerController = nil

pcall(function()
    CharacterService = Knit.GetService("CharacterService")
    PlayerController = Knit.GetController("PlayerController")
end)

local ToolController = nil
local ToolActivatedFunc = nil

pcall(function()
    for _, v in pairs(getgc(true)) do
        if type(v) == "table" then
            if rawget(v, "Name") == "ToolController" and rawget(v, "ToolActivated") then
                ToolController = v
                ToolActivatedFunc = v.ToolActivated
                break
            end
        end
    end
end)

local SERVICES = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")

local CHAR_RF = nil
pcall(function()
    CHAR_RF = SERVICES:WaitForChild("CharacterService", 5):WaitForChild("RF", 3):WaitForChild("EquipItem", 3)
end)

local TOOL_RF_BACKUP = nil
pcall(function()
    TOOL_RF_BACKUP = SERVICES:WaitForChild("ToolService", 5):WaitForChild("RF", 3):WaitForChild("ToolActivated", 3)
end)

local MINING_FOLDER_PATH = Workspace:WaitForChild("Rocks")

if CharacterService then print("✅ CharacterService Ready!") else warn("⚠️ CharacterService not found") end
if PlayerController then print("✅ PlayerController Ready!") else warn("⚠️ PlayerController not found") end
if ToolController then print("✅ ToolController Ready!") else warn("⚠️ ToolController not found") end

----------------------------------------------------------------
-- STATE MANAGEMENT
----------------------------------------------------------------
local State = {
    currentTarget = nil,
    targetDestroyed = false,
    hpWatchConn = nil,
    noclipConn = nil,
    moveConn = nil,
    positionLockConn = nil,
    bodyVelocity = nil,
    bodyGyro = nil,
}

-- 🛡️ BLACKLIST for rocks that someone else is mining
-- Format: { [rockModel] = expireTime }
local OccupiedRocks = {}
local OCCUPIED_TIMEOUT = 10  -- Remove from blacklist after 10 seconds

local function isRockOccupied(rock)
    if not rock then return false end
    local expireTime = OccupiedRocks[rock]
    if not expireTime then return false end
    
    if tick() > expireTime then
        OccupiedRocks[rock] = nil
        return false
    end
    return true
end

local function markRockAsOccupied(rock)
    if not rock then return end
    OccupiedRocks[rock] = tick() + OCCUPIED_TIMEOUT
    print(string.format("   🚫 Added to blacklist for %d seconds: %s", OCCUPIED_TIMEOUT, rock.Name))
end

local function cleanupExpiredBlacklist()
    local now = tick()
    for rock, expireTime in pairs(OccupiedRocks) do
        if now > expireTime or not rock.Parent then
            OccupiedRocks[rock] = nil
        end
    end
end

local function cleanupState()
    if State.hpWatchConn then State.hpWatchConn:Disconnect() State.hpWatchConn = nil end
    if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.positionLockConn then State.positionLockConn:Disconnect() State.positionLockConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    State.currentTarget = nil
    State.targetDestroyed = false
    
    if ToolController then
        ToolController.holdingM1 = false
    end
end

----------------------------------------------------------------
-- LEVEL SYSTEM
----------------------------------------------------------------
local function getPlayerLevel()
    local levelLabel = playerGui:FindFirstChild("Main")
                      and playerGui.Main:FindFirstChild("Screen")
                      and playerGui.Main.Screen:FindFirstChild("Hud")
                      and playerGui.Main.Screen.Hud:FindFirstChild("Level")
    
    if not levelLabel or not levelLabel:IsA("TextLabel") then
        return nil
    end
    
    local levelText = levelLabel.Text
    local level = tonumber(string.match(levelText, "%d+"))
    
    return level
end

local function shouldMine()
    local level = getPlayerLevel()
    
    if not level then
        warn("   ❌ Cannot determine player level!")
        return false
    end
    
    if level < QUEST_CONFIG.TARGET_LEVEL then
        return true
    else
        print(string.format("   ⏸️  Level %d >= %d - Stop mining", level, QUEST_CONFIG.TARGET_LEVEL))
        return false
    end
end

----------------------------------------------------------------
-- HELPER FUNCTIONS
----------------------------------------------------------------
local HOTKEY_MAP = {
    ["1"] = Enum.KeyCode.One,
    ["2"] = Enum.KeyCode.Two,
    ["3"] = Enum.KeyCode.Three,
    ["4"] = Enum.KeyCode.Four,
    ["5"] = Enum.KeyCode.Five,
    ["6"] = Enum.KeyCode.Six,
    ["7"] = Enum.KeyCode.Seven,
    ["8"] = Enum.KeyCode.Eight,
    ["9"] = Enum.KeyCode.Nine,
    ["0"] = Enum.KeyCode.Zero,
}

local function pressKey(keyCode)
    if not keyCode then return end
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

local function findPickaxeSlotKey()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end
    
    local hotbar = gui:FindFirstChild("BackpackGui") 
                   and gui.BackpackGui:FindFirstChild("Backpack") 
                   and gui.BackpackGui.Backpack:FindFirstChild("Hotbar")
    
    if hotbar then
        for _, slotFrame in ipairs(hotbar:GetChildren()) do
            local frame = slotFrame:FindFirstChild("Frame")
            local label = frame and frame:FindFirstChild("ToolName")
            if label and label:IsA("TextLabel") and string.find(label.Text, "Pickaxe") then
                return HOTKEY_MAP[slotFrame.Name]
            end
        end
    end
    
    return nil
end

local function checkMiningError()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return false end
    
    local notif = gui:FindFirstChild("Notifications")
    if notif and notif:FindFirstChild("Screen") and notif.Screen:FindFirstChild("NotificationsFrame") then
        for _, child in ipairs(notif.Screen.NotificationsFrame:GetChildren()) do
            local lbl = child:FindFirstChild("TextLabel", true)
            if lbl and string.find(lbl.Text, "Someone else is already mining") then
                return true
            end
        end
    end
    
    return false
end

----------------------------------------------------------------
-- ROCK HELPERS
----------------------------------------------------------------
local function getRockUndergroundPosition(rockModel)
    if not rockModel or not rockModel.Parent then
        return nil
    end
    
    local pivotCFrame = nil
    pcall(function()
        if rockModel.GetPivot then
            pivotCFrame = rockModel:GetPivot()
        elseif rockModel.WorldPivot then
            pivotCFrame = rockModel.WorldPivot
        end
    end)
    
    if pivotCFrame then
        local pos = pivotCFrame.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.UNDERGROUND_OFFSET, pos.Z)
    end
    
    if rockModel.PrimaryPart then
        local pos = rockModel.PrimaryPart.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.UNDERGROUND_OFFSET, pos.Z)
    end
    
    local part = rockModel:FindFirstChildWhichIsA("BasePart")
    if part then
        local pos = part.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.UNDERGROUND_OFFSET, pos.Z)
    end
    
    return nil
end

local function getRockHP(rock)
    if not rock or not rock.Parent then
        return 0
    end
    
    local success, result = pcall(function()
        return rock:GetAttribute("Health") or 0
    end)
    
    return success and result or 0
end

local function isTargetValid(rock)
    if not rock or not rock.Parent then
        return false
    end
    
    if not rock:FindFirstChildWhichIsA("BasePart") then
        return false
    end
    
    local hp = getRockHP(rock)
    return hp > 0
end

local function findNearestBoulder(excludeRock)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    cleanupExpiredBlacklist()
    
    local targetRock, minDist = nil, math.huge
    local skippedOccupied = 0
    
    for _, folder in ipairs(MINING_FOLDER_PATH:GetChildren()) do
        if folder:IsA("Folder") or folder:IsA("Model") then
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("SpawnLocation") or child.Name == "SpawnLocation" then
                    local rock = child:FindFirstChild(QUEST_CONFIG.ROCK_NAME)
                    
                    if rock and rock ~= excludeRock and isTargetValid(rock) then
                        if isRockOccupied(rock) then
                            skippedOccupied = skippedOccupied + 1
                        else
                            local pos = getRockUndergroundPosition(rock)
                            if pos then
                                local dist = (pos - hrp.Position).Magnitude
                                
                                if dist < minDist then
                                    minDist = dist
                                    targetRock = rock
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    if skippedOccupied > 0 then
        print(string.format("   ⏭️ Skipped %d occupied rocks (blacklisted)", skippedOccupied))
    end
    
    return targetRock, minDist
end

local function watchRockHP(rock)
    if State.hpWatchConn then
        State.hpWatchConn:Disconnect()
    end
    
    if not rock then return end
    
    State.hpWatchConn = rock:GetAttributeChangedSignal("Health"):Connect(function()
        local hp = rock:GetAttribute("Health") or 0
        
        if hp <= 0 then
            print("   ✅ Rock destroyed!")
            State.targetDestroyed = true
            
            if ToolController then
                ToolController.holdingM1 = false
            end
        end
    end)
end

----------------------------------------------------------------
-- NOCLIP & MOVEMENT
----------------------------------------------------------------
local function enableNoclip()
    if State.noclipConn then return end
    
    local char = player.Character
    if not char then return end
    
    State.noclipConn = RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
            return
        end
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
end

local function smoothMoveTo(targetPos, callback)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    enableNoclip()
    
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = hrp
    State.bodyVelocity = bv
    
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.D = 500
    bg.Parent = hrp
    State.bodyGyro = bg
    
    print(string.format("   🚀 Moving to (%.1f, %.1f, %.1f)...", targetPos.X, targetPos.Y, targetPos.Z))
    
    State.moveConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv then bv:Destroy() end
            if bg then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end
        
        local currentPos = hrp.Position
        local direction = (targetPos - currentPos)
        local distance = direction.Magnitude
        
        if distance < 2 then
            print("   ✅ Reached target!")
            
            bv.Velocity = Vector3.zero
            task.wait(0.1)
            
            bv:Destroy()
            bg:Destroy()
            State.bodyVelocity = nil
            State.bodyGyro = nil
            
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            
            if callback then callback() end
            return
        end
        
        local speed = math.min(QUEST_CONFIG.MOVE_SPEED, distance * 10)
        local velocity = direction.Unit * speed
        
        bv.Velocity = velocity
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
    end)
    
    return true
end

----------------------------------------------------------------
-- POSITION LOCK (SMOOTH TRANSITION)
----------------------------------------------------------------
local function lockPositionLayingDown(targetPos)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    if State.positionLockConn then
        State.positionLockConn:Disconnect()
        State.positionLockConn = nil
    end
    
    local angle = math.rad(QUEST_CONFIG.LAYING_ANGLE)
    local baseCFrame = CFrame.new(targetPos)
    local layingCFrame = baseCFrame * CFrame.Angles(angle, 0, 0)
    
    State.positionLockConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.positionLockConn then
                State.positionLockConn:Disconnect()
                State.positionLockConn = nil
            end
            return
        end
        
        hrp.CFrame = layingCFrame
        hrp.Velocity = Vector3.zero
        hrp.AssemblyLinearVelocity = Vector3.zero
    end)
    
    print("   🔒 Position locked")
end

local function transitionToNewTarget(newTargetPos)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    print(string.format("   🔄 Smooth transition to new target..."))
    
    if State.positionLockConn then
        State.positionLockConn:Disconnect()
        State.positionLockConn = nil
    end
    
    local moveComplete = false
    smoothMoveTo(newTargetPos, function()
        lockPositionLayingDown(newTargetPos)
        moveComplete = true
    end)
    
    local timeout = 60
    local startTime = tick()
    while not moveComplete and tick() - startTime < timeout do
        task.wait(0.1)
    end
    
    if not moveComplete then
        warn("   ⚠️ Transition timeout!")
        return false
    end
    
    return true
end

local function unlockPosition()
    if State.positionLockConn then
        State.positionLockConn:Disconnect()
        State.positionLockConn = nil
        print("   🔓 Position unlocked")
    end
end

----------------------------------------------------------------
-- MAIN MINING EXECUTION
----------------------------------------------------------------
local function doMineUntilLevel10()
    print("⛏️ Objective: Mine until Level 10...")
    
    IsMiningActive = true
    
    print("\n" .. string.rep("=", 50))
    print("⛏️ Starting Mining Loop...")
    print(string.rep("=", 50))
    
    while Quest17Active and shouldMine() do
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        
        if not hrp then
            warn("   ⚠️ Waiting for character...")
            task.wait(2)
            continue
        end
        
        if not State.positionLockConn and not State.moveConn and not State.bodyVelocity then
            cleanupState()
        end
        
        -- 1. Find Nearest Boulder
        local targetRock, dist = findNearestBoulder(State.currentTarget)
        
        if not targetRock then
            warn("   ❌ No Boulder found, waiting for respawn...")
            unlockPosition()
            cleanupState()
            task.wait(QUEST_CONFIG.RESPAWN_WAIT_TIME)
            continue
        end
        
        local previousTarget = State.currentTarget
        State.currentTarget = targetRock
        State.targetDestroyed = false
        
        -- 2. Get Underground Position
        local targetPos = getRockUndergroundPosition(targetRock)
        
        if not targetPos then
            warn("   ❌ Cannot get rock position!")
            task.wait(1)
            continue
        end
        
        local currentHP = getRockHP(targetRock)
        local currentLevel = getPlayerLevel()
        
        print(string.format("\n🎯 Target: %s.%s (HP: %d, Dist: %.1f, Level: %d)", 
            targetRock.Parent.Parent.Name,
            targetRock.Parent.Name,
            currentHP, 
            dist,
            currentLevel or 0))
        
        -- 3. Watch HP
        watchRockHP(targetRock)
        
        -- 4. Move to Rock
        if State.positionLockConn and previousTarget ~= targetRock then
            print("   🔄 Smooth transition from previous target...")
            transitionToNewTarget(targetPos)
        else
            local moveStarted = false
            smoothMoveTo(targetPos, function()
                lockPositionLayingDown(targetPos)
                moveStarted = true
            end)
            
            local timeout = 60
            local startTime = tick()
            while not moveStarted and tick() - startTime < timeout do
                task.wait(0.1)
            end
            
            if not moveStarted then
                warn("   ⚠️ Move timeout, skip this rock")
                State.targetDestroyed = true
                unlockPosition()
                continue
            end
        end
        
        task.wait(0.5)
        
        -- 5. Start Mining
        while not State.targetDestroyed and Quest17Active and shouldMine() do
            if not char or not char.Parent then
                print("   ❌ Character died!")
                break
            end
            
            if not targetRock or not targetRock.Parent then
                print("   ✅ Target removed!")
                State.targetDestroyed = true
                break
            end
            
            if checkMiningError() then
                print("   ⚠️ Someone else mining! Switching target...")
                markRockAsOccupied(targetRock)
                State.targetDestroyed = true
                if ToolController then
                    ToolController.holdingM1 = false
                end
                break
            end
            
            local toolInHand = char:FindFirstChildWhichIsA("Tool")
            local isPickaxeHeld = toolInHand and string.find(toolInHand.Name, "Pickaxe")
            
            if not isPickaxeHeld then
                if ToolController then
                    ToolController.holdingM1 = false
                end
                
                local key = findPickaxeSlotKey()
                if key then
                    pressKey(key)
                    task.wait(0.3)
                else
                    pcall(function()
                        if PlayerController and PlayerController.Replica then
                            local replica = PlayerController.Replica
                            if replica.Data and replica.Data.Inventory and replica.Data.Inventory.Equipments then
                                for id, item in pairs(replica.Data.Inventory.Equipments) do
                                    if type(item) == "table" and item.Type and string.find(item.Type, "Pickaxe") then
                                        CHAR_RF:InvokeServer({Runes = {}}, item)
                                        break
                                    end
                                end
                            end
                        end
                    end)
                    task.wait(0.5)
                end
            else
                if ToolController and ToolActivatedFunc then
                    ToolController.holdingM1 = true
                    pcall(function()
                        ToolActivatedFunc(ToolController, toolInHand)
                    end)
                else
                    pcall(function()
                        TOOL_RF_BACKUP:InvokeServer(toolInHand.Name, true)
                    end)
                end
            end
            
            task.wait(0.15)
        end
        
        -- 6. After Mining
        if QUEST_CONFIG.HOLD_POSITION_AFTER_MINE then
            print("   ⏸️  Holding position, searching for next target...")
        else
            unlockPosition()
        end
        
        local newLevel = getPlayerLevel()
        if newLevel and newLevel >= QUEST_CONFIG.TARGET_LEVEL then
            print(string.format("\n🎉 Level %d reached! Mining complete!", newLevel))
            break
        end
        
        if DEBUG_MODE then
            print(string.format("   📊 Current Level: %d / %d", newLevel or 0, QUEST_CONFIG.TARGET_LEVEL))
        end
        
        task.wait(0.5)
    end
    
    print("\n" .. string.rep("=", 50))
    print("✅ Mining ended")
    print(string.rep("=", 50))
    
    IsMiningActive = false
    unlockPosition()
    disableNoclip()
    cleanupState()
end

----------------------------------------------------------------
-- SMART QUEST RUNNER
----------------------------------------------------------------
print(string.rep("=", 50))
print("🚀 QUEST 17: " .. QUEST_CONFIG.QUEST_NAME)
print("🎯 Objective: Mine until Level 10")
print(string.format("✅ Strategy: Smooth mining all '%s' in workspace.Rocks", QUEST_CONFIG.ROCK_NAME))
print(string.rep("=", 50))

-- Check Level First
print("\n🔍 Pre-check: Verifying level requirement...")
if not shouldMine() then
    print("\n✅ Already Level 10 or higher!")
    print(string.rep("=", 50))
    cleanupState()
    disableNoclip()
    return
end

-- Check for Boulders
print("\n🔍 Pre-check: Scanning for Boulders...")
local targetRock, dist = findNearestBoulder()

if not targetRock then
    warn("\n❌ No Boulder found in workspace.Rocks!")
    print(string.rep("=", 50))
    cleanupState()
    disableNoclip()
    return
end

print("   ✅ Found Boulders!")

-- Start Mining
doMineUntilLevel10()

task.wait(1)

local finalLevel = getPlayerLevel()

if finalLevel and finalLevel >= QUEST_CONFIG.TARGET_LEVEL then
    print("\n" .. string.rep("=", 50))
    print("✅ Quest 17 Complete!")
    print(string.format("   🎉 Final Level: %d", finalLevel))
    print(string.rep("=", 50))
else
    warn("\n" .. string.rep("=", 50))
    warn("⚠️ Quest 17 incomplete")
    warn(string.format("   📊 Current Level: %d / %d", finalLevel or 0, QUEST_CONFIG.TARGET_LEVEL))
    warn(string.rep("=", 50))
end

Quest17Active = false
cleanupState()
disableNoclip()

end

-- Quest 18
_G.QuestFunctions[18] = function()
local Shared = _G.Shared

-- QUEST 18: Smart Teleport to Forgotten Kingdom
-- ✅ Checks if player is on Island1
-- ✅ If on Island1 → Teleport to Forgotten Kingdom (Island2)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest18Active = true

local QUEST_CONFIG = {
    QUEST_NAME = "Smart Teleport",
    REQUIRED_LEVEL = 10,
    ISLAND_NAME = "Forgotten Kingdom",
}

----------------------------------------------------------------
-- KNIT SETUP
----------------------------------------------------------------
local KnitPackage = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitPackage)

if not Knit.OnStart then 
    pcall(function() Knit.Start():await() end)
end

local SERVICES = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")

local PORTAL_RF = nil
pcall(function()
    PORTAL_RF = SERVICES:WaitForChild("PortalService", 5):WaitForChild("RF", 3):WaitForChild("TeleportToIsland", 3)
end)

local FORGES_FOLDER = Workspace:WaitForChild("Forges")

if PORTAL_RF then print("✅ Portal Remote Ready!") else warn("⚠️ Portal Remote not found") end

----------------------------------------------------------------
-- LEVEL SYSTEM
----------------------------------------------------------------
local function getPlayerLevel()
    local levelLabel = playerGui:FindFirstChild("Main")
                      and playerGui.Main:FindFirstChild("Screen")
                      and playerGui.Main.Screen:FindFirstChild("Hud")
                      and playerGui.Main.Screen.Hud:FindFirstChild("Level")
    
    if not levelLabel or not levelLabel:IsA("TextLabel") then
        return nil
    end
    
    local levelText = levelLabel.Text
    local level = tonumber(string.match(levelText, "%d+"))
    
    return level
end

local function hasRequiredLevel()
    local level = getPlayerLevel()
    
    if not level then
        warn("   ❌ Cannot determine level!")
        return false
    end
    
    if level >= QUEST_CONFIG.REQUIRED_LEVEL then
        print(string.format("   ✅ Level %d >= %d", level, QUEST_CONFIG.REQUIRED_LEVEL))
        return true
    else
        print(string.format("   ⏸️  Level %d < %d", level, QUEST_CONFIG.REQUIRED_LEVEL))
        return false
    end
end

----------------------------------------------------------------
-- ISLAND DETECTION
----------------------------------------------------------------
local function getCurrentIsland()
    for _, child in ipairs(FORGES_FOLDER:GetChildren()) do
        if child:IsA("Folder") or child:IsA("Model") then
            if string.match(child.Name, "Island%d+") then
                return child.Name
            end
        end
    end
    return nil
end

local function needsTeleport()
    local currentIsland = getCurrentIsland()
    
    if not currentIsland then
        return true
    end
    
    if currentIsland == "Island1" then
        print(string.format("   ✅ On %s → Need teleport!", currentIsland))
        return true
    elseif currentIsland == "Island2" then
        print(string.format("   ✅ On %s → Already on target!", currentIsland))
        return false
    else
        warn(string.format("   ⚠️ Unknown: %s", currentIsland))
        return true
    end
end

----------------------------------------------------------------
-- TELEPORT SYSTEM
----------------------------------------------------------------
local function teleportToIsland(islandName)
    if not PORTAL_RF then
        warn("   ❌ Portal Remote not available!")
        return false
    end
    
    print(string.format("   🌀 Teleporting to: %s", islandName))
    
    local args = {islandName}
    
    local success, result = pcall(function()
        return PORTAL_RF:InvokeServer(unpack(args))
    end)
    
    if success then
        print(string.format("   ✅ Teleported to: %s", islandName))
        return true
    else
        warn(string.format("   ❌ Failed: %s", tostring(result)))
        return false
    end
end

----------------------------------------------------------------
-- SMART QUEST RUNNER
----------------------------------------------------------------
print(string.rep("=", 50))
print("🚀 QUEST 18: " .. QUEST_CONFIG.QUEST_NAME)
print("🎯 Objective: Teleport to Forgotten Kingdom")
print(string.rep("=", 50))

-- Check Level
print("\n🔍 Pre-check: Verifying level requirement...")
if not hasRequiredLevel() then
    print("\n❌ Level requirement not met!")
    print(string.rep("=", 50))
    return
end

-- Check if teleport needed
print("\n🔍 Checking Location...")
if needsTeleport() then
    print("   ⚠️ Not on target island!")
    local success = teleportToIsland(QUEST_CONFIG.ISLAND_NAME)
    
    if success then
        print("\n" .. string.rep("=", 50))
        print("✅ Quest 18 Complete! Teleported to Forgotten Kingdom!")
        print(string.rep("=", 50))
    else
        print("\n" .. string.rep("=", 50))
        print("❌ Quest 18 Failed! Could not teleport!")
        print(string.rep("=", 50))
    end
else
    print("\n" .. string.rep("=", 50))
    print("✅ Quest 18 Complete! Already on target island!")
    print(string.rep("=", 50))
end

Quest18Active = false

end

-- Quest 19
_G.QuestFunctions[19] = function()
local Shared = _G.Shared

-- QUEST 19: Mining + Auto Sell & Auto Buy
-- ✅ Priority 1: Auto Sell Init (One-time setup)
-- ✅ Priority 2: Background Tasks (Auto Sell + Auto Buy - Always running)
-- ✅ Priority 3: Mining (Basalt Rock / Basalt Core)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Quest19Active = true
local IsMiningActive = false
local DEBUG_MODE = true

local QUEST_CONFIG = {
    QUEST_NAME = "Mining + Auto Sell & Buy",
    REQUIRED_LEVEL = 10,
    
    -- Priority 1: Auto Sell (Ores)
    AUTO_SELL_ENABLED = true,
    AUTO_SELL_INTERVAL = 10,
    AUTO_SELL_NPC_NAME = "Greedy Cey",
    
    -- Priority 2: Auto Buy Cobalt Pickaxe (Background)
    AUTO_BUY_ENABLED = true,
    AUTO_BUY_INTERVAL = 15,
    TARGET_PICKAXE = "Cobalt Pickaxe",
    MIN_GOLD_TO_BUY = 10000,
    SHOP_POSITION = Vector3.new(-165, 22, -111.7),
    
    -- Priority 2.5: Auto Buy Magma Pickaxe (Gold >= 150k)
    MAGMA_PICKAXE_CONFIG = {
        ENABLED = true,
        TARGET_PICKAXE = "Magma Pickaxe",
        MIN_GOLD_TO_BUY = 150000,
        SELL_SHOP_POSITION = Vector3.new(-115.1, 22.3, -92.3),  -- ขาย Weapon/Armor
        BUY_SHOP_POSITION = Vector3.new(378, 88.6, 109.6),       -- ซื้อ Magma Pickaxe
    },
    
    -- Priority 3: Mining (Default: Basalt Rock)
    ROCK_NAME = "Basalt Rock",
    UNDERGROUND_OFFSET = 4,
    LAYING_ANGLE = 90,
    MOVE_SPEED = 25,  
    STOP_DISTANCE = 2,
    
    MINING_PATHS = {
        "Island2CaveStart",
        "Island2CaveDanger1",
        "Island2CaveDanger2",
        "Island2CaveDanger3",
        "Island2CaveDanger4",
        "Island2CaveDangerClosed",
        "Island2CaveDeep",
        "Island2CaveLavaClosed",
        "Island2CaveMid",
    },
    
    -- Tier 2: Basalt Core (If have Cobalt Pickaxe)
    BASALT_CORE_CONFIG = {
        ROCK_NAME = "Basalt Core",
        MINING_PATHS = {
            "Island2CaveStart",
            "Island2CaveDanger1",
            "Island2CaveDanger2",
            "Island2CaveDanger3",
            "Island2CaveDanger4",
            "Island2CaveDangerClosed",
            "Island2CaveDeep",
            "Island2CaveLavaClosed",
            "Island2CaveMid",
        },
    },
    
    -- Tier 3: Basalt Vein (If have Magma Pickaxe)
    BASALT_VEIN_CONFIG = {
        ROCK_NAME = "Basalt Vein",
        MINING_PATHS = {
            "Island2CaveStart",
            "Island2CaveDanger1",
            "Island2CaveDanger2",
            "Island2CaveDanger3",
            "Island2CaveDanger4",
            "Island2CaveDangerClosed",
            "Island2CaveDeep",
            "Island2CaveLavaClosed",
            "Island2CaveMid",
        },
    },
    
    WAYPOINTS = {
        Vector3.new(-154.5, 39.1, 138.8),
        Vector3.new(11, 46.5, 124.2),
        Vector3.new(65, 74.2, -44),
    },
    
    WAYPOINT_STOP_DISTANCE = 5,
    MAX_ROCKS_TO_MINE = 99999999999999,
    HOLD_POSITION_AFTER_MINE = true,
}

----------------------------------------------------------------
-- KNIT SETUP
----------------------------------------------------------------
local KnitPackage = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitPackage)

if not Knit.OnStart then 
    pcall(function() Knit.Start():await() end)
end

local CharacterService = nil
local PlayerController = nil

pcall(function()
    CharacterService = Knit.GetService("CharacterService")
    PlayerController = Knit.GetController("PlayerController")
end)

local ToolController = nil
local ToolActivatedFunc = nil

pcall(function()
    for _, v in pairs(getgc(true)) do
        if type(v) == "table" then
            if rawget(v, "Name") == "ToolController" and rawget(v, "ToolActivated") then
                ToolController = v
                ToolActivatedFunc = v.ToolActivated
                break
            end
        end
    end
end)

local SERVICES = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")

local PORTAL_RF = nil
pcall(function()
    PORTAL_RF = SERVICES:WaitForChild("PortalService", 5):WaitForChild("RF", 3):WaitForChild("TeleportToIsland", 3)
end)

local CHAR_RF = nil
pcall(function()
    CHAR_RF = SERVICES:WaitForChild("CharacterService", 5):WaitForChild("RF", 3):WaitForChild("EquipItem", 3)
end)

local TOOL_RF_BACKUP = nil
pcall(function()
    TOOL_RF_BACKUP = SERVICES:WaitForChild("ToolService", 5):WaitForChild("RF", 3):WaitForChild("ToolActivated", 3)
end)

local DIALOGUE_RF = nil
local DialogueRE = nil
pcall(function()
    local dialogueService = SERVICES:WaitForChild("DialogueService", 5)
    DIALOGUE_RF = dialogueService:WaitForChild("RF", 3):WaitForChild("RunCommand", 3)
    DialogueRE = dialogueService:WaitForChild("RE", 3):WaitForChild("DialogueEvent", 3)
end)

local ProximityDialogueRF = nil
local PURCHASE_RF = nil
pcall(function()
    local proximityService = SERVICES:WaitForChild("ProximityService", 5)
    ProximityDialogueRF = proximityService:WaitForChild("RF", 3):WaitForChild("Dialogue", 3)
    PURCHASE_RF = proximityService:WaitForChild("RF", 3):WaitForChild("Purchase", 3)
end)

local FORGES_FOLDER = Workspace:WaitForChild("Forges")
local MINING_FOLDER_PATH = Workspace:WaitForChild("Rocks")

if PORTAL_RF then print("✅ Portal Remote Ready!") else warn("⚠️ Portal Remote not found") end
if PlayerController then print("✅ PlayerController Ready!") else warn("⚠️ PlayerController not found") end
if ToolController then print("✅ ToolController Ready!") else warn("⚠️ ToolController not found") end
if DIALOGUE_RF then print("✅ Dialogue Remote Ready!") else warn("⚠️ Dialogue Remote not found") end
if PURCHASE_RF then print("✅ Purchase Remote Ready!") else warn("⚠️ Purchase Remote not found") end

----------------------------------------------------------------
-- STATE MANAGEMENT
----------------------------------------------------------------
local State = {
    currentTarget = nil,
    targetDestroyed = false,
    hpWatchConn = nil,
    noclipConn = nil,
    moveConn = nil,
    positionLockConn = nil,
    bodyVelocity = nil,
    bodyGyro = nil,
    
    autoSellTask = nil,
    autoBuyTask = nil,
    isPaused = false,
}

-- 🛡️ BLACKLIST for rocks that someone else is mining
-- Format: { [rockModel] = expireTime }
local OccupiedRocks = {}
local OCCUPIED_TIMEOUT = 10  -- Remove from blacklist after 10 seconds

local function isRockOccupied(rock)
    if not rock then return false end
    local expireTime = OccupiedRocks[rock]
    if not expireTime then return false end
    
    if tick() > expireTime then
        OccupiedRocks[rock] = nil
        return false
    end
    return true
end

local function markRockAsOccupied(rock)
    if not rock then return end
    OccupiedRocks[rock] = tick() + OCCUPIED_TIMEOUT
    print(string.format("   🚫 Added to blacklist for %d seconds: %s", OCCUPIED_TIMEOUT, rock.Name))
end

local function cleanupExpiredBlacklist()
    local now = tick()
    for rock, expireTime in pairs(OccupiedRocks) do
        if now > expireTime or not rock.Parent then
            OccupiedRocks[rock] = nil
        end
    end
end

local AutoSellInitialized = false

local function cleanupState()
    if State.hpWatchConn then State.hpWatchConn:Disconnect() State.hpWatchConn = nil end
    if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.positionLockConn then State.positionLockConn:Disconnect() State.positionLockConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    State.currentTarget = nil
    State.targetDestroyed = false
    
    if ToolController then
        ToolController.holdingM1 = false
    end
end

----------------------------------------------------------------
-- GOLD SYSTEM
----------------------------------------------------------------
local function getGold()
    local goldLabel = playerGui:FindFirstChild("Main")
                     and playerGui.Main:FindFirstChild("Screen")
                     and playerGui.Main.Screen:FindFirstChild("Hud")
                     and playerGui.Main.Screen.Hud:FindFirstChild("Gold")
    
    if not goldLabel or not goldLabel:IsA("TextLabel") then
        return 0
    end
    
    local goldText = goldLabel.Text
    local goldString = string.gsub(goldText, "[$,]", "")
    local gold = tonumber(goldString)
    
    return gold or 0
end

----------------------------------------------------------------
-- INVENTORY CHECK
----------------------------------------------------------------
local function hasPickaxe(pickaxeName)
    -- Check UI: PlayerGui.Menu.Frame.Frame.Menus.Tools.Frame
    local menu = playerGui:FindFirstChild("Menu")
    if not menu then
        if DEBUG_MODE then
            warn("[Q18] Menu not found → treat as NO pickaxe")
        end
        return false
    end

    local ok, toolsFrame = pcall(function()
        local f1    = menu:FindFirstChild("Frame")
        local f2    = f1 and f1:FindFirstChild("Frame")
        local menus = f2 and f2:FindFirstChild("Menus")
        local tools = menus and menus:FindFirstChild("Tools")
        local frame = tools and tools:FindFirstChild("Frame")
        return frame
    end)

    if not ok or not toolsFrame then
        if DEBUG_MODE then
            warn("[Q18] Tools.Frame not found → treat as NO pickaxe")
        end
        return false
    end

    -- Children in Frame are like "Iron Pickaxe", "Stone Pickaxe", "Cobalt Pickaxe"
    local gui = toolsFrame:FindFirstChild(pickaxeName)
    if gui then
        if DEBUG_MODE then
            local visible = gui:IsA("GuiObject") and gui.Visible or "N/A"
            print(string.format("[Q18] ✅ UI pickaxe '%s' found (Visible=%s)", pickaxeName, tostring(visible)))
        end
        return true
    end

    if DEBUG_MODE then
        print(string.format("[Q18] ⚠️ UI pickaxe '%s' NOT found", pickaxeName))
    end
    return false
end

----------------------------------------------------------------
-- FORCE CLOSE DIALOG
----------------------------------------------------------------
local function ForceEndDialogueAndRestore()
    local gui = player:FindFirstChild("PlayerGui")
    if gui then
        local dUI = gui:FindFirstChild("DialogueUI")
        if dUI then
            dUI.Enabled = false
            local bb = dUI:FindFirstChild("ResponseBillboard")
            if bb then bb.Visible = false end
        end
    end
    
    local cam = Workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        cam.FieldOfView = 70
    end
    
    local char = player.Character
    if char then
        local status = char:FindFirstChild("Status")
        if status then
            for _, tag in ipairs(status:GetChildren()) do
                if tag.Name == "DisableBackpack" or tag.Name == "NoMovement" or tag.Name == "Talking" then
                    tag:Destroy()
                end
            end
        end
        
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
        end
    end
    
    if gui then
        local main = gui:FindFirstChild("Main")
        if main then main.Enabled = true end
        
        local backpack = gui:FindFirstChild("BackpackGui")
        if backpack then backpack.Enabled = true end
    end
    
    if DialogueRE then
        pcall(function()
            DialogueRE:FireServer("Closed")
        end)
    end
end

----------------------------------------------------------------
-- NOCLIP & MOVEMENT
----------------------------------------------------------------
local function enableNoclip()
    if State.noclipConn then return end
    
    local char = player.Character
    if not char then return end
    
    State.noclipConn = RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if State.noclipConn then State.noclipConn:Disconnect() State.noclipConn = nil end
            return
        end
        
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function disableNoclip()
    if State.noclipConn then
        State.noclipConn:Disconnect()
        State.noclipConn = nil
    end
    -- restoreCollisions() -- Not defined in this scope, assuming handled by game or not needed
end

local function smoothMoveTo(targetPos, callback)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
    if State.bodyVelocity then State.bodyVelocity:Destroy() State.bodyVelocity = nil end
    if State.bodyGyro then State.bodyGyro:Destroy() State.bodyGyro = nil end
    
    enableNoclip()
    
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = hrp
    State.bodyVelocity = bv
    
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 10000
    bg.D = 500
    bg.Parent = hrp
    State.bodyGyro = bg
    
    if DEBUG_MODE then
        print(string.format("   🚀 Moving to (%.1f, %.1f, %.1f)...", targetPos.X, targetPos.Y, targetPos.Z))
    end
    
    local reachedTarget = false
    
    State.moveConn = RunService.Heartbeat:Connect(function()
        if reachedTarget then return end
        
        -- Check if character or BodyVelocity is destroyed
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            if bv and bv.Parent then bv:Destroy() end
            if bg and bg.Parent then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            return
        end
        
        -- Check if BodyVelocity was destroyed by game/other script
        if not bv or not bv.Parent then
            warn("   ⚠️ BodyVelocity destroyed! Recreating...")
            
            -- Recreate BodyVelocity
            bv = Instance.new("BodyVelocity")
            bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bv.Parent = hrp
            State.bodyVelocity = bv
        end
        
        if not bg or not bg.Parent then
            bg = Instance.new("BodyGyro")
            bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
            bg.P = 10000
            bg.D = 500
            bg.Parent = hrp
            State.bodyGyro = bg
        end
        
        local currentPos = hrp.Position
        local direction = (targetPos - currentPos)
        local distance = direction.Magnitude
        
        if distance < QUEST_CONFIG.STOP_DISTANCE then
            if DEBUG_MODE then
                print(string.format("   ✅ Reached! (%.1f)", distance))
            end
            
            reachedTarget = true
            
            bv.Velocity = Vector3.zero
            hrp.Velocity = Vector3.zero
            hrp.AssemblyLinearVelocity = Vector3.zero
            
            task.wait(0.1)
            
            if bv and bv.Parent then bv:Destroy() end
            if bg and bg.Parent then bg:Destroy() end
            State.bodyVelocity = nil
            State.bodyGyro = nil
            
            if State.moveConn then State.moveConn:Disconnect() State.moveConn = nil end
            
            if callback then callback() end
            return
        end
        
        local speed = math.min(QUEST_CONFIG.MOVE_SPEED, distance * 10)
        local velocity = direction.Unit * speed
        
        bv.Velocity = velocity
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
    end)
    
    return true
end

----------------------------------------------------------------
-- AUTO SELL SYSTEM
----------------------------------------------------------------
local function getSellNPC()
    local prox = Workspace:FindFirstChild("Proximity")
    return prox and prox:FindFirstChild(QUEST_CONFIG.AUTO_SELL_NPC_NAME) or nil
end

local function getSellNPCPos()
    local npc = getSellNPC()
    if not npc then return nil end
    local hrp = npc:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position or nil
end

local function getStashBackground()
    local menu = playerGui:FindFirstChild("Menu")
    if not menu then return nil end
    local f1 = menu:FindFirstChild("Frame")
    if not f1 then return nil end
    local f2 = f1:FindFirstChild("Frame")
    if not f2 then return nil end
    local menus = f2:FindFirstChild("Menus")
    if not menus then return nil end
    local stash = menus:FindFirstChild("Stash")
    if not stash then return nil end
    return stash:FindFirstChild("Background")
end

local function parseQty(text)
    if not text or text == "" then return 1 end
    local n = string.match(text, "x?(%d+)")
    return tonumber(n) or 1
end

local function getStashItemsUI()
    local bg = getStashBackground()
    if not bg then return {} end
    
    local basket = {}
    for _, child in ipairs(bg:GetChildren()) do
        if child:IsA("GuiObject") and not string.match(child.Name, "^UI") then
            local qty = 1
            local main = child:FindFirstChild("Main")
            if main then
                local q = main:FindFirstChild("Quantity")
                if q and q:IsA("TextLabel") and q.Visible then
                    qty = parseQty(q.Text)
                end
            end
            basket[child.Name] = qty
        end
    end
    return basket
end

local function initAutoSellWithNPC()
    if AutoSellInitialized then return true end
    
    print("\n" .. string.rep("=", 60))
    print("🔧 INITIALIZING AUTO SELL (ONE-TIME)")
    print(string.rep("=", 60))
    
    local npcPos = getSellNPCPos()
    if not npcPos then
        warn("   ❌ NPC not found: " .. QUEST_CONFIG.AUTO_SELL_NPC_NAME)
        return false
    end
    
    print(string.format("   ✅ Found %s at (%.1f, %.1f, %.1f)", 
        QUEST_CONFIG.AUTO_SELL_NPC_NAME, npcPos.X, npcPos.Y, npcPos.Z))
    
    print("   🚶 Moving to NPC...")
    
    local done = false
    smoothMoveTo(npcPos, function() done = true end)
    
    local t0 = tick()
    while not done and tick() - t0 < 30 do
        task.wait(0.1)
    end
    
    if not done then
        warn("   ❌ Failed to reach NPC (timeout)")
        return false
    end
    
    print("   ✅ Reached NPC!")
    task.wait(1)
    
    local npc = getSellNPC()
    if npc and ProximityDialogueRF then
        print("   💬 Opening dialog...")
        pcall(function()
            ProximityDialogueRF:InvokeServer(npc)
        end)
    end
    
    task.wait(2)
    
    print("   🚪 Closing dialog...")
    ForceEndDialogueAndRestore()
    
    task.wait(1)
    
    AutoSellInitialized = true
    
    print("\n" .. string.rep("=", 60))
    print("✅ AUTO SELL INITIALIZED!")
    print(string.rep("=", 60))
    
    return true
end

local function sellAllFromUI()
    if not DIALOGUE_RF then return end
    if not AutoSellInitialized then return end
    
    local basket = getStashItemsUI()
    local hasItem = false
    for _, v in pairs(basket) do
        if v > 0 then hasItem = true break end
    end
    
    if not hasItem then
        if DEBUG_MODE then print("AutoSell: no items") end
        return
    end
    
    local args = { "SellConfirm", { Basket = basket } }
    local ok, res = pcall(function()
        return DIALOGUE_RF:InvokeServer(unpack(args))
    end)
    
    if ok then
        print("💰 AutoSell: sold items!")
    else
        warn("AutoSell failed:", res)
    end
end

local function startAutoSellTask()
    if not QUEST_CONFIG.AUTO_SELL_ENABLED or not DIALOGUE_RF then
        return
    end
    
    print("🤖 Auto Sell Background Task Started!")
    
    State.autoSellTask = task.spawn(function()
        while Quest18Active do
            task.wait(QUEST_CONFIG.AUTO_SELL_INTERVAL)
            
            if not State.isPaused then
                pcall(sellAllFromUI)
            end
        end
    end)
end

----------------------------------------------------------------
-- AUTO BUY SYSTEM (Background)
----------------------------------------------------------------
local function purchasePickaxe(pickaxeName)
    if not PURCHASE_RF then
        warn("Purchase RF missing")
        return false
    end
    
    print(string.format("   🛒 Purchasing: %s", pickaxeName))
    
    local ok, res = pcall(function()
        return PURCHASE_RF:InvokeServer(pickaxeName, 1)
    end)
    
    if ok then
        print(string.format("   ✅ Purchased: %s!", pickaxeName))
        return true
    else
        warn(string.format("   ❌ Failed: %s", tostring(res)))
        return false
    end
end

local function unlockPosition()
    if State.positionLockConn then
        State.positionLockConn:Disconnect()
        State.positionLockConn = nil
        if DEBUG_MODE then
            print("   🔓 Position unlocked")
        end
    end
end

local function tryBuyPickaxe()
    local pickaxeName = QUEST_CONFIG.TARGET_PICKAXE or "Cobalt Pickaxe"

    -- 1) Check if already have Pickaxe
    if hasPickaxe(pickaxeName) then
        if DEBUG_MODE then
            print(string.format("[Q18] ✅ Already have %s - skip auto buy", pickaxeName))
        end
        return true
    end

    -- 2) Check Gold
    local gold = getGold()
    gold = gold or 0

    if gold < QUEST_CONFIG.MIN_GOLD_TO_BUY then
        if DEBUG_MODE then
            print(string.format(
                "[Q18] ⏸ Gold not enough for %s (have %d, need > %d)",
                pickaxeName,
                gold,
                QUEST_CONFIG.MIN_GOLD_TO_BUY
            ))
        end
        return false
    end

    -- 3) Pause mining and go to Shop
    print(string.format("\n🛒 [Q18] Auto Buy: Need %s! (Gold: %d)", pickaxeName, gold))

    local wasMining = IsMiningActive
    if wasMining then
        State.isPaused = true
        print("   ⏸️  Pausing mining...")

        if ToolController then
            ToolController.holdingM1 = false
        end

        unlockPosition()
        task.wait(1)
    end

    -- 4) Move to Shop
    local shopPos = QUEST_CONFIG.SHOP_POSITION
    print(string.format("   🚶 Going to shop (%.1f, %.1f, %.1f)...",
        shopPos.X, shopPos.Y, shopPos.Z))

    local done = false
    smoothMoveTo(shopPos, function()
        done = true
    end)

    local t0 = tick()
    while not done and tick() - t0 < 30 do
        task.wait(0.1)
    end

    if not done then
        warn("   ⚠️ Failed to reach shop!")
        if wasMining then
            State.isPaused = false
        end
        return false
    end

    print("   ✅ Arrived at shop!")
    task.wait(1)

    -- 5) Purchase
    local purchased = purchasePickaxe(pickaxeName)

    if purchased then
        print("   ✅ Purchase complete!")
        task.wait(2)
    else
        warn("   ❌ Purchase failed!")
    end

    -- 6) Resume Mining
    if wasMining then
        print("   ▶️  Resuming mining...")
        State.isPaused = false
    end

    return purchased
end

local function startAutoBuyTask()
    if not QUEST_CONFIG.AUTO_BUY_ENABLED or not PURCHASE_RF then
        return
    end
    
    print("🤖 Auto Buy Background Task Started!")
    
    State.autoBuyTask = task.spawn(function()
        while Quest19Active do
            task.wait(QUEST_CONFIG.AUTO_BUY_INTERVAL)
            
            if State.isPaused then
                continue
            end
            
            pcall(function()
                tryBuyPickaxe()
            end)
        end
    end)
end

----------------------------------------------------------------
-- MAGMA PICKAXE AUTO BUY SYSTEM (With Sell Weapons/Armor)
----------------------------------------------------------------
local UIController = nil
pcall(function()
    for _, v in pairs(getgc(true)) do
        if type(v) == "table" then
            if rawget(v, "Open") and rawget(v, "Close") and rawget(v, "Modules") then
                UIController = v
                break
            end
        end
    end
end)

local function openToolsMenu()
    if not UIController then return false end
    
    if UIController.Modules["Menu"] then
        pcall(function() UIController:Open("Menu") end)
        task.wait(0.5)
        
        local menuModule = UIController.Modules["Menu"]
        if menuModule.OpenTab then
            pcall(function() menuModule:OpenTab("Tools") end)
        elseif menuModule.SwitchTab then
            pcall(function() menuModule:SwitchTab("Tools") end)
        end
        
        task.wait(0.5)
        return true
    end
    
    return false
end

local function closeToolsMenu()
    if UIController and UIController.Close then
        pcall(function() UIController:Close("Menu") end)
        task.wait(0.3)
    end
end

-- Check if item is equipped (has "Unequip" button)
local function isItemEquippedFromUI(guid)
    local menuGui = playerGui:FindFirstChild("Menu")
    if not menuGui then return false end
    
    local toolsFrame = menuGui:FindFirstChild("Frame") and menuGui.Frame:FindFirstChild("Frame") 
                    and menuGui.Frame.Frame:FindFirstChild("Menus") 
                    and menuGui.Frame.Frame.Menus:FindFirstChild("Tools")
                    and menuGui.Frame.Frame.Menus.Tools:FindFirstChild("Frame")
    
    if not toolsFrame then return false end
    
    local itemFrame = toolsFrame:FindFirstChild(guid)
    if not itemFrame then return false end
    
    local equipButton = itemFrame:FindFirstChild("Equip")
    if not equipButton then return false end
    
    local textLabel = equipButton:FindFirstChild("TextLabel")
    if not textLabel or not textLabel:IsA("TextLabel") then return false end
    
    return textLabel.Text == "Unequip"
end

-- Get all non-equipped weapons and armor
local function getNonEquippedItems()
    if not PlayerController or not PlayerController.Replica then
        warn("   ⚠️ Replica not available!")
        return {}
    end
    
    local replica = PlayerController.Replica
    
    if not replica.Data or not replica.Data.Inventory or not replica.Data.Inventory.Equipments then
        warn("   ⚠️ Equipments not found in Replica!")
        return {}
    end
    
    print("   📂 Opening Tools menu to check equipped items...")
    openToolsMenu()
    task.wait(0.5)
    
    local equipments = replica.Data.Inventory.Equipments
    local items = {}
    
    for id, item in pairs(equipments) do
        if type(item) == "table" and item.Type and item.GUID then
            -- Skip Pickaxe (don't sell pickaxes)
            if string.find(item.Type, "Pickaxe") then
                continue
            end
            
            local guid = item.GUID
            local isEquipped = isItemEquippedFromUI(guid)
            
            if not isEquipped then
                table.insert(items, {
                    ID = id,
                    GUID = guid,
                    Type = item.Type,
                    Name = item.Name or item.Type,
                })
                print(string.format("      💰 Can sell: %s (GUID: %s)", item.Type, guid))
            else
                print(string.format("      ⚡ Equipped (skip): %s", item.Type))
            end
        end
    end
    
    closeToolsMenu()
    
    return items
end

-- Sell all non-equipped weapons and armor
local function sellAllNonEquippedItems()
    print("\n💰 Selling all non-equipped Weapons/Armor...")
    
    local items = getNonEquippedItems()
    
    if #items == 0 then
        print("   ⏭️  No items to sell!")
        return true
    end
    
    print(string.format("   📦 Found %d items to sell", #items))
    
    -- Build basket with all GUIDs
    local basket = {}
    for _, item in ipairs(items) do
        basket[item.GUID] = true
        print(string.format("      - %s", item.Type))
    end
    
    -- Sell using DialogueService
    local success = false
    pcall(function()
        success = DIALOGUE_RF:InvokeServer("SellConfirm", { Basket = basket })
    end)
    
    if success then
        print("   ✅ Sold all items successfully!")
        return true
    else
        warn("   ⚠️ Sell may have partially failed")
        return true -- Continue anyway
    end
end

-- Try to buy Magma Pickaxe (with sell items first)
local function tryBuyMagmaPickaxe()
    local config = QUEST_CONFIG.MAGMA_PICKAXE_CONFIG
    if not config or not config.ENABLED then return false end
    
    local pickaxeName = config.TARGET_PICKAXE or "Magma Pickaxe"

    -- 1) Check if already have Magma Pickaxe
    if hasPickaxe(pickaxeName) then
        if DEBUG_MODE then
            print(string.format("[Q19] ✅ Already have %s - skip auto buy", pickaxeName))
        end
        return true
    end

    -- 2) Check Gold
    local gold = getGold()
    gold = gold or 0

    if gold < config.MIN_GOLD_TO_BUY then
        if DEBUG_MODE then
            print(string.format(
                "[Q19] ⏸ Gold not enough for %s (have %d, need > %d)",
                pickaxeName,
                gold,
                config.MIN_GOLD_TO_BUY
            ))
        end
        return false
    end

    -- 3) Pause mining
    print(string.format("\n🛒 [Q19] Auto Buy Magma: Need %s! (Gold: %d)", pickaxeName, gold))

    local wasMining = IsMiningActive
    if wasMining then
        State.isPaused = true
        print("   ⏸️  Pausing mining...")

        if ToolController then
            ToolController.holdingM1 = false
        end

        unlockPosition()
        task.wait(1)
    end

    -- 4) Move to Sell Shop and sell all weapons/armor
    local sellShopPos = config.SELL_SHOP_POSITION
    print(string.format("   🚶 Going to sell shop (%.1f, %.1f, %.1f)...",
        sellShopPos.X, sellShopPos.Y, sellShopPos.Z))

    local done = false
    smoothMoveTo(sellShopPos, function()
        done = true
    end)

    local t0 = tick()
    while not done and tick() - t0 < 30 do
        task.wait(0.1)
    end

    if not done then
        warn("   ⚠️ Failed to reach sell shop!")
        if wasMining then State.isPaused = false end
        return false
    end

    print("   ✅ Arrived at sell shop!")
    task.wait(1)

    -- Sell all non-equipped items
    sellAllNonEquippedItems()
    task.wait(1)

    -- 5) Move to Buy Shop
    local buyShopPos = config.BUY_SHOP_POSITION
    print(string.format("   🚶 Going to Magma shop (%.1f, %.1f, %.1f)...",
        buyShopPos.X, buyShopPos.Y, buyShopPos.Z))

    done = false
    smoothMoveTo(buyShopPos, function()
        done = true
    end)

    t0 = tick()
    while not done and tick() - t0 < 60 do
        task.wait(0.1)
    end

    if not done then
        warn("   ⚠️ Failed to reach Magma shop!")
        if wasMining then State.isPaused = false end
        return false
    end

    print("   ✅ Arrived at Magma shop!")
    task.wait(1)

    -- 6) Purchase Magma Pickaxe
    local purchased = purchasePickaxe(pickaxeName)

    if purchased then
        print("   ✅ Magma Pickaxe purchased!")
        print("   🔄 Switching to Basalt Vein mining...")
        task.wait(2)
    else
        warn("   ❌ Purchase failed!")
    end

    -- 7) Resume Mining
    if wasMining then
        print("   ▶️  Resuming mining...")
        State.isPaused = false
    end

    return purchased
end

-- Background task for Magma Pickaxe
local function startMagmaBuyTask()
    local config = QUEST_CONFIG.MAGMA_PICKAXE_CONFIG
    if not config or not config.ENABLED or not PURCHASE_RF then
        return
    end
    
    print("🤖 Magma Pickaxe Auto Buy Task Started!")
    
    State.magmaBuyTask = task.spawn(function()
        while Quest19Active do
            task.wait(30) -- Check every 30 seconds
            
            if State.isPaused then
                continue
            end
            
            -- Only try if we have Cobalt Pickaxe already
            if hasPickaxe(QUEST_CONFIG.TARGET_PICKAXE) then
                pcall(function()
                    tryBuyMagmaPickaxe()
                end)
            end
        end
    end)
end

----------------------------------------------------------------
-- ISLAND DETECTION
----------------------------------------------------------------
local function getCurrentIsland()
    for _, child in ipairs(FORGES_FOLDER:GetChildren()) do
        if child:IsA("Folder") or child:IsA("Model") then
            if string.match(child.Name, "Island%d+") then
                return child.Name
            end
        end
    end
    return nil
end

local function needsTeleport()
    local currentIsland = getCurrentIsland()
    
    if not currentIsland then
        return true
    end
    
    if currentIsland == "Island1" then
        print(string.format("   ✅ On %s → Need teleport!", currentIsland))
        return true
    elseif currentIsland == "Island2" then
        print(string.format("   ✅ On %s → Ready to mine!", currentIsland))
        return false
    else
        warn(string.format("   ⚠️ Unknown: %s", currentIsland))
        return true
    end
end

----------------------------------------------------------------
-- LEVEL SYSTEM
----------------------------------------------------------------
local function getPlayerLevel()
    local levelLabel = playerGui:FindFirstChild("Main")
                      and playerGui.Main:FindFirstChild("Screen")
                      and playerGui.Main.Screen:FindFirstChild("Hud")
                      and playerGui.Main.Screen.Hud:FindFirstChild("Level")
    
    if not levelLabel or not levelLabel:IsA("TextLabel") then
        return nil
    end
    
    local levelText = levelLabel.Text
    local level = tonumber(string.match(levelText, "%d+"))
    
    return level
end

local function hasRequiredLevel()
    local level = getPlayerLevel()
    
    if not level then
        warn("   ❌ Cannot determine level!")
        return false
    end
    
    if level >= QUEST_CONFIG.REQUIRED_LEVEL then
        print(string.format("   ✅ Level %d >= %d", level, QUEST_CONFIG.REQUIRED_LEVEL))
        return true
    else
        print(string.format("   ⏸️  Level %d < %d", level, QUEST_CONFIG.REQUIRED_LEVEL))
        return false
    end
end

----------------------------------------------------------------
-- HELPER FUNCTIONS
----------------------------------------------------------------
local HOTKEY_MAP = {
    ["1"] = Enum.KeyCode.One,
    ["2"] = Enum.KeyCode.Two,
    ["3"] = Enum.KeyCode.Three,
    ["4"] = Enum.KeyCode.Four,
    ["5"] = Enum.KeyCode.Five,
    ["6"] = Enum.KeyCode.Six,
    ["7"] = Enum.KeyCode.Seven,
    ["8"] = Enum.KeyCode.Eight,
    ["9"] = Enum.KeyCode.Nine,
    ["0"] = Enum.KeyCode.Zero,
}

local function pressKey(keyCode)
    if not keyCode then return end
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

local function findPickaxeSlotKey()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end
    
    local hotbar = gui:FindFirstChild("BackpackGui") 
                   and gui.BackpackGui:FindFirstChild("Backpack") 
                   and gui.BackpackGui.Backpack:FindFirstChild("Hotbar")
    
    if hotbar then
        for _, slotFrame in ipairs(hotbar:GetChildren()) do
            local frame = slotFrame:FindFirstChild("Frame")
            local label = frame and frame:FindFirstChild("ToolName")
            if label and label:IsA("TextLabel") and string.find(label.Text, "Pickaxe") then
                return HOTKEY_MAP[slotFrame.Name]
            end
        end
    end
    
    return nil
end

local function checkMiningError()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return false end
    
    local notif = gui:FindFirstChild("Notifications")
    if notif and notif:FindFirstChild("Screen") and notif.Screen:FindFirstChild("NotificationsFrame") then
        for _, child in ipairs(notif.Screen.NotificationsFrame:GetChildren()) do
            local lbl = child:FindFirstChild("TextLabel", true)
            if lbl and string.find(lbl.Text, "Someone else is already mining") then
                return true
            end
        end
    end
    
    return false
end

----------------------------------------------------------------
-- POSITION LOCK
----------------------------------------------------------------
local function lockPositionLayingDown(targetPos)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    if State.positionLockConn then
        State.positionLockConn:Disconnect()
        State.positionLockConn = nil
    end
    
    local angle = math.rad(QUEST_CONFIG.LAYING_ANGLE)
    local baseCFrame = CFrame.new(targetPos)
    local layingCFrame = baseCFrame * CFrame.Angles(angle, 0, 0)
    
    State.positionLockConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hrp or not hrp.Parent then
            if State.positionLockConn then
                State.positionLockConn:Disconnect()
                State.positionLockConn = nil
            end
            return
        end
        
        hrp.CFrame = layingCFrame
        hrp.Velocity = Vector3.zero
        hrp.AssemblyLinearVelocity = Vector3.zero
    end)
    
    if DEBUG_MODE then
        print("   🔒 Position locked")
    end
end

local function transitionToNewTarget(newTargetPos)
    if State.positionLockConn then
        State.positionLockConn:Disconnect()
        State.positionLockConn = nil
    end
    
    local moveComplete = false
    smoothMoveTo(newTargetPos, function()
        lockPositionLayingDown(newTargetPos)
        moveComplete = true
    end)
    
    local timeout = 60
    local startTime = tick()
    while not moveComplete and tick() - startTime < timeout do
        task.wait(0.1)
    end
    
    if not moveComplete then
        warn("   ⚠️ Transition timeout!")
        return false
    end
    
    return true
end

----------------------------------------------------------------
-- TELEPORT SYSTEM
----------------------------------------------------------------
local function teleportToIsland(islandName)
    if not PORTAL_RF then
        warn("   ❌ Portal Remote not available!")
        return false
    end
    
    print(string.format("   🌀 Teleporting to: %s", islandName))
    
    local args = {islandName}
    
    local success, result = pcall(function()
        return PORTAL_RF:InvokeServer(unpack(args))
    end)
    
    if success then
        print(string.format("   ✅ Teleported to: %s", islandName))
        return true
    else
        warn(string.format("   ❌ Failed: %s", tostring(result)))
        return false
    end
end

----------------------------------------------------------------
-- ROCK HELPERS
----------------------------------------------------------------
local function getRockUndergroundPosition(rockModel)
    if not rockModel or not rockModel.Parent then
        return nil
    end
    
    local pivotCFrame = nil
    pcall(function()
        if rockModel.GetPivot then
            pivotCFrame = rockModel:GetPivot()
        elseif rockModel.WorldPivot then
            pivotCFrame = rockModel.WorldPivot
        end
    end)
    
    if pivotCFrame then
        local pos = pivotCFrame.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.UNDERGROUND_OFFSET, pos.Z)
    end
    
    if rockModel.PrimaryPart then
        local pos = rockModel.PrimaryPart.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.UNDERGROUND_OFFSET, pos.Z)
    end
    
    local part = rockModel:FindFirstChildWhichIsA("BasePart")
    if part then
        local pos = part.Position
        return Vector3.new(pos.X, pos.Y - QUEST_CONFIG.UNDERGROUND_OFFSET, pos.Z)
    end
    
    return nil
end

local function getRockHP(rock)
    if not rock or not rock.Parent then
        return 0
    end
    
    local success, result = pcall(function()
        return rock:GetAttribute("Health") or 0
    end)
    
    return success and result or 0
end

local function isTargetValid(rock)
    if not rock or not rock.Parent then
        return false
    end
    
    if not rock:FindFirstChildWhichIsA("BasePart") then
        return false
    end
    
    local hp = getRockHP(rock)
    return hp > 0
end

-- Get current rock name and paths based on pickaxe
local function getCurrentMiningConfig()
    local magmaPickaxe = QUEST_CONFIG.MAGMA_PICKAXE_CONFIG and QUEST_CONFIG.MAGMA_PICKAXE_CONFIG.TARGET_PICKAXE or "Magma Pickaxe"
    local cobaltPickaxe = QUEST_CONFIG.TARGET_PICKAXE or "Cobalt Pickaxe"
    
    -- Tier 3: Magma Pickaxe → Basalt Vein
    if hasPickaxe(magmaPickaxe) then
        print("   🔥 Have Magma Pickaxe → Mining Basalt Vein")
        return {
            ROCK_NAME = QUEST_CONFIG.BASALT_VEIN_CONFIG.ROCK_NAME,
            MINING_PATHS = QUEST_CONFIG.BASALT_VEIN_CONFIG.MINING_PATHS,
        }
    -- Tier 2: Cobalt Pickaxe → Basalt Core
    elseif hasPickaxe(cobaltPickaxe) then
        print("   💎 Have Cobalt Pickaxe → Mining Basalt Core")
        return {
            ROCK_NAME = QUEST_CONFIG.BASALT_CORE_CONFIG.ROCK_NAME,
            MINING_PATHS = QUEST_CONFIG.BASALT_CORE_CONFIG.MINING_PATHS,
        }
    -- Tier 1: Default → Basalt Rock
    else
        print("   ⛏️ No special Pickaxe → Mining Basalt Rock")
        return {
            ROCK_NAME = QUEST_CONFIG.ROCK_NAME,
            MINING_PATHS = QUEST_CONFIG.MINING_PATHS,
        }
    end
end

local function findNearestBasaltRock(excludeRock)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    cleanupExpiredBlacklist()
    
    -- Get current mining config based on pickaxe
    local miningConfig = getCurrentMiningConfig()
    local rockName = miningConfig.ROCK_NAME
    local miningPaths = miningConfig.MINING_PATHS
    
    local targetRock, minDist = nil, math.huge
    local skippedOccupied = 0
    
    for _, pathName in ipairs(miningPaths) do
        local folder = MINING_FOLDER_PATH:FindFirstChild(pathName)
        
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("SpawnLocation") or child.Name == "SpawnLocation" then
                    local rock = child:FindFirstChild(rockName)
                    
                    if rock and rock ~= excludeRock and isTargetValid(rock) then
                        if isRockOccupied(rock) then
                            skippedOccupied = skippedOccupied + 1
                        else
                            local pos = getRockUndergroundPosition(rock)
                            if pos then
                                local dist = (pos - hrp.Position).Magnitude
                                
                                if dist < minDist then
                                    minDist = dist
                                    targetRock = rock
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    if skippedOccupied > 0 then
        print(string.format("   ⏭️ Skipped %d occupied rocks (blacklisted)", skippedOccupied))
    end
    
    return targetRock, minDist, rockName
end

local function watchRockHP(rock)
    if State.hpWatchConn then
        State.hpWatchConn:Disconnect()
    end
    
    if not rock then return end
    
    State.hpWatchConn = rock:GetAttributeChangedSignal("Health"):Connect(function()
        local hp = rock:GetAttribute("Health") or 0
        
        if hp <= 0 then
            print("   ✅ Rock destroyed!")
            State.targetDestroyed = true
            
            if ToolController then
                ToolController.holdingM1 = false
            end
        end
    end)
end

----------------------------------------------------------------
-- MINING EXECUTION
----------------------------------------------------------------
local function doMineBasaltRock()
    -- Check pickaxe and determine rock type
    local miningConfig = getCurrentMiningConfig()
    local currentRockName = miningConfig.ROCK_NAME
    
    print("\n⛏️ Mining Started...")
    print(string.format("   🎯 Mining: %s", currentRockName))
    print(string.format("   Target: %d rocks", QUEST_CONFIG.MAX_ROCKS_TO_MINE))
    
    IsMiningActive = true
    
    local miningCount = 0
    
    print("\n" .. string.rep("=", 50))
    print(string.format("⛏️ Mining Loop (%s)...", currentRockName))
    print(string.rep("=", 50))
    
    while Quest18Active and miningCount < QUEST_CONFIG.MAX_ROCKS_TO_MINE do
        if State.isPaused then
            print("   ⏸️  Paused (Auto Buy running)...")
            task.wait(2)
            continue
        end
        
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        
        if not hrp then
            warn("   ⚠️ Waiting for character...")
            task.wait(2)
            continue
        end
        
        if not State.positionLockConn and not State.moveConn and not State.bodyVelocity then
            cleanupState()
        end
        
        local targetRock, dist, rockName = findNearestBasaltRock(State.currentTarget)
        
        if not targetRock then
            warn(string.format("   ❌ No %s found!", rockName or "rocks"))
            unlockPosition()
            cleanupState()
            task.wait(3)
            continue
        end
        
        local previousTarget = State.currentTarget
        State.currentTarget = targetRock
        State.targetDestroyed = false
        
        local targetPos = getRockUndergroundPosition(targetRock)
        
        if not targetPos then
            warn("   ❌ Cannot get position!")
            task.wait(1)
            continue
        end
        
        local currentHP = getRockHP(targetRock)
        
        print(string.format("\n🎯 Target #%d: %s (HP: %d, Dist: %.1f)", 
            miningCount + 1,
            targetRock.Parent.Parent.Name,
            currentHP, 
            dist))
        
        watchRockHP(targetRock)
        
        -- If we're locked to a DIFFERENT target, use smooth transition
        -- Otherwise, always use smoothMoveTo (even for same target after respawn)
        if State.positionLockConn and previousTarget and previousTarget ~= targetRock then
            print("   🔄 Transition to new target...")
            transitionToNewTarget(targetPos)
        else
            -- Unlock any existing position lock first
            if State.positionLockConn then
                unlockPosition()
            end
            
            local moveStarted = false
            smoothMoveTo(targetPos, function()
                lockPositionLayingDown(targetPos)
                moveStarted = true
            end)
            
            local timeout = 60
            local startTime = tick()
            while not moveStarted and tick() - startTime < timeout do
                task.wait(0.1)
            end
            
            if not moveStarted then
                warn("   ⚠️ Move timeout, skip this rock")
                State.targetDestroyed = true
                unlockPosition()
                continue
            end
        end
        
        task.wait(0.5)
        
        while not State.targetDestroyed and Quest18Active and not State.isPaused do
            if not char or not char.Parent then
                break
            end
            
            if not targetRock or not targetRock.Parent then
                State.targetDestroyed = true
                break
            end
            
            if checkMiningError() then
                print("   ⚠️ Someone else mining! Switching target...")
                markRockAsOccupied(targetRock)
                State.targetDestroyed = true
                if ToolController then
                    ToolController.holdingM1 = false
                end
                break
            end
            
            local toolInHand = char:FindFirstChildWhichIsA("Tool")
            local isPickaxeHeld = toolInHand and string.find(toolInHand.Name, "Pickaxe")
            
            if not isPickaxeHeld then
                if ToolController then
                    ToolController.holdingM1 = false
                end
                
                local key = findPickaxeSlotKey()
                if key then
                    pressKey(key)
                    task.wait(0.3)
                else
                    pcall(function()
                        if PlayerController and PlayerController.Replica then
                            local replica = PlayerController.Replica
                            if replica.Data and replica.Data.Inventory and replica.Data.Inventory.Equipments then
                                for id, item in pairs(replica.Data.Inventory.Equipments) do
                                    if type(item) == "table" and item.Type and string.find(item.Type, "Pickaxe") then
                                        CHAR_RF:InvokeServer({Runes = {}}, item)
                                        break
                                    end
                                end
                            end
                        end
                    end)
                    task.wait(0.5)
                end
            else
                if ToolController and ToolActivatedFunc then
                    ToolController.holdingM1 = true
                    pcall(function()
                        ToolActivatedFunc(ToolController, toolInHand)
                    end)
                else
                    pcall(function()
                        TOOL_RF_BACKUP:InvokeServer(toolInHand.Name, true)
                    end)
                end
            end
            
            task.wait(0.15)
        end
        
        if State.targetDestroyed then
            miningCount = miningCount + 1
        end
        
        if QUEST_CONFIG.HOLD_POSITION_AFTER_MINE then
            print("   ⏸️  Holding position, searching for next target...")
        else
            unlockPosition()
        end
        
        task.wait(0.5)
    end
    
    print("\n" .. string.rep("=", 50))
    print("✅ Mining ended")
    print(string.rep("=", 50))
    
    IsMiningActive = false
    unlockPosition()
    disableNoclip()
    cleanupState()
end

----------------------------------------------------------------
-- SMART QUEST RUNNER
----------------------------------------------------------------
print(string.rep("=", 50))
print("🚀 QUEST 19: " .. QUEST_CONFIG.QUEST_NAME)
print("🎯 Objective: Mining + Auto Sell & Buy")
print(string.rep("=", 50))

-- Check Level
print("\n🔍 Pre-check: Verifying level requirement...")
if not hasRequiredLevel() then
    print("\n❌ Level requirement not met!")
    print(string.rep("=", 50))
    cleanupState()
    disableNoclip()
    return
end

-- Priority 1: Auto Sell Init
print("\n🔍 Priority 1: Auto Sell Initialization...")
if QUEST_CONFIG.AUTO_SELL_ENABLED then
    if not AutoSellInitialized then
        local success = initAutoSellWithNPC()
        if not success then
            warn("   ⚠️ Auto Sell Init Failed - Skipping")
        end
    else
        print("   ✅ Auto Sell already initialized")
    end
end

-- Priority 2: Background Tasks
print("\n🔍 Priority 2: Starting Background Tasks...")
startAutoSellTask()
startAutoBuyTask()
startMagmaBuyTask()

-- Priority 3: Mining
print("\n🔍 Priority 3: Starting Mining...")
doMineBasaltRock()

Quest19Active = false
cleanupState()
disableNoclip()

end


----------------------------------------------------------------
-- ⛏️ نظام التنجيم التلقائي (Auto-Mining System)
----------------------------------------------------------------
Shared.AutoMine = {}
Shared.AutoMine.IsActive = false
Shared.AutoMine.TargetRockName = "Boulder"
Shared.AutoMine.MiningLoop = nil

local MINING_CONFIG = {
    UNDERGROUND_OFFSET = 4,
    LAYING_ANGLE = 90,
    MOVE_SPEED = 25,
    RESPAWN_WAIT_TIME = 3,
    OCCUPIED_TIMEOUT = 10,
}

local OccupiedRocks = {}

local function isRockOccupied(rock)
    if not rock then return false end
    local expireTime = OccupiedRocks[rock]
    if not expireTime then return false end
    
    if tick() > expireTime then
        OccupiedRocks[rock] = nil
        return false
    end
    return true
end

local function markRockAsOccupied(rock)
    if not rock then return end
    OccupiedRocks[rock] = tick() + MINING_CONFIG.OCCUPIED_TIMEOUT
    print(string.format("   🚫 [AutoMine] أضيف إلى القائمة السوداء لـ %d ثانية: %s", MINING_CONFIG.OCCUPIED_TIMEOUT, rock.Name))
end

local function cleanupExpiredBlacklist()
    local now = tick()
    for rock, expireTime in pairs(OccupiedRocks) do
        if now > expireTime or not rock.Parent then
            OccupiedRocks[rock] = nil
        end
    end
end

local function findNearestRock(rockName, excludeRock)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    cleanupExpiredBlacklist()
    
    local targetRock, minDist = nil, math.huge
    local MINING_FOLDER_PATH = Workspace:FindFirstChild("Rocks")
    if not MINING_FOLDER_PATH then return nil end
    
    for _, folder in ipairs(MINING_FOLDER_PATH:GetChildren()) do
        if folder:IsA("Folder") or folder:IsA("Model") then
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("SpawnLocation") or child.Name == "SpawnLocation" then
                    local rock = child:FindFirstChild(rockName)
                    
                    if rock and rock ~= excludeRock and Shared.isRockValid(rock) then
                        if isRockOccupied(rock) then
                            -- تخطي الصخور المشغولة
                        else
                            local pos = Shared.getRockUndergroundPosition(rock, MINING_CONFIG.UNDERGROUND_OFFSET)
                            if pos then
                                local dist = (pos - hrp.Position).Magnitude
                                
                                if dist < minDist then
                                    minDist = dist
                                    targetRock = rock
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return targetRock, minDist
end

local function watchRockHP(rock)
    Shared.cleanupState() -- تنظيف أي اتصالات سابقة
    
    if not rock then return end
    
    Shared.State.hpWatchConn = rock:GetAttributeChangedSignal("Health"):Connect(function()
        local hp = rock:GetAttribute("Health") or 0
        
        if hp <= 0 then
            print("   ✅ [AutoMine] تم تدمير الصخرة!")
            Shared.State.targetDestroyed = true
            
            -- إيقاف محاكاة النقر
            if Shared.ToolController then
                Shared.ToolController.holdingM1 = false
            end
        end
    end)
end

function Shared.AutoMine.Start(rockName)
    if Shared.AutoMine.IsActive then return end
    Shared.AutoMine.IsActive = true
    Shared.AutoMine.TargetRockName = rockName or "Boulder"
    
    Shared.AutoMine.MiningLoop = task.spawn(function()
        while Shared.AutoMine.IsActive do
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            
            if not hrp then
                warn("   ⚠️ [AutoMine] انتظار الشخصية...")
                task.wait(2)
                goto continue_loop
            end
            
            Shared.cleanupState()
            
            -- 1. البحث عن أقرب صخرة
            local targetRock, dist = findNearestRock(Shared.AutoMine.TargetRockName, Shared.State.currentTarget)
            
            if not targetRock then
                warn("   ❌ [AutoMine] لم يتم العثور على صخرة، جاري الانتظار...")
                Shared.unlockPosition()
                task.wait(MINING_CONFIG.RESPAWN_WAIT_TIME)
                goto continue_loop
            end
            
            Shared.State.currentTarget = targetRock
            Shared.State.targetDestroyed = false
            
            -- 2. الحصول على موقع التنجيم
            local targetPos = Shared.getRockUndergroundPosition(targetRock, MINING_CONFIG.UNDERGROUND_OFFSET)
            
            if not targetPos then
                warn("   ❌ [AutoMine] لا يمكن الحصول على موقع الصخرة!")
                task.wait(1)
                goto continue_loop
            end
            
            print(string.format("\n🎯 [AutoMine] الهدف: %s (HP: %d, Dist: %.1f)", 
                targetRock.Name,
                Shared.getRockHP(targetRock), 
                dist))
            
            -- 3. مراقبة نقاط الحياة
            watchRockHP(targetRock)
            
            -- 4. التحرك إلى الصخرة وقفل الموقع
            local moveComplete = false
            Shared.smoothMoveTo(targetPos, 2, MINING_CONFIG.MOVE_SPEED, function()
                Shared.lockPositionLayingDown(targetPos, MINING_CONFIG.LAYING_ANGLE)
                moveComplete = true
            end)
            
            local timeout = 60
            local startTime = tick()
            while not moveComplete and tick() - startTime < timeout do
                task.wait(0.1)
            end
            
            if not moveComplete then
                warn("   ⚠️ [AutoMine] انتهت مهلة الحركة، تخطي هذه الصخرة.")
                Shared.State.targetDestroyed = true
                Shared.unlockPosition()
                goto continue_loop
            end
            
            task.wait(0.5)
            
            -- 5. بدء التنجيم
            while Shared.AutoMine.IsActive and not Shared.State.targetDestroyed do
                if not char or not char.Parent then
                    print("   ❌ [AutoMine] ماتت الشخصية!")
                    break
                end
                
                if not targetRock or not targetRock.Parent then
                    print("   ✅ [AutoMine] تمت إزالة الهدف!")
                    Shared.State.targetDestroyed = true
                    break
                end
                
                if Shared.checkMiningError() then
                    print("   ⚠️ [AutoMine] شخص آخر ينقب! جاري تبديل الهدف...")
                    markRockAsOccupied(targetRock)
                    Shared.State.targetDestroyed = true
                    if Shared.ToolController then
                        Shared.ToolController.holdingM1 = false
                    end
                    break
                end
                
                local toolInHand = char:FindFirstChildWhichIsA("Tool")
                local isPickaxeHeld = toolInHand and string.find(toolInHand.Name, "Pickaxe")
                
                if not isPickaxeHeld then
                    if Shared.ToolController then
                        Shared.ToolController.holdingM1 = false
                    end
                    
                    local key = Shared.findPickaxeSlotKey()
                    if key then
                        Shared.pressKey(key)
                        task.wait(0.3)
                    else
                        warn("   ❌ [AutoMine] لم يتم العثور على معول في شريط الأدوات!")
                        task.wait(1)
                    end
                else
                    if Shared.ToolController and Shared.ToolActivatedFunc then
                        Shared.ToolController.holdingM1 = true
                        pcall(function()
                            Shared.ToolActivatedFunc(Shared.ToolController, toolInHand)
                        end)
                    else
                        -- استخدام RemoteFunction احتياطي
                        local TOOL_RF_BACKUP = Services.ReplicatedStorage:FindFirstChild("Shared")
                            and Services.ReplicatedStorage.Shared:FindFirstChild("Packages")
                            and Services.ReplicatedStorage.Shared.Packages:FindFirstChild("Knit")
                            and Services.ReplicatedStorage.Shared.Packages.Knit.Services:FindFirstChild("ToolService")
                            and Services.ReplicatedStorage.Shared.Packages.Knit.Services.ToolService:FindFirstChild("RF")
                            and Services.ReplicatedStorage.Shared.Packages.Knit.Services.ToolService.RF:FindFirstChild("ToolActivated")
                        
                        if TOOL_RF_BACKUP then
                            pcall(function()
                                TOOL_RF_BACKUP:InvokeServer(toolInHand.Name, true)
                            end)
                        end
                    end
                end
                
                task.wait(0.15)
            end
            
            ::continue_loop::
            task.wait(0.1)
        end
    end)
end

function Shared.AutoMine.Stop()
    Shared.AutoMine.IsActive = false
    if Shared.AutoMine.MiningLoop then
        task.cancel(Shared.AutoMine.MiningLoop)
        Shared.AutoMine.MiningLoop = nil
    end
    Shared.cleanupState()
    Shared.disableNoclip()
    print("✅ [AutoMine] تم إيقاف التنجيم التلقائي.")
end

----------------------------------------------------------------
-- ⚔️ نظام القتال التلقائي (Auto-Farm System)
----------------------------------------------------------------
Shared.AutoFarm = {}
Shared.AutoFarm.IsActive = false
Shared.AutoFarm.TargetEnemyName = "Zombie" -- افتراضي
Shared.AutoFarm.FarmingLoop = nil

local FARMING_CONFIG = {
    UNDERGROUND_OFFSET = 5,
    MOVE_SPEED = 25,
    RESPAWN_WAIT_TIME = 5,
}

local function findNearestEnemy(enemyName)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local targetEnemy, minDist = nil, math.huge
    local ENEMIES_FOLDER_PATH = Workspace:FindFirstChild("Enemies")
    if not ENEMIES_FOLDER_PATH then return nil end
    
    for _, enemy in ipairs(ENEMIES_FOLDER_PATH:GetChildren()) do
        if enemy:IsA("Model") and enemy.Name == enemyName then
            if Shared.isZombieValid(enemy) then
                local enemyHRP = enemy:FindFirstChild("HumanoidRootPart")
                if enemyHRP then
                    local dist = (enemyHRP.Position - hrp.Position).Magnitude
                    if dist < minDist then
                        minDist = dist
                        targetEnemy = enemy
                    end
                end
            end
        end
    end
    
    return targetEnemy, minDist
end

local function watchEnemyHP(enemy)
    Shared.cleanupState()
    
    if not enemy then return end
    
    local humanoid = enemy:FindFirstChild("Humanoid")
    if not humanoid then return end
    
    Shared.State.hpWatchConn = humanoid:GetPropertyChangedSignal("Health"):Connect(function()
        if humanoid.Health <= 0 then
            print("   ✅ [AutoFarm] تم تدمير العدو!")
            Shared.State.targetDestroyed = true
            
            if Shared.ToolController then
                Shared.ToolController.holdingM1 = false
            end
        end
    end)
end

function Shared.AutoFarm.Start(enemyName)
    if Shared.AutoFarm.IsActive then return end
    Shared.AutoFarm.IsActive = true
    Shared.AutoFarm.TargetEnemyName = enemyName or "Zombie"
    
    Shared.AutoFarm.FarmingLoop = task.spawn(function()
        while Shared.AutoFarm.IsActive do
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            
            if not hrp then
                warn("   ⚠️ [AutoFarm] انتظار الشخصية...")
                task.wait(2)
                goto continue_loop
            end
            
            Shared.cleanupState()
            
            -- 1. البحث عن أقرب عدو
            local targetEnemy, dist = findNearestEnemy(Shared.AutoFarm.TargetEnemyName)
            
            if not targetEnemy then
                warn("   ❌ [AutoFarm] لم يتم العثور على عدو، جاري الانتظار...")
                Shared.unlockPosition()
                task.wait(FARMING_CONFIG.RESPAWN_WAIT_TIME)
                goto continue_loop
            end
            
            Shared.State.currentTarget = targetEnemy
            Shared.State.targetDestroyed = false
            
            -- 2. الحصول على موقع القتال (تحت الأرض)
            local targetPos = Shared.getZombieUndergroundPosition(targetEnemy, FARMING_CONFIG.UNDERGROUND_OFFSET)
            
            if not targetPos then
                warn("   ❌ [AutoFarm] لا يمكن الحصول على موقع العدو!")
                task.wait(1)
                goto continue_loop
            end
            
            print(string.format("\n🎯 [AutoFarm] الهدف: %s (HP: %d, Dist: %.1f)", 
                targetEnemy.Name,
                Shared.getZombieHP(targetEnemy), 
                dist))
            
            -- 3. مراقبة نقاط الحياة
            watchEnemyHP(targetEnemy)
            
            -- 4. التحرك إلى العدو وقفل الموقع
            local moveComplete = false
            Shared.smoothMoveTo(targetPos, 2, FARMING_CONFIG.MOVE_SPEED, function()
                Shared.lockPositionLayingDown(targetPos, MINING_CONFIG.LAYING_ANGLE)
                moveComplete = true
            end)
            
            local timeout = 60
            local startTime = tick()
            while not moveComplete and tick() - startTime < timeout do
                task.wait(0.1)
            end
            
            if not moveComplete then
                warn("   ⚠️ [AutoFarm] انتهت مهلة الحركة، تخطي هذا العدو.")
                Shared.State.targetDestroyed = true
                Shared.unlockPosition()
                goto continue_loop
            end
            
            task.wait(0.5)
            
            -- 5. بدء القتال
            while Shared.AutoFarm.IsActive and not Shared.State.targetDestroyed do
                if not char or not char.Parent then
                    print("   ❌ [AutoFarm] ماتت الشخصية!")
                    break
                end
                
                if not targetEnemy or not targetEnemy.Parent then
                    print("   ✅ [AutoFarm] تمت إزالة الهدف!")
                    Shared.State.targetDestroyed = true
                    break
                end
                
                local toolInHand = char:FindFirstChildWhichIsA("Tool")
                local key, weaponName = Shared.findWeaponSlotKey()
                
                if not toolInHand or toolInHand.Name ~= weaponName then
                    if Shared.ToolController then
                        Shared.ToolController.holdingM1 = false
                    end
                    
                    if key then
                        Shared.pressKey(key)
                        task.wait(0.3)
                    else
                        warn("   ❌ [AutoFarm] لم يتم العثور على سلاح في شريط الأدوات!")
                        task.wait(1)
                    end
                else
                    if Shared.ToolController and Shared.ToolActivatedFunc then
                        Shared.ToolController.holdingM1 = true
                        pcall(function()
                            Shared.ToolActivatedFunc(Shared.ToolController, toolInHand)
                        end)
                    else
                        -- استخدام RemoteFunction احتياطي
                        local TOOL_RF_BACKUP = Services.ReplicatedStorage:FindFirstChild("Shared")
                            and Services.ReplicatedStorage.Shared:FindFirstChild("Packages")
                            and Services.ReplicatedStorage.Shared.Packages:FindFirstChild("Knit")
                            and Services.ReplicatedStorage.Shared.Packages.Knit.Services:FindFirstChild("ToolService")
                            and Services.ReplicatedStorage.Shared.Packages.Knit.Services.ToolService:FindFirstChild("RF")
                            and Services.ReplicatedStorage.Shared.Packages.Knit.Services.ToolService.RF:FindFirstChild("ToolActivated")
                        
                        if TOOL_RF_BACKUP then
                            pcall(function()
                                TOOL_RF_BACKUP:InvokeServer(toolInHand.Name, true)
                            end)
                        end
                    end
                end
                
                task.wait(0.15)
            end
            
            ::continue_loop::
            task.wait(0.1)
        end
    end)
end

function Shared.AutoFarm.Stop()
    Shared.AutoFarm.IsActive = false
    if Shared.AutoFarm.FarmingLoop then
        task.cancel(Shared.AutoFarm.FarmingLoop)
        Shared.AutoFarm.FarmingLoop = nil
    end
    Shared.cleanupState()
    Shared.disableNoclip()
    print("✅ [AutoFarm] تم إيقاف القتال التلقائي.")
end
