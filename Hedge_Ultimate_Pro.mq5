//+------------------------------------------------------------------+
//|   HEDGE FUND ULTIMATE PRO v5.1 – DUAL ENGINE (MT5)               |
//|   Swing Trend-Follow + Scalp Mean-Reversion                      |
//|   God-Tier: Adaptive Risk + Anti-MC + Profit Accumulator         |
//+------------------------------------------------------------------+
#property strict
#property copyright "Hedge Ultimate Pro v5.1"
#property version   "5.10"

#include <Trade/Trade.mqh>
CTrade trade;

//============================================================
//  RISK MANAGEMENT
//============================================================
input group "=== Risk Management ==="
input double RiskPercent       = 0.75;     // Risk per trade swing (% balance)
input double ScalpRiskPercent  = 0.3;      // Risk per trade scalp (% balance) - kecil!
input double MaxDailyLossP     = 3.0;      // Max daily loss (% balance)
input double MaxDrawdownP      = 8.0;      // Max equity drawdown (%) - circuit breaker
input int    MaxSwingPos       = 2;        // Max open swing positions
input int    MaxScalpPos       = 3;        // Max open scalp positions
input int    MagicSwing        = 778899;   // Magic Number swing
input int    MagicScalp        = 778900;   // Magic Number scalp
input int    CooldownBars      = 3;        // Cooldown bars setelah loss
input int    MaxConsecLoss     = 3;        // N loss berturut → risk -50%
input int    MaxTotalPos      = 4;        // Max TOTAL posisi (swing+scalp combined)
input double DailyProfitTarget = 2.0;      // Stop trading jika profit hari ini >= % balance (0=off)
input double MinMarginLevel   = 200.0;     // Min margin level % untuk entry baru

//============================================================
//  TREND FILTER (SWING)
//============================================================
input group "=== Swing: Trend Filter ==="
input int             EMA_Fast     = 50;
input int             EMA_Slow     = 200;
input ENUM_TIMEFRAMES HTF          = PERIOD_H1;   // HTF untuk trend direction (legacy)
input ENUM_TIMEFRAMES SwingEMA_TF = PERIOD_CURRENT;  // Swing EMA TF (sync dengan web: PERIOD_CURRENT = chart TF)
input int             ADX_Period   = 14;
input double          ADX_Min      = 20.0;

//============================================================
//  SWING ENTRY
//============================================================
input group "=== Swing: Entry ==="
input int    RSI_Period     = 14;
input double RSI_OB         = 70.0;
input double RSI_OS         = 30.0;
input double ATR_SL_Multi   = 1.5;      // SL = ATR x multi
input double Swing_RR       = 2.5;      // R:R ratio swing
input int    ATR_Period     = 14;

//============================================================
//  SWING TRADE MANAGEMENT
//============================================================
input group "=== Swing: Management ==="
input bool   UsePartialClose  = true;
input double PartialCloseRR   = 1.0;
input double PartialPercent   = 50.0;
input double BE_ATR_Multi     = 1.0;
input double Trail_ATR_Multi  = 1.5;
input double Trail_Step_ATR   = 0.8;
input bool   CloseOnOpposite  = true;

//============================================================
//  SCALP SETTINGS
//============================================================
input group "=== Scalp: Settings ==="
input bool   EnableScalp       = true;      // Aktifkan scalp mode
input int    BB_Period         = 20;        // Bollinger Band period
input double BB_Dev            = 2.0;       // BB deviasi
input int    Scalp_RSI_Period  = 7;         // RSI cepat untuk scalp
input double Scalp_RSI_OB     = 75.0;      // RSI overbought scalp trigger
input double Scalp_RSI_OS     = 25.0;      // RSI oversold scalp trigger
input int    Scalp_EMA_Fast    = 21;        // EMA fast scalp (sync dengan web)
input int    Scalp_EMA_Slow    = 55;        // EMA slow scalp (sync dengan web)
input bool   Scalp_RequireEMACross = true;  // Butuh EMA fast > slow (sync dengan web)
input double Scalp_RR         = 1.2;       // R:R ratio scalp (cepat ambil profit)
input double Scalp_SL_ATR     = 0.8;       // SL scalp = ATR x multi (ketat)
input double Scalp_MaxSpread  = 15;        // Max spread untuk scalp (lebih ketat)
input double Scalp_BE_ATR     = 0.3;       // Scalp BE trigger = ATR × multi (adaptive)
input double Scalp_Trail_ATR  = 0.15;      // Scalp trail distance = ATR × multi (adaptive)

//============================================================
//  FILTERS
//============================================================
input group "=== Filters ==="
input double MaxSpread         = 30;
input bool   UseSessionFilter  = true;
input int    SessionStartHour  = 2;        // London open
input int    SessionEndHour    = 20;       // NY close
input int    ScalpStartHour    = 7;        // Scalp hanya jam sibuk
input int    ScalpEndHour      = 17;       // Scalp stop sebelum NY close
input bool   CloseBeforeWeekend = true;
input bool   AvoidHighImpactHour = true;   // Skip entry 30m sebelum/sesudah news hour
input string NewsHours         = "8,13,15"; // Jam server rawan news (pisah koma)
input bool   DebugLog          = false;     // Print alasan filter reject (untuk diagnosis)

//============================================================
//  GLOBAL VARIABLES
//============================================================
int    ema_fast_handle, ema_slow_handle;
int    ema_fast_ltf_handle, ema_slow_ltf_handle;   // Swing EMA pada chart TF (sinkron dengan web)
int    ema_scalp_fast_handle, ema_scalp_slow_handle; // Scalp EMA pada chart TF
int    adx_handle, rsi_handle, atr_handle;
int    bb_handle, scalp_rsi_handle;
double ema_fast_val[], ema_slow_val[];
double ema_fast_ltf_val[], ema_slow_ltf_val[];
double ema_scalp_fast_val[], ema_scalp_slow_val[];
double adx_val[], plus_di[], minus_di[];
double rsi_val[], atr_val[];
double bb_upper[], bb_lower[], bb_mid[];
double scalp_rsi_val[];

