//+------------------------------------------------------------------+
//|              GoldAI_M1_API_3Candle.mq5                           |
//| XAUUSD M1                                                        |
//| 3 Candle Bullish/Bearish Confirmation                            |
//| Initial SL 20 Pips                                                |
//| Trailing Start +10 Pips                                           |
//| Trailing Distance 5 Pips                                         |
//| API START / STOP                                                   |
//+------------------------------------------------------------------+
#property strict
#property version "3.00"

#include <Trade/Trade.mqh>

CTrade trade;

//====================================================================
// INPUT
//====================================================================

input string TradeSymbol = "XAUUSD";

input double LotSize = 0.01;

// Ukuran 1 pip untuk XAUUSD.
// Sesuaikan dengan broker jika diperlukan.
input double PipSize = 0.10;

// Stop Loss awal
input double InitialSL_Pips = 20.0;

// Trailing mulai aktif
input double TrailingStart_Pips = 10.0;

// Jarak trailing dari harga sekarang
input double TrailingDistance_Pips = 5.0;

// Maksimum spread
input double MaxSpread_Pips = 8.0;

// Magic Number
input long MagicNumber = 26081602;

// Cek API setiap 3 detik
input int API_Check_Seconds = 3;

// API STATUS
input string API_STATUS =
"https://gold-scalper-api-h376.onrender.com/status";

//====================================================================
// VARIABLE
//====================================================================

bool EA_Running = false;

datetime LastCandleTime = 0;
datetime LastAPICheck = 0;

//====================================================================
// INIT
//====================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   Print("================================================");
   Print(" GOLD AI M1 - 3 CANDLE SYSTEM");
   Print("================================================");
   Print("Symbol              : ", TradeSymbol);
   Print("Lot                 : ", LotSize);
   Print("Initial SL          : ", InitialSL_Pips, " pips");
   Print("Trailing Start      : ", TrailingStart_Pips, " pips");
   Print("Trailing Distance   : ", TrailingDistance_Pips, " pips");
   Print("API Status          : ", API_STATUS);
   Print("================================================");

   // Cek API pertama kali
   CheckAPI();

   // Supaya EA tidak langsung entry
   // dari candle lama ketika pertama dipasang
   LastCandleTime = iTime(
      TradeSymbol,
      PERIOD_M1,
      0
   );

   return(INIT_SUCCEEDED);
}

//====================================================================
// TICK
//====================================================================

void OnTick()
{
   //===============================================================
   // 1. CEK API
   //===============================================================

   if(
      TimeCurrent() - LastAPICheck
      >= API_Check_Seconds
   )
   {
      CheckAPI();

      LastAPICheck = TimeCurrent();
   }

   //===============================================================
   // 2. TRAILING SELALU AKTIF
   //===============================================================

   ManageTrailing();

   //===============================================================
   // 3. API STOP
   //===============================================================

   if(!EA_Running)
      return;

   //===============================================================
   // 4. CEK CANDLE BARU
   //===============================================================

   datetime CurrentCandleTime =
      iTime(
         TradeSymbol,
         PERIOD_M1,
         0
      );

   if(CurrentCandleTime == LastCandleTime)
      return;

   LastCandleTime = CurrentCandleTime;

   //===============================================================
   // 5. CEK SPREAD
   //===============================================================

   if(!CheckSpread())
   {
      Print("Spread terlalu besar. Tidak entry.");
      return;
   }

   //===============================================================
   // 6. HANYA SATU POSISI
   //===============================================================

   if(HasOurPosition())
   {
      Print("Masih ada posisi EA. Tidak membuka posisi baru.");
      return;
   }

   //===============================================================
   // 7. CEK 3 CANDLE
   //===============================================================

   int Signal = GetSignal();

   //===============================================================
   // BUY
   //===============================================================

   if(Signal == 1)
   {
      Print("--------------------------------------------");
      Print("3 CANDLE BULLISH CONFIRMATION");
      Print("SIGNAL : BUY");
      Print("--------------------------------------------");

      OpenBuy();
   }

   //===============================================================
   // SELL
   //===============================================================

   else if(Signal == -1)
   {
      Print("--------------------------------------------");
      Print("3 CANDLE BEARISH CONFIRMATION");
      Print("SIGNAL : SELL");
      Print("--------------------------------------------");

      OpenSell();
   }

   else
   {
      Print("Tidak ada konfirmasi 3 candle.");
   }
}

//====================================================================
// API STATUS
//====================================================================

