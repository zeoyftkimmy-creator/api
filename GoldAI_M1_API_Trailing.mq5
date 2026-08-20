//+------------------------------------------------------------------+
//| GoldAI_M1_API_Trailing.mq5                                       |
//| XAUUSD M1 - 3 Candle + Initial SL + Trailing (basis dolar) + API |
//+------------------------------------------------------------------+
#property copyright "Custom EA"
#property version   "1.42"
#property strict

//==================================================================//
// INPUT
//==================================================================//

//--- LOT
input double LotSize = 0.01;

//--- INITIAL STOP LOSS (dalam dolar pergerakan harga)
// BUY  : Entry 3998.00 -> SL 3996.00
// SELL : Entry 3998.00 -> SL 4000.00
input double InitialSLDistance = 2.00;

//--- TRAILING (dalam dolar pergerakan harga)
// Trailing aktif begitu profit floating >= TrailStart_USD
// SL akan selalu berjarak TrailDistance_USD di belakang harga
input double TrailStart_USD    = 5.0;
input double TrailDistance_USD = 1.0;

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
   datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);

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

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
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


//==================================================================//
// CEK API START / STOP
//==================================================================//

void CheckApiStatus()
{
   if(ApiStatusUrl == "")
      return;

   if(TimeCurrent() - lastApiCheckTime < ApiCheckSeconds)
      return;

   lastApiCheckTime = TimeCurrent();

   string headers = "";
   char   postData[];
   char   result[];
   string resultHeaders;
   int    timeout = 5000;

   ResetLastError();

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
      Print("WebRequest API gagal. Error = ", GetLastError());
      return;
   }

   string response = CharArrayToString(result);

   Print("API Response: ", response);

   if(
      StringFind(response, "\"status\":\"RUNNING\"") >= 0 ||
      StringFind(response, "\"running\":true")        >= 0 ||
      StringFind(response, "\"running\": true")        >= 0
   )
   {
      if(!botEnabled)
         Print("API RUNNING -> Bot AKTIF");

      botEnabled = true;
      return;
   }

   if(
      StringFind(response, "\"status\":\"STOPPED\"") >= 0 ||
      StringFind(response, "\"running\":false")        >= 0 ||
      StringFind(response, "\"running\": false")        >= 0
   )
   {
      if(botEnabled)
         Print("API STOPPED -> Entry BARU dihentikan");

      botEnabled = false;
      return;
   }

   Print("Response API tidak dikenali: ", response);
}


//==================================================================//
// CEK JARAK MINIMUM SL BROKER
//==================================================================//

bool IsValidSLDistance(ENUM_ORDER_TYPE orderType, double sl)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = stopsLevel * _Point;

   if(orderType == ORDER_TYPE_BUY)
   {
      if((bid - sl) < minDistance)
         return false;
   }

   if(orderType == ORDER_TYPE_SELL)
   {
      if((sl - ask) < minDistance)
         return false;
   }

   return true;
}


//==================================================================//
// TENTUKAN FILLING MODE YANG DIDUKUNG BROKER
//==================================================================//

ENUM_ORDER_TYPE_FILLING GetFillingMode()
{
   int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);

   if(filling == 0)
      return ORDER_FILLING_IOC;

   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;

   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;
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

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double sl = ask - InitialSLDistance;
   sl = NormalizeDouble(sl, _Digits);

   if(!IsValidSLDistance(ORDER_TYPE_BUY, sl))
   {
      Print("BUY dibatalkan: Initial SL terlalu dekat.");
      return;
   }

   request.action       = TRADE_ACTION_DEAL;
   request.symbol        = _Symbol;
   request.volume        = LotSize;
   request.type          = ORDER_TYPE_BUY;
   request.price         = ask;
   request.sl            = sl;
   request.tp             = 0;
   request.deviation     = Slippage;
   request.magic         = MagicNumber;
   request.comment       = "3Candle-BUY";
   request.type_filling  = GetFillingMode();

   ResetLastError();

   if(!OrderSend(request, result))
   {
      Print("BUY gagal. Error = ", GetLastError());
      return;
   }

   if(result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED)
   {
      Print("BUY ditolak broker. Retcode = ", result.retcode);
      return;
   }

   Print("BUY BERHASIL | Entry = ", ask, " | Initial SL = ", sl);
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

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl = bid + InitialSLDistance;
   sl = NormalizeDouble(sl, _Digits);

   if(!IsValidSLDistance(ORDER_TYPE_SELL, sl))
   {
      Print("SELL dibatalkan: Initial SL terlalu dekat.");
      return;
   }

   request.action       = TRADE_ACTION_DEAL;
   request.symbol        = _Symbol;
   request.volume        = LotSize;
   request.type          = ORDER_TYPE_SELL;
   request.price         = bid;
   request.sl            = sl;
   request.tp             = 0;
   request.deviation     = Slippage;
   request.magic         = MagicNumber;
   request.comment       = "3Candle-SELL";
   request.type_filling  = GetFillingMode();

   ResetLastError();

   if(!OrderSend(request, result))
   {
      Print("SELL gagal. Error = ", GetLastError());
      return;
   }

   if(result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED)
   {
      Print("SELL ditolak broker. Retcode = ", result.retcode);
      return;
   }

   Print("SELL BERHASIL | Entry = ", bid, " | Initial SL = ", sl);
}