datetime lastSwingBar    = 0;
datetime lastLossTime    = 0;
int      consecLosses    = 0;
datetime lastTradeDay    = 0;        // Track hari terakhir untuk OnTrade reset
int      lastDealsTotal  = 0;        // Track total deal terakhir untuk OnTrade

string gvPeakEquity;

// News hours parsed
int    newsHourArr[10];
int    newsHourCount = 0;

//============================================================
//  AUTO-DETECT FILLING MODE
//============================================================
ENUM_ORDER_TYPE_FILLING DetectFilling()
{
   long fillMode = 0;
   SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE, fillMode);
   if((fillMode & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((fillMode & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

//============================================================
//  PARSE NEWS HOURS STRING
//============================================================
void ParseNewsHours()
{
   newsHourCount = 0;
   string parts[];
   int count = StringSplit(NewsHours, ',', parts);
   for(int i = 0; i < count && i < 10; i++)
   {
      StringTrimLeft(parts[i]);
      StringTrimRight(parts[i]);
      newsHourArr[newsHourCount] = (int)StringToInteger(parts[i]);
      newsHourCount++;
   }
}

bool IsNearNewsHour()
{
   if(!AvoidHighImpactHour || newsHourCount == 0) return false;

   MqlDateTime dt;
   TimeCurrent(dt);
   int min = dt.hour * 60 + dt.min;

   for(int i = 0; i < newsHourCount; i++)
   {
      int newsMin = newsHourArr[i] * 60;
      // Hindari 30 menit sebelum dan 15 menit sesudah
      if(min >= newsMin - 30 && min <= newsMin + 15)
         return true;
   }
   return false;
}

//============================================================
//  INIT
//============================================================
int OnInit()
{
   trade.SetExpertMagicNumber(MagicSwing);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(DetectFilling());

   // Swing indicators
   ema_fast_handle = iMA(_Symbol, HTF, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   ema_slow_handle = iMA(_Symbol, HTF, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);

   // Swing EMA pada chart TF (sinkron dengan web)
   ema_fast_ltf_handle = iMA(_Symbol, SwingEMA_TF, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   ema_slow_ltf_handle = iMA(_Symbol, SwingEMA_TF, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);

   adx_handle      = iADX(_Symbol, _Period, ADX_Period);
   rsi_handle      = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
   atr_handle      = iATR(_Symbol, _Period, ATR_Period);

   // Scalp indicators
   bb_handle        = iBands(_Symbol, _Period, BB_Period, 0, BB_Dev, PRICE_CLOSE);
   scalp_rsi_handle = iRSI(_Symbol, _Period, Scalp_RSI_Period, PRICE_CLOSE);
   ema_scalp_fast_handle = iMA(_Symbol, _Period, Scalp_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   ema_scalp_slow_handle = iMA(_Symbol, _Period, Scalp_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);

   if(ema_fast_handle==INVALID_HANDLE || ema_slow_handle==INVALID_HANDLE ||
      ema_fast_ltf_handle==INVALID_HANDLE || ema_slow_ltf_handle==INVALID_HANDLE ||
      ema_scalp_fast_handle==INVALID_HANDLE || ema_scalp_slow_handle==INVALID_HANDLE ||
      adx_handle==INVALID_HANDLE || rsi_handle==INVALID_HANDLE ||
      atr_handle==INVALID_HANDLE || bb_handle==INVALID_HANDLE ||
      scalp_rsi_handle==INVALID_HANDLE)
   {
      Print("ERROR: Gagal membuat indicator handle!");
      return(INIT_FAILED);
   }

   ArraySetAsSeries(ema_fast_val, true);
   ArraySetAsSeries(ema_slow_val, true);
   ArraySetAsSeries(ema_fast_ltf_val, true);
   ArraySetAsSeries(ema_slow_ltf_val, true);
   ArraySetAsSeries(ema_scalp_fast_val, true);
   ArraySetAsSeries(ema_scalp_slow_val, true);
   ArraySetAsSeries(adx_val, true);
   ArraySetAsSeries(plus_di, true);
   ArraySetAsSeries(minus_di, true);
   ArraySetAsSeries(rsi_val, true);
   ArraySetAsSeries(atr_val, true);
   ArraySetAsSeries(bb_upper, true);
   ArraySetAsSeries(bb_lower, true);
   ArraySetAsSeries(bb_mid, true);
   ArraySetAsSeries(scalp_rsi_val, true);

   // Peak equity persistent
   gvPeakEquity = "HUP5_PeakEq_" + _Symbol + "_" + IntegerToString(MagicSwing);
   if(GlobalVariableCheck(gvPeakEquity))
   {
      double stored = GlobalVariableGet(gvPeakEquity);
      double current = AccountInfoDouble(ACCOUNT_EQUITY);
      if(stored > current && stored < current * 2.0)
         current = stored;
      GlobalVariableSet(gvPeakEquity, current);
   }
   else
      GlobalVariableSet(gvPeakEquity, AccountInfoDouble(ACCOUNT_EQUITY));

   CountRecentLosses();
   ParseNewsHours();

   // Inisialisasi tracking bar dan trade history untuk mencegah double-counting & entry tengah bar saat startup
   lastSwingBar   = iTime(_Symbol, _Period, 0);
   lastTradeDay   = iTime(_Symbol, PERIOD_D1, 0);
   HistorySelect(lastTradeDay, TimeCurrent());
   lastDealsTotal = HistoryDealsTotal();

   Print("HUP v5.0 DUAL ENGINE | Filling=", EnumToString(DetectFilling()),
         " | Scalp=", EnableScalp ? "ON" : "OFF",
         " | ConsecLoss=", consecLosses);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(ema_fast_handle!=INVALID_HANDLE)        IndicatorRelease(ema_fast_handle);
   if(ema_slow_handle!=INVALID_HANDLE)        IndicatorRelease(ema_slow_handle);
   if(ema_fast_ltf_handle!=INVALID_HANDLE)    IndicatorRelease(ema_fast_ltf_handle);
   if(ema_slow_ltf_handle!=INVALID_HANDLE)    IndicatorRelease(ema_slow_ltf_handle);
   if(ema_scalp_fast_handle!=INVALID_HANDLE)  IndicatorRelease(ema_scalp_fast_handle);
   if(ema_scalp_slow_handle!=INVALID_HANDLE)  IndicatorRelease(ema_scalp_slow_handle);
   if(adx_handle!=INVALID_HANDLE)             IndicatorRelease(adx_handle);
   if(rsi_handle!=INVALID_HANDLE)             IndicatorRelease(rsi_handle);
   if(atr_handle!=INVALID_HANDLE)             IndicatorRelease(atr_handle);
   if(bb_handle!=INVALID_HANDLE)              IndicatorRelease(bb_handle);
   if(scalp_rsi_handle!=INVALID_HANDLE)       IndicatorRelease(scalp_rsi_handle);
}

//============================================================
//  COUNT RECENT CONSECUTIVE LOSSES
//============================================================
void CountRecentLosses()
{
   consecLosses = 0;
   // Scan history 30 hari ke belakang untuk consec losses lintas hari
   HistorySelect(TimeCurrent() - 30 * 24 * 3600, TimeCurrent());

   int total = HistoryDealsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      long magic = (long)HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(magic != MagicSwing && magic != MagicScalp) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      if(profit < 0)
      {
         consecLosses++;
         if(consecLosses == 1)
            lastLossTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      }
      else
         break;
   }
}

//============================================================
//  COUNT POSITIONS (by magic)
//============================================================
int CountPositions(int magic)
{
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      count++;
   }
   return count;
}

//============================================================
//  CLOSE POSITIONS (by magic + optional direction filter)
//============================================================
void ClosePositions(int magic, int dirFilter=0)
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;

      if(dirFilter != 0)
      {
         int type = (int)PositionGetInteger(POSITION_TYPE);
         if(dirFilter == +1 && type != POSITION_TYPE_SELL) continue; // close sells only
         if(dirFilter == -1 && type != POSITION_TYPE_BUY) continue;  // close buys only
      }
      trade.SetExpertMagicNumber(magic);
      trade.PositionClose(ticket);
   }
}

void CloseAllMyPositions()
{
   ClosePositions(MagicSwing);
   ClosePositions(MagicScalp);
}

//============================================================
//  DAILY LOSS CHECK (both engines combined)
//============================================================
double GetTodayPnL()
{
   double pnl = 0;
   datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);
   HistorySelect(dayStart, TimeCurrent());

   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      long magic = (long)HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(magic != MagicSwing && magic != MagicScalp) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;

      pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT)
           + HistoryDealGetDouble(ticket, DEAL_SWAP)
           + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }
   return pnl;
}

