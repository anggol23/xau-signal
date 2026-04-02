module.exports = async (req, res) => {
  if (req.method !== "GET") {
    res.statusCode = 405;
    res.setHeader("Allow", "GET");
    res.end(JSON.stringify({ error: "Method not allowed" }));
    return;
  }

  try {
    const response = await fetch("https://scanner.tradingview.com/forex/scan", {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        symbols: {
          tickers: ["OANDA:XAUUSD"],
          query: { types: [] }
        },
        columns: ["close"]
      })
    });

    if (!response.ok) {
      throw new Error(`TradingView scanner HTTP ${response.status}`);
    }

    const payload = await response.json();
    const row = payload && payload.data && payload.data[0];
    const price = row && row.d && Number(row.d[0]);

    if (!Number.isFinite(price)) {
      throw new Error("TradingView price not available");
    }

    res.statusCode = 200;
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({
      symbol: "OANDA:XAUUSD",
      source: "TradingView Scanner",
      price,
      ts: Date.now()
    }));
  } catch (error) {
    res.statusCode = 500;
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({
      error: "Failed to fetch TradingView quote",
      detail: error.message
    }));
  }
};
