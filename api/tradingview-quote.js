// ============================================================
//  XAUUSD LIVE QUOTE — Vercel serverless function
//  Multi-source fallback chain (matches server.js):
//    1. Yahoo Finance (XAUUSD=X, 1m, regularMarketPrice)
//    2. Stooq        (xauusd free CSV)
//    3. TradingView  (scanner forex/global, often rate-limited)
//
//  Vercel Hobby = 10s timeout. Each source is capped at 3.5s
//  so the whole function stays under the limit.
// ============================================================

const QUOTE_SOURCES = [
  {
    name: "Yahoo Finance",
    url: "https://query1.finance.yahoo.com/v8/finance/chart/XAUUSD=X?interval=1m&range=1d&includePrePost=true",
    isJson: true,
    headers: {
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
      "Accept": "application/json, text/plain, */*"
    }
  },
  {
    name: "Stooq",
    url: "https://stooq.com/q/l/?s=xauusd&f=sd2t2ohlcv&h&e=csv",
    isJson: false,
    headers: { "User-Agent": "Mozilla/5.0" }
  },
  {
    name: "TradingView",
    url: "https://scanner.tradingview.com/forex/scan",
    isJson: true,
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Origin": "https://www.tradingview.com",
      "Referer": "https://www.tradingview.com/"
    },
    body: JSON.stringify({
      symbols: { tickers: ["OANDA:XAUUSD", "TVC:GOLD"], query: { types: [] } },
      columns: ["close"]
    })
  }
];

const PER_SOURCE_TIMEOUT_MS = 2500;

async function fetchWithTimeout(url, options, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

function parseYahooChart(json) {
  const result = json && json.chart && json.chart.result && json.chart.result[0];
  if (!result) return null;
  const meta = result.meta || {};
  if (Number.isFinite(Number(meta.regularMarketPrice))) return Number(meta.regularMarketPrice);
  if (Number.isFinite(Number(meta.previousClose))) return Number(meta.previousClose);
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
  const cols = lines[1].split(",");
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

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET");
  res.setHeader("Cache-Control", "no-store");

  if (req.method !== "GET") {
    res.statusCode = 405;
    res.setHeader("Allow", "GET");
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({ error: "Method not allowed" }));
    return;
  }

  let lastError = "All sources failed";

  for (const src of QUOTE_SOURCES) {
    try {
      const response = await fetchWithTimeout(
        src.url,
        {
          method: src.method || "GET",
          headers: { "User-Agent": "Mozilla/5.0", ...(src.headers || {}) },
          body: src.body
        },
        PER_SOURCE_TIMEOUT_MS
      );

      if (!response.ok) {
        lastError = `${src.name} HTTP ${response.status}`;
        continue;
      }

      const raw = src.isJson ? await response.json() : await response.text();
      const price =
        src.name === "Yahoo Finance" ? parseYahooChart(raw) :
        src.name === "Stooq"         ? parseStooqCsv(raw) :
        src.name === "TradingView"   ? parseTradingView(raw) :
        null;

      if (Number.isFinite(price) && price > 100) {
        res.statusCode = 200;
        res.setHeader("Content-Type", "application/json");
        res.end(JSON.stringify({
          symbol: "XAUUSD",
          source: src.name,
          price: Number(price.toFixed(2)),
          ts: Date.now()
        }));
        return;
      }

      lastError = `${src.name} returned no valid price`;
    } catch (e) {
      lastError = `${src.name}: ${e.message}`;
    }
  }

  res.statusCode = 500;
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify({
    error: "Failed to fetch quote",
    detail: lastError
  }));
};