bool DailySafe()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double maxLoss = balance * MaxDailyLossP / 100.0;
   double closedPnL = GetTodayPnL();

   // Cek closed PnL
   if(closedPnL < -maxLoss)
   {
      CloseAllMyPositions();
      Print("DAILY LOSS LIMIT: closed PnL=", DoubleToString(closedPnL,2));
      return false;
   }

   // Cek closed + floating PnL combined
   double floatingPnL = GetFloatingPnL();
   if((closedPnL + floatingPnL) < -maxLoss)
   {
      CloseAllMyPositions();
      Print("DAILY LOSS LIMIT (floating): total=", DoubleToString(closedPnL+floatingPnL,2));
      return false;
   }

   return true;
}

//============================================================
//  FLOATING PnL (posisi terbuka milik EA ini)
//============================================================
double GetFloatingPnL()
{
   double pnl = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      if(magic != MagicSwing && magic != MagicScalp) continue;
      pnl += PositionGetDouble(POSITION_PROFIT)
           + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

//============================================================
//  DAILY PROFIT TARGET (stop trading kalau sudah cukup)
//============================================================
bool DailyTargetReached()
{
   if(DailyProfitTarget <= 0) return false;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double target = balance * DailyProfitTarget / 100.0;
   double todayPnL = GetTodayPnL();
   return (todayPnL >= target);
}

//============================================================
//  MARGIN CHECK
//============================================================
bool MarginOK()
{
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   // marginLevel=0 berarti tidak ada posisi terbuka (unlimited)
   if(marginLevel == 0) return true;
   return (marginLevel >= MinMarginLevel);
}

//============================================================
//  TOTAL POSITION CHECK (combined)
//============================================================
int CountAllMyPositions()
{
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      if(magic == MagicSwing || magic == MagicScalp)
         count++;
   }
   return count;
}

//============================================================
//  EQUITY CIRCUIT BREAKER
//============================================================
bool EquitySafe()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double peak = GlobalVariableGet(gvPeakEquity);
   if(peak <= 0) peak = equity;

   if(equity > peak)
   {
      peak = equity;
      GlobalVariableSet(gvPeakEquity, peak);
   }

   double ddPercent = (peak - equity) / peak * 100.0;
   if(ddPercent >= MaxDrawdownP)
   {
      CloseAllMyPositions();
      Print("CIRCUIT BREAKER: DD ", DoubleToString(ddPercent,1), "%");
      return false;
   }
   return true;
}

//============================================================
//  FILTERS
//============================================================
bool SpreadOK(double maxSpr)
{
   double s = (SymbolInfoDouble(_Symbol,SYMBOL_ASK) - SymbolInfoDouble(_Symbol,SYMBOL_BID)) / _Point;
   return s <= maxSpr;
}

bool SessionOK()
{
   if(!UseSessionFilter) return true;
   MqlDateTime dt;
   TimeCurrent(dt);
   return (dt.hour >= SessionStartHour && dt.hour < SessionEndHour);
}

bool ScalpSessionOK()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   return (dt.hour >= ScalpStartHour && dt.hour < ScalpEndHour);
}

void CheckWeekendClose()
{
   if(!CloseBeforeWeekend) return;
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_week == 5 && dt.hour >= 20)
      CloseAllMyPositions();
}

