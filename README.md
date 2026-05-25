# XAUUSD SNIPER - MT5 Signal Engine Integration

Dashboard sinyal trading XAUUSD (Gold) berbasis web dengan **dual engine**: **SWING Trend-Follow + SCALP Mean-Reversion** dari MT5 EA.

## 🎯 Fitur Utama

### 1. SWING TREND-FOLLOW ENGINE
Strategi trend-following jangka menengah untuk swing trading:

**Indicators:**
- EMA 50 & 200 - Trend direction
- ADX (14) - Trend strength (min 20)
- RSI (14) - Overbought/oversold levels
- ATR (14) - Dynamic SL/TP

**Entry Signals:**
- Pin Bar (Hammer/Shooting Star)
- Breakout (break struktur)
- Engulfing patterns
- Requirement: ADX > 20 + RSI dalam zona

**Risk Management:**
- Risk per trade: 0.75% balance
- R:R Ratio: 2.5:1
- Max daily loss: 3%
- Max drawdown: 8%
- Consecutive loss auto-reduce risk 50%

**Trade Management:**
- Partial Close @ 1R (50%)
- Breakeven @ 1 ATR
- Trailing Stop @ 1.5 ATR (adaptive)

---

### 2. SCALP MEAN-REVERSION ENGINE  
Strategi mean-reversion cepat untuk scalping:

**Indicators:**
- Bollinger Bands (20, 2.0) - Bounce zones
- RSI Fast (7) - Quick oversold/overbought
- EMA 20 & 50 - Micro trend
- ATR (14) - Position sizing

**Entry Signals:**
- **BUY SCALP**: BB lower bounce + RSI < 25 + EMA bullish
- **SELL SCALP**: BB upper bounce + RSI > 75 + EMA bearish

**Risk Management:**
- Risk per trade: 0.3% balance (lebih kecil dari swing)
- R:R Ratio: 1.2-1.4:1 (cepat ambil profit)
- SL Distance: 0.8 ATR (ketat)
- Max daily loss: 3% (shared dengan swing)

**Trade Management:**
- Adaptive BE @ 0.3 ATR profit
- Dynamic TP toward BB Middle
- Adaptive Trailing @ 0.15 ATR

**Presets:**
- **SAFE**: Strict AND logic (SND + OF both needed)
- **AGGRESSIVE**: Fast OR logic (SND or OF enough)

---

### 3. GLOBAL RISK & FILTERS

**Daily Monitoring:**
- Daily P&L tracking (% balance)
- Consecutive loss counter
- Circuit breaker @ 8% equity drawdown
- Daily profit target (auto-stop @ 2%)

**Session Filters:**
- London: 14:00-18:30 (default allowed)
- New York: 19:30-00:30 (default allowed)
- Scalp Hours: 07:00-17:00 (tighter)

**News Filter:**
- Auto-block 20-45 min sebelum/sesudah high-impact news
- NFP: First Friday, 45 min window
- Custom configurable

---

## 📊 Cara Pakai

### Mode Selection:
```
[Mode Swing]     → Trend-follow swing trading
[Mode Scalping]  → Mean-reversion scalping
[Preset Safe]    → Strict confirmations (SAFE only)
[Preset Aggressive] → Fast signals (SCALPING only)
```

### Signal Display:
- **BUY SWING** / **SELL SWING** - Swing entry ready
- **BUY SCALP** / **SELL SCALP** - Scalp entry ready
- **WAIT** - Menunggu setup atau data
- **FILTER** - Session/News filter active
- **DONE** - Trade closed (TP/SL hit)

### Columns Displayed:
```
Mode:         SWING / SCALPING (SAFE/AGGRESSIVE)
Entry:        Harga masuk
TP:           Take profit target
SL:           Stop loss
Lot:          Risk amount (% balance)
Status:       VALID / RUNNING / DONE / WAIT
Reason:       Why this signal / Why no signal
Engine Info:  Indicator values & confirmations
Management:   MOVE BE / CLOSE PARTIAL / HOLD RUNNER
Market Comment: Penjelasan kondisi chart
```

---

## 🔧 Technical Stack

### Files:
- **index.html** - Main dashboard (UI + logic)
- **api/signal-engine.js** - Technical indicators + pattern detection
- **api/tradingview-history.js** - Historical M5 data (fallback)
- **api/tradingview-quote.js** - Live tick data

### Data Flow:
```
Live Tick (every 3s) 
  ↓
Build Synthetic 1M Candles
  ↓
Build M5/M15/M30/H1 OHLC
  ↓
Calculate Indicators (EMA, RSI, ATR, BB, ADX)
  ↓
┌─ Check Session/News Filters
├─ SWING or SCALP Signal Engine
└─ Output Signal + Management
```

### Indicator Functions (signal-engine.js):
```javascript
SMA(prices, period)
EMA(prices, period)
RSI(prices, period)
ATR(high, low, close, period)
BollingerBands(prices, period, devStdFactor)
ADX(high, low, close, period)

// Pattern Detection
isPinBar(open, close, high, low, direction)
isEngulfing(o1, c1, o2, c2, direction)
isBreakout(close, prevHigh, prevLow, direction)

// Signal Engines
SwingSignalEngine(bars) → Signal dengan atr, rsi, adx
ScalpSignalEngine(bars) → Signal dengan rsiScalp, bb, atr

// Risk Management
calculateRiskParameters(entry, sl, risk%, balance, rrRatio)
getDynamicRisk(baseRisk, consecutiveLosses, maxConsec)
isEquitySafe(equity, peak, maxDD%)
isDailyLossSafe(closedPnL, balance, maxDaily%)
```

