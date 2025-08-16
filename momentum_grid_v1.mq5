//+------------------------------------------------------------------+
//| MomentumGridEA_USDJPY.mq5                                        |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

//--- inputs
input double Lots           = 0.01;
input int    TP_Pips        = 30;
input int    DAILY_ZONE_N   = 252; // use year period
input int    MA50_DAYS      = 50;
input int    EMA120         = 120;
input int    KAMA_FAST      = 5;
input int    KAMA_SLOW      = 50;
input int    ER_PERIOD      = 12;
input int    MinDistancePips= 40;  // min distance between entries in same zone

//--- globals
int    handle_ma50   = INVALID_HANDLE;
int    handle_ema120 = INVALID_HANDLE;
int    digits_symbol;
double point_symbol;
double pip_value;

//--- helper: compute pip size
void ComputePip()
{
   digits_symbol = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   point_symbol  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Special handling for JPY pairs
   if(StringFind(_Symbol, "JPY") >= 0)
      pip_value = 0.01; // 1 pip = 0.01
   else
      pip_value = (digits_symbol > 3 ? point_symbol * 10.0 : point_symbol);
}

//--- simple KAMA (expects price[] oldest-first)
double ComputeKAMAOnBuffer(const double &price[], int total, int index, int n_fast, int n_slow, int er_period)
{
   if(total<=0 || index<0 || index>=total) return(0.0);
   static double kama_arr[]; ArrayResize(kama_arr, total);
   kama_arr[0] = price[0];
   double fastest = 2.0/(n_fast+1);
   double slowest = 2.0/(n_slow+1);
   for(int i=1;i<total;i++)
   {
      int lookback = er_period;
      if(i - lookback + 1 < 0) lookback = i+1;
      double change = MathAbs(price[i] - price[i - lookback + 1]);
      double volatility = 0.0;
      for(int k = i - lookback + 1; k < i+1; k++)
         volatility += MathAbs(price[k] - price[k-1 < 0 ? 0 : k-1]);
      double er = (volatility == 0.0) ? 0.0 : change / volatility;
      double sc = MathPow(er * (fastest - slowest) + slowest, 2);
      kama_arr[i] = kama_arr[i-1] + sc * (price[i] - kama_arr[i-1]);
   }
   return(kama_arr[index]);
}

//--- zone helper
int ZoneOfPrice(double price, double mean, double sd)
{
   if(sd <= 0.0) return -1;
   double t1 = mean + sd, t2 = mean + 2*sd, t3 = mean + 3*sd;
   double b1 = mean - sd, b2 = mean - 2*sd, b3 = mean - 3*sd;
   if(price > t2) return 2;
   if(price > t1) return 1;
   if(price > mean) return 0;
   if(price < b3) return 5;
   if(price < b2) return 4;
   if(price < b1) return 3;
   return -1;
}

//--- check zone availability with distance filter
bool ZoneHasRoom(int zone, double current_price, int max_positions, double min_distance_pips)
{
   int count = 0;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         long type = PositionGetInteger(POSITION_TYPE);
         string comment = PositionGetString(POSITION_COMMENT);
         double pos_price = PositionGetDouble(POSITION_PRICE_OPEN);
         if(type == POSITION_TYPE_BUY && StringFind(comment, StringFormat("ZONE%d", zone)) >= 0)
         {
            count++;
            double dist_pips = MathAbs(current_price - pos_price) / pip_value;
            if(dist_pips < min_distance_pips)
               return false; // too close to existing position
         }
      }
   }
   return (count < max_positions);
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   // Ensure this runs only on USDJPY
   if(_Symbol != "USDJPY")
   {
      Print("This EA is designed for USDJPY only.");
      return INIT_FAILED;
   }

   ComputePip();

   // create indicator handles
   handle_ma50 = iMA(_Symbol, PERIOD_D1, MA50_DAYS, 0, MODE_SMA, PRICE_CLOSE);
   if(handle_ma50 == INVALID_HANDLE)
   {
      Print("Failed to create MA50 handle");
      return INIT_FAILED;
   }

   handle_ema120 = iMA(_Symbol, PERIOD_M5, EMA120, 0, MODE_EMA, PRICE_CLOSE);
   if(handle_ema120 == INVALID_HANDLE)
   {
      Print("Failed to create EMA120 handle");
      if(handle_ma50 != INVALID_HANDLE) IndicatorRelease(handle_ma50);
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handle_ma50 != INVALID_HANDLE)  IndicatorRelease(handle_ma50);
   if(handle_ema120 != INVALID_HANDLE) IndicatorRelease(handle_ema120);
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // --- 1) Daily bias: use last *closed* daily bar => shift=1
   double ma_buf[]; ArraySetAsSeries(ma_buf, true);
   if(CopyBuffer(handle_ma50, 0, 1, 1, ma_buf) != 1) return;
   double ma50 = ma_buf[0];
   double daily_close = iClose(_Symbol, PERIOD_D1, 1);

   if(!(daily_close > ma50)) return; // no buy bias

   // --- 2) Get previous M5 EMA120 (shift=1)
   double ema_buf[]; ArraySetAsSeries(ema_buf, true);
   if(CopyBuffer(handle_ema120, 0, 1, 1, ema_buf) != 1) return;
   double prev_ema120 = ema_buf[0];
   double prev_close = iClose(_Symbol, PERIOD_M5, 1);

   // --- 3) Compute KAMA on M5 closes
   int need = EMA120 + KAMA_SLOW + 50;
   double close_newest[]; ArraySetAsSeries(close_newest, true);
   int copied = CopyClose(_Symbol, PERIOD_M5, 0, need, close_newest);
   if(copied <= 1) return;
   double close_old[]; ArrayResize(close_old, copied);
   for(int i=0;i<copied;i++) close_old[i] = close_newest[copied-1 - i];
   int idx_prev = copied - 2;
   double prev_kama = ComputeKAMAOnBuffer(close_old, copied, idx_prev, KAMA_FAST, KAMA_SLOW, ER_PERIOD);

   // --- 4) Compute daily mean & sd for zones
   double daily_closes[]; ArraySetAsSeries(daily_closes, true);
   int dcopied = CopyClose(_Symbol, PERIOD_D1, 1, DAILY_ZONE_N, daily_closes);
   if(dcopied < DAILY_ZONE_N) return;
   double sum = 0.0;
   for(int i=0;i<dcopied;i++) sum += daily_closes[i];
   double mean = sum / dcopied;
   double var = 0.0;
   for(int i=0;i<dcopied;i++){ double d = daily_closes[i] - mean; var += d*d; }
   double sd = MathSqrt(var / (dcopied - 1));

   int zone = ZoneOfPrice(prev_close, mean, sd);
   if(zone < 0) return;

   // --- 5) Entry condition
   if(prev_kama > prev_ema120 && prev_close > prev_kama)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if( ZoneHasRoom(zone, ask, 2, MinDistancePips) )
      {
         double tp  = ask + TP_Pips * pip_value;
         string comment = StringFormat("MomentumGrid ZONE%d", zone);
         trade.SetExpertMagicNumber(123456);
         if(!trade.Buy(Lots, NULL, ask, 0.0, tp, comment))
            Print("Buy failed: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
         else
            PrintFormat("Buy placed zone=%d ask=%.3f tp=%.3f", zone, ask, tp);
      }
   }
}
//+------------------------------------------------------------------+