bool CooldownOK()
{
   if(CooldownBars <= 0 || lastLossTime == 0) return true;
   int barsSinceLoss = iBarShift(_Symbol, _Period, lastLossTime, false);
   return (barsSinceLoss >= CooldownBars);
}

//============================================================
//  DYNAMIC RISK
//============================================================
double GetEffectiveRisk(double baseRisk)
{
   double risk = baseRisk;
   if(consecLosses >= MaxConsecLoss)
      risk *= 0.5;
   return risk;
}

//============================================================
//  LOAD ALL INDICATORS
//============================================================
bool LoadIndicators()
{
   if(CopyBuffer(ema_fast_handle, 0, 0, 3, ema_fast_val)            < 3) return false;
   if(CopyBuffer(ema_slow_handle, 0, 0, 3, ema_slow_val)            < 3) return false;
   if(CopyBuffer(ema_fast_ltf_handle, 0, 0, 3, ema_fast_ltf_val)    < 3) return false;
   if(CopyBuffer(ema_slow_ltf_handle, 0, 0, 3, ema_slow_ltf_val)    < 3) return false;
   if(CopyBuffer(ema_scalp_fast_handle, 0, 0, 3, ema_scalp_fast_val)< 3) return false;
   if(CopyBuffer(ema_scalp_slow_handle, 0, 0, 3, ema_scalp_slow_val)< 3) return false;
   if(CopyBuffer(adx_handle, 0, 0, 3, adx_val)                      < 3) return false;
   if(CopyBuffer(adx_handle, 1, 0, 3, plus_di)                       < 3) return false;
   if(CopyBuffer(adx_handle, 2, 0, 3, minus_di)                      < 3) return false;
   if(CopyBuffer(rsi_handle, 0, 0, 3, rsi_val)                       < 3) return false;
   if(CopyBuffer(atr_handle, 0, 0, 50, atr_val)                      < 50) return false;
   if(CopyBuffer(bb_handle, 1, 0, 3, bb_upper)                       < 3) return false; // Upper
   if(CopyBuffer(bb_handle, 2, 0, 3, bb_lower)                       < 3) return false; // Lower
   if(CopyBuffer(bb_handle, 0, 0, 3, bb_mid)                         < 3) return false; // Middle
   if(CopyBuffer(scalp_rsi_handle, 0, 0, 3, scalp_rsi_val)           < 3) return false;
   return true;
}

//============================================================
//  VOLATILITY FILTER (DYNAMIC ATR)
//============================================================
bool IsVolatilityOk()
{
   int totalATR = ArraySize(atr_val);
   if(totalATR < 10) return true; // fallback jika data kurang
   double sum = 0;
   for(int i = 0; i < totalATR; i++) sum += atr_val[i];
   double avgATR = sum / totalATR;
   // Volatilitas OK jika ATR saat ini >= 60% dari rata-rata 50 bar terakhir
   return (atr_val[1] >= avgATR * 0.6);
}

//============================================================
//  LOT CALCULATION
//============================================================
double LotCalc(double sl_points, double baseRisk)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * GetEffectiveRisk(baseRisk) / 100.0;

   double tickvalue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ticksize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(sl_points <= 0 || tickvalue <= 0 || ticksize <= 0)
      return 0.0;

   double lot = risk / (sl_points * (tickvalue / ticksize) * _Point);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0) lotStep = 0.01;

   lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   return NormalizeDouble(lot, 2);
}

//============================================================
//  VALIDATE SL/TP vs BROKER LIMITS
//============================================================
bool ValidateSLTP(double price, double sl, double tp, int direction)
{
   long stopsLevel = 0;
   SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL, stopsLevel);
   double minDist = stopsLevel * _Point;

   if(minDist > 0)
   {
      if(direction == +1)
      {
         if((sl > 0 && (price - sl) < minDist) || (tp > 0 && (tp - price) < minDist)) return false;
      }
      else
      {
         if((sl > 0 && (sl - price) < minDist) || (tp > 0 && (price - tp) < minDist)) return false;
      }
   }

   long freezeLevel = 0;
   SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL, freezeLevel);
   double freezeDist = freezeLevel * _Point;
   if(freezeDist > 0)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(direction == +1 && sl > 0 && (ask - sl) < freezeDist) return false;
      if(direction == -1 && sl > 0 && (sl - bid) < freezeDist) return false;
   }
   return true;
}

double NormalizePrice(double price)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) return NormalizeDouble(price, _Digits);
   return NormalizeDouble(MathRound(price / tickSize) * tickSize, _Digits);
}

//============================================================
//  TREND ANALYSIS (SWING)
//  Pakai chart TF EMA (bar[1] = last closed) supaya stabil
//============================================================
int GetTrend()
{
   if(ema_fast_ltf_val[1] > ema_slow_ltf_val[1]) return +1;
   if(ema_fast_ltf_val[1] < ema_slow_ltf_val[1]) return -1;
   return 0;
}

bool TrendStrong() { return adx_val[1] >= ADX_Min; }

//============================================================
//  DETECT PIN BAR PATTERN
//============================================================
bool IsPinBar(int barIndex, int direction)
{
   double open  = iOpen(_Symbol, _Period, barIndex);
   double close = iClose(_Symbol, _Period, barIndex);
   double high  = iHigh(_Symbol, _Period, barIndex);
   double low   = iLow(_Symbol, _Period, barIndex);
   
   double range = high - low;
   if(range <= 0) return false;
   
   double body = MathAbs(close - open);
   
   if(direction == +1) // Bullish Pin Bar (Hammer)
   {
      double lowerShadow = MathMin(open, close) - low;
      double upperShadow = high - MathMax(open, close);
      return (lowerShadow >= range * 0.6 && body <= range * 0.3 && upperShadow <= range * 0.2);
   }
   else if(direction == -1) // Bearish Pin Bar (Shooting Star)
   {
      double lowerShadow = MathMin(open, close) - low;
      double upperShadow = high - MathMax(open, close);
      return (upperShadow >= range * 0.6 && body <= range * 0.3 && lowerShadow <= range * 0.2);
   }
   return false;
}

