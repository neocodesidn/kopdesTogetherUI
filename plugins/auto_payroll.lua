local API = ...

local Lighting = game:GetService("Lighting")
local GetStateRemote = API.Remotes.Bank:WaitForChild("GetState")
local TransferRemote = API.Remotes.Bank:WaitForChild("Transfer")

local autoGajianGantiHari = false
local modeUlangTiapHari = true
local gajiPerHariJuta = 10
local modePembagian = "Bagi Rata Anggaran ke Semua Anggota"
local targetUserId = nil
local targetPlayerName = ""

-- State Deposit 2x Tap
local nominalDepositJuta = 10
local konfirmasiDeposit = false
local tokenKonfirmasiDeposit = 0
local sedangProsesDeposit = false

-- State Anti-Double Gajian
local hariTerakhir = nil
local hariSudahDibayar = nil
local adaLabelHari = false
local sudahGajianClockTime = false
local sedangProsesGajian = false
local waktuGajianAutoTerakhir = 0

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

local function depositKeToko(nominalJuta)
    if sedangProsesDeposit then return end
    sedangProsesDeposit = true

    pcall(function()
        local jumlahDeposit = nominalJuta * 1000000
        local state = ambilStateBank()

        if state and typeof(state.userBalance) == "number" and state.userBalance < jumlahDeposit then
            API.Notify("Saldo Pribadi Kurang", "Saldo kamu kurang dari Rp " .. nominalJuta .. " Juta.", 4)
            return
        end

        local res = TransferRemote:InvokeServer({
            targetType = "Toko",
            sourceType = "User",
            amount = jumlahDeposit
        })

        if typeof(res) == "table" and res.ok then
            API.Notify("Deposit Berhasil!", "Setor Rp " .. API.FormatRupiah(jumlahDeposit) .. " ke kas Toko.", 3)
        else
            local msg = (typeof(res) == "table" and res.message) or "Gagal melakukan deposit."
            API.Notify("Deposit Ditolak", tostring(msg), 4)
        end
    end)

    task.wait(0.25)
    sedangProsesDeposit = false
end

