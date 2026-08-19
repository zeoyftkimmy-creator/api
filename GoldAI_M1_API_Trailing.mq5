//+------------------------------------------------------------------+
//|                  GoldAI_M1_API_Trailing.mq5                      |
//| XAUUSD M1 - Bullish/Bearish Confirmation + API START/STOP       |
//| SL 20 pips + Trailing 5 pips                                    |
//+------------------------------------------------------------------+
#property strict
#property version "2.00"

#include <Trade/Trade.mqh>

CTrade trade;

//========================= SETTINGS =================================

input string TradeSymbol = "XAUUSD";
input double LotSize = 0.01;

// 1 pip XAUUSD
input double PipSize = 0.10;

// Stop Loss awal
input double InitialSL_Pips = 20.0;

// Trailing
input double TrailingStart_Pips = 10.0;
input double TrailingDistance_Pips = 5.0;

// Maksimum spread
input double MaxSpread_Pips = 8.0;

// Magic Number
input long MagicNumber = 26081602;

// Cek API setiap berapa detik
input int API_Check_Seconds = 3;

// API status
input string API_STATUS =
"https://gold-scalper-api-h376.onrender.com/status";

//===================================================================

bool EA_Running = false;
datetime LastCandle = 0;
datetime LastAPICheck = 0;

//===================================================================
// INIT
//===================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   Print("======================================");
   Print(" GOLD AI M1 API TRAILING");
   Print(" EA INITIALIZED");
   Print(" Symbol: ", TradeSymbol);
   Print(" SL: ", InitialSL_Pips, " pips");
   Print(" Trailing Start: ", TrailingStart_Pips, " pips");
   Print(" Trailing Distance: ", TrailingDistance_Pips, " pips");
   Print(" API: ", API_STATUS);
   Print("======================================");

   CheckAPI();

   return(INIT_SUCCEEDED);
}

//===================================================================
// TICK
//===================================================================

void OnTick()
{
   //===============================================================
   // CHECK API
   //===============================================================

   if(TimeCurrent() - LastAPICheck >= API_Check_Seconds)
   {
      CheckAPI();
      LastAPICheck = TimeCurrent();
   }

   //===============================================================
   // TRAILING TETAP BERJALAN
   //===============================================================

   ManageTrailing();

   //===============================================================
   // API STOP = JANGAN ENTRY
   //===============================================================

   if(!EA_Running)
      return;

   //===============================================================
   // HANYA CEK ENTRY PADA CANDLE M1 BARU
   //===============================================================

   datetime candleTime =
      iTime(TradeSymbol, PERIOD_M1, 0);

   if(candleTime == LastCandle)
      return;

   LastCandle = candleTime;

   //===============================================================
   // CEK SPREAD
   //===============================================================

   if(!CheckSpread())
   {
      Print("Spread terlalu besar.");
      return;
   }

   //===============================================================
   // SATU POSISI SAJA
   //===============================================================

   if(HasOurPosition())
      return;

   //===============================================================
   // CARI SIGNAL
   //===============================================================

   int signal = GetSignal();

   if(signal == 1)
   {
      Print("================================");
      Print("BULLISH CONFIRMATION");
      Print("SIGNAL = BUY");
      Print("================================");

      OpenBuy();
   }
   else if(signal == -1)
   {
      Print("================================");
      Print("BEARISH CONFIRMATION");
      Print("SIGNAL = SELL");
      Print("================================");

      OpenSell();
   }
   else
   {
      Print("M1: Tidak ada confirmation.");
   }
}

//===================================================================
// API STATUS
//===================================================================