//============================================================
//  SWING BUY SIGNAL
//  - Semua cek indikator pakai bar[1] (last closed bar)
//  - Body threshold diturunkan 0.4 -> 0.2 ATR
//  - body1/range1 > 0.5 dihapus agar pin bar tidak mati
//============================================================
bool SwingBuySignal()
{
   if(GetTrend() != +1) { if(DebugLog) Print("[SWING BUY] reject: trend != +1 (EMA", ema_fast_ltf_val[1], " vs ", ema_slow_ltf_val[1], ")"); return false; }
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= ema_fast_ltf_val[1]) { if(DebugLog) Print("[SWING BUY] reject: bid<=EMA50 ", bid, " vs ", ema_fast_ltf_val[1]); return false; }

   if(!TrendStrong()) { if(DebugLog) Print("[SWING BUY] reject: ADX<", ADX_Min, " (adx[1]=", adx_val[1], ")"); return false; }
   if(plus_di[1] <= minus_di[1]) { if(DebugLog) Print("[SWING BUY] reject: +DI<= -DI (", plus_di[1], " vs ", minus_di[1], ")"); return false; }

   // Zona RSI 35-70 di bar[1] (last closed)
   if(rsi_val[1] >= RSI_OB || rsi_val[1] < 35.0) { if(DebugLog) Print("[SWING BUY] reject: RSI[1]=", rsi_val[1], " di luar zona 35-70"); return false; }

   double open1  = iOpen(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);
   double open2  = iOpen(_Symbol, _Period, 2);
   double close2 = iClose(_Symbol, _Period, 2);
   double high2  = iHigh(_Symbol, _Period, 2);

   double body1  = close1 - open1;
   double body2  = close2 - open2;

   double atr = atr_val[1];
   if(atr <= 0) return false;

   // Body harus bullish DAN > 0.2 ATR (turun dari 0.4 supaya tidak terlalu ketat)
   if(body1 <= 0) { if(DebugLog) Print("[SWING BUY] reject: bar[1] non-bullish body=", body1); return false; }
   if(body1 < atr * 0.2) { if(DebugLog) Print("[SWING BUY] reject: body1<0.2*ATR (", body1, " < ", atr*0.2, ")"); return false; }
   // body1/range1 > 0.5 dihapus: konflik dengan IsPinBar (body <= 30%)

   bool breakout  = close1 > high2;
   bool engulfing = (body2 < 0) && (close1 > open2) && (open1 < close2);
   bool pinbar    = IsPinBar(1, +1);
   if(DebugLog) Print("[SWING BUY] body=", body1, " ATR=", atr, " BO=", breakout, " Eng=", engulfing, " PB=", pinbar);
   return (breakout || engulfing || pinbar);
}

//============================================================
//  SWING SELL SIGNAL
//============================================================
bool SwingSellSignal()
{
   if(GetTrend() != -1) { if(DebugLog) Print("[SWING SELL] reject: trend != -1"); return false; }
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ask >= ema_fast_ltf_val[1]) { if(DebugLog) Print("[SWING SELL] reject: ask>=EMA50"); return false; }

   if(!TrendStrong()) { if(DebugLog) Print("[SWING SELL] reject: ADX<", ADX_Min); return false; }
   if(minus_di[1] <= plus_di[1]) { if(DebugLog) Print("[SWING SELL] reject: -DI<= +DI"); return false; }

   // Zona RSI 30-65 di bar[1]
   if(rsi_val[1] <= RSI_OS || rsi_val[1] > 65.0) { if(DebugLog) Print("[SWING SELL] reject: RSI[1]=", rsi_val[1], " di luar zona 30-65"); return false; }

   double open1  = iOpen(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);
   double open2  = iOpen(_Symbol, _Period, 2);
   double close2 = iClose(_Symbol, _Period, 2);
   double low2   = iLow(_Symbol, _Period, 2);

   double body1  = open1 - close1;
   double body2  = open2 - close2;

   double atr = atr_val[1];
   if(atr <= 0) return false;

   // Body harus bearish DAN > 0.2 ATR
   if(body1 <= 0) { if(DebugLog) Print("[SWING SELL] reject: bar[1] non-bearish body=", body1); return false; }
   if(body1 < atr * 0.2) { if(DebugLog) Print("[SWING SELL] reject: body1<0.2*ATR"); return false; }
   // body1/range1 > 0.5 dihapus

   bool breakout  = close1 < low2;
   bool engulfing = (body2 < 0) && (close1 < open2) && (open1 > close2);
   bool pinbar    = IsPinBar(1, -1);
   if(DebugLog) Print("[SWING SELL] body=", body1, " ATR=", atr, " BO=", breakout, " Eng=", engulfing, " PB=", pinbar);
   return (breakout || engulfing || pinbar);
}

//============================================================
//  SCALP BUY SIGNAL (BB Lower bounce + RSI oversold + EMA cross)
//  Sync dengan web: tambah EMA fast > slow (chart TF)
//============================================================
bool ScalpBuySignal()
{
   if(!EnableScalp) return false;

   double close1 = iClose(_Symbol, _Period, 1);
   double low1   = iLow(_Symbol, _Period, 1);

   // Kondisi 1: Candle sebelumnya menyentuh/menembus BB lower
   if(low1 > bb_lower[1]) { if(DebugLog) Print("[SCALP BUY] reject: low1>BB_lower (", low1, " vs ", bb_lower[1], ")"); return false; }

   // Kondisi 2: Close kembali di atas BB lower (bounce, bukan tembus terus)
   if(close1 < bb_lower[1]) return false;

   // Kondisi 3: RSI cepat di area oversold (pada bar[1])
   if(scalp_rsi_val[1] > Scalp_RSI_OS) { if(DebugLog) Print("[SCALP BUY] reject: RSI[1]=", scalp_rsi_val[1], " > ", Scalp_RSI_OS); return false; }

   // Kondisi 4: Candle bounce bullish (close > open)
   if(close1 <= iOpen(_Symbol, _Period, 1)) return false;

   // Kondisi 5: Harga di bawah BB middle (masih ada ruang ke atas)
   if(close1 > bb_mid[0]) return false;

   // Kondisi 6 (sinkron web): EMA fast > slow pada chart TF (bar[1])
   if(Scalp_RequireEMACross && ema_scalp_fast_val[1] <= ema_scalp_slow_val[1]) { if(DebugLog) Print("[SCALP BUY] reject: EMA cross down"); return false; }

   // Kondisi 7: Tidak melawan HTF trend kuat (ADX > 30 + bearish H1/Swing = skip)
   if(adx_val[1] > 30.0 && GetTrend() == -1) return false;

   return true;
}

