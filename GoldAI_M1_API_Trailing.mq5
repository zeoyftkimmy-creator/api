//+------------------------------------------------------------------+
//| Gold3CandleTrail.mq5                                             |
//| XAUUSD M1 - 3 Candle + Initial SL + Trailing + API START/STOP   |
//+------------------------------------------------------------------+
#property copyright "Custom EA"
#property version   "1.40"
#property strict

//==================================================================//
// INPUT
//==================================================================//

//--- LOT
input double LotSize = 0.01;

//--- INITIAL STOP LOSS
// BUY  : Entry 3998.00 -> SL 3996.00
// SELL : Entry 3998.00 -> SL 4000.00
input double InitialSLDistance = 2.00;

//--- TRAILING
// 50 pips = $0.50
// 5 pips  = $0.05
input double TrailStart_Pips    = 50.0;
input double TrailDistance_Pips = 5.0;

//--- GOLD PIP
// 1 pip = $0.01
input double PipSize = 0.01;

//--- TRADE
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


//==================================================================//
// CEK BAR M1 BARU
//==================================================================//

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


//==================================================================//
// HITUNG POSISI EA
//==================================================================//

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

      //--- Symbol harus sama
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      //--- Magic Number harus sama
      if(PositionGetInteger(POSITION_MAGIC)
         != (long)MagicNumber)
         continue;

      count++;
   }

   return count;
}


//==================================================================//
// CEK 3 CANDLE
//==================================================================//

int Check3CandleSignal()
{
   //--- Candle 1
   double open1 =
      iOpen(_Symbol, PERIOD_M1, 1);

   double close1 =
      iClose(_Symbol, PERIOD_M1, 1);

   //--- Candle 2
   double open2 =
      iOpen(_Symbol, PERIOD_M1, 2);

   double close2 =
      iClose(_Symbol, PERIOD_M1, 2);

   //--- Candle 3
   double open3 =
      iOpen(_Symbol, PERIOD_M1, 3);

   double close3 =
      iClose(_Symbol, PERIOD_M1, 3);


   //--- Bullish
   bool bull1 = close1 > open1;
   bool bull2 = close2 > open2;
   bool bull3 = close3 > open3;


   //--- Bearish
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


//==================================================================//
// CEK API START / STOP
//==================================================================//

void CheckApiStatus()
{
   //--- API kosong
   if(ApiStatusUrl == "")
      return;


   //--- Cek setiap beberapa detik
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


   //===============================================================
   // WEB REQUEST
   //===============================================================

   int res = WebRequest(
      "GET",
      ApiStatusUrl,
      headers,
      timeout,
      postData,
      result,
      resultHeaders
   );


   //===============================================================
   // REQUEST GAGAL
   //===============================================================

   if(res == -1)
   {
      Print(
         "WebRequest API gagal. Error = ",
         GetLastError()
      );

      return;
   }


   //===============================================================
   // RESPONSE API
   //===============================================================

   string response =
      CharArrayToString(result);


   Print(
      "API Response: ",
      response
   );


   //===============================================================
   // API RUNNING
   //
   // Contoh:
   // {"running":true}
   //===============================================================

   if(
      StringFind(response, "\"running\":true") >= 0 ||
      StringFind(response, "\"running\": true") >= 0
   )
   {
      if(!botEnabled)
      {
         Print(
            "API RUNNING -> Bot AKTIF"
         );
      }

      botEnabled = true;

      return;
   }


   //===============================================================
   // API STOPPED
   //
   // Contoh:
   // {"running":false}
   //===============================================================

   if(
      StringFind(response, "\"running\":false") >= 0 ||
      StringFind(response, "\"running\": false") >= 0
   )
   {
      if(botEnabled)
      {
         Print(
            "API STOPPED -> Entry BARU dihentikan"
         );
      }

      botEnabled = false;

      return;
   }


   //===============================================================
   // RESPONSE TIDAK DIKENALI
   //===============================================================

   Print(
      "Response API tidak dikenali: ",
      response
   );
}


//==================================================================//
// CEK JARAK MINIMUM SL BROKER
//==================================================================//

bool IsValidSLDistance(
   ENUM_ORDER_TYPE orderType,
   double sl
)
{
   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID
      );

   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK
      );


   long stopsLevel =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      );


   double minDistance =
      stopsLevel * _Point;


   //--- BUY
   if(orderType == ORDER_TYPE_BUY)
   {
      if((bid - sl) < minDistance)
         return false;
   }


   //--- SELL
   if(orderType == ORDER_TYPE_SELL)
   {
      if((sl - ask) < minDistance)
         return false;
   }


   return true;
}