//==================================================================//
// TRAILING STOP (BERBASIS PROFIT DOLAR)
//
// Trailing aktif setelah profit floating >= TrailStart_USD
// SL selalu digeser supaya berjarak TrailDistance_USD dari harga
//==================================================================//

void TrailPositions()
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
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

      long   posType   = PositionGetInteger(POSITION_TYPE);
      double posOpen    = PositionGetDouble(POSITION_PRICE_OPEN);
      double posSL       = PositionGetDouble(POSITION_SL);
      double posVolume  = PositionGetDouble(POSITION_VOLUME);
      double bid          = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask          = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      //--- profit floating dalam DOLAR (pakai profit riil dari posisi, paling akurat)
      double profitUSD = PositionGetDouble(POSITION_PROFIT);

      //--- konversi TrailDistance_USD ke jarak HARGA (bukan uang) untuk XAUUSD
      // priceDistance = (TrailDistance_USD / tickValue) * tickSize / volume
      double priceDistance = (TrailDistance_USD / (tickValue * posVolume)) * tickSize;

      if(posType == POSITION_TYPE_BUY)
      {
         if(profitUSD < TrailStart_USD)
            continue;

         double newSL = bid - priceDistance;
         newSL = NormalizeDouble(newSL, _Digits);

         if(!IsValidSLDistance(ORDER_TYPE_BUY, newSL))
            continue;

         if(posSL == 0 || newSL > posSL)
            ModifySL(ticket, newSL);
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         if(profitUSD < TrailStart_USD)
            continue;

         double newSL = ask + priceDistance;
         newSL = NormalizeDouble(newSL, _Digits);

         if(!IsValidSLDistance(ORDER_TYPE_SELL, newSL))
            continue;

         if(posSL == 0 || newSL < posSL)
            ModifySL(ticket, newSL);
      }
   }
}


//==================================================================//
// MODIFIKASI SL
//==================================================================//

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
   request.symbol    = _Symbol;
   request.sl         = newSL;
   request.tp          = PositionGetDouble(POSITION_TP);

   ResetLastError();

   if(!OrderSend(request, result))
   {
      Print("Modify SL gagal | Ticket = ", ticket, " | Error = ", GetLastError());
      return;
   }

   if(result.retcode != TRADE_RETCODE_DONE)
   {
      Print("Modify SL ditolak | Ticket = ", ticket, " | Retcode = ", result.retcode);
      return;
   }

   Print("TRAILING SL BERGERAK | Ticket = ", ticket, " | New SL = ", newSL);
}


//==================================================================//
// INIT
//==================================================================//

int OnInit()
{
   lastBarTime = iTime(_Symbol, PERIOD_M1, 0);

   CheckApiStatus();

   Print("==========================================");
   Print("GoldAI_M1_API_Trailing AKTIF");
   Print("Symbol = ", _Symbol);
   Print("Timeframe = M1");
   Print("Lot = ", LotSize);
   Print("Initial SL = $", InitialSLDistance);
   Print("Trailing Start = $", TrailStart_USD);
   Print("Trailing Distance = $", TrailDistance_USD);
   Print("Filling Mode terdeteksi = ", EnumToString(GetFillingMode()));
   Print("==========================================");

   return(INIT_SUCCEEDED);
}


//==================================================================//
// TICK
//==================================================================//

void OnTick()
{
   CheckApiStatus();

   if(CountOpenPositions() > 0)
      TrailPositions();

   if(!botEnabled)
      return;

   if(!IsNewBar())
      return;

   if(CountOpenPositions() >= 1)
      return;

   int signal = Check3CandleSignal();

   if(signal == 1)
      OpenBuy();
   else if(signal == -1)
      OpenSell();
}
//+------------------------------------------------------------------+