void CheckAPI()
{
   char post[];
   char result[];

   string headers = "";
   string responseHeaders = "";

   ResetLastError();

   int statusCode =
      WebRequest(
         "GET",
         API_STATUS,
         headers,
         5000,
         post,
         result,
         responseHeaders
      );

   if(statusCode == -1)
   {
      Print("API ERROR: ", GetLastError());
      Print("WebRequest belum diizinkan atau API tidak dapat diakses.");
      return;
   }

   string response =
      CharArrayToString(result);

   Print("API STATUS: ", response);

   //===============================================================
   // RUNNING TRUE
   //===============================================================

   if(StringFind(response, "\"running\":true") >= 0)
   {
      if(!EA_Running)
         Print(">>> API START - EA RUNNING");

      EA_Running = true;
   }

   //===============================================================
   // RUNNING FALSE
   //===============================================================

   else if(StringFind(response, "\"running\":false") >= 0)
   {
      if(EA_Running)
         Print(">>> API STOP - EA STOPPED");

      EA_Running = false;
   }
}

//===================================================================
// SIGNAL M1
//===================================================================

int GetSignal()
{
   // Candle 1 = candle M1 yang sudah close
   // Candle 2 = candle sebelumnya

   double open1 =
      iOpen(TradeSymbol, PERIOD_M1, 1);

   double close1 =
      iClose(TradeSymbol, PERIOD_M1, 1);

   double high1 =
      iHigh(TradeSymbol, PERIOD_M1, 1);

   double low1 =
      iLow(TradeSymbol, PERIOD_M1, 1);

   double open2 =
      iOpen(TradeSymbol, PERIOD_M1, 2);

   double close2 =
      iClose(TradeSymbol, PERIOD_M1, 2);

   double high2 =
      iHigh(TradeSymbol, PERIOD_M1, 2);

   double low2 =
      iLow(TradeSymbol, PERIOD_M1, 2);

   //===============================================================
   // BULLISH
   //
   // Candle terakhir bullish
   // Close menembus high candle sebelumnya
   //===============================================================

   bool bullish =
      close1 > open1 &&
      close1 > high2 &&
      high1 > high2;

   //===============================================================
   // BEARISH
   //
   // Candle terakhir bearish
   // Close menembus low candle sebelumnya
   //===============================================================

   bool bearish =
      close1 < open1 &&
      close1 < low2 &&
      low1 < low2;

   if(bullish)
      return 1;

   if(bearish)
      return -1;

   return 0;
}

//===================================================================
// BUY
//===================================================================

void OpenBuy()
{
   double ask =
      SymbolInfoDouble(
         TradeSymbol,
         SYMBOL_ASK
      );

   if(ask <= 0)
      return;

   double sl =
      ask -
      (InitialSL_Pips * PipSize);

   sl = NormalizePrice(sl);

   trade.SetDeviationInPoints(50);

   bool result =
      trade.Buy(
         LotSize,
         TradeSymbol,
         0,
         sl,
         0,
         "GoldAI M1 BUY"
      );

   if(result)
   {
      Print("BUY OPENED");
      Print("Entry = ", ask);
      Print("SL = ", sl);
   }
   else
   {
      Print("BUY ERROR: ",
            trade.ResultRetcode(),
            " / ",
            trade.ResultRetcodeDescription());
   }
}

//===================================================================
// SELL
//===================================================================

void OpenSell()
{
   double bid =
      SymbolInfoDouble(
         TradeSymbol,
         SYMBOL_BID
      );

   if(bid <= 0)
      return;

   double sl =
      bid +
      (InitialSL_Pips * PipSize);

   sl = NormalizePrice(sl);

   trade.SetDeviationInPoints(50);

   bool result =
      trade.Sell(
         LotSize,
         TradeSymbol,
         0,
         sl,
         0,
         "GoldAI M1 SELL"
      );

   if(result)
   {
      Print("SELL OPENED");
      Print("Entry = ", bid);
      Print("SL = ", sl);
   }
   else
   {
      Print("SELL ERROR: ",
            trade.ResultRetcode(),
            " / ",
            trade.ResultRetcodeDescription());
   }
}

//===================================================================
// TRAILING
//===================================================================