---

## ⚙️ Configuration

### Risk Parameters (RiskConfig):
```javascript
SwingRisk: 0.75,        // % balance per swing trade
ScalpRisk: 0.3,         // % balance per scalp trade
MaxDailyLoss: 3.0,      // % balance daily limit
MaxDrawdown: 8.0,       // % equity circuit breaker
MaxConsecLoss: 3,       // Triggers 50% risk reduction
DailyProfitTarget: 2.0  // Auto-stop when reached
```

### Mode Config (getModeConfig):
```javascript
SWING: {
  emaFast: 50, emaSlow: 200,
  adxMin: 20, rsiPeriod: 14,
  rr: 2.5, atrSLMulti: 1.5,
  usePartialClose: true
}

SCALP SAFE: {
  fastEma: 21, slowEma: 55,
  risk: 24, rr: 1.4,
  requireHtfReady: true,
  requireHtfAlignment: true,
  confirmationMode: "AND"
}

SCALP AGGRESSIVE: {
  fastEma: 18, slowEma: 50,
  risk: 28, rr: 2,
  requireHtfReady: false,
  requireHtfAlignment: false,
  confirmationMode: "OR"
}
```

---

## 📈 Trading Logic Flow

### SWING Mode:
```
1. Check: trend (EMA 50 > 200?) → bullish/bearish
2. Check: ADX >= 20? → trend kuat?
3. Detect: Pin Bar / Breakout / Engulfing di last bar?
4. Check: RSI dalam zone (bullish: 35-70, bearish: 30-65)?
5. YES → Signal BUY/SELL SWING
6. SL: recent extreme + 1.5 ATR
7. TP: SL distance × 2.5 RR
8. Manage: BE @ 1 ATR, Trail @ 1.5 ATR
```

### SCALP Mode (SAFE):
```
1. Check: Session & News filters → allowed?
2. Check: H1 & M30 ready & aligned?
3. Detect: Harga bounce BB + RSI ekstrem?
4. Check: SND zone (demand/supply)?
5. Check: Order flow (bullish/bearish rejection)?
6. Require BOTH: SND zone AND order flow
7. YES → Signal BUY/SELL SCALP
8. SL: 0.8 ATR
9. TP: 0.8 ATR × 1.2-1.4 RR
10. Manage: BE @ 0.3 ATR, Trail @ 0.15 ATR
```

### SCALP Mode (AGGRESSIVE):
```
Same as SAFE, tapi:
- H1/M30 alignment NOT required
- Require EITHER: SND zone OR order flow (OR logic)
- Faster entry with looser confirmations
```

---

## 🔄 Trade Management

### Breakeven Setting:
- **SWING**: Move SL to BE when profit = 1 ATR
- **SCALP**: Move SL to BE when profit = 0.3 ATR

### Partial Close:
- **SWING**: Close 50% lot @ 1R profit
- **SCALP**: Close when profit >= 15 points

### Trailing Stop:
- **SWING**: Start trailing @ 1.5 ATR profit
  - Trail distance = 0.8 ATR (tightens as price advances)
  - Min step = 10% ATR (prevent order spam)
  
- **SCALP**: Start trailing @ 1.5× BE trigger
  - Trail distance = 0.15 ATR × adaptive
  - Min step = 5% ATR (smaller for faster moves)

### TP Extension:
- If price reaches 80% of distance to TP → extend TP by 1 ATR
- Applicable untuk SWING; SCALP locks TP

---

## 🎓 Example Signals

### Example 1: SWING BUY
```
Condition:
- EMA20 crossing above EMA50
- ADX = 24 (> 20 ✓)
- Recent bar: Engulfing pattern bullish
- RSI = 42 (in zone 35-70 ✓)

Output:
Entry: 4600.50
SL: 4590.25 (recent low - 1.5 ATR)
TP: 4625.00 (SL distance × 2.5)
Lot: 0.75% risk
Signal: BUY SWING [VALID]
Manage: Await profit...
```

### Example 2: SCALP BUY (SAFE mode)
```
Condition:
- Price bounces BB lower (touch below, close above) ✓
- RSI(7) = 18 (< 25 oversold) ✓
- EMA20 > EMA50 (bullish) ✓
- In demand zone ✓
- Order flow bullish (wick rejection) ✓
- H1 & M30 aligned bullish ✓

Output:
Entry: 4600.50
SL: 4599.75 (entry - 0.8 ATR)
TP: 4601.95 (entry + 0.8×1.4 ATR)
Lot: 0.3% risk
Signal: BUY SCALP [VALID]
Manage: AT profit + 5poin → Move BE, etc
```

---

## 📝 Notes & Disclaimers

- **Informational only** - Sinyal bersifat education, bukan rekomendasi
- **XAUUSD only** - Tuned untuk gold pair
- **1-min + 5-min** - Timeframe utama
- **Risk management mandatory** - Always use SL
- **Backtest required** - Test strategy dengan data real
- **No guarantee** - Masa lalu bukan jaminan masa depan

---

## 🚀 Future Enhancements

- [ ] Multi-symbol support (EURUSD, GBPUSD, etc)
- [ ] WebSocket real-time feed
- [ ] Database backtesting engine
- [ ] Advanced analytics dashboard
- [ ] Alert system (email/Discord/Telegram)
- [ ] Portfolio risk aggregation
- [ ] Machine learning signal confirmation

---

**Version**: 5.1 (Web Integration from MT5 EA)  
**Last Updated**: May 25, 2026  
**Status**: Production Ready

MIT
