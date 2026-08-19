//+------------------------------------------------------------------+
//|                  GoldAI_M1_API_Trailing.mq5                      |
//| XAUUSD M1 - Bullish/Bearish Confirmation + API START/STOP       |
//| SL 20 Pips + Trailing mulai 10 Pips, jarak 5 Pips               |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>

CTrade trade;

//========================= INPUT ====================================

input string TradeSymbol = "XAUUSD";

// Lot
input double LotSize = 0.01;

// Pip setting
// Untuk XAUUSD biasanya bisa disesuaikan dengan broker.
// Contoh:
// 0.10 = 1 pip
input double PipSize = 0.10;

// Initial Stop Loss
input double InitialSL_Pips = 20.0;

// Trailing
input double TrailingStart_Pips = 10.0;
input double TrailingDistance_Pips = 5.0;

// Magic Number
input long MagicNumber = 26081602;

// Spread maksimum
input double MaxSpread_Pips = 8.0;

// API
input string API_URL =
"https://gold-scalper-api-h376.onrender.com/api/status";

// API check interval
input int API_Check_Seconds = 3;

//========================= VARIABLES ===============================

bool EA_Running = false;

datetime LastCandleTime = 0;
datetime LastAPI_Check = 0;

//===================================================================
// Expert initialization
//===================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   Print("========================================");
   Print("Gold AI M1 API Trailing STARTED");
   Print("Symbol: ", TradeSymbol);
   Print("Initial SL: ", InitialSL_Pips, " pips");
   Print("Trailing Start: ", TrailingStart_Pips, " pips");
   Print("Trailing Distance: ", TrailingDistance_Pips, " pips");
   Print("API: ", API_URL);
   Print("========================================");

   CheckAPI();

   return(INIT_SUCCEEDED);
}

//===================================================================
// Expert tick
//===================================================================

void OnTick()
{
   //===============================================================
   // 1. Check API
   //===============================================================

   if(TimeCurrent() - LastAPI_Check >= API_Check_Seconds)
   {
      CheckAPI();
      LastAPI_Check = TimeCurrent();
   }

   //===============================================================
   // 2. Kelola posisi yang sudah ada
   //===============================================================

   ManageTrailing();

   //===============================================================
   // 3. Jika API STOP, jangan entry baru
   //===============================================================

   if(!EA_Running)
      return;

   //===============================================================
   // 4. Hanya entry pada candle M1 baru
   //===============================================================

   datetime currentCandle = iTime(TradeSymbol, PERIOD_M1, 0);

   if(currentCandle == LastCandleTime)
      return;

   LastCandleTime = currentCandle;

   //===============================================================
   // 5. Cek spread
   //===============================================================

   if(!CheckSpread())
   {
      Print("Spread terlalu besar. Tidak entry.");
      return;
   }

   //===============================================================
   // 6. Jangan buka posisi kedua
   //===============================================================

   if(HasOpenPosition())
      return;

   //===============================================================
   // 7. Cari sinyal
   //===============================================================

   int signal = GetSignal();

   if(signal == 1)
   {
      Print("BULLISH CONFIRMATION -> BUY");
      OpenBuy();
   }
   else if(signal == -1)
   {
      Print("BEARISH CONFIRMATION -> SELL");
      OpenSell();
   }
   else
   {
      Print("Tidak ada konfirmasi M1.");
   }
}

//===================================================================
// API START / STOP
//===================================================================

void CheckAPI()
{
   char data[];
   char result[];

   string headers;
   string result_headers;

   ResetLastError();

   int timeout = 5000;

   int res = WebRequest(
      "GET",
      API_URL,
      headers,
      timeout,
      data,
      result,
      result_headers
   );

   if(res == -1)
   {
      Print("API WebRequest ERROR: ", GetLastError());
      Print("Pastikan URL API sudah dimasukkan ke:");
      Print("Tools -> Options -> Expert Advisors -> Allow WebRequest");

      return;
   }

   string response = CharArrayToString(result);

   Print("API Response: ", response);

   //===============================================================
   // Parse running
   //===============================================================

   if(StringFind(response, "\"running\":true") >= 0)
   {
      if(!EA_Running)
         Print("API COMMAND: START");

      EA_Running = true;
   }
   else if(StringFind(response, "\"running\":false") >= 0)
   {
      if(EA_Running)
         Print("API COMMAND: STOP");

      EA_Running = false;
   }
}

//===================================================================
// Signal
//===================================================================