void ManageTrailing()
{
   if(!PositionSelect(TradeSymbol))
      return;

   long magic =
      PositionGetInteger(POSITION_MAGIC);

   if(magic != MagicNumber)
      return;

   long type =
      PositionGetInteger(POSITION_TYPE);

   double openPrice =
      PositionGetDouble(POSITION_PRICE_OPEN);

   double currentSL =
      PositionGetDouble(POSITION_SL);

   double currentTP =
      PositionGetDouble(POSITION_TP);

   double bid =
      SymbolInfoDouble(
         TradeSymbol,
         SYMBOL_BID
      );

   double ask =
      SymbolInfoDouble(
         TradeSymbol,
         SYMBOL_ASK
      );

   double price;
   double profitPips;

   //===============================================================
   // BUY
   //===============================================================

   if(type == POSITION_TYPE_BUY)
   {
      price = bid;

      profitPips =
         (price - openPrice) /
         PipSize;

      // Belum mencapai +10 pip
      if(profitPips < TrailingStart_Pips)
         return;

      // SL berada 5 pip di bawah harga sekarang
      double newSL =
         price -
         (TrailingDistance_Pips * PipSize);

      newSL =
         NormalizePrice(newSL);

      // SL hanya boleh naik
      if(currentSL == 0 ||
         newSL > currentSL)
      {
         if(newSL < bid)
         {
            if(trade.PositionModify(
               TradeSymbol,
               newSL,
               currentTP))
            {
               Print(
                  "BUY TRAILING | Profit +",
                  DoubleToString(profitPips,1),
                  " pips | SL = ",
                  DoubleToString(newSL,_Digits)
               );
            }
         }
      }
   }

   //===============================================================
   // SELL
   //===============================================================

   if(type == POSITION_TYPE_SELL)
   {
      price = ask;

      profitPips =
         (openPrice - price) /
         PipSize;

      // Belum mencapai +10 pip
      if(profitPips < TrailingStart_Pips)
         return;

      // SL berada 5 pip di atas harga sekarang
      double newSL =
         price +
         (TrailingDistance_Pips * PipSize);

      newSL =
         NormalizePrice(newSL);

      // SL hanya boleh turun
      if(currentSL == 0 ||
         newSL < currentSL)
      {
         if(newSL > ask)
         {
            if(trade.PositionModify(
               TradeSymbol,
               newSL,
               currentTP))
            {
               Print(
                  "SELL TRAILING | Profit +",
                  DoubleToString(profitPips,1),
                  " pips | SL = ",
                  DoubleToString(newSL,_Digits)
               );
            }
         }
      }
   }
}

//===================================================================
// CHECK POSITION
//===================================================================

bool HasOurPosition()
{
   if(!PositionSelect(TradeSymbol))
      return false;

   long magic =
      PositionGetInteger(POSITION_MAGIC);

   if(magic != MagicNumber)
      return false;

   return true;
}

//===================================================================
// CHECK SPREAD
//===================================================================

bool CheckSpread()
{
   double ask =
      SymbolInfoDouble(
         TradeSymbol,
         SYMBOL_ASK
      );

   double bid =
      SymbolInfoDouble(
         TradeSymbol,
         SYMBOL_BID
      );

   if(ask <= 0 || bid <= 0)
      return false;

   double spreadPips =
      (ask - bid) /
      PipSize;

   Print(
      "Spread = ",
      DoubleToString(spreadPips,1),
      " pips"
   );

   if(spreadPips > MaxSpread_Pips)
      return false;

   return true;
}

//===================================================================
// NORMALIZE PRICE
//===================================================================

double NormalizePrice(double price)
{
   int digits =
      (int)SymbolInfoInteger(
         TradeSymbol,
         SYMBOL_DIGITS
      );

   return NormalizeDouble(
      price,
      digits
   );
}

//+------------------------------------------------------------------+
