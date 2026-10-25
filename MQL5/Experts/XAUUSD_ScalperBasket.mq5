//+------------------------------------------------------------------+
//|                                        XAUUSD_ScalperBasket.mq5  |
//|  M1 trend yonunde ayni anda 4-5 adet 0.01 lot islem acan,        |
//|  kucuk karlari hizli kapatan ve zarari sinirlayan scalper bot.   |
//+------------------------------------------------------------------+
#property copyright "Proje-1"
#property version   "1.00"
#property description "XAUUSD M1 sepet scalper: trend yonunde 4-5 x 0.01 lot,"
#property description "islem basi 0.30-0.60$ TP, sepet 1.5-3$ olunca hepsini kapatir."

#include <Trade/Trade.mqh>

//--- Islem ayarlari
input group "=== Islem ayarlari ==="
input double InpLot              = 0.01;   // Her islemin lotu
input int    InpTradesPerBasket  = 5;      // Ayni anda acilacak islem sayisi (4-5)
input double InpTPMinUSD         = 0.30;   // En dusuk islem basi kar ($)
input double InpTPMaxUSD         = 0.60;   // En yuksek islem basi kar ($)
input double InpSLUSD            = 0.80;   // Islem basi en fazla zarar ($)
input double InpBasketTPUSD      = 2.00;   // Sepet toplam kari bu olunca hepsini kapat ($)
input double InpBasketSLUSD      = 3.00;   // Sepet toplam zarari bu olunca hepsini kapat ($)
input int    InpMaxHoldSeconds   = 180;    // Islemi en fazla tutma suresi (saniye, 180 = 3 dk)
input int    InpCooldownSeconds  = 30;     // Sepet kapandiktan sonra bekleme (saniye)
input int    InpSlippagePoints   = 30;     // Izin verilen kayma (point)

//--- Trend ayarlari
input group "=== Trend (M1) ==="
input int    InpFastEMA          = 9;      // Hizli EMA
input int    InpSlowEMA          = 21;     // Yavas EMA
input int    InpTrendEMA         = 50;     // Ana trend EMA
input bool   InpUseM5Filter      = true;   // M5 EMA50 ile trend onayi

//--- Volatilite / spread
input group "=== Volatilite ve spread ==="
input int    InpATRPeriod        = 14;     // ATR periyodu (M1)
input double InpMinATR           = 0.60;   // Minimum M1 ATR (fiyat birimi, $)
input double InpMaxSpread        = 0.40;   // Maksimum spread (fiyat birimi, $)

//--- Seans (BROKER SUNUCU SAATI)
input group "=== Seans (sunucu saati) ==="
input bool   InpUseSession       = true;   // Sadece oynak saatlerde islem
input int    InpSession1Start    = 10;     // Seans 1 baslangic (Londra acilisi)
input int    InpSession1End      = 13;     // Seans 1 bitis
input int    InpSession2Start    = 15;     // Seans 2 baslangic (New York acilisi)
input int    InpSession2End      = 19;     // Seans 2 bitis

//--- Hesap koruma
input group "=== Hesap koruma ==="
input double InpDailyLossLimit   = 6.00;   // Gunluk max zarar ($) - asilinca bot o gun durur
input double InpDailyProfitTarget= 0.00;   // Gunluk kar hedefi ($) - 0 = kapali
input double InpMinEquity        = 60.00;  // Equity bunun altina inerse bot durur ($)
input long   InpMagic            = 260425; // Magic number

//--- Globaller
CTrade   trade;
int      hFast = INVALID_HANDLE, hSlow = INVALID_HANDLE, hTrend = INVALID_HANDLE;
int      hATR  = INVALID_HANDLE, hM5   = INVALID_HANDLE;
datetime g_lastEntryBar   = 0;
datetime g_lastBasketExit = 0;
int      g_lastCount      = 0;
string   g_status         = "";

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpTradesPerBasket < 1 || InpTradesPerBasket > 10)
   {
      Print("Islem sayisi 1-10 arasi olmali");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpTPMaxUSD < InpTPMinUSD || InpTPMinUSD <= 0 || InpSLUSD <= 0)
   {
      Print("TP/SL ayarlari hatali");
      return INIT_PARAMETERS_INCORRECT;
   }

   hFast  = iMA(_Symbol, PERIOD_M1, InpFastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlow  = iMA(_Symbol, PERIOD_M1, InpSlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   hTrend = iMA(_Symbol, PERIOD_M1, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hATR   = iATR(_Symbol, PERIOD_M1, InpATRPeriod);
   hM5    = iMA(_Symbol, PERIOD_M5, 50, 0, MODE_EMA, PRICE_CLOSE);
   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE || hTrend == INVALID_HANDLE ||
      hATR == INVALID_HANDLE || hM5 == INVALID_HANDLE)
   {
      Print("Indikator olusturulamadi");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_lastCount = CountPositions();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hFast);
   IndicatorRelease(hSlow);
   IndicatorRelease(hTrend);
   IndicatorRelease(hATR);
   IndicatorRelease(hM5);
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   ManagePositions();

   int count = CountPositions();
   if(g_lastCount > 0 && count == 0)
      g_lastBasketExit = TimeCurrent();
   g_lastCount = count;

   if(count == 0)
      TryOpenBasket();

   ShowStatus(count);
}

//+------------------------------------------------------------------+
//| Acik pozisyonlari yonet: sepet TP/SL ve sure cikisi              |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double basket = 0.0;
   int    count  = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsMine())
         continue;
      count++;
      basket += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   if(count == 0)
      return;

   if(basket >= InpBasketTPUSD)
   {
      CloseAll(StringFormat("Sepet kar hedefi: %.2f$", basket));
      return;
   }
   if(basket <= -InpBasketSLUSD)
   {
      CloseAll(StringFormat("Sepet zarar limiti: %.2f$", basket));
      return;
   }

   // Sure dolan islemleri kapat (1-3 dakika kurali)
   datetime now = TimeCurrent();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsMine())
         continue;
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      if(now - opened >= InpMaxHoldSeconds)
      {
         if(!trade.PositionClose(ticket))
            PrintFormat("Sure cikisi basarisiz #%I64u: %d", ticket, trade.ResultRetcode());
      }
   }
}

