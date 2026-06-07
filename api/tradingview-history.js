// ============================================================
//  XAUUSD M5 HISTORY — Vercel serverless function
//  Fetches Yahoo Finance 5d M5 OHLCV with synthetic fallback
//  on failure (so frontend never sees a 500).
// ============================================================

const YAHOO_TIMEOUT_MS = 6000;

async function fetchWithTimeout(url, options, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

function makeSyntheticBars() {
  const now = Date.now();
  const tfMs = 300000; // 5m
  const currentBucket = Math.floor(now / tfMs);
  const base = 3300; // current gold band
  const bars = [];

  for (let i = 200; i >= 1; i--) {
    const t = (currentBucket - i) * tfMs;
    const phase = (i % 40) / 40 * Math.PI * 2;
    const trend = Math.sin(i / 15) * 6;
    const vol   = 1.2 + Math.sin(i / 7) * 0.8;
    const o = base + Math.sin(phase) * 8 + trend * 0.5;
    const c = o + trend * 0.4 + (i % 2 === 0 ? vol : -vol);
    const h = Math.max(o, c) + vol * 1.4 + Math.abs(Math.sin(i / 3)) * 0.6;
    const l = Math.min(o, c) - vol * 1.4 - Math.abs(Math.cos(i / 3)) * 0.6;
    bars.push({ t, o, h, l, c });
  }

  return bars;
}

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET");
  res.setHeader("Cache-Control", "no-cache");

  if (req.method !== "GET") {
    res.statusCode = 405;
    res.setHeader("Allow", "GET");
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({ error: "Method not allowed" }));
    return;
  }

  try {
    const url =
      "https://query1.finance.yahoo.com/v8/finance/chart/XAUUSD=X" +
      "?interval=5m&range=5d&includePrePost=false";

    const response = await fetchWithTimeout(url, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                      "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Accept": "application/json, text/plain, */*",
        "Referer": "https://finance.yahoo.com/"
      }
    }, YAHOO_TIMEOUT_MS);

    if (!response.ok) throw new Error(`Yahoo Finance HTTP ${response.status}`);

    const json = await response.json();
    const result = json && json.chart && json.chart.result && json.chart.result[0];
    if (!result) throw new Error("No chart result from Yahoo Finance");

    const timestamps = result.timestamp || [];
    const q = result.indicators && result.indicators.quote && result.indicators.quote[0];
    if (!q) throw new Error("Missing OHLCV data");

    const bars = [];
    for (let i = 0; i < timestamps.length; i++) {
      const o = q.open[i], h = q.high[i], l = q.low[i], c = q.close[i];
      if (![o, h, l, c].every(Number.isFinite)) continue;
      bars.push({ t: timestamps[i] * 1000, o, h, l, c });
    }
    if (bars.length === 0) throw new Error("All bars filtered out (null values)");

    res.statusCode = 200;
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({ bars, source: "yahoo", count: bars.length }));
  } catch (e) {
    // Return 200 with synthetic bars tagged so client can decide
    const bars = makeSyntheticBars();
    res.statusCode = 200;
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({
      bars,
      source: "synthetic-fallback",
      warning: e.message
    }));
  }
};