int GetSignal()
{
   // Candle 1 = candle M1 yang baru saja close
   // Candle 2 = candle sebelumnya

   double open1  = iOpen(TradeSymbol, PERIOD_M1, 1);
   double close1 = iClose(TradeSymbol, PERIOD_M1, 1);
   double high1  = iHigh(TradeSymbol, PERIOD_M1, 1);
   double low1   = iLow(TradeSymbol, PERIOD_M1, 1);

   double open2  = iOpen(TradeSymbol, PERIOD_M1, 2);
   double close2 = iClose(TradeSymbol, PERIOD_M1, 2);
   double high2  = iHigh(TradeSymbol, PERIOD_M1, 2);
   double low2   = iLow(TradeSymbol, PERIOD_M1, 2);

   //===============================================================
   // BULLISH CONFIRMATION
   //
   // Candle terakhir bullish
   // DAN close menembus high candle sebelumnya
   //===============================================================

   bool bullish =
      close1 > open1 &&
      close1 > high2 &&
      high1 > high2;

   //===============================================================
   // BEARISH CONFIRMATION
   //
   // Candle terakhir bearish
   // DAN close menembus low candle sebelumnya
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
   double ask = SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);

   if(ask <= 0)
      return;

   double slDistance = InitialSL_Pips * PipSize;

   double sl = ask - slDistance;

   sl = NormalizePrice(sl);

   trade.SetDeviationInPoints(50);

   bool result = trade.Buy(
      LotSize,
      TradeSymbol,
      ask,
      sl,
      0,
      "Gold AI M1 BUY"
   );

   if(result)
   {
      Print("BUY OPENED");
      Print("Entry: ", ask);
      Print("Initial SL: ", sl);
   }
   else
   {
      Print("BUY FAILED: ",
            trade.ResultRetcode(),
            " - ",
            trade.ResultRetcodeDescription());
   }
}

//===================================================================
// SELL
//===================================================================

void OpenSell()
{
   double bid = SymbolInfoDouble(TradeSymbol, SYMBOL_BID);

   if(bid <= 0)
      return;

   double slDistance = InitialSL_Pips * PipSize;

   double sl = bid + slDistance;

   sl = NormalizePrice(sl);

   trade.SetDeviationInPoints(50);

   bool result = trade.Sell(
      LotSize,
      TradeSymbol,
      bid,
      sl,
      0,
      "Gold AI M1 SELL"
   );

   if(result)
   {
      Print("SELL OPENED");
      Print("Entry: ", bid);
      Print("Initial SL: ", sl);
   }
   else
   {
      Print("SELL FAILED: ",
            trade.ResultRetcode(),
            " - ",
            trade.ResultRetcodeDescription());
   }
}

//===================================================================
// TRAILING STOP
//===================================================================

void ManageTrailing()
{
   if(!PositionSelect(TradeSymbol))
      return;

   long magic = PositionGetInteger(POSITION_MAGIC);

   if(magic != MagicNumber)
      return;

   long type = PositionGetInteger(POSITION_TYPE);

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);

   double bid = SymbolInfoDouble(TradeSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);

   double currentPrice;

   if(type == POSITION_TYPE_BUY)
      currentPrice = bid;
   else
      currentPrice = ask;

   //===============================================================
   // Hitung profit dalam pips
   //===============================================================

   double profitPips;

   if(type == POSITION_TYPE_BUY)
   {
      profitPips =
         (currentPrice - openPrice) / PipSize;
   }
   else
   {
      profitPips =
         (openPrice - currentPrice) / PipSize;
   }

   //===============================================================
   // Trailing belum aktif
   //===============================================================

   if(profitPips < TrailingStart_Pips)
      return;

   //===============================================================
   // BUY TRAILING
   //===============================================================

   if(type == POSITION_TYPE_BUY)
   {
      double newSL =
         currentPrice -
         (TrailingDistance_Pips * PipSize);

      newSL = NormalizePrice(newSL);

      // Jangan pernah turunkan SL
      if(currentSL == 0 || newSL > currentSL)
      {
         // Jangan pasang SL di atas harga sekarang
         if(newSL < bid)
         {
            if(trade.PositionModify(
               TradeSymbol,
               newSL,
               PositionGetDouble(POSITION_TP)))
            {
               Print(
                  "BUY TRAILING -> Profit: ",
                  DoubleToString(profitPips,1),
                  " pips | SL: ",
                  DoubleToString(newSL,_Digits)
               );
            }
         }
      }
   }

   //===============================================================
   // SELL TRAILING
   //===============================================================

   if(type == POSITION_TYPE_SELL)
   {
      double newSL =
         currentPrice +
         (TrailingDistance_Pips * PipSize);

      newSL = NormalizePrice(newSL);

      // Jangan pernah turunkan SL untuk SELL
      if(currentSL == 0 || newSL < currentSL)
      {
         if(newSL > ask)
         {
            if(trade.PositionModify(
               TradeSymbol,
               newSL,
               PositionGetDouble(POSITION_TP)))
            {
               Print(
                  "SELL TRAILING -> Profit: ",
                  DoubleToString(profitPips,1),
                  " pips | SL: ",
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

bool HasOpenPosition()
{
   if(!PositionSelect(TradeSymbol))
      return false;

   long magic = PositionGetInteger(POSITION_MAGIC);

   if(magic != MagicNumber)
      return false;

   return true;
}

//===================================================================
// CHECK SPREAD
//===================================================================

bool CheckSpread()
{
   double ask = SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(TradeSymbol, SYMBOL_BID);

   if(ask <= 0 || bid <= 0)
      return false;

   double spreadPips =
      (ask - bid) / PipSize;

   Print(
      "Spread: ",
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

   return NormalizeDouble(price, digits);
}

//+------------------------------------------------------------------+