void CheckAPI()
{
   char PostData[];
   char Result[];

   string Headers = "";
   string ResultHeaders = "";

   ResetLastError();

   int HTTPCode =
      WebRequest(
         "GET",
         API_STATUS,
         Headers,
         5000,
         PostData,
         Result,
         ResultHeaders
      );

   //===============================================================
   // ERROR
   //===============================================================

   if(HTTPCode == -1)
   {
      Print(
         "API WebRequest ERROR = ",
         GetLastError()
      );

      return;
   }

   string Response =
      CharArrayToString(Result);

   Print(
      "API Response = ",
      Response
   );

   //===============================================================
   // START
   //===============================================================

   if(
      StringFind(
         Response,
         "\"running\":true"
      ) >= 0
   )
   {
      if(!EA_Running)
      {
         Print("============================================");
         Print(" API START RECEIVED");
         Print(" EA RUNNING");
         Print("============================================");
      }

      EA_Running = true;
   }

   //===============================================================
   // STOP
   //===============================================================

   else if(
      StringFind(
         Response,
         "\"running\":false"
      ) >= 0
   )
   {
      if(EA_Running)
      {
         Print("============================================");
         Print(" API STOP RECEIVED");
         Print(" EA STOPPED");
         Print("============================================");
      }

      EA_Running = false;
   }
}

//====================================================================
// GET SIGNAL
//====================================================================

int GetSignal()
{
   //===============================================================
   // Candle 1 = candle terakhir yang SUDAH CLOSE
   // Candle 2 = candle sebelumnya
   // Candle 3 = candle sebelumnya lagi
   //
   // Candle 0 tidak digunakan karena masih berjalan.
   //===============================================================

   double Open1 =
      iOpen(
         TradeSymbol,
         PERIOD_M1,
         1
      );

   double Close1 =
      iClose(
         TradeSymbol,
         PERIOD_M1,
         1
      );

   double Open2 =
      iOpen(
         TradeSymbol,
         PERIOD_M1,
         2
      );

   double Close2 =
      iClose(
         TradeSymbol,
         PERIOD_M1,
         2
      );

   double Open3 =
      iOpen(
         TradeSymbol,
         PERIOD_M1,
         3
      );

   double Close3 =
      iClose(
         TradeSymbol,
         PERIOD_M1,
         3
      );

   //===============================================================
   // 3 CANDLE BULLISH
   //===============================================================

   bool Bullish3 =
      Close1 > Open1 &&
      Close2 > Open2 &&
      Close3 > Open3;

   //===============================================================
   // 3 CANDLE BEARISH
   //===============================================================

   bool Bearish3 =
      Close1 < Open1 &&
      Close2 < Open2 &&
      Close3 < Open3;

   //===============================================================
   // SIGNAL BUY
   //===============================================================

   if(Bullish3)
      return 1;

   //===============================================================
   // SIGNAL SELL
   //===============================================================

   if(Bearish3)
      return -1;

   //===============================================================
   // NO SIGNAL
   //===============================================================

   return 0;
}

//====================================================================
// OPEN BUY
//====================================================================

void OpenBuy()
{
   double Ask =
      SymbolInfoDouble(
         TradeSymbol,
         SYMBOL_ASK
      );

   if(Ask <= 0)
      return;

   //===============================================================
   // SL 20 PIPS
   //===============================================================

   double SL =
      Ask -
      (
         InitialSL_Pips *
         PipSize
      );

   SL = NormalizePrice(SL);

   trade.SetDeviationInPoints(50);

   bool Result =
      trade.Buy(
         LotSize,
         TradeSymbol,
         0,
         SL,
         0,
         "GoldAI 3 Candle BUY"
      );

   //===============================================================
   // SUCCESS
   //===============================================================

   if(Result)
   {
      Print("============================================");
      Print("BUY OPENED");
      Print("Entry = ", Ask);
      Print("SL    = ", SL);
      Print("============================================");
   }

   //===============================================================
   // ERROR
   //===============================================================

   else
   {
      Print(
         "BUY FAILED: ",
         trade.ResultRetcode(),
         " - ",
         trade.ResultRetcodeDescription()
      );
   }
}

//====================================================================
// OPEN SELL
//====================================================================

void OpenSell()
{
   double Bid =
      SymbolInfoDouble(
         TradeSymbol,
         SYMBOL_BID
      );

   if(Bid <= 0)
      return;

   //===============================================================
   // SL 20 PIPS
   //===============================================================

   double SL =
      Bid +
      (
         InitialSL_Pips *
         PipSize
      );

   SL = NormalizePrice(SL);

   trade.SetDeviationInPoints(50);

   bool Result =
      trade.Sell(
         LotSize,
         TradeSymbol,
         0,
         SL,
         0,
         "GoldAI 3 Candle SELL"
      );

   //===============================================================
   // SUCCESS
   //===============================================================

   if(Result)
   {
      Print("============================================");
      Print("SELL OPENED");
      Print("Entry = ", Bid);
      Print("SL    = ", SL);
      Print("============================================");
   }

   //===============================================================
   // ERROR
   //===============================================================

   else
   {
      Print(
         "SELL FAILED: ",
         trade.ResultRetcode(),
         " - ",
         trade.ResultRetcodeDescription()
      );
   }
}