//==================================================================//
// BUKA BUY
//==================================================================//

void OpenBuy()
{
   MqlTradeRequest request;
   MqlTradeResult  result;

   ZeroMemory(request);
   ZeroMemory(result);


   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK
      );


   //===============================================================
   // INITIAL SL
   //
   // Contoh:
   // Entry = 3998.00
   // SL    = 3996.00
   //===============================================================

   double sl =
      ask - InitialSLDistance;


   sl =
      NormalizeDouble(
         sl,
         _Digits
      );


   //--- Cek jarak SL
   if(!IsValidSLDistance(
      ORDER_TYPE_BUY,
      sl
   ))
   {
      Print(
         "BUY dibatalkan: Initial SL terlalu dekat."
      );

      return;
   }


   //===============================================================
   // REQUEST BUY
   //===============================================================

   request.action =
      TRADE_ACTION_DEAL;

   request.symbol =
      _Symbol;

   request.volume =
      LotSize;

   request.type =
      ORDER_TYPE_BUY;

   request.price =
      ask;

   request.sl =
      sl;

   request.tp =
      0;

   request.deviation =
      Slippage;

   request.magic =
      MagicNumber;

   request.comment =
      "3Candle-BUY";


   //--- gunakan filling mode broker
   request.type_filling =
      (ENUM_ORDER_TYPE_FILLING)
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_FILLING_MODE
      );


   ResetLastError();


   if(!OrderSend(
      request,
      result
   ))
   {
      Print(
         "BUY gagal. Error = ",
         GetLastError()
      );

      return;
   }


   //===============================================================
   // CEK HASIL ORDER
   //===============================================================

   if(
      result.retcode != TRADE_RETCODE_DONE &&
      result.retcode != TRADE_RETCODE_PLACED
   )
   {
      Print(
         "BUY ditolak broker. Retcode = ",
         result.retcode
      );

      return;
   }


   Print(
      "BUY BERHASIL | Entry = ",
      ask,
      " | Initial SL = ",
      sl
   );
}


//==================================================================//
// BUKA SELL
//==================================================================//

void OpenSell()
{
   MqlTradeRequest request;
   MqlTradeResult  result;

   ZeroMemory(request);
   ZeroMemory(result);


   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID
      );


   //===============================================================
   // INITIAL SL
   //
   // Contoh:
   // Entry = 3998.00
   // SL    = 4000.00
   //===============================================================

   double sl =
      bid + InitialSLDistance;


   sl =
      NormalizeDouble(
         sl,
         _Digits
      );


   //--- Cek jarak SL
   if(!IsValidSLDistance(
      ORDER_TYPE_SELL,
      sl
   ))
   {
      Print(
         "SELL dibatalkan: Initial SL terlalu dekat."
      );

      return;
   }


   //===============================================================
   // REQUEST SELL
   //===============================================================

   request.action =
      TRADE_ACTION_DEAL;

   request.symbol =
      _Symbol;

   request.volume =
      LotSize;

   request.type =
      ORDER_TYPE_SELL;

   request.price =
      bid;

   request.sl =
      sl;

   request.tp =
      0;

   request.deviation =
      Slippage;

   request.magic =
      MagicNumber;

   request.comment =
      "3Candle-SELL";


   //--- gunakan filling mode broker
   request.type_filling =
      (ENUM_ORDER_TYPE_FILLING)
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_FILLING_MODE
      );


   ResetLastError();


   if(!OrderSend(
      request,
      result
   ))
   {
      Print(
         "SELL gagal. Error = ",
         GetLastError()
      );

      return;
   }


   //===============================================================
   // CEK HASIL ORDER
   //===============================================================

   if(
      result.retcode != TRADE_RETCODE_DONE &&
      result.retcode != TRADE_RETCODE_PLACED
   )
   {
      Print(
         "SELL ditolak broker. Retcode = ",
         result.retcode
      );

      return;
   }


   Print(
      "SELL BERHASIL | Entry = ",
      bid,
      " | Initial SL = ",
      sl
   );
}


