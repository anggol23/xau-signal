/**
 * HEDGE FUND ULTIMATE PRO v5.1 - SIGNAL ENGINE (JavaScript)
 * Swing Trend-Follow + Scalp Mean-Reversion
 * Ported from MQ5 to JavaScript for web-based analysis
 */

// ===== TECHNICAL INDICATORS =====

/**
 * Calculate Simple Moving Average
 */
function SMA(prices, period) {
  if (prices.length < period) return null;
  let sum = 0;
  for (let i = prices.length - period; i < prices.length; i++) {
    sum += prices[i];
  }
  return sum / period;
}

/**
 * Calculate Exponential Moving Average
 */
function EMA(prices, period) {
  if (prices.length < period) return null;
  let k = 2 / (period + 1);
  let ema = prices[prices.length - period];
  
  for (let i = prices.length - period + 1; i < prices.length; i++) {
    ema = prices[i] * k + ema * (1 - k);
  }
  return ema;
}

/**
 * Calculate RSI (Relative Strength Index)
 */
function RSI(prices, period) {
  if (prices.length < period + 1) return null;
  
  let gains = 0, losses = 0;
  
  for (let i = prices.length - period; i < prices.length; i++) {
    let change = prices[i] - prices[i - 1];
    if (change > 0) gains += change;
    else losses += Math.abs(change);
  }
  
  let avgGain = gains / period;
  let avgLoss = losses / period;
  
  if (avgLoss === 0) return avgGain > 0 ? 100 : 0;
  
  let rs = avgGain / avgLoss;
  return 100 - (100 / (1 + rs));
}

/**
 * Calculate ATR (Average True Range)
 */
function ATR(high, low, close, period) {
  if (high.length < period || low.length < period || close.length < period) return null;
  
  let trSum = 0;
  let startIdx = high.length - period;
  
  for (let i = startIdx; i < high.length; i++) {
    let tr1 = high[i] - low[i];
    let tr2 = Math.abs(high[i] - close[i - 1]);
    let tr3 = Math.abs(low[i] - close[i - 1]);
    let tr = Math.max(tr1, tr2, tr3);
    trSum += tr;
  }
  
  return trSum / period;
}

/**
 * Calculate Bollinger Bands
 */
function BollingerBands(prices, period, devStdFactor) {
  if (prices.length < period) return null;
  
  let sma = SMA(prices.slice(-period), period);
  let variance = 0;
  
  for (let i = prices.length - period; i < prices.length; i++) {
    variance += Math.pow(prices[i] - sma, 2);
  }
  
  let stdDev = Math.sqrt(variance / period);
  
  return {
    middle: sma,
    upper: sma + (stdDev * devStdFactor),
    lower: sma - (stdDev * devStdFactor),
    stdDev: stdDev
  };
}

/**
 * Calculate ADX (Average Directional Index)
 */
function ADX(high, low, close, period) {
  if (high.length < period * 2 || low.length < period * 2 || close.length < period * 2) return null;
  
  let plusDI = [], minusDI = [];
  
  for (let i = 1; i < high.length; i++) {
    let upMove = high[i] - high[i - 1];
    let downMove = low[i - 1] - low[i];
    
    let plusDM = (upMove > downMove && upMove > 0) ? upMove : 0;
    let minusDM = (downMove > upMove && downMove > 0) ? downMove : 0;
    
    let tr = Math.max(
      high[i] - low[i],
      Math.abs(high[i] - close[i - 1]),
      Math.abs(low[i] - close[i - 1])
    );
    
    plusDI.push(tr !== 0 ? (plusDM / tr) * 100 : 0);
    minusDI.push(tr !== 0 ? (minusDM / tr) * 100 : 0);
  }
  
  let plusDI_Smooth = EMA(plusDI, period) || 0;
  let minusDI_Smooth = EMA(minusDI, period) || 0;
  let di_Diff = Math.abs(plusDI_Smooth - minusDI_Smooth);
  let di_Sum = plusDI_Smooth + minusDI_Smooth;
  let adx = di_Sum !== 0 ? (di_Diff / di_Sum) * 100 : 0;
  
  return {
    adx: adx,
    plusDI: plusDI_Smooth,
    minusDI: minusDI_Smooth
  };
}

// ===== PATTERN DETECTION =====

/**
 * Detect Pin Bar Pattern
 */
