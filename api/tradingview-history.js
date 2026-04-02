// Fetch historical M5 OHLCV bars for XAUUSD from Yahoo Finance.
// Used by the client to pre-populate fallbackTicks on first load so that
// M5 analysis is immediately available regardless of localStorage state.
module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET");
  res.setHeader("Cache-Control", "no-cache");

  if (req.method !== "GET") {
    res.statusCode = 405;
    res.end(JSON.stringify({ error: "Method not allowed" }));
    return;
  }

  try {
    const url =
      "https://query1.finance.yahoo.com/v8/finance/chart/XAUUSD=X" +
      "?interval=5m&range=2d&includePrePost=false";

    const response = await fetch(url, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
          "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Accept": "application/json, text/plain, */*",
        "Referer": "https://finance.yahoo.com/"
      }
    });

    if (!response.ok) {
      throw new Error(`Yahoo Finance HTTP ${response.status}`);
    }

    const json = await response.json();
    const result = json?.chart?.result?.[0];
    if (!result) throw new Error("No chart result from Yahoo Finance");

    const timestamps = result.timestamp;
    const q = result.indicators?.quote?.[0];
    if (!timestamps || !q) throw new Error("Missing OHLCV data");

    const bars = [];
    for (let i = 0; i < timestamps.length; i++) {
      const o = q.open[i];
      const h = q.high[i];
      const l = q.low[i];
      const c = q.close[i];
      // Skip bars with null/invalid values (off-hours gaps)
      if (!Number.isFinite(o) || !Number.isFinite(h) ||
          !Number.isFinite(l) || !Number.isFinite(c)) continue;
      bars.push({ t: timestamps[i] * 1000, o, h, l, c });
    }

    if (bars.length === 0) throw new Error("All bars filtered out (null values)");

    res.statusCode = 200;
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({ bars }));
  } catch (e) {
    res.statusCode = 500;
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({ error: e.message }));
  }
};
