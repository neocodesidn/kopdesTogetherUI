-- Kopdes Together v2.2 | WindUI Edition
-- Core API dan Event Bus dipertahankan agar plugin lama tetap kompatibel.

-- ==========================================
-- GAME RESTRICTION
-- Hentikan eksekusi sebelum memuat UI/plugin jika bukan game target.
-- ==========================================
local SUPPORTED_PLACE_ID = 102028200883125

if game.PlaceId ~= SUPPORTED_PLACE_ID then
    local StarterGui = game:GetService("StarterGui")
    local message = "Kopdes Together hanya dapat digunakan di game Kopdes Together."

    -- SetCore terkadang belum siap tepat saat script mulai dijalankan.
    task.spawn(function()
        for _ = 1, 5 do
            local ok = pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = "Unsupported Game",
                    Text = message,
                    Duration = 5,
                })
            end)
            if ok then return end
            task.wait(1)
        end
        warn("[Kopdes Together] Unsupported Game | PlaceId: " .. tostring(game.PlaceId))
    end)

    return
end

local WindUI = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/download/1.6.66/main.lua"
))()

local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ==========================================
-- KONFIGURASI REPOSITORY PLUGIN
-- ==========================================
local REPO_PLUGINS = "https://raw.githubusercontent.com/neocodesidn/kopdesTogether/main/plugins/"

local DaftarPlugin = {
    { id = "restok",        name = "Auto Restok (Gudang-Safe)",    file = "auto_restok.lua" },
    { id = "payroll",       name = "Auto Payroll & Deposit",       file = "auto_payroll.lua" },
    { id = "smart_payroll", name = "Smart Payroll (Profit Share)", file = "smart_payroll.lua" },
    { id = "quest",         name = "Auto Claim Quest",             file = "auto_quest.lua" },
    { id = "webhook",       name = "Discord Webhook V2",           file = "discord_log.lua" },
}

-- ==========================================
-- WINDUI WINDOW
-- ==========================================
local Window = WindUI:CreateWindow({
    Title = "Kopdes Together",
    Author = "Cheese Dev • Modular Suite",
    Icon = "landmark",
    Theme = "Dark",
    Folder = "KopdesTogether",
    Size = UDim2.fromOffset(620, 520),
    MinSize = Vector2.new(320, 360),
    Resizable = true,
    SideBarWidth = 190,
    HideSearchBar = false,
    ScrollBarEnabled = true,
    OpenButton = { Enabled = true },
})

Window:Tag({ Title = "v2.2", Color = Color3.fromRGB(74, 144, 226) })
Window:Tag({ Title = "MODULAR", Color = "#22A06B" })

-- ==========================================
-- SHARED CORE API & EVENT BUS UNTUK PLUGIN
-- ==========================================
local EventListeners = {}
local LoadedPlugins = {}
local ActiveContainers = setmetatable({}, { __mode = "k" })

local function formatRupiah(angka)
    local formatted = tostring(math.floor(tonumber(angka) or 0))
    while true do
        local k
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1.%2")
        if k == 0 then break end
    end
    return formatted
end

local KopdesAPI = {
    Version = "2.2",
    WindUI = WindUI,
    Window = Window,
    Players = Players,
    LocalPlayer = LocalPlayer,
    PlayerGui = PlayerGui,
    HttpService = HttpService,
    Plot = workspace:WaitForChild("Plot1"),
    Remotes = {
        Kardus = ReplicatedStorage:WaitForChild("KardusRemotes"),
        Bank = ReplicatedStorage:WaitForChild("BankRemotes"),
        Quest = ReplicatedStorage:WaitForChild("QuestRemotes"),
    },
    FormatRupiah = formatRupiah,
}

function KopdesAPI.On(eventName, callback)
    EventListeners[eventName] = EventListeners[eventName] or {}
    table.insert(EventListeners[eventName], callback)
end

function KopdesAPI.Emit(eventName, data)
    local listeners = EventListeners[eventName]
    if not listeners then return end
    for _, callback in ipairs(listeners) do
        task.spawn(function()
            local ok, err = pcall(callback, data)
            if not ok then warn("[Kopdes EventBus] " .. tostring(err)) end
        end)
    end
end