//==================================================================//
// TRAILING STOP
//==================================================================//

void TrailPositions()
{
   for(
      int i = PositionsTotal() - 1;
      i >= 0;
      i--
   )
   {
      ulong ticket =
         PositionGetTicket(i);


      if(ticket <= 0)
         continue;


      if(!PositionSelectByTicket(ticket))
         continue;


      //=============================================================
      // FILTER SYMBOL
      //=============================================================

      if(
         PositionGetString(
            POSITION_SYMBOL
         ) != _Symbol
      )
         continue;


      //=============================================================
      // FILTER MAGIC
      //=============================================================

      if(
         PositionGetInteger(
            POSITION_MAGIC
         ) != (long)MagicNumber
      )
         continue;


      //=============================================================
      // DATA POSISI
      //=============================================================

      long posType =
         PositionGetInteger(
            POSITION_TYPE
         );


      double posOpen =
         PositionGetDouble(
            POSITION_PRICE_OPEN
         );


      double posSL =
         PositionGetDouble(
            POSITION_SL
         );


      double bid =
         SymbolInfoDouble(
            _Symbol,
            SYMBOL_BID
         );


      double ask =
         SymbolInfoDouble(
            _Symbol,
            SYMBOL_ASK
         );


      //=============================================================
      // BUY TRAILING
      //=============================================================

      if(
         posType == POSITION_TYPE_BUY
      )
      {
         //--- Hitung running dalam pip
         double profitPips =
            (bid - posOpen)
            / PipSize;


         //--- Belum mencapai +50 pips
         if(
            profitPips <
            TrailStart_Pips
         )
         {
            continue;
         }


         //==========================================================
         // TRAILING SL
         //
         // Entry 3998.00
         //
         // Harga 3998.50
         // Running +50 pips
         //
         // SL:
         // 3998.50 - 0.05
         // = 3998.45
         //==========================================================

         double newSL =
            bid -
            (
               TrailDistance_Pips *
               PipSize
            );


         newSL =
            NormalizeDouble(
               newSL,
               _Digits
            );


         //--- Pastikan SL valid
         if(!IsValidSLDistance(
            ORDER_TYPE_BUY,
            newSL
         ))
         {
            continue;
         }


         //--- SL hanya BOLEH NAIK
         if(
            posSL == 0 ||
            newSL > posSL
         )
         {
            ModifySL(
               ticket,
               newSL
            );
         }
      }


      //=============================================================
      // SELL TRAILING
      //=============================================================

      else
      if(
         posType == POSITION_TYPE_SELL
      )
      {
         //--- Hitung running dalam pip
         double profitPips =
            (posOpen - ask)
            / PipSize;


         //--- Belum mencapai +50 pips
         if(
            profitPips <
            TrailStart_Pips
         )
         {
            continue;
         }


         //==========================================================
         // TRAILING SL
         //
         // Entry 3998.00
         //
         // Harga 3997.50
         // Running +50 pips
         //
         // SL:
         // 3997.50 + 0.05
         // = 3997.55
         //==========================================================

         double newSL =
            ask +
            (
               TrailDistance_Pips *
               PipSize
            );


         newSL =
            NormalizeDouble(
               newSL,
               _Digits
            );


         //--- Pastikan SL valid
         if(!IsValidSLDistance(
            ORDER_TYPE_SELL,
            newSL
         ))
         {
            continue;
         }


         //--- SL hanya BOLEH TURUN
         if(
            posSL == 0 ||
            newSL < posSL
         )
         {
            ModifySL(
               ticket,
               newSL
            );
         }
      }
   }
}