local function cairkanGajiHarian(labelWaktu, isManual)
    if sedangProsesGajian then return end
    if not isManual and (os.clock() - waktuGajianAutoTerakhir) < 30 then return end

    sedangProsesGajian = true
    if not isManual then waktuGajianAutoTerakhir = os.clock() end

    pcall(function()
        local totalGaji = gajiPerHariJuta * 1000000
        local state = ambilStateBank()
        local saldoToko = state and state.shopBalance

        if typeof(saldoToko) ~= "number" then
            API.Notify("Gagal Mengecek Kas", "Tidak dapat membaca saldo toko.", 4)
            return
        end

        if saldoToko < totalGaji then
            API.Notify("Kas Toko Tidak Cukup", "Saldo kurang dari Rp " .. gajiPerHariJuta .. " Juta.", 4)
            return
        end

        if modePembagian == "Bagi Rata Anggaran ke Semua Anggota" then
            local penerima = {}
            for _, plr in ipairs(API.Players:GetPlayers()) do
                if plr ~= API.LocalPlayer then table.insert(penerima, plr) end
            end

            if #penerima == 0 then
                API.Notify("Tidak Ada Karyawan", "Tidak ada pemain lain di server.", 3)
                return
            end

            local gajiPerOrang = math.floor(totalGaji / #penerima)
            if gajiPerOrang < 10000 then
                API.Notify("Nominal Terlalu Kecil", "Jatah per orang di bawah minimal Rp 10.000.", 4)
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

            local sisaSaldo = saldoToko - (gajiPerOrang * berhasil)
            API.Notify(
                "Gajian " .. (labelWaktu or "Harian") .. " Cair!",
                "Rp " .. API.FormatRupiah(gajiPerOrang) .. "/orang dikirim ke " .. berhasil .. " anggota.",
                5
            )

            if berhasil > 0 then
                API.Emit("PayrollPaid", {
                    waktu = labelWaktu or "Harian",
                    mode = "Bagi Rata (" .. berhasil .. " Anggota)",
                    perOrang = gajiPerOrang,
                    totalKeluar = gajiPerOrang * berhasil,
                    penerimaText = table.concat(daftarNama, ", "),
                    sisaSaldo = sisaSaldo
                })
            end
        else
            if not targetUserId then
                API.Notify("Anggota Belum Dipilih", "Pilih penerima dulu di dropdown Bank.", 3)
                return
            end

            local res = TransferRemote:InvokeServer({
                targetType = "Player",
                targetUserId = targetUserId,
                sourceType = "Toko",
                amount = totalGaji
            })

            if typeof(res) == "table" and res.ok then
                local sisaSaldo = saldoToko - totalGaji
                API.Notify(
                    "Gajian " .. (labelWaktu or "Harian") .. " Cair!",
                    "Terkirim Rp " .. API.FormatRupiah(totalGaji) .. " ke " .. targetPlayerName,
                    4
                )
                API.Emit("PayrollPaid", {
                    waktu = labelWaktu or "Harian",
                    mode = "Perorangan",
                    perOrang = totalGaji,
                    totalKeluar = totalGaji,
                    penerimaText = "`" .. targetPlayerName .. "` (`" .. targetUserId .. "`)",
                    sisaSaldo = sisaSaldo
                })
            else
                local msg = (typeof(res) == "table" and res.message) or "Transaksi ditolak server."
                API.Notify("Transfer Gagal", tostring(msg), 4)
            end
        end
    end)

    sedangProsesGajian = false
end

-- UI Tab Bank
local BankTab = API.CreateTab("Bank")

API.Section(BankTab, "Deposit Saldo User ke Toko (2x Tap)")
local DepositButton

API.Dropdown(BankTab, "Pilih Nominal Deposit", {
    "10 Juta", "20 Juta", "30 Juta", "40 Juta", "50 Juta",
    "60 Juta", "70 Juta", "80 Juta", "90 Juta", "100 Juta"
}, "10 Juta", function(opt)
    local angka = tonumber(tostring(opt):match("%d+"))
    if angka then
        nominalDepositJuta = angka
        konfirmasiDeposit = false
        tokenKonfirmasiDeposit = tokenKonfirmasiDeposit + 1
        API.SetElementText(DepositButton, "Setor " .. nominalDepositJuta .. " Juta ke Toko")
    end
end)

DepositButton = API.Button(BankTab, "Setor 10 Juta ke Toko", function()
    if not konfirmasiDeposit then
        konfirmasiDeposit = true
        tokenKonfirmasiDeposit = tokenKonfirmasiDeposit + 1
        local tokenSaatIni = tokenKonfirmasiDeposit

        API.SetElementText(DepositButton, "Tap Lagi untuk Konfirmasi Setor Rp " .. nominalDepositJuta .. " Juta")
        API.Notify("Konfirmasi Deposit", "Tap tombol sekali lagi dalam 5 detik untuk setor.", 4)

        task.delay(5, function()
            if konfirmasiDeposit and tokenKonfirmasiDeposit == tokenSaatIni then
                konfirmasiDeposit = false
                API.SetElementText(DepositButton, "Setor " .. nominalDepositJuta .. " Juta ke Toko")
            end
        end)
    else
        konfirmasiDeposit = false
        tokenKonfirmasiDeposit = tokenKonfirmasiDeposit + 1
        API.SetElementText(DepositButton, "Setor " .. nominalDepositJuta .. " Juta ke Toko")
        task.spawn(depositKeToko, nominalDepositJuta)
    end
end)

API.Section(BankTab, "Anggaran & Penerima Gaji (Standar)")
API.Slider(BankTab, "Anggaran Gaji Per Hari", 1, 50, 1, " Juta / Hari", 10, function(val)
    gajiPerHariJuta = val
end)

API.Dropdown(BankTab, "Mode Pembagian Gaji", {
    "Bagi Rata Anggaran ke Semua Anggota",
    "Full ke 1 Anggota Pilihan"
}, "Bagi Rata Anggaran ke Semua Anggota", function(opt)
    modePembagian = opt
end)

local AnggotaDropdown = API.Dropdown(BankTab, "Pilih Anggota (Mode 1 Orang)", ambilDaftarAnggota(), "", function(opt)
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

API.Button(BankTab, "Refresh Daftar Anggota Server", function()
    if AnggotaDropdown and AnggotaDropdown.Refresh then
        pcall(function() AnggotaDropdown:Refresh(ambilDaftarAnggota()) end)
    end
    API.Notify("Daftar Diperbarui", "Daftar pemain di server telah dimuat ulang.", 2)
end)

API.Section(BankTab, "Otomatisasi Gajian Ganti Hari (21:00)")
API.Toggle(BankTab, "Mode AFK: Ulangi Tiap Ganti Hari", true, function(val)
    modeUlangTiapHari = val
end)

local AutoGajianToggle
AutoGajianToggle = API.Toggle(BankTab, "Auto Gajian Saat Ganti Hari (21:00)", false, function(val)
    autoGajianGantiHari = val
    if val then
        API.Emit("DisableSmartPayroll")
    end
    API.Notify(
        val and "Auto Gajian Aktif" or "Auto Gajian Mati",
        val and ("Gaji Rp " .. gajiPerHariJuta .. " Juta cair 1x tiap ganti hari.") or "Auto gajian dihentikan.",
        3
    )
end)

API.Button(BankTab, "Cairkan Gaji Sekarang (Manual 1x Klik)", function()
    task.spawn(cairkanGajiHarian, "Manual", true)
end)

API.On("DisableStandardPayroll", function()
    if autoGajianGantiHari then
        autoGajianGantiHari = false
        API.SetElementText(AutoGajianToggle, false)
    end
end)

-- Detektor Ganti Hari Real-Time
local function eksekusiTriggerHariBaru(hariBaru)
    if not autoGajianGantiHari then return end
    if not modeUlangTiapHari then
        autoGajianGantiHari = false
        API.SetElementText(AutoGajianToggle, false)
    end
    local teksHari = hariBaru and ("Hari " .. tostring(hariBaru)) or "Ganti Hari"
    task.spawn(cairkanGajiHarian, teksHari, false)
end

local function pasangListenerLabelHari(obj)
    if obj:IsA("TextLabel") and obj.Text:match("^Hari%s*%d+") then
        adaLabelHari = true
        local angkaAwal = tonumber(obj.Text:match("%d+"))
        if angkaAwal and not hariTerakhir then
            hariTerakhir = angkaAwal
            hariSudahDibayar = angkaAwal
        end

        obj:GetPropertyChangedSignal("Text"):Connect(function()
            local angkaBaru = tonumber(obj.Text:match("%d+"))
            if angkaBaru and hariTerakhir and angkaBaru > hariTerakhir then
                hariTerakhir = angkaBaru
                if hariSudahDibayar ~= angkaBaru then
                    hariSudahDibayar = angkaBaru
                    eksekusiTriggerHariBaru(angkaBaru)
                end
            end
        end)
    end
end

for _, uiObj in ipairs(API.PlayerGui:GetDescendants()) do
    pasangListenerLabelHari(uiObj)
end
API.PlayerGui.DescendantAdded:Connect(pasangListenerLabelHari)

Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
    if adaLabelHari then return end
    local jam = Lighting.ClockTime
    if jam >= 21 and jam < 21.5 then
        if not sudahGajianClockTime then
            sudahGajianClockTime = true
            eksekusiTriggerHariBaru(nil)
        end
    elseif jam < 20 then
        sudahGajianClockTime = false
    end
end)
