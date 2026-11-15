local API = ...

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GetStateRemote = API.Remotes.Bank:WaitForChild("GetState")
local TransferRemote = API.Remotes.Bank:WaitForChild("Transfer")

-- ==========================================
-- KONFIGURASI SMART PAYROLL
-- ==========================================
local smartPayrollAktif = false
local modeUlangTiapHari = true
local filterPekerjaAktif = true

local persenProfitGaji = 25      -- Persentase dari totalProfit bersih harian
local maxGajiPerOrangJuta = 10   -- Batas maksimal per orang (anti-overpay saat cuma 1 pekerja)
local modePembagian = "Smart Profit Share (Bagi Rata + Cap)"
local targetUserId = nil
local targetPlayerName = ""

-- State Pelacak Hari & Profit Terakhir
local hariSudahDibayar = nil
local sedangProsesGajian = false
local lastRecapData = nil

-- State Sensor Aktivitas Pekerja di Plot1
local skorKerja = {}
local posisiTerakhir = {}
local MINIMAL_POIN_KERJA = 5 -- Minimal aktif bergerak/angkut sekitar ~15 detik di Plot1

-- ==========================================
-- SENSOR AKTIVITAS PEKERJA DI PLOT1
-- ==========================================
local function apakahDiAreaToko(posisi)
    local ok, plotCF, plotSize = pcall(function()
        return API.Plot:GetBoundingBox()
    end)
    if not ok or not plotCF then return true end

    local rel = plotCF:PointToObjectSpace(posisi)
    local bufferDepan = 16
    return math.abs(rel.X) <= (plotSize.X / 2 + bufferDepan)
       and math.abs(rel.Z) <= (plotSize.Z / 2 + bufferDepan)
end

local function apakahSedangAngkut(character)
    for _, obj in ipairs(character:GetDescendants()) do
        local n = obj.Name:lower()
        if n:find("kardus") or n:find("box") or obj:IsA("Tool") then
            return true
        end
    end
    return false
end

task.spawn(function()
    while true do
        for _, plr in ipairs(API.Players:GetPlayers()) do
            if plr ~= API.LocalPlayer and plr.Character then
                local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local posNow = hrp.Position
                    local posOld = posisiTerakhir[plr.UserId]

                    if apakahDiAreaToko(posNow) then
                        local bergerak = posOld and (posNow - posOld).Magnitude > 2
                        local angkut = apakahSedangAngkut(plr.Character)

                        if angkut then
                            skorKerja[plr.UserId] = (skorKerja[plr.UserId] or 0) + 2
                        elseif bergerak then
                            skorKerja[plr.UserId] = (skorKerja[plr.UserId] or 0) + 1
                        end
                    end

                    posisiTerakhir[plr.UserId] = posNow
                end
            end
        end
        task.wait(3)
    end
end)

API.Players.PlayerRemoving:Connect(function(plr)
    posisiTerakhir[plr.UserId] = nil
    skorKerja[plr.UserId] = nil
end)

-- ==========================================
-- HELPER BANK & EKSEKUSI SMART PAYROLL
-- ==========================================
local function ambilStateBank()
    local ok, state = pcall(function() return GetStateRemote:InvokeServer() end)
    return (ok and typeof(state) == "table") and state or nil
end

local function ambilDaftarAnggota()
    local daftar = {}
    for _, plr in ipairs(API.Players:GetPlayers()) do
        if plr ~= API.LocalPlayer then
            table.insert(daftar, plr.Name)
        end
    end
    if #daftar == 0 then table.insert(daftar, "Tidak ada anggota lain") end
    return daftar
end