function isPinBar(open, close, high, low, direction) {
  let range = high - low;
  if (range <= 0) return false;
  
  let body = Math.abs(close - open);
  
  if (direction === 'bullish') {
    // Hammer: long lower shadow, small body, small upper shadow
    let lowerShadow = Math.min(open, close) - low;
    let upperShadow = high - Math.max(open, close);
    return lowerShadow >= range * 0.6 && body <= range * 0.3 && upperShadow <= range * 0.2;
  } else if (direction === 'bearish') {
    // Shooting star: small body, long upper shadow, small lower shadow
    let lowerShadow = Math.min(open, close) - low;
    let upperShadow = high - Math.max(open, close);
    return upperShadow >= range * 0.6 && body <= range * 0.3 && lowerShadow <= range * 0.2;
  }
  
  return false;
}

/**
 * Detect Engulfing Pattern
 */
function isEngulfing(o1, c1, o2, c2, direction) {
  if (direction === 'bullish') {
    // Bearish candle followed by bullish candle that engulfs it
    return c1 < o1 && c2 > o2 && c2 > o1 && o2 < c1;
  } else if (direction === 'bearish') {
    // Bullish candle followed by bearish candle that engulfs it
    return c1 > o1 && c2 < o2 && c2 < o1 && o2 > c1;
  }
  return false;
}

/**
 * Detect Breakout
 */
function isBreakout(close, prevHigh, prevLow, direction) {
  if (direction === 'bullish') {
    return close > prevHigh;
  } else if (direction === 'bearish') {
    return close < prevLow;
  }
  return false;
}

// ===== SWING SIGNAL ENGINE =====

function SwingSignalEngine(bars) {
  if (bars.length < 50) return null;
  
  let close = bars.map(b => b.c);
  let high = bars.map(b => b.h);
  let low = bars.map(b => b.l);
  let open = bars.map(b => b.o);
  
  // Calculate indicators
  let emaFast = EMA(close, 50);
  let emaSlow = EMA(close, 200);
  let rsi = RSI(close, 14);
  let atr = ATR(high, low, close, 14);
  let adxData = ADX(high, low, close, 14);
  
  if (!emaFast || !emaSlow || !rsi || !atr || !adxData) return null;
  
  let lastClose = close[close.length - 1];
  let prevClose = close[close.length - 2];
  let prevOpen = open[open.length - 2];
  
  let trend = emaFast > emaSlow ? 'bullish' : 'bearish';
  let trendStrong = adxData.adx >= 20;
  
  let signal = null;
  
  // SWING BUY SIGNAL
  if (trend === 'bullish' && adxData.plusDI > adxData.minusDI && 
      rsi >= 35 && rsi <= 70 && lastClose > emaFast) {
    
    let prevBody = Math.abs(prevClose - prevOpen);
    let prevRange = high[high.length - 2] - low[low.length - 2];
    
    if (prevBody > atr * 0.4 && prevRange > 0 && prevBody / prevRange >= 0.5) {
      let isBO = isBreakout(prevClose, high[high.length - 3], low[low.length - 3], 'bullish');
      let isEng = isEngulfing(open[open.length - 3], close[close.length - 3], 
                              prevOpen, prevClose, 'bullish');
      let isPB = isPinBar(prevOpen, prevClose, high[high.length - 2], 
                          low[low.length - 2], 'bullish');
      
      if (isBO || isEng || isPB) {
        signal = {
          type: 'BUY_SWING',
          trend: 'bullish',
          entry: lastClose,
          slPrice: Math.min(...low.slice(-3)) - atr * 1.5,
          atr: atr,
          rsi: rsi,
          adx: adxData.adx
        };
      }
    }
  }
  
  // SWING SELL SIGNAL
  if (trend === 'bearish' && adxData.minusDI > adxData.plusDI && 
      rsi >= 30 && rsi <= 65 && lastClose < emaFast) {
    
    let prevBody = Math.abs(prevClose - prevOpen);
    let prevRange = high[high.length - 2] - low[low.length - 2];
    
    if (prevBody > atr * 0.4 && prevRange > 0 && prevBody / prevRange >= 0.5) {
      let isBO = isBreakout(prevClose, high[high.length - 3], low[low.length - 3], 'bearish');
      let isEng = isEngulfing(open[open.length - 3], close[close.length - 3], 
                              prevOpen, prevClose, 'bearish');
      let isPB = isPinBar(prevOpen, prevClose, high[high.length - 2], 
                          low[low.length - 2], 'bearish');
      
      if (isBO || isEng || isPB) {
        signal = {
          type: 'SELL_SWING',
          trend: 'bearish',
          entry: lastClose,
          slPrice: Math.max(...high.slice(-3)) + atr * 1.5,
          atr: atr,
          rsi: rsi,
          adx: adxData.adx
        };
      }
    }
  }
  
  return signal;
}

