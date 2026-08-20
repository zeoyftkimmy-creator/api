//+------------------------------------------------------------------+
//| Gold3CandleTrail.mq5                                             |
//| XAUUSD M1 - 3 Candle Confirmation + Initial SL + Trailing       |
//+------------------------------------------------------------------+
#property copyright "Custom EA"
#property version   "1.30"
#property strict

//==================================================================//
// INPUT
//==================================================================//

input double LotSize = 0.01;

//--- INITIAL SL
// BUY  : Entry 3998.00 -> SL 3996.00
// SELL : Entry 3998.00 -> SL 4000.00
input double InitialSLDistance = 2.00;

//--- TRAILING
// 50 pips = $0.50
// 5 pips  = $0.05
input double TrailStart_Pips    = 50.0;
input double TrailDistance_Pips = 5.0;

//--- XAUUSD
// 1 pip = $0.01
input double PipSize = 0.01;

input ulong MagicNumber = 20260819;
input int   Slippage    = 50;

//--- API
input string ApiStatusUrl =
"https://gold-scalper-api-h376.onrender.com/status";

input int ApiCheckSeconds = 5;

//==================================================================//
// VARIABLES
//==================================================================//

datetime lastBarTime      = 0;
datetime lastApiCheckTime = 0;

bool botEnabled = true;


//+------------------------------------------------------------------+
//| CEK BAR BARU                                                     |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime =
      iTime(_Symbol, PERIOD_M1, 0);

   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }

   return false;
}


//+------------------------------------------------------------------+
//| HITUNG POSISI EA                                                 |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket <= 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC)
         != (long)MagicNumber)
         continue;

      count++;
   }

   return count;
}


//+------------------------------------------------------------------+
//| KONFIRMASI 3 CANDLE                                              |
//+------------------------------------------------------------------+
int Check3CandleSignal()
{
   double open1  = iOpen(_Symbol, PERIOD_M1, 1);
   double close1 = iClose(_Symbol, PERIOD_M1, 1);

   double open2  = iOpen(_Symbol, PERIOD_M1, 2);
   double close2 = iClose(_Symbol, PERIOD_M1, 2);

   double open3  = iOpen(_Symbol, PERIOD_M1, 3);
   double close3 = iClose(_Symbol, PERIOD_M1, 3);

   bool bull1 = close1 > open1;
   bool bull2 = close2 > open2;
   bool bull3 = close3 > open3;

   bool bear1 = close1 < open1;
   bool bear2 = close2 < open2;
   bool bear3 = close3 < open3;

   //--- 3 candle bullish
   if(bull1 && bull2 && bull3)
      return 1;

   //--- 3 candle bearish
   if(bear1 && bear2 && bear3)
      return -1;

   return 0;
}


//+------------------------------------------------------------------+
//| CEK API START / STOP                                             |
//+------------------------------------------------------------------+
void CheckApiStatus()
{
   if(ApiStatusUrl == "")
      return;

   if(TimeCurrent() - lastApiCheckTime
      < ApiCheckSeconds)
      return;

   lastApiCheckTime = TimeCurrent();

   string headers = "";

   char postData[];
   char result[];

   string resultHeaders;

   int timeout = 5000;

   ResetLastError();

   int res = WebRequest(
      "GET",
      ApiStatusUrl,
      headers
