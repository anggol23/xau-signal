# XAUUSD Sniper Signal Dashboard

Dashboard sinyal trading XAUUSD (Gold) berbasis web, realtime, dengan dua mode strategi: **Normal** dan **Scalping**.

## Fitur

- **Realtime Chart** — TradingView widget `OANDA:XAUUSD`, interval 1 menit, tema dark
- **Live Price Feed** — Data harga dari [Gold API](https://api.gold-api.com) (gratis, tanpa API key)
- **Mode Normal** — Deteksi sweep + BOS + rejection + momentum, SL berbasis struktur, RR 1:2
- **Mode Scalping** — EMA 20/50 pullback entry, SL tetap 25 poin, RR 1:1.5, anti-spike & anti-sideways filter
- **Filter Jam Trading** — Hanya aktif pada sesi London (14:00–18:30 WIB) dan New York (19:30–00:30 WIB)
- **Filter News** — Blackout otomatis saat rilis data US penting dan NFP (Jumat pertama setiap bulan)
- **Manajemen Posisi Scalping** — BE otomatis di +15 poin, partial close di +30 poin, hold runner di +50 poin
- **Komentar Pasar** — Analisis kondisi candle/chart otomatis di bawah panel sinyal

## Cara Pakai

Tidak ada build step. Cukup buka `index.html` di browser, atau akses via URL Vercel.

```
index.html   ← single-file app, semua HTML/CSS/JS tergabung
```

## Tech Stack

- Pure HTML / CSS / JavaScript (no framework)
- [TradingView Lightweight Widget](https://www.tradingview.com/widget/)
- [Gold API](https://api.gold-api.com) — endpoint `GET /price/XAU`

## Deploy

Live di Vercel: [xau-signal.vercel.app](https://xau-signal.vercel.app)

## Strategi

### Mode Normal
- Deteksi sweep likuiditas + Break of Structure (BOS)
- Konfirmasi rejection candle + momentum EMA
- SL: struktur + 20 poin buffer
- TP: SL × RR 1:2

### Mode Scalping
- Entry saat pullback ke EMA 20 searah trend EMA 50
- Anti-spike: batal jika ukuran candle > 80 poin
- Anti-gap: batal jika jarak EMA > 3× rata-rata candle
- Anti-sideways: batal jika rata-rata candle ≤ 1 poin
- SL: 25 poin tetap | TP: 37.5 poin (RR 1:1.5)

## Lisensi

MIT