//============================================================
//  SCALP SELL SIGNAL (BB Upper bounce + RSI overbought + EMA cross)
//============================================================
bool ScalpSellSignal()
{
   if(!EnableScalp) return false;

   double close1 = iClose(_Symbol, _Period, 1);
   double high1  = iHigh(_Symbol, _Period, 1);

   // Kondisi 1: Candle sebelumnya menyentuh/menembus BB upper
   if(high1 < bb_upper[1]) { if(DebugLog) Print("[SCALP SELL] reject: high1<BB_upper"); return false; }

   // Kondisi 2: Close kembali di bawah BB upper (bounce)
   if(close1 > bb_upper[1]) return false;

   // Kondisi 3: RSI cepat di area overbought (bar[1])
   if(scalp_rsi_val[1] < Scalp_RSI_OB) { if(DebugLog) Print("[SCALP SELL] reject: RSI[1]=", scalp_rsi_val[1], " < ", Scalp_RSI_OB); return false; }

   // Kondisi 4: Candle bounce bearish
   if(close1 >= iOpen(_Symbol, _Period, 1)) return false;

   // Kondisi 5: Harga di atas BB middle
   if(close1 < bb_mid[0]) return false;

   // Kondisi 6 (sinkron web): EMA fast < slow pada chart TF (bar[1])
   if(Scalp_RequireEMACross && ema_scalp_fast_val[1] >= ema_scalp_slow_val[1]) { if(DebugLog) Print("[SCALP SELL] reject: EMA cross up"); return false; }

   // Kondisi 7: Tidak melawan HTF trend kuat
   if(adx_val[1] > 30.0 && GetTrend() == +1) return false;

   return true;
}

//============================================================
//  MANAGE SWING POSITIONS
//============================================================
void ManageSwing()
{
   double atrNow[];
   ArraySetAsSeries(atrNow, true);
   if(CopyBuffer(atr_handle, 0, 0, 1, atrNow) < 1) return;
   double atr = atrNow[0];
   if(atr <= 0) return;

   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicSwing) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      double volume    = PositionGetDouble(POSITION_VOLUME);
      int    type      = (int)PositionGetInteger(POSITION_TYPE);

      double price = (type==POSITION_TYPE_BUY) ?
                     SymbolInfoDouble(_Symbol,SYMBOL_BID) :
                     SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      double profitDist = (type==POSITION_TYPE_BUY) ?
                          (price-openPrice) : (openPrice-price);
      double slDist     = (type==POSITION_TYPE_BUY) ?
                          (openPrice-sl) : (sl-openPrice);

      // Partial Close
      if(UsePartialClose && slDist > 0 && profitDist >= slDist * PartialCloseRR)
      {
         string gvP = "HUP5_SwP_" + IntegerToString(ticket);
         if(!GlobalVariableCheck(gvP))
         {
            double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            if(lotStep <= 0) lotStep = 0.01;
            double closeLot = MathFloor((volume * PartialPercent / 100.0) / lotStep) * lotStep;
            closeLot = NormalizeDouble(closeLot, 2);
            double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            if(closeLot >= minLot && (volume - closeLot) >= minLot)
            {
               trade.SetExpertMagicNumber(MagicSwing);
               if(trade.PositionClosePartial(ticket, closeLot))
                  GlobalVariableSet(gvP, 1.0);
            }
         }
      }

      // Breakeven
      if(profitDist >= atr * BE_ATR_Multi)
      {
         double lock = atr * 0.2;
         if(type==POSITION_TYPE_BUY)
         {
            double nSL = NormalizePrice(openPrice + lock);
            if(sl < nSL)
            {
               trade.SetExpertMagicNumber(MagicSwing);
               trade.PositionModify(ticket, nSL, tp);
            }
         }
         else
         {
            double nSL = NormalizePrice(openPrice - lock);
            if(sl > nSL || sl == 0)
            {
               trade.SetExpertMagicNumber(MagicSwing);
               trade.PositionModify(ticket, nSL, tp);
            }
         }
      }

      // Progressive Trailing + Dynamic TP Extension
      if(profitDist >= atr * Trail_ATR_Multi)
      {
         double baseDist  = atr * Trail_Step_ATR;
         double profATR   = profitDist / atr;
         double tightF    = MathMax(0.4, 1.0 - (profATR - Trail_ATR_Multi) * 0.15);
         double trailDist = baseDist * tightF;

         // Dynamic TP: jika harga sudah > 80% jarak ke TP, extend TP 1 ATR
         double tpDist = (type==POSITION_TYPE_BUY) ? (tp - openPrice) : (openPrice - tp);
         double newTP = tp;
         if(tp > 0 && tpDist > 0 && profitDist >= tpDist * 0.8)
         {
            if(type==POSITION_TYPE_BUY)
               newTP = NormalizePrice(tp + atr);
            else
               newTP = NormalizePrice(tp - atr);
         }

         if(type==POSITION_TYPE_BUY)
         {
            double nSL = NormalizePrice(price - trailDist);
            // Trailing step minimal 10% dari ATR untuk mencegah spamming order modifikasi ke broker
            if((nSL - sl >= atr * 0.1 || sl == 0) && nSL > openPrice)
            {
               trade.SetExpertMagicNumber(MagicSwing);
               trade.PositionModify(ticket, nSL, newTP);
            }
            else if(newTP != tp && newTP > tp)
            {
               trade.SetExpertMagicNumber(MagicSwing);
               trade.PositionModify(ticket, sl, newTP);
            }
         }
         else
         {
            double nSL = NormalizePrice(price + trailDist);
            // Trailing step minimal 10% dari ATR
            if((sl - nSL >= atr * 0.1 || sl == 0) && nSL < openPrice)
            {
               trade.SetExpertMagicNumber(MagicSwing);
               trade.PositionModify(ticket, nSL, newTP);
            }
            else if(newTP != tp && newTP < tp)
            {
               trade.SetExpertMagicNumber(MagicSwing);
               trade.PositionModify(ticket, sl, newTP);
            }
         }
      }
   }
}

