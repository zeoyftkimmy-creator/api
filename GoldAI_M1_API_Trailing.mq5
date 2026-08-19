//+------------------------------------------------------------------+
//| Gold3CandleTrail.mq5                                            |
//| XAUUSD M1 - 3 Candle Confirmation + Initial SL + Trailing       |
//+------------------------------------------------------------------+
#property copyright "Custom EA"
#property version   "1.20"
#property strict

//--- INPUT
input double LotSize             = 0.01;

//--- SL AWAL berdasarkan JARAK HARGA GOLD
// Contoh BUY 3998 -> SL 3996
// Contoh SELL 3998 -> SL 4000
input double InitialSLDistance   = 2.0;

//--- TRAILING
input double TrailStart_Pips     = 50.0;
input double TrailDistance_Pips  = 5.0;

//--- TRAILING pip tetap menggunakan nilai harga
input double PipSize             = 1.00;

input ulong  MagicNumber         = 20260819;
input int    Slippage            = 50;

//--- API
input string ApiStatusUrl =
"https://gold-scalper-api-h376.onrender.com/status";

input int ApiCheckSeconds = 5;

//--- VARIABLES
datetime lastBarTime      = 0;
datetime lastApiCheckTime = 0;
bool     botEnabled       = true;


//+------------------------------------------------------------------+
//| CEK BAR BARU                                                     |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);

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

      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
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

   if(bull1 && bull2 && bull3)
      return 1;

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

   if(TimeCurrent() - lastApiCheckTime < ApiCheckSeconds)
      return;

   lastApiCheckTime = TimeCurrent();

   string headers = "";

   char postData[];
   char result[];

   string resultHeaders;

   int timeout = 5000;

   int res = WebRequest(
      "GET",
      ApiStatusUrl,
      headers,
      timeout,
      postData,
      result,
      resultHeaders
   );

   if(res == -1)
   {
      Print(
         "WebRequest API gagal. Error: ",
         GetLastError()
      );

      return;
   }

   string response = CharArrayToString(result);

   if(StringFind(response, "RUNNING") >= 0)
   {
      if(!botEnabled)
         Print("API RUNNING -> Bot aktif");

      botEnabled = true;
   }
   else
   if(StringFind(response, "STOPPED") >= 0)
   {
      if(botEnabled)
         Print("API STOPPED -> Entry baru dihentikan");

      botEnabled = false;
   }
   else
   {
      Print("Response API tidak dikenali: ", response);
   }
}


//+------------------------------------------------------------------+
//| BUKA BUY                                                         |
//+------------------------------------------------------------------+
void OpenBuy()
{
   MqlTradeRequest request;
   MqlTradeResult  result;

   ZeroMemory(request);
   ZeroMemory(result);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   //===============================================================
   // SL AWAL:
   // Contoh ASK = 3998
   // InitialSLDistance = 2
   // SL = 3996
   //===============================================================
   double sl = ask - InitialSLDistance;

   sl = NormalizeDouble(sl, _Digits);

   request.action      = TRADE_ACTION_DEAL;
   request.symbol      = _Symbol;
   request.volume      = LotSize;
   request.type        = ORDER_TYPE_BUY;
   request.price       = ask;
   request.sl          = sl;
   request.tp          = 0;
   request.deviation   = Slippage;
   request.magic      = MagicNumber;
   request.comment     = "3Candle-BUY";
   request.type_filling = ORDER_FILLING_FOK;

   if(!OrderSend(request, result))
   {
      Print(
         "BUY gagal. Error: ",
         GetLastError()
      );
   }
   else
   {
      Print(
         "BUY berhasil | Entry: ",
         ask,
         " | Initial SL: ",
         sl
      );
   }
}


