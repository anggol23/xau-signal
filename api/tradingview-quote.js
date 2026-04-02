module.exports = async (req, res) => {
  if (req.method !== "GET") {
    res.statusCode = 405;
    res.setHeader("Allow", "GET");
    res.end(JSON.stringify({ error: "Method not allowed" }));
    return;
  }

  try {
    const scannerPayload = {
      symbols: {
        tickers: ["OANDA:XAUUSD"],
        query: { types: [] }
      },
      columns: ["close"]
    };

    const scannerHeaders = {
      "Content-Type": "application/json",
      "Accept": "application/json, text/plain, */*",
      "Origin": "https://www.tradingview.com",
      "Referer": "https://www.tradingview.com/",
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    };

    const scannerEndpoints = [
      "https://scanner.tradingview.com/forex/scan",
      "https://scanner.tradingview.com/global/scan"
    ];

    let price = NaN;
    let lastError = "Unknown TradingView scanner error";

    for (const url of scannerEndpoints) {
      try {
        const response = await fetch(url, {
          method: "POST",
          headers: scannerHeaders,
          body: JSON.stringify(scannerPayload)
        });

        if (!response.ok) {
          lastError = `Scanner ${url} HTTP ${response.status}`;
          continue;
        }

        const payload = await response.json();
        const row = payload && payload.data && payload.data[0];
        const candidate = row && row.d && Number(row.d[0]);
        if (Number.isFinite(candidate)) {
          price = candidate;
          break;
        }

        lastError = `Scanner ${url} returned no valid price`;
      } catch (error) {
        lastError = error.message;
      }
    }

    if (!Number.isFinite(price)) {
      throw new Error(lastError || "TradingView price not available");
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