local function prosesSmartGaji(recapData, isManual)
    if sedangProsesGajian then return end
    sedangProsesGajian = true

    pcall(function()
        local dayNum = recapData and recapData.day
        local labelWaktu = dayNum and ("Hari " .. tostring(dayNum)) or "Manual"
        local totalProfit = recapData and tonumber(recapData.totalProfit)

        if not totalProfit then
            if isManual then
                totalProfit = (maxGajiPerOrangJuta * 1000000) * (100 / math.max(persenProfitGaji, 1))
            else
                API.Notify("Data Profit Kosong", "Menunggu rekap harian (21:00) dari server.", 3)
                return
            end
        end

        if totalProfit <= 0 then
            API.Notify(
                "Smart Payroll Ditahan (" .. labelWaktu .. ")",
                "Toko tidak mencatat profit bersih (Rp " .. API.FormatRupiah(totalProfit) .. ").",
                4
            )
            skorKerja = {}
            return
        end

        local poolGaji = math.floor(totalProfit * (persenProfitGaji / 100))
        local batasMaxPerOrang = maxGajiPerOrangJuta * 1000000

        local state = ambilStateBank()
        local saldoToko = state and state.shopBalance
        if typeof(saldoToko) ~= "number" then
            API.Notify("Gagal Mengecek Kas", "Tidak dapat membaca saldo toko.", 4)
            return
        end

        if modePembagian == "Smart Profit Share (Bagi Rata + Cap)" then
            local penerima = {}
            for _, plr in ipairs(API.Players:GetPlayers()) do
                if plr ~= API.LocalPlayer then
                    if filterPekerjaAktif then
                        local poin = skorKerja[plr.UserId] or 0
                        if poin >= MINIMAL_POIN_KERJA then
                            table.insert(penerima, plr)
                        end
                    else
                        table.insert(penerima, plr)
                    end
                end
            end

            if #penerima == 0 then
                API.Notify(
                    "Tidak Ada Pekerja Aktif",
                    filterPekerjaAktif and "Tidak ada anggota yang mencapai aktivitas kerja di Plot1." or "Tidak ada pemain lain di server.",
                    4
                )
                skorKerja = {}
                return
            end

            local jatahMentah = math.floor(poolGaji / #penerima)
            local gajiPerOrang = math.min(jatahMentah, batasMaxPerOrang)

            if gajiPerOrang < 10000 then
                API.Notify(
                    "Smart Payroll Ditahan (" .. labelWaktu .. ")",
                    "Porsi gaji Rp " .. API.FormatRupiah(gajiPerOrang) .. " di bawah minimal Rp 10.000.",
                    4
                )
                skorKerja = {}
                return
            end

            local totalDibutuhkan = gajiPerOrang * #penerima
            if saldoToko < totalDibutuhkan then
                API.Notify("Kas Toko Kurang", "Saldo kas tidak mencukupi untuk mencairkan gaji.", 4)
                return
            end

            local berhasil = 0
            local daftarNama = {}

            for _, plr in ipairs(penerima) do
                local res = TransferRemote:InvokeServer({
                    targetType = "Player",
                    targetUserId = plr.UserId,
                    sourceType = "Toko",
                    amount = gajiPerOrang
                })
                if typeof(res) == "table" and res.ok then
                    berhasil = berhasil + 1
                    table.insert(daftarNama, "`" .. plr.Name .. "`")
                end
                task.wait(0.35)
            end

            local totalKeluar = gajiPerOrang * berhasil
            local sisaSaldo = saldoToko - totalKeluar

            API.Notify(
                "Smart Payroll " .. labelWaktu .. " Cair!",
                "Profit: Rp " .. API.FormatRupiah(totalProfit) .. "\nCair: Rp " .. API.FormatRupiah(gajiPerOrang) .. "/orang (" .. berhasil .. " pekerja)",
                5
            )

            if berhasil > 0 then
                API.Emit("PayrollPaid", {
                    waktu = labelWaktu,
                    mode = "Smart Payroll (" .. persenProfitGaji .. "% • Max " .. maxGajiPerOrangJuta .. "Jt)",
                    totalProfit = totalProfit,
                    penghasilan = recapData and recapData.penghasilan or 0,
                    restock = recapData and recapData.restock or 0,
                    pelanggan = recapData and recapData.pelanggan or 0,
                    perOrang = gajiPerOrang,
                    totalKeluar = totalKeluar,
                    penerimaText = table.concat(daftarNama, ", "),
                    sisaSaldo = sisaSaldo
                })
            end
        else
            if not targetUserId then
                API.Notify("Anggota Belum Dipilih", "Pilih penerima dulu di dropdown Smart Payroll.", 3)
                return
            end

            local gajiFinal = math.min(poolGaji, batasMaxPerOrang)
            if gajiFinal < 10000 then
                API.Notify("Smart Payroll Ditahan", "Porsi profit di bawah minimal Rp 10.000.", 4)
                return
            end

            if saldoToko < gajiFinal then
                API.Notify("Kas Toko Kurang", "Saldo kas tidak mencukupi.", 4)
                return
            end

            local res = TransferRemote:InvokeServer({
                targetType = "Player",
                targetUserId = targetUserId,
                sourceType = "Toko",
                amount = gajiFinal
            })

            if typeof(res) == "table" and res.ok then
                local sisaSaldo = saldoToko - gajiFinal
                API.Notify(
                    "Smart Payroll " .. labelWaktu .. " Cair!",
                    "Terkirim Rp " .. API.FormatRupiah(gajiFinal) .. " ke " .. targetPlayerName,
                    4
                )
                API.Emit("PayrollPaid", {
                    waktu = labelWaktu,
                    mode = "Smart Perorangan (" .. persenProfitGaji .. "% • Max " .. maxGajiPerOrangJuta .. "Jt)",
                    totalProfit = totalProfit,
                    penghasilan = recapData and recapData.penghasilan or 0,
                    restock = recapData and recapData.restock or 0,
                    pelanggan = recapData and recapData.pelanggan or 0,
                    perOrang = gajiFinal,
                    totalKeluar = gajiFinal,
                    penerimaText = "`" .. targetPlayerName .. "` (`" .. targetUserId .. "`)",
                    sisaSaldo = sisaSaldo
                })
            else
                local msg = (typeof(res) == "table" and res.message) or "Transaksi ditolak server."
                API.Notify("Transfer Gagal", tostring(msg), 4)
            end
        end

        skorKerja = {}
    end)

    sedangProsesGajian = false
end

-- ==========================================
-- UI TAB KHUSUS: SMART PAYROLL
-- ==========================================
local SmartTab = API.CreateTab("Smart Payroll")

API.Section(SmartTab, "Rekap Profit Harian (ShowDayRecap)")
local RecapCard = API.Paragraph(
    SmartTab,
    "Menunggu Tutup Hari (21:00)...",
    "Data profit bersih otomatis terbaca saat ShowDayRecap muncul."
)

API.Section(SmartTab, "Rumus Smart Gaji (Anti-Overpay)")
API.Slider(SmartTab, "Porsi Anggaran dari Total Profit", 5, 50, 5, "% Profit", 25, function(val)
    persenProfitGaji = val
end)

API.Slider(SmartTab, "Batas Maksimal Gaji Per Orang", 1, 50, 1, " Juta / Orang", 10, function(val)
    maxGajiPerOrangJuta = val
end)

API.Toggle(SmartTab, "Filter Pekerja Aktif (Wajib Kerja di Plot1)", true, function(val)
    filterPekerjaAktif = val
end)

API.Dropdown(SmartTab, "Mode Pembagian", {
    "Smart Profit Share (Bagi Rata + Cap)",
    "Perorangan (1 Anggota + Cap)"
}, "Smart Profit Share (Bagi Rata + Cap)", function(opt)
    modePembagian = opt
end)

local AnggotaDropdown = API.Dropdown(SmartTab, "Pilih Anggota (Khusus Perorangan)", ambilDaftarAnggota(), "", function(opt)
    local plrTarget = API.Players:FindFirstChild(tostring(opt))
    if plrTarget then
        targetUserId = plrTarget.UserId
        targetPlayerName = plrTarget.Name
        API.Notify("Penerima Dipilih", plrTarget.Name, 2)
    else
        targetUserId = nil
        targetPlayerName = ""
    end
end)

API.Button(SmartTab, "Refresh Daftar Anggota", function()
    if AnggotaDropdown and AnggotaDropdown.Refresh then
        pcall(function() AnggotaDropdown:Refresh(ambilDaftarAnggota()) end)
    end
    API.Notify("Daftar Diperbarui", "Daftar pemain di server telah dimuat ulang.", 2)
end)

API.Section(SmartTab, "Otomatisasi Tutup Hari (21:00)")
API.Toggle(SmartTab, "Mode AFK: Ulangi Tiap Ganti Hari", true, function(val)
    modeUlangTiapHari = val
end)

local SmartPayrollToggle
SmartPayrollToggle = API.Toggle(SmartTab, "Auto Smart Payroll Saat Tutup Hari", false, function(val)
    smartPayrollAktif = val
    if val then
        -- Matikan Auto Payroll reguler di tab Bank agar tidak bentrok/double bayar
        API.Emit("DisableStandardPayroll")
    end
    API.Notify(
        val and "Smart Payroll Aktif" or "Smart Payroll Mati",
        val and ("Mengambil " .. persenProfitGaji .. "% profit (Max " .. maxGajiPerOrangJuta .. "Jt/orang).") or "Smart Payroll dihentikan.",
        3
    )
end)

API.Button(SmartTab, "Cairkan Smart Gaji Sekarang (Manual)", function()
    task.spawn(prosesSmartGaji, lastRecapData, true)
end)

-- Matikan Smart Payroll jika user mengaktifkan Auto Payroll standar di tab Bank
API.On("DisableSmartPayroll", function()
    if smartPayrollAktif then
        smartPayrollAktif = false
        API.SetElementText(SmartPayrollToggle, false)
    end
end)

-- ==========================================
-- LISTENER REMOTE SHOWDAYRECAP
-- ==========================================
task.spawn(function()
    local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes", 15)
    local ShowDayRecap = RemotesFolder and RemotesFolder:WaitForChild("ShowDayRecap", 15)

    if ShowDayRecap and ShowDayRecap:IsA("RemoteEvent") then
        ShowDayRecap.OnClientEvent:Connect(function(data)
            if typeof(data) ~= "table" then return end
            lastRecapData = data

            local teksJudul = "Hari " .. tostring(data.day or "?") .. " • Pelanggan: " .. tostring(data.pelanggan or 0)
            local teksIsi = string.format(
                "Total Profit: Rp %s\nPenghasilan: Rp %s | Restock: Rp %s",
                API.FormatRupiah(data.totalProfit or 0),
                API.FormatRupiah(data.penghasilan or 0),
                API.FormatRupiah(data.restock or 0)
            )
            API.SetElementText(RecapCard, teksJudul, teksIsi)

            if smartPayrollAktif then
                local dayId = data.day or os.time()
                if hariSudahDibayar ~= dayId then
                    hariSudahDibayar = dayId

                    if not modeUlangTiapHari then
                        smartPayrollAktif = false
                        API.SetElementText(SmartPayrollToggle, false)
                    end

                    task.spawn(prosesSmartGaji, data, false)
                end
            end
        end)
    end
end)