//==================================================================//
// MODIFIKASI SL
//==================================================================//

void ModifySL(
   ulong ticket,
   double newSL
)
{
   MqlTradeRequest request;
   MqlTradeResult  result;

   ZeroMemory(request);
   ZeroMemory(result);


   //--- pilih posisi
   if(!PositionSelectByTicket(ticket))
      return;


   //===============================================================
   // REQUEST SLTP
   //===============================================================

   request.action =
      TRADE_ACTION_SLTP;

   request.position =
      ticket;

   request.symbol =
      _Symbol;

   request.sl =
      newSL;

   request.tp =
      PositionGetDouble(
         POSITION_TP
      );


   ResetLastError();


   if(!OrderSend(
      request,
      result
   ))
   {
      Print(
         "Modify SL gagal | Ticket = ",
         ticket,
         " | Error = ",
         GetLastError()
      );

      return;
   }


   //===============================================================
   // CEK HASIL
   //===============================================================

   if(
      result.retcode !=
      TRADE_RETCODE_DONE
   )
   {
      Print(
         "Modify SL ditolak | Ticket = ",
         ticket,
         " | Retcode = ",
         result.retcode
      );

      return;
   }


   Print(
      "TRAILING SL BERGERAK | Ticket = ",
      ticket,
      " | New SL = ",
      newSL
   );
}


//==================================================================//
// INIT
//==================================================================//

int OnInit()
{
   //--- simpan candle saat EA dipasang
   lastBarTime =
      iTime(
         _Symbol,
         PERIOD_M1,
         0
      );


   //--- cek API
   CheckApiStatus();


   //===============================================================
   // LOG
   //===============================================================

   Print(
      "=========================================="
   );

   Print(
      "Gold3CandleTrail AKTIF"
   );

   Print(
      "Symbol = ",
      _Symbol
   );

   Print(
      "Timeframe = M1"
   );

   Print(
      "Lot = ",
      LotSize
   );

   Print(
      "Initial SL = $",
      InitialSLDistance
   );

   Print(
      "Trailing Start = ",
      TrailStart_Pips,
      " pips ($",
      TrailStart_Pips * PipSize,
      ")"
   );

   Print(
      "Trailing Distance = ",
      TrailDistance_Pips,
      " pips ($",
      TrailDistance_Pips * PipSize,
      ")"
   );

   Print(
      "PipSize = ",
      PipSize
   );

   Print(
      "=========================================="
   );


   return(INIT_SUCCEEDED);
}


//==================================================================//
// TICK
//==================================================================//

void OnTick()
{
   //===============================================================
   // CEK API
   //===============================================================

   CheckApiStatus();


   //===============================================================
   // TRAILING SELALU BERJALAN
   //
   // Walaupun API STOP
   //===============================================================

   if(
      CountOpenPositions() > 0
   )
   {
      TrailPositions();
   }


   //===============================================================
   // API STOP
   //
   // Tidak boleh entry baru
   //===============================================================

   if(!botEnabled)
      return;


   //===============================================================
   // ENTRY HANYA PADA CANDLE M1 BARU
   //===============================================================

   if(!IsNewBar())
      return;


   //===============================================================
   // MAKSIMAL 1 POSISI
   //===============================================================

   if(
      CountOpenPositions() >= 1
   )
   {
      return;
   }


   //===============================================================
   // CEK 3 CANDLE
   //===============================================================

   int signal =
      Check3CandleSignal();


   //===============================================================
   // BUY
   //===============================================================

   if(signal == 1)
   {
      OpenBuy();
   }


   //===============================================================
   // SELL
   //===============================================================

   else
   if(signal == -1)
   {
      OpenSell();
   }
}
//+------------------------------------------------------------------+
