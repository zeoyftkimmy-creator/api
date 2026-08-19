//+------------------------------------------------------------------+
//|  Gold3CandleTrail.mq5                                            |
//|  Strategi:                                                       |
//|   - XAUUSD, timeframe M1                                         |
//|   - Konfirmasi 3 candle searah (3 bullish -> BUY, 3 bearish -> SELL)|
//|   - Entry hanya setelah candle ke-3 CLOSE                        |
//|   - SL awal 20 pips                                              |
//|   - Trailing mulai aktif saat profit >= 50 pips                  |
//|   - Jarak trailing 5 pips, terus mengikuti profit tanpa batas     |
//|   - Tidak ada TP                                                 |
//|   - Maksimal 1 posisi terbuka                                    |
//|   - Cek status START/STOP dari API sebelum entry baru            |
//+------------------------------------------------------------------+
#property copyright "Custom EA"
#property version   "1.10"
#property strict

//--- input parameter
input double   LotSize            = 0.01;   // Lot size
input double   SL_Pips            = 20.0;   // Stop Loss awal (pips)
input double   TrailStart_Pips    = 50.0;   // Profit minimum untuk mulai trailing (pips)
input double   TrailDistance_Pips = 5.0;    // Jarak trailing dari harga saat ini (pips)
input double   PipSize            = 1.00;   // Nilai 1 pip dalam harga (1 pip = $1 pergerakan harga, sesuai konvensi yang dipakai)
input ulong    MagicNumber        = 20260819;
input int      Slippage           = 50;     // slippage dalam poin
input string   ApiStatusUrl       = "https://gold-scalper-api-h376.onrender.com/status"; // URL API status/kontrol (START/STOP)
input int      ApiCheckSeconds    = 5;      // interval cek status API (detik)

datetime lastBarTime      = 0;
datetime lastApiCheckTime = 0;
bool     botEnabled        = true; // status terakhir yang diketahui dari API (default aktif)

//+------------------------------------------------------------------+
//| Cek apakah bar baru sudah terbentuk di M1                        |
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
//| Hitung jumlah posisi terbuka milik EA ini                        |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Cek konfirmasi 3 candle searah (candle 1,2,3 = shift 1,2,3)      |
//| shift 0 = candle yang sedang berjalan (belum close)               |
//+------------------------------------------------------------------+
int Check3CandleSignal()
{
   double open1  = iOpen(_Symbol, PERIOD_M1, 1);
   double close1 = iClose(_Symbol, PERIOD_M1, 1);
   double open2  = iOpen(_Symbol, PERIOD_M1, 2);
   double close2 = iClose(_Symbol, PERIOD_M1, 2);
   double open3  = iOpen(_