//====================================================================
// TRAILING STOP
//====================================================================

void ManageTrailing()
{
   //===============================================================
   // Tidak ada posisi
   //===============================================================

   if(!PositionSelect(TradeSymbol))
      return;

   //===============================================================
   // Cek Magic Number
   //===============================================================

   long PositionMagic =
      PositionGetInteger(
         POSITION_MAGIC
      );

   if(PositionMagic != MagicNumber)
      return;

   //===============================================================
   // DATA POSISI
   //===============================================================

   long PositionType =
      PositionGetInteger(
         POSITION_TYPE
      );

   double OpenPrice =
      PositionGetDouble(
         POSITION_PRICE_OPEN
      );

   double CurrentSL =
      PositionGetDouble(
         POSITION_SL
      );

   double CurrentTP =
      PositionGetDouble(
         POSITION_TP
      );

   double Bid =
      SymbolInfoDouble(
         TradeSymbol,
         SYMBOL_BID
      );

   double Ask =
      SymbolInfoDouble(
         TradeSymbol,
         SYMBOL_ASK
      );

   //===============================================================
   // BUY
   //===============================================================

   if(PositionType == POSITION_TYPE_BUY)
   {
      double ProfitPips =
         (
            Bid -
            OpenPrice
         )
         /
         PipSize;

      // Trailing baru aktif +10 pip
      if(
         ProfitPips <
         TrailingStart_Pips
      )
         return;

      // SL 5 pip di bawah harga sekarang
      double NewSL =
         Bid -
         (
            TrailingDistance_Pips *
            PipSize
         );

      NewSL =
         NormalizePrice(NewSL);

      //===========================================================
      // SL HANYA BOLEH NAIK
      //===========================================================

      if(
         CurrentSL == 0 ||
         NewSL > CurrentSL
      )
      {
         if(NewSL < Bid)
         {
            bool Modified =
               trade.PositionModify(
                  TradeSymbol,
                  NewSL,
                  CurrentTP
               );

            if(Modified)
            {
               Print(
                  "BUY TRAILING | Profit +",
                  DoubleToString(
                     ProfitPips,
                     1
                  ),
                  " pips | SL = ",
                  DoubleToString(
                     NewSL,
                     _Digits
                  )
               );
            }
         }
      }
   }

   //===============================================================
   // SELL
   //===============================================================

   if(PositionType == POSITION_TYPE_SELL)
   {
      double ProfitPips =
         (
            OpenPrice -
            Ask
         )
         /
         PipSize;

      // Trailing baru aktif +10 pip
      if(
         ProfitPips <
         TrailingStart_Pips
      )
         return;

      // SL 5 pip di atas harga sekarang
      double NewSL =
         Ask +
         (
            TrailingDistance_Pips *
            PipSize
         );

      NewSL =
         NormalizePrice(NewSL);

      //===========================================================
      // SL HANYA BOLEH TURUN
      //===========================================================

      if(
         CurrentSL == 0 ||
         NewSL < CurrentSL
      )
      {
         if(NewSL > Ask)
         {
            bool Modified =
               trade.PositionModify(
                  TradeSymbol,
                  NewSL,
                  CurrentTP
               );

            if(Modified)
            {
               Print(
                  "SELL TRAILING | Profit +",
                  DoubleToString(
                     ProfitPips,
                     1
                  ),
                  " pips | SL = ",
                  DoubleToString(
                     NewSL,
                     _Digits
                  )
               );
            }
         }
      }
   }
}

//====================================================================
// CHECK OUR POSITION
//====================================================================

bool HasOurPosition()
{
   if(!PositionSelect(TradeSymbol))
      return false;

   long PositionMagic =
      PositionGetInteger(
         POSITION_MAGIC
      );

   if(
      PositionMagic !=
      MagicNumber
   )
      return false;

   return true;
}

//====================================================================
// CHECK SPREAD
//====================================================================

bool CheckSpread()
{
   double Ask =
      SymbolInfoDouble(
         TradeSymbol,
         SYMBOL_ASK
      );

   double Bid =
      SymbolInfoDouble(
         TradeSymbol,
         SYMBOL_BID
      );

   if(
      Ask <= 0 ||
      Bid <= 0
   )
      return false;

   double SpreadPips =
      (
         Ask -
         Bid
      )
      /
      PipSize;

   Print(
      "Current Spread = ",
      DoubleToString(
         SpreadPips,
         1
      ),
      " pips"
   );

   if(
      SpreadPips >
      MaxSpread_Pips
   )
      return false;

   return true;
}

//====================================================================
// NORMALIZE PRICE
//====================================================================

double NormalizePrice(double Price)
{
   int Digits =
      (int)SymbolInfoInteger(
         TradeSymbol,
         SYMBOL_DIGITS
      );

   return NormalizeDouble(
      Price,
      Digits
   );
}

//+------------------------------------------------------------------+
