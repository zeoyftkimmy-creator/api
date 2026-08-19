//+------------------------------------------------------------------+
//|  Gold3CandleTrail.mq5                                            |
//|  Strategi:                                                       |
//|   - XAUUSD, timeframe M1                                         |
//|   - Konfirmasi 3 candle searah (3 bullish -> BUY, 3 bearish -> SELL)|
//|   - Entry hanya setelah candle ke-3 CLOSE                        |
//|   - SL awal 20 pips                                              |
//|   - Trailing mulai aktif saat profit >= 10 pips                  |
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
input double   TrailStart_Pips    = 10.0;   // Profit minimum untuk mulai trailing (pips)
input double   TrailDistance_Pips = 5.0;    // Jarak trailing dari harga saat ini (pips)
input double   PipSize            = 0.10;   // Nilai 1 pip dalam harga (cek digit harga XAUUSD di broker anda: 2 digit -> 0.10, 3 digit -> 0.01)
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
   double open3  = iOpen(_Symbol, PERIOD_M1, 3);
   double close3 = iClose(_Symbol, PERIOD_M1, 3);

   bool bull1 = close1 > open1;
   bool bull2 = close2 > open2;
   bool bull3 = close3 > open3;

   bool bear1 = close1 < open1;
   bool bear2 = close2 < open2;
   bool bear3 = close3 < open3;

   if(bull1 && bull2 && bull3) return 1;   // BUY signal
   if(bear1 && bear2 && bear3) return -1;  // SELL signal
   return 0;
}

//+------------------------------------------------------------------+
//| Cek status START/STOP dari API (GET request)                     |
//| Response yang diharapkan: {"status":"RUNNING"} atau {"status":"STOPPED"} |
//+------------------------------------------------------------------+
void CheckApiStatus()
{
   if(ApiStatusUrl == "") return;
   if(TimeCurrent() - lastApiCheckTime < ApiCheckSeconds) return;
   lastApiCheckTime = TimeCurrent();

   string headers = "";
   char   postData[];
   char   result[];
   string resultHeaders;
   int    timeout = 5000;

   int res = WebRequest("GET", ApiStatusUrl, headers, timeout, postData, result, resultHeaders);

   if(res == -1)
   {
      int err = GetLastError();
      Print("WebRequest ke API status gagal, error: ", err,
            " -- pastikan URL sudah ditambahkan di Tools > Options > Expert Advisors > Allow WebRequest for listed URL");
      return; // pertahankan status terakhir yang diketahui, jangan diubah saat gagal fetch
   }

   string response = CharArrayToString(result);

   if(StringFind(response, "RUNNING") >= 0)
   {
      if(!botEnabled) Print("Status API: RUNNING -> bot diaktifkan kembali");
      botEnabled = true;
   }
   else if(StringFind(response, "STOPPED") >= 0)
   {
      if(botEnabled) Print("Status API: STOPPED -> entry baru dihentikan (posisi berjalan tetap di-trailing)");
      botEnabled = false;
   }
   else
   {
      Print("Response API tidak dikenali: ", response);
   }
}

//+------------------------------------------------------------------+
//| Buka posisi BUY                                                  |
//+------------------------------------------------------------------+
void OpenBuy()
{
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl  = ask - SL_Pips * PipSize;

   request.action       = TRADE_ACTION_DEAL;
   request.symbol        = _Symbol;
   request.volume        = LotSize;
   request.type          = ORDER_TYPE_BUY;
   request.price         = ask;
   request.sl            = NormalizeDouble(sl, _Digits);
   request.tp             = 0; // tanpa TP
   request.deviation     = Slippage;
   request.magic         = MagicNumber;
   request.comment       = "3Candle-BUY";
   request.type_filling  = ORDER_FILLING_FOK;

   if(!OrderSend(request, result))
      Print("OpenBuy gagal, error: ", GetLastError());
   else
      Print("OpenBuy sukses, ticket: ", result.order);
}

//+------------------------------------------------------------------+
//| Buka posisi SELL                                                 |
//+------------------------------------------------------------------+
void OpenSell()
{
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl  = bid + SL_Pips * PipSize;

   request.action       = TRADE_ACTION_DEAL;
   request.symbol        = _Symbol;
   request.volume        = LotSize;
   request.type          = ORDER_TYPE_SELL;
   request.price         = bid;
   request.sl            = NormalizeDouble(sl, _Digits);
   request.tp             = 0; // tanpa TP
   request.deviation     = Slippage;
   request.magic         = MagicNumber;
   request.comment       = "3Candle-SELL";
   request.type_filling  = ORDER_FILLING_FOK;

   if(!OrderSend(request, result))
      Print("OpenSell gagal, error: ", GetLastError());
   else
      Print("OpenSell sukses, ticket: ", result.order);
}

//+------------------------------------------------------------------+
//| Trailing stop untuk semua posisi EA ini                          |
//+------------------------------------------------------------------+
void TrailPositions()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;

      long   posType   = PositionGetInteger(POSITION_TYPE);
      double posOpen    = PositionGetDouble(POSITION_PRICE_OPEN);
      double posSL       = PositionGetDouble(POSITION_SL);
      double bid          = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask          = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(posType == POSITION_TYPE_BUY)
      {
         double profitPips = (bid - posOpen) / PipSize;
         if(profitPips >= TrailStart_Pips)
         {
            double newSL = NormalizeDouble(bid - TrailDistance_Pips * PipSize, _Digits);
            // hanya geser SL naik (mengunci profit lebih banyak), tidak pernah turun
            if(newSL > posSL || posSL == 0)
            {
               ModifySL(ticket, newSL);
            }
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double profitPips = (posOpen - ask) / PipSize;
         if(profitPips >= TrailStart_Pips)
         {
            double newSL = NormalizeDouble(ask + TrailDistance_Pips * PipSize, _Digits);
            // hanya geser SL turun (mengunci profit lebih banyak), tidak pernah naik
            if(newSL < posSL || posSL == 0)
            {
               ModifySL(ticket, newSL);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modifikasi SL posisi                                             |
//+------------------------------------------------------------------+
void ModifySL(ulong ticket, double newSL)
{
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   if(!PositionSelectByTicket(ticket)) return;

   request.action   = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol    = _Symbol;
   request.sl         = newSL;
   request.tp          = PositionGetDouble(POSITION_TP); // tetap 0 (tanpa TP)

   if(!OrderSend(request, result))
      Print("ModifySL gagal untuk ticket ", ticket, ", error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   lastBarTime = iTime(_Symbol, PERIOD_M1, 0);
   CheckApiStatus(); // cek status awal saat EA di-load
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Cek status START/STOP dari API secara berkala
   CheckApiStatus();

   // Trailing dicek setiap tick supaya presisi, tetap jalan meskipun status STOPPED
   if(CountOpenPositions() > 0)
      TrailPositions();

   // Kalau bot sedang dinonaktifkan lewat API, jangan buka posisi baru
   if(!botEnabled) return;

   // Entry hanya dicek saat bar baru terbentuk (artinya candle sebelumnya sudah close)
   if(!IsNewBar()) return;

   // Maksimal 1 posisi terbuka
   if(CountOpenPositions() >= 1) return;

   int signal = Check3CandleSignal();
   if(signal == 1)
      OpenBuy();
   else if(signal == -1)
      OpenSell();
}
//+------------------------------------------------------------------+