function KopdesAPI.Notify(title, content, duration)
    pcall(function()
        WindUI:Notify({
            Title = tostring(title or "Kopdes Together"),
            Content = tostring(content or ""),
            Duration = duration or 3,
        })
    end)
end

function KopdesAPI.CreateTab(name, icon)
    local ok, tab = pcall(function()
        return Window:Tab({ Title = name, Icon = icon or "layout-dashboard" })
    end)
    if ok and tab then
        ActiveContainers[tab] = tab
        return tab
    end
    warn("[Kopdes UI] Gagal membuat tab " .. tostring(name) .. ": " .. tostring(tab))
    return nil
end

-- API.Section memilih container section untuk elemen berikutnya pada tab itu.
function KopdesAPI.Section(tab, title)
    if not tab then return nil end
    local ok, section = pcall(function()
        return tab:Section({
            Title = title,
            Box = true,
            BoxBorder = true,
            Opened = true,
        })
    end)
    if ok and section then
        ActiveContainers[tab] = section
        return section
    end
    ActiveContainers[tab] = tab
    warn("[Kopdes UI] Section fallback ke tab: " .. tostring(title))
    return tab
end

local function getContainer(tab)
    return ActiveContainers[tab] or tab
end

function KopdesAPI.Paragraph(tab, title, content)
    local ok, element = pcall(function()
        return getContainer(tab):Paragraph({
            Title = tostring(title or "Informasi"),
            Desc = tostring(content or ""),
        })
    end)
    if ok then return element end
    warn("[Kopdes UI] Paragraph gagal: " .. tostring(element))
    return nil
end

function KopdesAPI.Button(tab, name, callback)
    return getContainer(tab):Button({
        Title = name,
        Callback = callback,
    })
end

function KopdesAPI.Toggle(tab, name, defaultVal, callback)
    return getContainer(tab):Toggle({
        Title = name,
        Value = defaultVal == true,
        Callback = callback,
    })
end

function KopdesAPI.Slider(tab, name, minVal, maxVal, inc, suffix, defaultVal, callback)
    return getContainer(tab):Slider({
        Title = name,
        Value = { Min = minVal, Max = maxVal, Default = defaultVal or minVal },
        Step = inc or 1,
        Suffix = suffix or "",
        Callback = callback,
    })
end

function KopdesAPI.Dropdown(tab, name, options, defaultOpt, callback)
    return getContainer(tab):Dropdown({
        Title = name,
        Values = options or {},
        Value = defaultOpt or (options and options[1]),
        SearchBarEnabled = true,
        AllowNone = true,
        Callback = function(selected)
            local value = (typeof(selected) == "table" and (selected.Title or selected[1])) or selected
            if callback then callback(value) end
        end,
    })
end

function KopdesAPI.Input(tab, name, placeholder, callback)
    return getContainer(tab):Input({
        Title = name,
        Placeholder = placeholder or "",
        Callback = callback,
    })
end

function KopdesAPI.SetElementText(element, newText, newContent)
    if not element then return end
    pcall(function()
        if newContent ~= nil then
            if element.SetTitle then element:SetTitle(tostring(newText)) end
            if element.SetDesc then element:SetDesc(tostring(newContent)) end
            if element.Set then
                element:Set({ Title = tostring(newText), Desc = tostring(newContent) })
            end
        elseif element.Set then
            element:Set(newText)
        elseif element.SetTitle then
            element:SetTitle(tostring(newText))
        end
    end)
end

-- ==========================================
-- ANTI-AFK GLOBAL
-- ==========================================
local antiAfkEnabled = true
LocalPlayer.Idled:Connect(function()
    if antiAfkEnabled then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end)

-- ==========================================
-- TAB DASHBOARD
-- ==========================================
local HomeTab = KopdesAPI.CreateTab("Dashboard", "layout-dashboard")

KopdesAPI.Section(HomeTab, "Live Status Koperasi")
local StatusCard = KopdesAPI.Paragraph(
    HomeTab,
    "Memuat Data Koperasi...",
    "Menghubungkan ke server Bank & Plot1..."
)

KopdesAPI.Section(HomeTab, "Sistem & Keamanan AFK")
KopdesAPI.Toggle(HomeTab, "Anti-AFK (Cegah Kick 20 Menit)", true, function(value)
    antiAfkEnabled = value
end)

