local API = ...

local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request
local webhookUrl = ""
local webhookEnabled = false

local function kirimWebhookV2(judul, isiLaporan, catatanFooter)
    if not httpRequest then return false, "Executor tidak mendukung HTTP Request." end
    if webhookUrl == "" or not webhookUrl:find("discord.com/api/webhooks/") then
        return false, "URL Webhook tidak valid."
    end

    local targetUrl = webhookUrl
    if not targetUrl:find("with_components=true") then
        targetUrl = targetUrl .. (targetUrl:find("?") and "&" or "?") .. "with_components=true"
    end

    -- Components V2 tanpa accent_color pada Container (type = 17)
    local payload = {
        username = "Kopdes Payroll System",
        flags = 32768,
        components = {
            {
                type = 17,
                components = {
                    {
                        type = 10,
                        content = "### " .. judul .. "\n" .. isiLaporan
                    },
                    {
                        type = 14,
                        divider = true,
                        spacing = 1
                    },
                    {
                        type = 10,
                        content = "-# " .. (catatanFooter or "Kopdes Together • Cheese Dev")
                    }
                }
            }
        }
    }

    local success, response = pcall(function()
        return httpRequest({
            Url = targetUrl,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = API.HttpService:JSONEncode(payload)
        })
    end)

    if success and response and (response.StatusCode == 200 or response.StatusCode == 204) then
        return true, "Terkirim"
    end
    local kode = response and tostring(response.StatusCode) or "Unknown"
    return false, "Gagal HTTP (" .. kode .. ")"
end

-- Dengarkan event PayrollPaid dari plugin auto_payroll.lua
API.On("PayrollPaid", function(data)
    if not webhookEnabled or typeof(data) ~= "table" then return end

    local isi = string.format(
        "**Waktu:** %s\n**Mode:** %s\n**Jatah / Orang:** Rp %s\n**Total Keluar:** Rp %s\n**Penerima:** %s\n**Sisa Kas Toko:** Rp %s",
        data.waktu,
        data.mode,
        API.FormatRupiah(data.perOrang),
        API.FormatRupiah(data.totalKeluar),
        data.penerimaText,
        API.FormatRupiah(data.sisaSaldo)
    )
    kirimWebhookV2("Laporan Gajian Koperasi", isi, "Auto Payroll • " .. os.date("%d/%m/%Y %H:%M"))
end)

-- UI Tab Webhook
local WebhookTab = API.CreateTab("Webhook")
API.Section(WebhookTab, "Discord Components V2 (Tanpa Accent Color)")

API.Input(WebhookTab, "URL Webhook Discord (Tekan Enter)", "https://discord.com/api/webhooks/...", function(txt)
    webhookUrl = txt
    if txt ~= "" then
        API.Notify("Webhook Disimpan", "URL Webhook telah diatur.", 2)
    end
end)

API.Toggle(WebhookTab, "Kirim Slip Gaji ke Discord", false, function(val)
    webhookEnabled = val
end)

API.Button(WebhookTab, "Test Kirim Webhook V2", function()
    task.spawn(function()
        local ok, info = kirimWebhookV2(
            "Test Koneksi Koperasi",
            "**Status:** WindUI + Modular Plugin aktif.\n**Toko:** Plot1",
            "Test Notifikasi • Kopdes Together"
        )
        API.Notify(ok and "Webhook Terkirim!" or "Webhook Gagal", info, 3)
    end)
end)