//+------------------------------------------------------------------+
//| Kosullar uygunsa trend yonunde sepet ac                          |
//+------------------------------------------------------------------+
void TryOpenBasket()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      g_status = "AutoTrading kapali";
      return;
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= InpMinEquity)
   {
      g_status = StringFormat("DURDU: equity %.2f$ <= %.2f$", equity, InpMinEquity);
      return;
   }

   double dayPL = DailyClosedPL();
   if(dayPL <= -InpDailyLossLimit)
   {
      g_status = StringFormat("DURDU: gunluk zarar limiti (%.2f$)", dayPL);
      return;
   }
   if(InpDailyProfitTarget > 0 && dayPL >= InpDailyProfitTarget)
   {
      g_status = StringFormat("DURDU: gunluk hedef tamam (%.2f$)", dayPL);
      return;
   }

   if(TimeCurrent() - g_lastBasketExit < InpCooldownSeconds)
   {
      g_status = "Bekleme suresi";
      return;
   }

   if(InpUseSession && !InSession())
   {
      g_status = "Seans disi (oynak saat degil)";
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;
   double spread = tick.ask - tick.bid;
   if(spread > InpMaxSpread)
   {
      g_status = StringFormat("Spread yuksek: %.2f", spread);
      return;
   }

   double atr = GetBuf(hATR, 1);
   if(atr < InpMinATR)
   {
      g_status = StringFormat("Piyasa sakin, ATR %.2f < %.2f", atr, InpMinATR);
      return;
   }

   // Ayni mumda ikinci kez giris yapma
   datetime bar = iTime(_Symbol, PERIOD_M1, 0);
   if(bar == g_lastEntryBar)
   {
      g_status = "Yeni mum bekleniyor";
      return;
   }

   int dir = TrendSignal();
   if(dir == 0)
   {
      g_status = "Net trend yok, bekliyor";
      return;
   }

   g_lastEntryBar = bar;
   OpenBasket(dir);
}

