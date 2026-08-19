//+------------------------------------------------------------------+
//|                                             GoldScalperEA.mq5    |
//|  Multi-timeframe XAUUSD scalper, dikendalikan START/STOP oleh    |
//|  API eksternal (dibaca dari APK). Parsing JSON asli untuk        |
//|  field "running", bukan sekadar string search.                  |
//+------------------------------------------------------------------+
#property copyright "Custom"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//====================== INPUT PARAMETER ======================
input string InpApiUrl            = "https://gold-scalper-api-h376.onrender.com/status";
input int    InpPollSeconds       = 5;      // interval cek status API (detik)

input double InpLotSize           = 0.01;
input int    InpMaxPositions      = 1;
input long   InpMagic             = 990011;
input int    InpCooldownMinutes   = 2;      // jeda minimal antar entry baru

input int    InpInitialSLPoints   = 1500;   // SL awal dalam POINTS (bukan pip) - sesuaikan ke broker
input int    InpTrailingStartPts  = 1000;   // profit (points) sebelum trailing mulai aktif
input int    InpTrailingStepPts   = 500;    // jarak SL trailing dari harga saat ini (points)
input double InpMinM1BodyPoints   = 150;    // syarat minimum body candle M1 (momentum), dalam points

input ENUM_TIMEFRAMES TF_AREA     = PERIOD_M30;
input ENUM_TIMEFRAMES TF_CONFIRM  = PERIOD_M15;
input ENUM_TIMEFRAMES TF_SIGNAL   = PERIOD_M5;
input ENUM_TIMEFRAMES TF_TRIGGER  = PERIOD_M1;

//====================== GLOBAL ======================
CTrade   trade;
bool     g_running        = false;
datetime g_lastTradeTime  = 0;

