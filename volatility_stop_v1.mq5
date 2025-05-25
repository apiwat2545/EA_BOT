//+------------------------------------------------------------------+
//|                                                     volatility_stop_v1.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh> // Include CTrade class

// Input parameters
input int    VS_Period = 20;           // Volatility Stop Period
input double VS_Multiplier = 2.75;      // Volatility Stop Multiplier
input double LotSize = 0.1;            // Lot Size
input ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT;

// Global variables
CTrade trade;
double prevStop = 0.0;
bool uptrend = true;
datetime lastBarTime = 0;
int atrHandle;
double atrBuffer[];

int OnInit(){
//---
   Print("Start Bot Now !!!!");
   atrHandle = iATR(_Symbol, timeframe, VS_Period); 
//---
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
   
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+


void OnTick(){
   
   datetime barTime = iTime(_Symbol, timeframe, 1);
   
   // detect new bar : if not new bar -> skip
   if (barTime == lastBarTime)
      return;
   lastBarTime = barTime;
   
   if (CopyBuffer(atrHandle, 0, 1, 1, atrBuffer) <= 0) {
      Print("Failed to get ATR data");
      return;
   }

   
   // Corrected iATR call
   //double atr = iATR(_Symbol, PERIOD_CURRENT, VS_Period);
   double atr = atrBuffer[0];
   double closePrice = iClose(_Symbol, timeframe, 1);
   double highPrice = iHigh(_Symbol, timeframe, 1);
   double lowPrice = iLow(_Symbol, timeframe, 1);
   
   double newStop = 0.0;
   bool trendChanged = false;
   
   
   /*
      Calculate the Volatility Stop:
      Uptrend: Volatility Stop = Close price - (ATR * Multiplier). 
      Downtrend: Volatility Stop = Close price + (ATR * Multiplier)
      
      Adjust for Previous Bars:
      For ongoing trends, the Volatility Stop is updated by comparing it to the previous bar's Volatility Stop.
      Uptrend: Volatility Stop = MAX(Previous Volatility Stop, Close price - (ATR * Multiplier)). 
      Downtrend: Volatility Stop = MIN(Previous Volatility Stop, Close price + (ATR * Multiplier)). 
   */
   // uptrend is vstop below price
   if (uptrend) {
      double stop = closePrice - atr * VS_Multiplier;
      newStop = MathMax(prevStop, stop);
      if (closePrice < newStop) {
         uptrend = false;
         trendChanged = true;
      }
   } else {
      double stop = closePrice + atr * VS_Multiplier;
      newStop = MathMin(prevStop, stop);
      if (closePrice > newStop) {
         uptrend = true;
         trendChanged = true;
      }
   }
   
   double sl, tp;
 
   if (trendChanged) {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if (uptrend) {
        // Set newStop
        newStop = closePrice - atr * VS_Multiplier;
        sl = NormalizeDouble(closePrice + atr * VS_Multiplier, _Digits); 
        tp = NormalizeDouble(closePrice - atr * VS_Multiplier, _Digits);
        trade.Sell(LotSize, _Symbol, bid, sl, tp, NULL);
    } else {
        // Set newStop
        newStop = closePrice + atr * VS_Multiplier;
        sl = NormalizeDouble(closePrice - atr * VS_Multiplier, _Digits);
        tp = NormalizeDouble(closePrice + atr * VS_Multiplier, _Digits); 
        trade.Buy(LotSize, _Symbol, ask, sl, tp, NULL);
    }
   }

   prevStop = newStop;
   

}
//+------------------------------------------------------------------+