//+------------------------------------------------------------------+
//| Trend sinyali: +1 buy, -1 sell, 0 yok (kapanmis mumlara bakar)   |
//+------------------------------------------------------------------+
int TrendSignal()
{
   double fast1  = GetBuf(hFast, 1),  fast2 = GetBuf(hFast, 2);
   double slow1  = GetBuf(hSlow, 1);
   double trend1 = GetBuf(hTrend, 1);
   if(fast1 == 0 || slow1 == 0 || trend1 == 0)
      return 0;

   double open1  = iOpen(_Symbol, PERIOD_M1, 1);
   double close1 = iClose(_Symbol, PERIOD_M1, 1);

   bool m5Up = true, m5Down = true;
   if(InpUseM5Filter)
   {
      double m5ema   = GetBuf(hM5, 1);
      double m5close = iClose(_Symbol, PERIOD_M5, 1);
      if(m5ema == 0)
         return 0;
      m5Up   = m5close > m5ema;
      m5Down = m5close < m5ema;
   }

   bool buy  = fast1 > slow1 && slow1 > trend1 && fast1 > fast2 &&
               close1 > open1 && close1 > fast1 && m5Up;
   bool sell = fast1 < slow1 && slow1 < trend1 && fast1 < fast2 &&
               close1 < open1 && close1 < fast1 && m5Down;

   if(buy)  return  1;
   if(sell) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Sepeti ac: her isleme TPmin..TPmax arasi farkli kar hedefi       |
//+------------------------------------------------------------------+
void OpenBasket(int dir)
{
   double lot = NormalizeLot(InpLot);
   if(lot <= 0)
      return;

   int n = InpTradesPerBasket;

   // Teminat yetmezse islem sayisini azalt
   double margin1 = 0.0;
   double price   = dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   ENUM_ORDER_TYPE type = dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcMargin(type, _Symbol, lot, price, margin1) && margin1 > 0)
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.8;
      int maxByMargin = (int)MathFloor(freeMargin / margin1);
      if(maxByMargin < n)
      {
         PrintFormat("Teminat yetersiz: %d yerine %d islem aciliyor", n, maxByMargin);
         n = maxByMargin;
      }
   }
   if(n <= 0)
   {
      g_status = "Teminat yetersiz";
      return;
   }

   for(int i = 0; i < n; i++)
   {
      double tpMoney = (n > 1) ? InpTPMinUSD + (InpTPMaxUSD - InpTPMinUSD) * i / (n - 1) : InpTPMinUSD;

      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick))
         return;

      double tpDist = MathMax(MoneyToPrice(tpMoney, lot), MinStopDistance());
      double slDist = MathMax(MoneyToPrice(InpSLUSD, lot), MinStopDistance());
      if(tpDist <= 0 || slDist <= 0)
         return;

      string cmt = StringFormat("XAU basket %d/%d", i + 1, n);
      bool ok;
      if(dir > 0)
         ok = trade.Buy(lot, _Symbol, tick.ask,
                        RoundPrice(tick.ask - slDist), RoundPrice(tick.ask + tpDist), cmt);
      else
         ok = trade.Sell(lot, _Symbol, tick.bid,
                         RoundPrice(tick.bid + slDist), RoundPrice(tick.bid - tpDist), cmt);

      if(!ok)
      {
         PrintFormat("Islem acilamadi: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
         break;
      }
   }
   g_status = dir > 0 ? "BUY sepeti acildi" : "SELL sepeti acildi";
}

//+------------------------------------------------------------------+
void CloseAll(string reason)
{
   Print("Hepsi kapatiliyor - ", reason);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsMine())
         continue;
      if(!trade.PositionClose(ticket))
         PrintFormat("Kapatma basarisiz #%I64u: %d", ticket, trade.ResultRetcode());
   }
}

//+------------------------------------------------------------------+
//| Yardimcilar                                                      |
//+------------------------------------------------------------------+
bool IsMine()   // PositionGetTicket ile secilmis pozisyon icin
{
   return PositionGetString(POSITION_SYMBOL) == _Symbol &&
          PositionGetInteger(POSITION_MAGIC) == InpMagic;
}

int CountPositions()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) != 0 && IsMine())
         c++;
   return c;
}

double GetBuf(int handle, int shift)
{
   double buf[1];
   if(CopyBuffer(handle, 0, shift, 1, buf) != 1)
      return 0.0;
   return buf[0];
}

bool InSession()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(t.day_of_week == 0 || t.day_of_week == 6)
      return false;
   return HourIn(t.hour, InpSession1Start, InpSession1End) ||
          HourIn(t.hour, InpSession2Start, InpSession2End);
}

bool HourIn(int h, int start, int end)
{
   if(start == end)
      return false;
   if(start < end)
      return h >= start && h < end;
   return h >= start || h < end;   // gece yarisini gecen seans
}

// Bugun kapanan bot islemlerinin net kari (komisyon + swap dahil)
double DailyClosedPL()
{
   datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);
   if(dayStart == 0 || !HistorySelect(dayStart, TimeCurrent() + 60))
      return 0.0;

   double pl = 0.0;
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic)
         continue;
      pl += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) +
            HistoryDealGetDouble(d, DEAL_COMMISSION);
   }
   return pl;
}

// $ tutarini fiyat mesafesine cevir (0.01 lot XAUUSD: 1$ hareket ~ 1$)
double MoneyToPrice(double money, double lot)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0 || lot <= 0)
      return 0.0;
   return money / (lot * tickValue / tickSize);
}

double MinStopDistance()
{
   long   level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return (level + 2) * point;
}

double RoundPrice(double p)
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts > 0)
      p = MathRound(p / ts) * ts;
   return NormalizeDouble(p, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

double NormalizeLot(double lot)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step > 0)
      lot = MathFloor(lot / step + 1e-9) * step;
   return MathMax(minLot, MathMin(maxLot, lot));
}

void ShowStatus(int count)
{
   double basket = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) != 0 && IsMine())
         basket += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

   Comment(StringFormat(
      "XAUUSD Scalper Basket\n"
      "Durum: %s\n"
      "Acik islem: %d   Sepet: %.2f$ (hedef %.2f$ / limit -%.2f$)\n"
      "Bugun kapanan: %.2f$   (gunluk limit -%.2f$)\n"
      "Equity: %.2f$",
      g_status, count, basket, InpBasketTPUSD, InpBasketSLUSD,
      DailyClosedPL(), InpDailyLossLimit, AccountInfoDouble(ACCOUNT_EQUITY)));
}
//+------------------------------------------------------------------+