int h_ema_fast_area, h_ema_slow_area;
int h_ema_fast_confirm, h_ema_slow_confirm;
int h_ema_fast_signal, h_ema_slow_signal;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);

   h_ema_fast_area    = iMA(_Symbol, TF_AREA,    20, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_slow_area    = iMA(_Symbol, TF_AREA,    50, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_fast_confirm = iMA(_Symbol, TF_CONFIRM, 20, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_slow_confirm = iMA(_Symbol, TF_CONFIRM, 50, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_fast_signal  = iMA(_Symbol, TF_SIGNAL,   9, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_slow_signal  = iMA(_Symbol, TF_SIGNAL,  21, 0, MODE_EMA, PRICE_CLOSE);

   if(h_ema_fast_area==INVALID_HANDLE || h_ema_slow_area==INVALID_HANDLE ||
      h_ema_fast_confirm==INVALID_HANDLE || h_ema_slow_confirm==INVALID_HANDLE ||
      h_ema_fast_signal==INVALID_HANDLE || h_ema_slow_signal==INVALID_HANDLE)
   {
      Print("Gagal membuat indicator handle");
      return INIT_FAILED;
   }

   EventSetTimer(InpPollSeconds);
   PollApiStatus(); // cek status begitu EA nyala
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer()
{
   PollApiStatus();
}

//+------------------------------------------------------------------+
//| Ambil status running dari API dengan parsing JSON asli           |
//+------------------------------------------------------------------+
void PollApiStatus()
{
   string headers = "";
   char   post[];
   char   result[];
   string resultHeaders;
   int    timeout = 5000;

   ResetLastError();
   int res = WebRequest("GET", InpApiUrl, headers, timeout, post, result, resultHeaders);

   if(res == -1)
   {
      int err = GetLastError();
      PrintFormat("WebRequest gagal (error %d). Pastikan URL sudah ditambahkan di Tools > Options > Expert Advisors > Allow WebRequest for listed URL: %s", err, InpApiUrl);
      return;
   }

   string json = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);

   bool found = false;
   bool val = JsonGetBool(json, "running", found);

   if(found)
   {
      if(val != g_running)
         PrintFormat("Status berubah: running %s -> %s", (g_running ? "true" : "false"), (val ? "true" : "false"));
      g_running = val;
   }
   else
   {
      PrintFormat("Field running tidak ditemukan di response JSON. Raw: %s", json);
   }
}

//+------------------------------------------------------------------+
//| Parser JSON minimal: ambil boolean untuk key yang PERSIS cocok   |
//| (dibatasi tanda kutip + titik dua), bukan cari kata di teks bebas|
//+------------------------------------------------------------------+
bool JsonGetBool(const string &json, const string key, bool &found)
{
   found = false;
   string dq = CharToString(34); // karakter tanda kutip ("), dibuat lewat kode ASCII
                                  // biar aman dari masalah escape \" di compiler
   string needle = dq + key + dq;
   int pos = StringFind(json, needle);
   if(pos < 0) return false;

   int i   = pos + StringLen(needle);
   int len = StringLen(json);

   // lewati whitespace, lalu wajib ketemu ':'
   while(i < len && (StringGetCharacter(json, i) == ' ' || StringGetCharacter(json, i) == '\t' ||
                      StringGetCharacter(json, i) == '\n' || StringGetCharacter(json, i) == '\r'))
      i++;
   if(i >= len || StringGetCharacter(json, i) != ':') return false;
   i++;

   // lewati whitespace setelah ':'
   while(i < len && (StringGetCharacter(json, i) == ' ' || StringGetCharacter(json, i) == '\t' ||
                      StringGetCharacter(json, i) == '\n' || StringGetCharacter(json, i) == '\r'))
      i++;

   if(i + 4 <= len && StringSubstr(json, i, 4) == "true")
   {
      found = true;
      return true;
   }
   if(i + 5 <= len && StringSubstr(json, i, 5) == "false")
   {
      found = true;
      return false;
   }
   return false; // value bukan boolean (mis. null/angka) -> found tetap false
}

//+------------------------------------------------------------------+
//| Bias M30: area utama. 1 = area BUY, -1 = area SELL, 0 = netral   |
//+------------------------------------------------------------------+
int GetAreaBias()
{
   double fast[], slow[];
   if(CopyBuffer(h_ema_fast_area, 0, 1, 1, fast) <= 0) return 0;
   if(CopyBuffer(h_ema_slow_area, 0, 1, 1, slow) <= 0) return 0;
   if(fast[0] > slow[0]) return 1;
   if(fast[0] < slow[0]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Konfirmasi M15: harus searah dengan bias M30                     |
//+------------------------------------------------------------------+
int GetConfirmBias()
{
   double fast[], slow[];
   if(CopyBuffer(h_ema_fast_confirm, 0, 1, 1, fast) <= 0) return 0;
   if(CopyBuffer(h_ema_slow_confirm, 0, 1, 1, slow) <= 0) return 0;
   if(fast[0] > slow[0]) return 1;
   if(fast[0] < slow[0]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Sinyal M5: tentukan BUY(1) / SELL(-1) / tidak ada(0)             |
//+------------------------------------------------------------------+
int GetSignal()
{
   double fast[], slow[];
   if(CopyBuffer(h_ema_fast_signal, 0, 1, 1, fast) <= 0) return 0;
   if(CopyBuffer(h_ema_slow_signal, 0, 1, 1, slow) <= 0) return 0;
   if(fast[0] > slow[0]) return 1;
   if(fast[0] < slow[0]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Trigger M1: cukup pakai momentum candle terakhir yang sudah     |
//| closed (shift=1), tidak perlu 3 candle berturut-turut lagi       |
//+------------------------------------------------------------------+
bool CheckM1Trigger(int direction) // direction: 1=BUY, -1=SELL
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, TF_TRIGGER, 1, 1, rates) <= 0) return false;

   double open  = rates[0].open;
   double close = rates[0].close;
   double body  = MathAbs(close - open) / _Point;

   if(body < InpMinM1BodyPoints) return false; // momentum kurang kuat

   if(direction == 1  && close > open) return true;  // candle bullish
   if(direction == -1 && close < open) return true;  // candle bearish
   return false;
}

//+------------------------------------------------------------------+
int CountMyPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Trailing SL untuk posisi yang sudah terbuka, tanpa TP fixed      |
//+------------------------------------------------------------------+
void ManageTrailing()
{
   double point = _Point;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long   type      = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL      = PositionGetDouble(POSITION_SL);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(type == POSITION_TYPE_BUY)
      {
         double profitPts = (bid - openPrice) / point;
         if(profitPts >= InpTrailingStartPts)
         {
            double newSL = bid - InpTrailingStepPts * point;
            if(newSL > curSL || curSL == 0.0)
               trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), 0.0); // TP tetap 0 (tanpa TP fixed)
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double profitPts = (openPrice - ask) / point;
         if(profitPts >= InpTrailingStartPts)
         {
            double newSL = ask + InpTrailingStepPts * point;
            if(newSL < curSL || curSL == 0.0)
               trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), 0.0);
         }
      }
   }
}

//+------------------------------------------------------------------+
void OpenTrade(int direction)
{
   double point = _Point;
   if(direction == 1)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = ask - InpInitialSLPoints * point;
      trade.Buy(InpLotSize, _Symbol, ask, NormalizeDouble(sl, _Digits), 0.0, "GoldScalper BUY");
   }
   else if(direction == -1)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = bid + InpInitialSLPoints * point;
      trade.Sell(InpLotSize, _Symbol, bid, NormalizeDouble(sl, _Digits), 0.0, "GoldScalper SELL");
   }

   if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
      g_lastTradeTime = TimeCurrent();
   else
      PrintFormat("Order gagal, retcode=%d, komentar=%s", trade.ResultRetcode(), trade.ResultComment());
}

//+------------------------------------------------------------------+
void OnTick()
{
   // trailing tetap jalan walau running=false, supaya posisi yang sudah   
   // terbuka tetap dikelola amannya (tidak dibiarkan tanpa trailing)
   ManageTrailing();

   if(!g_running)
      return; // STOP dari APK -> tidak buka posisi baru

   if(CountMyPositions() >= InpMaxPositions)
      return;

   if(TimeCurrent() - g_lastTradeTime < InpCooldownMinutes * 60)
      return;

   int area    = GetAreaBias();      // M30
   int confirm = GetConfirmBias();   // M15
   int signal  = GetSignal();        // M5

   if(area == 0 || confirm == 0 || signal == 0) return;
   if(area != confirm || confirm != signal) return; // semua timeframe harus searah

   int direction = signal; // 1 = BUY, -1 = SELL

   if(CheckM1Trigger(direction)) // M1 = trigger entry pakai momentum candle terakhir
      OpenTrade(direction);
}
//+------------------------------------------------------------------+