//============================================================
//  MANAGE SCALP POSITIONS (fast BE + quick trail)
//============================================================
void ManageScalp()
{
   double atrNow[];
   ArraySetAsSeries(atrNow, true);
   if(CopyBuffer(atr_handle, 0, 0, 1, atrNow) < 1) return;
   double atr = atrNow[0];
   if(atr <= 0) return;

   // BB mid untuk dynamic TP
   double bbMid[];
   ArraySetAsSeries(bbMid, true);
   if(CopyBuffer(bb_handle, 0, 0, 1, bbMid) < 1) return;

   double beTrigger  = atr * Scalp_BE_ATR;   // Adaptive BE trigger
   double lockDist   = atr * 0.05;           // Lock ~5% ATR profit
   double trailDist  = atr * Scalp_Trail_ATR; // Adaptive trail distance
   double trailStart = beTrigger * 1.5;       // Trail mulai setelah 1.5x BE trigger

   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicScalp) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      int    type      = (int)PositionGetInteger(POSITION_TYPE);

      double price = (type==POSITION_TYPE_BUY) ?
                     SymbolInfoDouble(_Symbol,SYMBOL_BID) :
                     SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      double profitDist = (type==POSITION_TYPE_BUY) ?
                          (price-openPrice) : (openPrice-price);

      // Adaptive Breakeven
      if(profitDist >= beTrigger)
      {
         if(type==POSITION_TYPE_BUY)
         {
            double nSL = NormalizePrice(openPrice + lockDist);
            if(sl < nSL)
            {
               trade.SetExpertMagicNumber(MagicScalp);
               trade.PositionModify(ticket, nSL, tp);
            }
         }
         else
         {
            double nSL = NormalizePrice(openPrice - lockDist);
            if(sl > nSL || sl == 0)
            {
               trade.SetExpertMagicNumber(MagicScalp);
               trade.PositionModify(ticket, nSL, tp);
            }
         }
      }

      // Adaptive Trailing + Dynamic TP toward BB mid
      if(profitDist >= trailStart)
      {
         // Dynamic TP: geser ke BB mid secara dinamis mengikuti pergerakan band
         double newTP = tp;
         if(type==POSITION_TYPE_BUY && bbMid[0] > price)
            newTP = NormalizePrice(bbMid[0]);
         else if(type==POSITION_TYPE_SELL && bbMid[0] < price)
            newTP = NormalizePrice(bbMid[0]);

         // Hanya modifikasi jika perbedaan TP cukup signifikan untuk mencegah spamming order ke broker
         bool updateTP = (newTP != tp && MathAbs(tp - newTP) >= atr * 0.1);

         if(type==POSITION_TYPE_BUY)
         {
            double nSL = NormalizePrice(price - trailDist);
            // Trailing step minimal 5% dari ATR untuk scalp
            if((nSL - sl >= atr * 0.05 || sl == 0) && nSL > openPrice)
            {
               trade.SetExpertMagicNumber(MagicScalp);
               trade.PositionModify(ticket, nSL, newTP);
            }
            else if(updateTP)
            {
               trade.SetExpertMagicNumber(MagicScalp);
               trade.PositionModify(ticket, sl, newTP);
            }
         }
         else
         {
            double nSL = NormalizePrice(price + trailDist);
            // Trailing step minimal 5% dari ATR untuk scalp
            if((sl - nSL >= atr * 0.05 || sl == 0) && nSL < openPrice)
            {
               trade.SetExpertMagicNumber(MagicScalp);
               trade.PositionModify(ticket, nSL, newTP);
            }
            else if(updateTP)
            {
               trade.SetExpertMagicNumber(MagicScalp);
               trade.PositionModify(ticket, sl, newTP);
            }
         }
      }
   }
}

//============================================================
//  ON TRADE EVENT
//============================================================
void OnTrade()
{
   datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);

   // Reset counter saat ganti hari (fix day-boundary bug)
   if(dayStart != lastTradeDay)
   {
      lastDealsTotal = 0;
      lastTradeDay = dayStart;
   }

   HistorySelect(dayStart, TimeCurrent());
   int currentTotal = HistoryDealsTotal();

   if(currentTotal > lastDealsTotal)
   {
      for(int i = lastDealsTotal; i < currentTotal; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         long magic = (long)HistoryDealGetInteger(ticket, DEAL_MAGIC);
         if(magic != MagicSwing && magic != MagicScalp) continue;
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                       + HistoryDealGetDouble(ticket, DEAL_SWAP)
                       + HistoryDealGetDouble(ticket, DEAL_COMMISSION);

         string mode = (magic == MagicScalp) ? "SCALP" : "SWING";

         if(profit < 0)
         {
            consecLosses++;
            lastLossTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
            Print(mode, " LOSS #", consecLosses, " net=", DoubleToString(profit,2));
         }
         else if(profit > 0)
         {
            if(consecLosses > 0)
               Print(mode, " WIN +", DoubleToString(profit,2), " after ", consecLosses, " losses");
            consecLosses = 0;
         }

         // Cleanup GlobalVariable partial close
         ulong posId = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         string gvP = "HUP5_SwP_" + IntegerToString(posId);
         if(GlobalVariableCheck(gvP)) GlobalVariableDel(gvP);
      }
   }
   lastDealsTotal = currentTotal;
}

