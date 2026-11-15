# Kopdes Together — WindUI Edition

Versi UI: WindUI 1.6.66  
Core API: KopdesAPI v2.2

## Struktur

- `loader.lua` — inisialisasi WindUI, Core API, Event Bus, Plugin Loader, dashboard, dan live status.
- `plugins/` — plugin modular yang menggunakan `KopdesAPI`.

## Kompatibilitas plugin

API helper yang tersedia untuk plugin:

- `API.CreateTab(name, icon)`
- `API.Section(tab, title)`
- `API.Paragraph(tab, title, content)`
- `API.Button(tab, name, callback)`
- `API.Toggle(tab, name, defaultValue, callback)`
- `API.Slider(tab, name, min, max, step, suffix, defaultValue, callback)`
- `API.Dropdown(tab, name, options, defaultOption, callback)`
- `API.Input(tab, name, placeholder, callback)`
- `API.SetElementText(element, title, description)`
- `API.Notify(title, content, duration)`
- `API.On(eventName, callback)` dan `API.Emit(eventName, data)`

Plugin lama dipertahankan dan memakai adapter agar tidak perlu ditulis ulang untuk API WindUI.

## Catatan

Loader mengambil WindUI dari release resmi Footagesus/WindUI versi 1.6.66 dan plugin dari repository yang dikonfigurasi di `loader.lua`. Kode plugin eksternal yang dijalankan dengan `loadstring` harus berasal dari sumber yang dipercaya dan ditinjau sebelum digunakan.
## Game Restriction

Loader hanya berjalan pada Roblox Place ID `111993336672818` (Kopdes Together). Jika dieksekusi di game lain, loader menampilkan notifikasi **Unsupported Game** lalu menghentikan eksekusi sebelum WindUI, dashboard, maupun plugin dimuat.

