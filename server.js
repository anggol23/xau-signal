const express = require('express');
const path = require('path');
const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.static(path.join(__dirname, '.')));

// ============================================================
// LIVE QUOTE — multi-source fallback chain
// TradingView's forex scanner stopped returning XAUUSD reliably
// after their 2024 endpoint refactor. We try:
//   1. Yahoo Finance  (XAUUSD=X, intraday 1m, regularMarketPrice)
//   2. Stooq          (xauusd free CSV endpoint)
//   3. TradingView    (last-resort, often 404 for XAUUSD)
// ============================================================
const QUOTE_SOURCES = [
  {
    name: 'Yahoo Finance',
    url: 'https://query1.finance.yahoo.com/v8/finance/chart/XAUUSD=X?interval=1m&range=1d&includePrePost=true',
    isJson: true,
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': 'application/json, text/plain, */*'
    }
  },
  {
    name: 'Stooq',
    url: 'https://stooq.com/q/l/?s=xauusd&f=sd2t2ohlcv&h&e=csv',
    isJson: false,
    headers: { 'User-Agent': 'Mozilla/5.0' }
  },
  {
    name: 'TradingView',
    url: 'https://scanner.tradingview.com/forex/scan',
    isJson: true,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Origin': 'https://www.tradingview.com',
      'Referer': 'https://www.tradingview.com/'
    },
    body: JSON.stringify({
      symbols: { tickers: ['OANDA:XAUUSD', 'TVC:GOLD'], query: { types: [] } },
      columns: ['close']
    })
  }
];

function parseYahooChart(json) {
  const result = json && json.chart && json.chart.result && json.chart.result[0];
  if (!result) return null;
  const meta = result.meta || {};
  if (Number.isFinite(Number(meta.regularMarketPrice))) return Number(meta.regularMarketPrice);
  if (Number.isFinite(Number(meta.previousClose)))      return Number(meta.previousClose);
  const q = result.indicators && result.indicators.quote && result.indicators.quote[0];
  const closes = (q && q.close) || [];
  for (let i = closes.length - 1; i >= 0; i--) {
    if (Number.isFinite(closes[i])) return Number(closes[i]);
  }
  return null;
}

function parseStooqCsv(text) {
  const lines = String(text).trim().split(/\r?\n/);
  if (lines.length < 2) return null;
  const cols = lines[1].split(',');
  const close = Number(cols[6]);
  return Number.isFinite(close) ? close : null;
}

function parseTradingView(json) {
  const rows = (json && json.data) || [];
  for (const row of rows) {
    const d = row && row.d;
    if (Array.isArray(d) && Number.isFinite(Number(d[0]))) return Number(d[0]);
  }
  return null;
}

app.get('/api/tradingview-quote', async (req, res) => {
  let lastError = 'All sources failed';

  for (const src of QUOTE_SOURCES) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 4500);
    try {
      const response = await fetch(src.url, {
        method: src.method || 'GET',
        headers: { 'User-Agent': 'Mozilla/5.0', ...(src.headers || {}) },
        body: src.body,
        signal: controller.signal
      });
      if (!response.ok) { lastError = `${src.name} HTTP ${response.status}`; continue; }

      const raw = src.isJson ? await response.json() : await response.text();
      const price =
        src.name === 'Yahoo Finance'  ? parseYahooChart(raw) :
        src.name === 'Stooq'          ? parseStooqCsv(raw) :
        src.name === 'TradingView'    ? parseTradingView(raw) :
        null;

      if (Number.isFinite(price) && price > 100) {
        return res.json({
          symbol: 'XAUUSD',
          source: src.name,
          price: Number(price.toFixed(2)),
          ts: Date.now()
        });
      }
      lastError = `${src.name} returned no valid price`;
    } catch (e) {
      lastError = `${src.name}: ${e.message}`;
    } finally {
      clearTimeout(timeout);
    }
  }

  res.status(500).json({ error: 'Failed to fetch quote', detail: lastError });
});

// ============================================================
// HISTORY — Yahoo Finance M5 (5 days) for instant bootstrap.
// On failure returns 200 with synthetic bars tagged as
// 'synthetic-fallback'; client may still choose to use it
// when live seed price is unavailable.
// ============================================================
app.get('/api/tradingview-history', async (req, res) => {
  try {
    const url = 'https://query1.finance.yahoo.com/v8/finance/chart/XAUUSD=X?interval=5m&range=5d&includePrePost=false';
    const response = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept': 'application/json'
      }
    });
    if (!response.ok) throw new Error(`Yahoo HTTP ${response.status}`);

    const json = await response.json();
    const result = json && json.chart && json.chart.result && json.chart.result[0];
    if (!result) throw new Error('No chart result');

    const timestamps = result.timestamp || [];
    const q = result.indicators && result.indicators.quote && result.indicators.quote[0];
    if (!q) throw new Error('Missing OHLCV data');

    const bars = [];
    for (let i = 0; i < timestamps.length; i++) {
      const o = q.open[i], h = q.high[i], l = q.low[i], c = q.close[i];
      if (![o, h, l, c].every(Number.isFinite)) continue;
      bars.push({ t: timestamps[i] * 1000, o, h, l, c });
    }
    if (bars.length === 0) throw new Error('All bars filtered');

    return res.json({ bars, source: 'yahoo', count: bars.length });
  } catch (e) {
    // Realistic synthetic fallback (deterministic) — kept for
    // offline / rate-limit scenarios. Client already handles
    // 'synthetic-fallback' tag and price-level sanity check.
    const now = Date.now();
    const tfMs = 300000;
    const currentBucket = Math.floor(now / tfMs);
    const base = 3300;
    const bars = [];
    for (let i = 200; i >= 1; i--) {
      const t = (currentBucket - i) * tfMs;
      const phase  = (i % 40) / 40 * Math.PI * 2;
      const trend  = Math.sin(i / 15) * 6;
      const vol    = 1.2 + Math.sin(i / 7) * 0.8;
      const o = base + Math.sin(phase) * 8 + trend * 0.5;
      const c = o + trend * 0.4 + (i % 2 === 0 ? vol : -vol);
      const h = Math.max(o, c) + vol * 1.4 + Math.abs(Math.sin(i / 3)) * 0.6;
      const l = Math.min(o, c) - vol * 1.4 - Math.abs(Math.cos(i / 3)) * 0.6;
      bars.push({ t, o, h, l, c });
    }
    return res.json({ bars, source: 'synthetic-fallback', warning: e.message });
  }
});

app.listen(PORT, () => {
  console.log(`XAUUSD SNIPER Server running at http://localhost:${PORT}`);
  console.log(`  Quote   : http://localhost:${PORT}/api/tradingview-quote`);
  console.log(`  History : http://localhost:${PORT}/api/tradingview-history`);
});