//============================================================
//  MAIN TICK
//============================================================
void OnTick()
{
   // ===== Management setiap tick =====
   ManageSwing();
   ManageScalp();

   // ===== Circuit breakers =====
   if(!EquitySafe()) return;
   CheckWeekendClose();

   // ===== Bar baru check =====
   datetime now = iTime(_Symbol, _Period, 0);
   bool newBar = (now != lastSwingBar);
   if(newBar) lastSwingBar = now;

   if(!newBar) return; // Semua entry hanya di bar baru

   // ===== Global filters =====
   if(!DailySafe()) return;
   if(!CooldownOK()) return;
   if(DailyTargetReached()) return;  // Sudah cukup profit hari ini
   if(!MarginOK()) return;           // Margin terlalu rendah

   // ===== Load indicators =====
   if(!LoadIndicators()) return;

   double atr = atr_val[1];
   if(atr < _Point * 10) return; // Proteksi batas spread dasar (sangat kecil)
   if(!IsVolatilityOk()) return; // Filter volatilitas adaptif

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   int totalPos = CountAllMyPositions();

   // =========================================================
   //  ENGINE 1: SWING ENTRIES
   // =========================================================
   if(SpreadOK(MaxSpread) && SessionOK() && !IsNearNewsHour() && totalPos < MaxTotalPos)
   {
      int swingPos = CountPositions(MagicSwing);

      // --- SWING BUY ---
      if(SwingBuySignal() && swingPos < MaxSwingPos)
      {
         if(CloseOnOpposite) ClosePositions(MagicSwing, +1); // close sells

         double slP = NormalizePrice(iLow(_Symbol,_Period,1) - atr * ATR_SL_Multi);
         if(slP < ask)
         {
            double minD = atr * 0.5;
            if((ask - slP) < minD) slP = NormalizePrice(ask - minD);

            double tpP = NormalizePrice(ask + (ask - slP) * Swing_RR);

            if(ValidateSLTP(ask, slP, tpP, +1))
            {
               double lot = LotCalc((ask - slP) / _Point, RiskPercent);
               if(lot > 0)
               {
                  trade.SetExpertMagicNumber(MagicSwing);
                  if(trade.Buy(lot, _Symbol, ask, slP, tpP, "SWING BUY"))
                     Print("SWING BUY: Lot=", lot, " SL=", slP, " TP=", tpP);
               }
            }
         }
      }

      // --- SWING SELL ---
      if(SwingSellSignal() && swingPos < MaxSwingPos)
      {
         if(CloseOnOpposite) ClosePositions(MagicSwing, -1); // close buys

         double slP = NormalizePrice(iHigh(_Symbol,_Period,1) + atr * ATR_SL_Multi);
         if(slP > bid)
         {
            double minD = atr * 0.5;
            if((slP - bid) < minD) slP = NormalizePrice(bid + minD);

            double tpP = NormalizePrice(bid - (slP - bid) * Swing_RR);

            if(ValidateSLTP(bid, slP, tpP, -1))
            {
               double lot = LotCalc((slP - bid) / _Point, RiskPercent);
               if(lot > 0)
               {
                  trade.SetExpertMagicNumber(MagicSwing);
                  if(trade.Sell(lot, _Symbol, bid, slP, tpP, "SWING SELL"))
                     Print("SWING SELL: Lot=", lot, " SL=", slP, " TP=", tpP);
               }
            }
         }
      }
   }

   totalPos = CountAllMyPositions(); // Refresh setelah swing mungkin buka posisi

   // =========================================================
   //  ENGINE 2: SCALP ENTRIES
   // =========================================================
   if(EnableScalp && SpreadOK(Scalp_MaxSpread) && ScalpSessionOK() && !IsNearNewsHour() && totalPos < MaxTotalPos)
   {
      int scalpPos = CountPositions(MagicScalp);

      // --- SCALP BUY (BB lower bounce) ---
      if(ScalpBuySignal() && scalpPos < MaxScalpPos)
      {
         double slDist = atr * Scalp_SL_ATR;
         double slP    = NormalizePrice(ask - slDist);
         double tpP    = NormalizePrice(ask + slDist * Scalp_RR);

         // TP tidak melewati BB mid (target realistis)
         if(tpP > bb_mid[0])
            tpP = NormalizePrice(bb_mid[0]);

         // Pastikan masih ada ruang profit minimal 0.5x SL
         if((tpP - ask) < slDist * 0.5) { /* skip, target terlalu kecil */ }
         else if(ValidateSLTP(ask, slP, tpP, +1))
         {
            double lot = LotCalc(slDist / _Point, ScalpRiskPercent);
            if(lot > 0)
            {
               trade.SetExpertMagicNumber(MagicScalp);
               if(trade.Buy(lot, _Symbol, ask, slP, tpP, "SCALP BUY"))
                  Print("SCALP BUY: Lot=", lot, " SL=", slP, " TP=", tpP,
                        " BB_low=", DoubleToString(bb_lower[1],_Digits));
            }
         }
      }

      // --- SCALP SELL (BB upper bounce) ---
      if(ScalpSellSignal() && scalpPos < MaxScalpPos)
      {
         double slDist = atr * Scalp_SL_ATR;
         double slP    = NormalizePrice(bid + slDist);
         double tpP    = NormalizePrice(bid - slDist * Scalp_RR);

         // TP tidak melewati BB mid
         if(tpP < bb_mid[0])
            tpP = NormalizePrice(bb_mid[0]);

         // Pastikan masih ada ruang profit minimal 0.5x SL
         if((bid - tpP) < slDist * 0.5) { /* skip */ }
         else if(ValidateSLTP(bid, slP, tpP, -1))
         {
            double lot = LotCalc(slDist / _Point, ScalpRiskPercent);
            if(lot > 0)
            {
               trade.SetExpertMagicNumber(MagicScalp);
               if(trade.Sell(lot, _Symbol, bid, slP, tpP, "SCALP SELL"))
                  Print("SCALP SELL: Lot=", lot, " SL=", slP, " TP=", tpP,
                        " BB_up=", DoubleToString(bb_upper[1],_Digits));
            }
         }
      }
   }
}