//+------------------------------------------------------------------+
//| BUKA SELL                                                        |
//+------------------------------------------------------------------+
void OpenSell()
{
   MqlTradeRequest request;
   MqlTradeResult  result;

   ZeroMemory(request);
   ZeroMemory(result);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //===============================================================
   // SL AWAL:
   // Contoh BID = 3998
   // InitialSLDistance = 2
   // SL = 4000
   //===============================================================
   double sl = bid + InitialSLDistance;

   sl = NormalizeDouble(sl, _Digits);

   request.action      = TRADE_ACTION_DEAL;
   request.symbol      = _Symbol;
   request.volume      = LotSize;
   request.type        = ORDER_TYPE_SELL;
   request.price       = bid;
   request.sl          = sl;
   request.tp          = 0;
   request.deviation   = Slippage;
   request.magic      = MagicNumber;
   request.comment     = "3Candle-SELL";
   request.type_filling = ORDER_FILLING_FOK;

   if(!OrderSend(request, result))
   {
      Print(
         "SELL gagal. Error: ",
         GetLastError()
      );
   }
   else
   {
      Print(
         "SELL berhasil | Entry: ",
         bid,
         " | Initial SL: ",
         sl
      );
   }
}


//+------------------------------------------------------------------+
//| TRAILING STOP                                                    |
//+------------------------------------------------------------------+
void TrailPositions()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket <= 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;

      long posType = PositionGetInteger(POSITION_TYPE);

      double posOpen = PositionGetDouble(POSITION_PRICE_OPEN);
      double posSL   = PositionGetDouble(POSITION_SL);

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);


      //=============================================================
      // BUY TRAILING
      //=============================================================
      if(posType == POSITION_TYPE_BUY)
      {
         double profitPips =
            (bid - posOpen) / PipSize;

         if(profitPips >= TrailStart_Pips)
         {
            double newSL =
               bid - TrailDistance_Pips * PipSize;

            newSL = NormalizeDouble(newSL, _Digits);

            // SL hanya boleh naik
            if(newSL > posSL || posSL == 0)
            {
               ModifySL(ticket, newSL);
            }
         }
      }


      //=============================================================
      // SELL TRAILING
      //=============================================================
      else
      if(posType == POSITION_TYPE_SELL)
      {
         double profitPips =
            (posOpen - ask) / PipSize;

         if(profitPips >= TrailStart_Pips)
         {
            double newSL =
               ask + TrailDistance_Pips * PipSize;

            newSL = NormalizeDouble(newSL, _Digits);

            // SL hanya boleh turun
            if(newSL < posSL || posSL == 0)
            {
               ModifySL(ticket, newSL);
            }
         }
      }
   }
}


//+------------------------------------------------------------------+
//| MODIFIKASI SL                                                    |
//+------------------------------------------------------------------+
void ModifySL(ulong ticket, double newSL)
{
   MqlTradeRequest request;
   MqlTradeResult  result;

   ZeroMemory(request);
   ZeroMemory(result);

   if(!PositionSelectByTicket(ticket))
      return;

   request.action   = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol   = _Symbol;
   request.sl       = newSL;
   request.tp       = PositionGetDouble(POSITION_TP);

   if(!OrderSend(request, result))
   {
      Print(
         "Modify SL gagal | Ticket: ",
         ticket,
         " | Error: ",
         GetLastError()
      );
   }
}


//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   lastBarTime = iTime(
      _Symbol,
      PERIOD_M1,
      0
   );

   CheckApiStatus();

   Print("Gold3CandleTrail aktif.");
   Print(
      "Initial SL distance = ",
      InitialSLDistance,
      " harga"
   );

   return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| TICK                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Cek API
   CheckApiStatus();


   //===============================================================
   // TRAILING TETAP BERJALAN WALAU API STOP
   //===============================================================
   if(CountOpenPositions() > 0)
      TrailPositions();


   //===============================================================
   // API STOP = TIDAK ADA ENTRY BARU
   //===============================================================
   if(!botEnabled)
      return;


   //===============================================================
   // ENTRY HANYA SAAT CANDLE M1 BARU
   //===============================================================
   if(!IsNewBar())
      return;


   //===============================================================
   // MAKSIMAL 1 POSISI
   //===============================================================
   if(CountOpenPositions() >= 1)
      return;


   //===============================================================
   // CEK 3 CANDLE
   //===============================================================
   int signal = Check3CandleSignal();


   if(signal == 1)
   {
      OpenBuy();
   }
   else
   if(signal == -1)
   {
      OpenSell();
   }
}
//+------------------------------------------------------------------+