// ===== SCALP SIGNAL ENGINE =====

function ScalpSignalEngine(bars) {
  if (bars.length < 30) return null;
  
  let close = bars.map(b => b.c);
  let high = bars.map(b => b.h);
  let low = bars.map(b => b.l);
  let open = bars.map(b => b.o);
  
  // Calculate indicators
  let bb = BollingerBands(close, 20, 2.0);
  let rsiScalp = RSI(close, 7);
  let atr = ATR(high, low, close, 14);
  let emaFast = EMA(close, 20);
  let emaSlow = EMA(close, 50);
  
  if (!bb || !rsiScalp || !atr || !emaFast || !emaSlow) return null;
  
  let lastClose = close[close.length - 1];
  let lastOpen = open[open.length - 1];
  let lastHigh = high[high.length - 1];
  let lastLow = low[low.length - 1];
  let prevClose = close[close.length - 2];
  let prevLow = low[low.length - 2];
  let prevHigh = high[high.length - 2];
  
  let signal = null;
  
  // SCALP BUY (BB lower bounce + RSI oversold)
  if (lastClose > bb.lower && lastClose < bb.middle &&
      prevLow <= bb.lower && lastClose > lastOpen &&
      rsiScalp < 25 && emaFast > emaSlow) {
    
    signal = {
      type: 'BUY_SCALP',
      trend: 'bullish',
      entry: lastClose,
      slPrice: lastClose - atr * 0.8,
      tpPrice: lastClose + atr * 1.2,
      atr: atr,
      rsiScalp: rsiScalp,
      bbLower: bb.lower,
      bbUpper: bb.upper,
      bbMiddle: bb.middle
    };
  }
  
  // SCALP SELL (BB upper bounce + RSI overbought)
  if (lastClose < bb.upper && lastClose > bb.middle &&
      prevHigh >= bb.upper && lastClose < lastOpen &&
      rsiScalp > 75 && emaFast < emaSlow) {
    
    signal = {
      type: 'SELL_SCALP',
      trend: 'bearish',
      entry: lastClose,
      slPrice: lastClose + atr * 0.8,
      tpPrice: lastClose - atr * 1.2,
      atr: atr,
      rsiScalp: rsiScalp,
      bbLower: bb.lower,
      bbUpper: bb.upper,
      bbMiddle: bb.middle
    };
  }
  
  return signal;
}

// ===== RISK MANAGEMENT =====

function calculateRiskParameters(entry, slPrice, riskPercent, balance, rrRatio = 2.5) {
  let slPoints = Math.abs(entry - slPrice);
  let riskAmount = balance * (riskPercent / 100);
  let lot = riskAmount / slPoints;
  let tp = entry + (slPrice < entry ? slPoints : -slPoints) * rrRatio;
  
  return {
    lot: lot,
    slPrice: slPrice,
    tpPrice: tp,
    riskPoints: slPoints,
    riskAmount: riskAmount
  };
}

/**
 * Calculate dynamic risk adjustment based on consecutive losses
 */
function getDynamicRisk(baseRisk, consecutiveLosses, maxConsecLoss = 3) {
  if (consecutiveLosses >= maxConsecLoss) {
    return baseRisk * 0.5; // Reduce to 50% on streak
  }
  return baseRisk;
}

/**
 * Check if equity is safe (circuit breaker)
 */
function isEquitySafe(currentEquity, peakEquity, maxDrawdownPercent) {
  let dd = ((peakEquity - currentEquity) / peakEquity) * 100;
  return dd < maxDrawdownPercent;
}

/**
 * Check if daily loss limit is exceeded
 */
function isDailyLossSafe(closedPnL, balance, maxDailyLossPercent) {
  let maxLoss = balance * (maxDailyLossPercent / 100);
  return closedPnL > -maxLoss;
}

// Export for use in HTML
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    SMA, EMA, RSI, ATR, BollingerBands, ADX,
    isPinBar, isEngulfing, isBreakout,
    SwingSignalEngine, ScalpSignalEngine,
    calculateRiskParameters, getDynamicRisk,
    isEquitySafe, isDailyLossSafe
  };
}