KopdesAPI.Button(HomeTab, "Salin Link Discord Cheese Dev", function()
    if setclipboard then
        setclipboard("https://cheesedev.biz.id")
        KopdesAPI.Notify("Tersalin!", "https://cheesedev.biz.id disalin ke clipboard.", 3)
    else
        KopdesAPI.Notify("Clipboard Tidak Tersedia", "Executor tidak menyediakan setclipboard.", 3)
    end
end)

-- ==========================================
-- FUNGSI PEMUAT PLUGIN
-- ==========================================
local function muatPluginDariUrl(pluginName, url)
    local okGet, source = pcall(function()
        return game:HttpGet(url .. (url:find("?", 1, true) and "&" or "?") .. "t=" .. tostring(os.time()))
    end)
    if not okGet or not source or source == "" or source:find("404: Not Found", 1, true) then
        return false, "File tidak ditemukan atau gagal diunduh"
    end

    local fn, errCompile = loadstring(source)
    if not fn then return false, "Syntax Error: " .. tostring(errCompile) end

    local okRun, errRun = pcall(fn, KopdesAPI)
    if not okRun then return false, "Runtime Error: " .. tostring(errRun) end
    return true, "Aktif"
end

local ringkasanPlugin = {}
for _, info in ipairs(DaftarPlugin) do
    local ok, status = muatPluginDariUrl(info.name, REPO_PLUGINS .. info.file)
    LoadedPlugins[info.id] = { name = info.name, ok = ok, status = status }
    table.insert(ringkasanPlugin, (ok and "● " or "○ ") .. info.name .. " — " .. status)
end

KopdesAPI.Section(HomeTab, "Plugin Manager")
KopdesAPI.Paragraph(
    HomeTab,
    "Modul Terpasang (" .. #DaftarPlugin .. " Plugin)",
    table.concat(ringkasanPlugin, "\n")
)

local customPluginUrl = ""
KopdesAPI.Input(HomeTab, "Load Custom Plugin via URL (.lua)", "https://raw.githubusercontent.com/...", function(value)
    customPluginUrl = value
end)

KopdesAPI.Button(HomeTab, "Jalankan Custom Plugin", function()
    if customPluginUrl == "" or not customPluginUrl:find("^https?://") then
        KopdesAPI.Notify("URL Tidak Valid", "Masukkan link raw .lua yang valid.", 3)
        return
    end
    local ok, status = muatPluginDariUrl("Custom Plugin", customPluginUrl)
    KopdesAPI.Notify(ok and "Plugin Dimuat!" or "Gagal Memuat Plugin", status, 4)
end)

-- ==========================================
-- LOOP LIVE DASHBOARD (UPDATE TIAP 4 DETIK)
-- ==========================================
local GetStateRemote = KopdesAPI.Remotes.Bank:WaitForChild("GetState")
local clickObject = KopdesAPI.Plot:WaitForChild("ClickObject")

task.spawn(function()
    while true do
        local saldoTokoText, saldoUserText = "-", "-"
        local okState, state = pcall(function()
            return GetStateRemote:InvokeServer()
        end)
        if okState and typeof(state) == "table" then
            if typeof(state.shopBalance) == "number" then
                saldoTokoText = "Rp " .. formatRupiah(state.shopBalance)
            end
            if typeof(state.userBalance) == "number" then
                saldoUserText = "Rp " .. formatRupiah(state.userBalance)
            end
        end

        local hariText = "Memantau..."
        for _, obj in ipairs(PlayerGui:GetDescendants()) do
            if obj:IsA("TextLabel") and obj.Text:match("^Hari%s*%d+") then
                hariText = obj.Text
                break
            end
        end

        local totalKardus = 0
        for _, obj in ipairs(clickObject:GetChildren()) do
            if obj.Name == "Kardus" then totalKardus = totalKardus + 1 end
        end

        KopdesAPI.SetElementText(
            StatusCard,
            hariText .. "  •  Kardus Area: " .. totalKardus,
            "Kas Toko: " .. saldoTokoText .. "\nSaldo Pribadi: " .. saldoUserText
        )
        task.wait(4)
    end
end)
