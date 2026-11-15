local API = ...

local BeliProductRemote = API.Remotes.Kardus:WaitForChild("BeliProduct")
local clickObject = API.Plot:WaitForChild("ClickObject")

local autoRestokEnabled = false
local namaItem = "Bebelove"
local jumlahBeli = 10
local sudahBeli = false

local function ambilPosisiObjek(obj)
    if obj:IsA("BasePart") then
        return obj.Position
    elseif obj:IsA("Model") then
        local ok, cf = pcall(function() return obj:GetPivot() end)
        if ok and cf then return cf.Position end
        local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
        if part then return part.Position end
    end
    return nil
end

local function apakahKardusDiRakGudang(kardus)
    local curr = kardus.Parent
    while curr and curr ~= workspace do
        if curr.Name:lower():find("gudang") then
            return true
        end
        curr = curr.Parent
    end

    if kardus:GetAttribute("InGudang") == true
        or kardus:GetAttribute("Stored") == true
        or kardus:GetAttribute("IsStored") == true then
        return true
    end

    local posKardus = ambilPosisiObjek(kardus)
    if not posKardus then return false end

    for _, obj in ipairs(API.Plot:GetDescendants()) do
        if (obj:IsA("Model") or obj:IsA("BasePart")) and obj.Name:lower():find("gudang") then
            local cf, size
            if obj:IsA("Model") then
                local ok, boxCF, boxSize = pcall(function() return obj:GetBoundingBox() end)
                if ok then cf, size = boxCF, boxSize end
            else
                cf, size = obj.CFrame, obj.Size
            end

            if cf and size then
                local rel = cf:PointToObjectSpace(posKardus)
                local tol = 1.5
                if math.abs(rel.X) <= (size.X / 2 + tol)
                    and math.abs(rel.Y) <= (size.Y / 2 + tol)
                    and math.abs(rel.Z) <= (size.Z / 2 + tol) then
                    return true
                end
            end
        end
    end

    return false
end

local function hitungSisaKardus()
    local jumlah = 0
    for _, v in ipairs(clickObject:GetChildren()) do
        if v.Name == "Kardus" and not apakahKardusDiRakGudang(v) then
            jumlah = jumlah + 1
        end
    end
    return jumlah
end

-- UI Tab Shop
local ShopTab = API.CreateTab("Shop")
API.Section(ShopTab, "Pengaturan Produk")

API.Input(ShopTab, "Nama Item (Tekan Enter)", "Bebelove", function(text)
    if text ~= "" then
        namaItem = text
        API.Notify("Item Diatur", "Target produk: " .. namaItem, 2)
    end
end)

API.Slider(ShopTab, "Jumlah Kardus Sekali Beli", 1, 50, 1, " Kardus", 10, function(val)
    jumlahBeli = val
end)

API.Section(ShopTab, "Otomatisasi Restok")
API.Toggle(ShopTab, "Auto Restok Kardus (Kecuali Rak Gudang)", false, function(val)
    autoRestokEnabled = val
    if val then sudahBeli = false end
    API.Notify(
        val and "Auto Restok Aktif" or "Auto Restok Mati",
        val and "Memantau kardus di luar Rak Gudang..." or "Auto beli dihentikan.",
        3
    )
end)

task.spawn(function()
    while true do
        if autoRestokEnabled then
            local sisa = hitungSisaKardus()
            if sisa > 0 then
                sudahBeli = false
            elseif sisa == 0 and not sudahBeli then
                sudahBeli = true
                BeliProductRemote:FireServer({
                    {
                        jumlahKardus = jumlahBeli,
                        itemName = namaItem
                    }
                })
                API.Notify("Restok Berhasil", "Membeli " .. jumlahBeli .. "x " .. namaItem, 3)
            end
        end
        task.wait(1)
    end
end)
