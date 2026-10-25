//+------------------------------------------------------------------+
//|                                           XAU_TrendBreakout.mq5  |
//|  XAUUSD H1 trend kirilim botu                                    |
//|                                                                  |
//|  Kural (2020-2026 dakikalik veride test edildi):                 |
//|   - H1 mum kapanisi son 10 H1 mumun tepesini kirarsa BUY,        |
//|     dibini kirarsa SELL                                          |
//|   - Sadece uzun vadeli trend yonunde (H1 EMA 1150 ~ 50 gun)      |
//|   - Sadece piyasa hareketliyken (H1 ATR120 / fiyat > %0.30)      |
//|   - Stop = 0.5 x H1 ATR14, kar hedefi yok (trend gunu kosar)     |
//|   - Tum pozisyonlar New York saatiyle 16:00'da kapanir           |
//|   - Gunde en fazla 1 islem                                       |
//+------------------------------------------------------------------+
#property copyright "Proje-1"
#property version   "1.00"
#property description "XAUUSD H1 trend kirilimi: 10 saatlik kanal kirilimi + trend + volatilite filtresi."
#property description "Stop 0.5 x ATR, kar hedefi yok, New York 16:00'da kapanis, gunde max 1 islem."

#include <Trade/Trade.mqh>

#define LOG_FILE "XAU_TrendBreakout_log.csv"

enum ENUM_TZ_MODE
  {
   TZ_AUTO    = 0, // Otomatik (canli/demo hesapta)
   TZ_NYCLOSE = 1, // GMT+2 / GMT+3 (cogu broker)
   TZ_GMT0    = 2, // GMT+0 (or. Exness)
   TZ_CUSTOM  = 3  // Sabit fark (asagidaki ayar)
  };

//--- Risk
input group "=== Risk ==="
input double InpLots            = 0.01;  // Lot (pozisyon basi)
input int    InpPositions       = 1;     // Sinyal basina pozisyon sayisi
input double InpMaxLossUSD      = 10.0;  // Pozisyon basi max zarar ($) - stop daha genisse islem acma
input double InpMinEquity       = 40.0;  // Equity bunun altina inerse bot yeni islem acmaz ($)
input int    InpMaxTradesPerDay = 1;     // Gunluk max islem (sinyal)

//--- Strateji
input group "=== Strateji (H1) ==="
input int    InpChannelBars     = 10;    // Kanal: son kac H1 mumun tepesi/dibi
input int    InpTrendEMA        = 1150;  // Trend filtresi: H1 EMA periyodu (~50 gun)
input int    InpVolATRPeriod    = 120;   // Volatilite filtresi: H1 ATR periyodu (~5 gun)
input double InpMinVolPercent   = 0.30;  // Min volatilite: ATR / fiyat (%)
input int    InpStopATRPeriod   = 14;    // Stop icin H1 ATR periyodu
input double InpStopATRMult     = 0.5;   // Stop mesafesi = ATR x bu carpan

//--- Zaman
input group "=== Zaman ==="
input ENUM_TZ_MODE InpTZMode    = TZ_AUTO; // Broker saat dilimi
input int    InpCustomGMTOffset = 0;     // Sabit fark modu: sunucu saati - GMT (saat)
input int    InpExitHourNY      = 16;    // Kapanis saati (New York saati, 1-16)
input int    InpEntryWindowMin  = 10;    // Yeni H1 mumundan sonra giris icin kac dk beklenir

//--- Islem
input group "=== Islem ayarlari ==="
input double InpMaxSpread       = 0.60;  // Max spread (fiyat birimi, $)
input int    InpSlippagePoints  = 50;    // Max kayma (point)
input long   InpMagic           = 20261025; // Magic number
input bool   InpWriteLog        = true;  // Islemleri CSV dosyasina yaz

//--- Globaller
CTrade   trade;
int      hATRStop = INVALID_HANDLE;
int      hATRVol  = INVALID_HANDLE;
int      hEMA     = INVALID_HANDLE;
datetime g_lastH1        = 0;
int      g_pendingDir    = 0;
double   g_pendingSLDist = 0.0;
datetime g_pendingUntil  = 0;
string   g_status        = "Basliyor";
string   g_lastSignal    = "-";
int      g_cacheDay      = -1;
int      g_cacheTrades   = 0;
datetime g_cacheTime     = 0;
bool     g_cacheDirty    = true;

// son degerlendirilen H1 mumunun degerleri (panel icin)
double   g_close = 0, g_hh = 0, g_ll = 0, g_ema = 0, g_volPct = 0, g_atrStop = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpLots <= 0 || InpPositions < 1 || InpPositions > 10 || InpChannelBars < 2 ||
      InpTrendEMA < 2 || InpVolATRPeriod < 2 || InpStopATRPeriod < 2 || InpStopATRMult <= 0 ||
      InpExitHourNY < 1 || InpExitHourNY > 16 || InpMaxTradesPerDay < 1 || InpEntryWindowMin < 1)
     {
      Print("Ayarlar hatali, lutfen kontrol edin.");
      return INIT_PARAMETERS_INCORRECT;
     }

   hATRStop = iATR(_Symbol, PERIOD_H1, InpStopATRPeriod);
   hATRVol  = iATR(_Symbol, PERIOD_H1, InpVolATRPeriod);
   hEMA     = iMA(_Symbol, PERIOD_H1, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(hATRStop == INVALID_HANDLE || hATRVol == INVALID_HANDLE || hEMA == INVALID_HANDLE)
     {
      Print("Indikator olusturulamadi");
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(InpTZMode == TZ_AUTO && IsTester())
      Print("Strategy Tester: saat dilimi otomatik bulunamaz, GMT+2/+3 (NY kapanis) varsayiliyor. ",
            "Broker GMT+0 ise 'Broker saat dilimi' ayarini GMT+0 yapin.");

   WriteLogHeader();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(hATRStop);
   IndicatorRelease(hATRVol);
   IndicatorRelease(hEMA);
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   // 1) Kapanis saati geldiyse pozisyonlari kapat
   if(CountPositions() > 0 && IsExitTime())
      CloseAll("NY kapanis saati");

   // 2) Yeni H1 mumu: kapanan mumu degerlendir
   datetime h1 = iTime(_Symbol, PERIOD_H1, 0);
   if(h1 != 0 && h1 != g_lastH1)
     {
      g_lastH1 = h1;
      EvaluateSignal(h1);
     }

   // 3) Bekleyen sinyal varsa girisi dene
   if(g_pendingDir != 0)
     {
      if(TimeCurrent() > g_pendingUntil)
        {
         g_status = "Giris suresi doldu (spread/sart uygun olmadi)";
         g_pendingDir = 0;
        }
      else
         TryEnter();
     }

   UpdatePanel();
  }

//+------------------------------------------------------------------+
//| Kapanan H1 mumunda kirilim var mi?                               |
//+------------------------------------------------------------------+
void EvaluateSignal(datetime barOpen)
  {
   g_pendingDir = 0;

   if(Bars(_Symbol, PERIOD_H1) < MathMax(InpTrendEMA, InpVolATRPeriod) + InpChannelBars + 5)
     {
      g_status = "H1 gecmisi yetersiz, grafik verisi yukleniyor";
      return;
     }

   double close1 = iClose(_Symbol, PERIOD_H1, 1);
   int    iHi    = iHighest(_Symbol, PERIOD_H1, MODE_HIGH, InpChannelBars, 2);
   int    iLo    = iLowest(_Symbol, PERIOD_H1, MODE_LOW, InpChannelBars, 2);
   double ema    = GetBuf(hEMA, 1);
   double atrS   = GetBuf(hATRStop, 1);
   double atrV   = GetBuf(hATRVol, 1);
   if(close1 <= 0 || iHi < 0 || iLo < 0 || ema <= 0 || atrS <= 0 || atrV <= 0)
     {
      g_status = "Veri hazir degil";
      return;
     }

   double hh = iHigh(_Symbol, PERIOD_H1, iHi);
   double ll = iLow(_Symbol, PERIOD_H1, iLo);
   double volPct = 100.0 * atrV / close1;

   g_close = close1; g_hh = hh; g_ll = ll; g_ema = ema; g_volPct = volPct; g_atrStop = atrS;

   int dir = 0;
   if(close1 > hh && close1 > ema)
      dir = 1;
   else if(close1 < ll && close1 < ema)
      dir = -1;

   if(dir == 0)
     {
      g_status = "Sinyal yok, bekliyor";
      return;
     }
   if(volPct < InpMinVolPercent)
     {
      g_status = StringFormat("Kirilim var ama piyasa sakin (%.2f%% < %.2f%%), islem yok", volPct, InpMinVolPercent);
      return;
     }

   g_pendingDir    = dir;
   g_pendingSLDist = InpStopATRMult * atrS;
   g_pendingUntil  = (datetime)((long)barOpen + InpEntryWindowMin * 60);
   g_lastSignal    = StringFormat("%s %s (kapanis %.2f, kanal %.2f/%.2f)",
                                  TimeToString(barOpen, TIME_DATE | TIME_MINUTES),
                                  dir > 0 ? "BUY" : "SELL", close1, hh, ll);
   g_status        = "Sinyal: " + (dir > 0 ? string("BUY") : string("SELL"));
  }

//+------------------------------------------------------------------+
//| Giris: tum kontrolleri yap, uygunsa pozisyon(lar)i ac            |
//+------------------------------------------------------------------+
void TryEnter()
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      g_status = "Algo Trading kapali";
      return;
     }
   if(CountPositions() > 0)
     {
      g_pendingDir = 0;
      return;
     }

   datetime ny = NYTime(TimeCurrent());
   int nyHour = HourOf(ny);
   if(nyHour >= InpExitHourNY && nyHour < 19)
     {
      g_status = "Kapanis saatlerinde giris yok";
      g_pendingDir = 0;
      return;
     }

   int dayKey = TradingDayKey(ny);
   if(TradesOnDay(dayKey) >= InpMaxTradesPerDay)
     {
      g_status = "Bugunku islem hakki doldu";
      g_pendingDir = 0;
      return;
     }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity < InpMinEquity)
     {
      g_status = StringFormat("DURDU: equity %.2f$ < %.2f$", equity, InpMinEquity);
      g_pendingDir = 0;
      return;
     }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;
   double spread = tick.ask - tick.bid;
   if(spread > InpMaxSpread)
     {
      g_status = StringFormat("Spread yuksek (%.2f), bekleniyor", spread);
      return;   // sinyal bekler, spread duserse girilir
     }

   double lots = NormalizeLots(InpLots);
   if(lots <= 0)
     {
      g_status = "Lot ayari gecersiz";
      g_pendingDir = 0;
      return;
     }

   double slDist = MathMax(g_pendingSLDist, MinStopDistance());
   double lossPerPos = LossForDistance(g_pendingDir, lots, g_pendingDir > 0 ? tick.ask : tick.bid, slDist);
   if(lossPerPos > InpMaxLossUSD)
     {
      g_status = StringFormat("Stop cok genis (%.2f$ > %.2f$), islem atlandi", lossPerPos, InpMaxLossUSD);
      WriteLog("SKIP", g_pendingDir, lots, 0, 0, 0, StringFormat("stop %.2f$ > max %.2f$", lossPerPos, InpMaxLossUSD));
      g_pendingDir = 0;
      return;
     }

   // teminat kontrolu
   double margin1 = 0.0;
   ENUM_ORDER_TYPE type = g_pendingDir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = g_pendingDir > 0 ? tick.ask : tick.bid;
   if(OrderCalcMargin(type, _Symbol, lots, price, margin1) &&
      margin1 * InpPositions > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     {
      g_status = "Teminat yetersiz, islem acilamadi";
      g_pendingDir = 0;
      return;
     }

   int opened = 0;
   for(int i = 0; i < InpPositions; i++)
     {
      if(!SymbolInfoTick(_Symbol, tick))
         break;
      bool ok;
      string cmt = StringFormat("XAU TB %d/%d", i + 1, InpPositions);
      if(g_pendingDir > 0)
         ok = trade.Buy(lots, _Symbol, tick.ask, RoundPrice(tick.ask - slDist), 0.0, cmt);
      else
         ok = trade.Sell(lots, _Symbol, tick.bid, RoundPrice(tick.bid + slDist), 0.0, cmt);
      if(!ok)
        {
         PrintFormat("Islem acilamadi: %u %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
         break;
        }
      opened++;
     }

   if(opened > 0)
      g_status = StringFormat("%s acildi: %d x %.2f lot, stop %.2f$ uzakta",
                              g_pendingDir > 0 ? "BUY" : "SELL", opened, lots, slDist);
   else
      g_status = "Islem acilamadi: " + trade.ResultRetcodeDescription();
   g_pendingDir = 0;
  }

//+------------------------------------------------------------------+
void CloseAll(string reason)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsMine())
         continue;
      if(!trade.PositionClose(ticket, (ulong)InpSlippagePoints))
         PrintFormat("Kapatma basarisiz #%I64u: %u", ticket, trade.ResultRetcode());
     }
   g_status = "Pozisyonlar kapatildi: " + reason;
  }

//+------------------------------------------------------------------+
//| Islem kaydi: pozisyon acilis/kapanislarini dosyaya yaz           |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic ||
      HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;

   g_cacheDirty = true;
   long   entry  = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   long   dtype  = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   double vol    = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
   double price  = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                   HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   ENUM_DEAL_REASON why = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);
   int dir = (dtype == DEAL_TYPE_BUY) ? 1 : -1;

   if(entry == DEAL_ENTRY_IN)
      WriteLog("OPEN", dir, vol, price, 0.0, g_atrStop, StringFormat("vol %.2f%% ema %.2f", g_volPct, g_ema));
   else
      WriteLog("CLOSE", -dir, vol, price, profit, 0.0, EnumToString(why));
  }

//+------------------------------------------------------------------+
//| Zaman yardimcilari                                               |
//+------------------------------------------------------------------+
bool IsTester()
  {
   return MQLInfoInteger(MQL_TESTER) != 0 || MQLInfoInteger(MQL_OPTIMIZATION) != 0;
  }

ENUM_TZ_MODE EffectiveTZ()
  {
   if(InpTZMode == TZ_AUTO && IsTester())
      return TZ_NYCLOSE;
   return InpTZMode;
  }

// Sunucu saati ile GMT arasindaki fark (saniye)
long ServerOffsetSeconds()
  {
   ENUM_TZ_MODE mode = EffectiveTZ();
   if(mode == TZ_GMT0)
      return 0;
   if(mode == TZ_CUSTOM)
      return (long)InpCustomGMTOffset * 3600;
   long diff = (long)TimeTradeServer() - (long)TimeGMT();
   return (long)(MathRound(diff / 1800.0) * 1800.0);
  }

// Ayin n'inci pazar gunu (00:00)
datetime NthSunday(int year, int month, int n)
  {
   MqlDateTime t;
   ZeroMemory(t);
   t.year = year;
   t.mon  = month;
   t.day  = 1;
   datetime first = StructToTime(t);
   MqlDateTime f;
   TimeToStruct(first, f);
   int firstSunday = 1 + (7 - f.day_of_week) % 7;
   return (datetime)((long)first + (long)(firstSunday - 1 + 7 * (n - 1)) * 86400);
  }

// ABD yaz saati: Mart 2. pazar 02:00 - Kasim 1. pazar 02:00 (yerel)
bool IsUsDst(datetime utc)
  {
   MqlDateTime t;
   TimeToStruct(utc, t);
   datetime start = (datetime)((long)NthSunday(t.year, 3, 2) + 7 * 3600);
   datetime end   = (datetime)((long)NthSunday(t.year, 11, 1) + 6 * 3600);
   return utc >= start && utc < end;
  }

// Sunucu saatini New York saatine cevir
datetime NYTime(datetime server)
  {
   if(EffectiveTZ() == TZ_NYCLOSE)
      return (datetime)((long)server - 7 * 3600);   // bu brokerlarda sunucu = NY + 7 saat
   datetime utc = (datetime)((long)server - ServerOffsetSeconds());
   return (datetime)((long)utc - (IsUsDst(utc) ? 4 : 5) * 3600);
  }

int HourOf(datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.hour;
  }

// Islem gunu NY 17:00'da degisir
int TradingDayKey(datetime ny)
  {
   return (int)(((long)ny + 7 * 3600) / 86400);
  }

bool IsExitTime()
  {
   int h = HourOf(NYTime(TimeCurrent()));
   return h >= InpExitHourNY && h < 19;
  }

//+------------------------------------------------------------------+
//| Bugun acilan sinyal sayisi (gecmisten, yeniden baslatmaya dayanikli)|
//+------------------------------------------------------------------+
int TradesOnDay(int dayKey)
  {
   datetime now = TimeCurrent();
   if(!HistorySelect(now - 2 * 86400, now + 3600))
      return 0;
   int entries = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic || HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol)
         continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      datetime t = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
      if(TradingDayKey(NYTime(t)) == dayKey)
         entries++;
     }
   return (entries + InpPositions - 1) / InpPositions;
  }

// Panel icin onbellekli sayim (her tikte gecmis taramasin)
int TradesTodayCached()
  {
   datetime now = TimeCurrent();
   int dayKey = TradingDayKey(NYTime(now));
   if(g_cacheDirty || dayKey != g_cacheDay || now - g_cacheTime > 300)
     {
      g_cacheTrades = TradesOnDay(dayKey);
      g_cacheDay    = dayKey;
      g_cacheTime   = now;
      g_cacheDirty  = false;
     }
   return g_cacheTrades;
  }

//+------------------------------------------------------------------+
//| Genel yardimcilar                                                |
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

double OpenProfit()
  {
   double p = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) != 0 && IsMine())
         p += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   return p;
  }

double GetBuf(int handle, int shift)
  {
   double v[];
   if(CopyBuffer(handle, 0, shift, 1, v) != 1)
      return 0.0;
   return v[0];
  }

// Stop mesafesinde kapanirsa kaybedilecek para (pozitif sayi)
double LossForDistance(int dir, double lots, double price, double dist)
  {
   double pnl = 0.0;
   ENUM_ORDER_TYPE type = dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double exitPrice = dir > 0 ? price - dist : price + dist;
   if(OrderCalcProfit(type, _Symbol, lots, price, exitPrice, pnl))
      return MathAbs(pnl);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0 || ts <= 0)
      return 0.0;
   return dist / ts * tv * lots;
  }

double MinStopDistance()
  {
   long   level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return (double)(level + 5) * point;
  }

double RoundPrice(double p)
  {
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts > 0)
      p = MathRound(p / ts) * ts;
   return NormalizeDouble(p, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
  }

double NormalizeLots(double lots)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step > 0)
      lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < minLot)
      lots = minLot;
   if(lots > maxLot)
      lots = maxLot;
   return NormalizeDouble(lots, 2);
  }

//+------------------------------------------------------------------+
//| CSV kaydi                                                        |
//+------------------------------------------------------------------+
void WriteLogHeader()
  {
   if(!InpWriteLog || FileIsExist(LOG_FILE))
      return;
   int h = FileOpen(LOG_FILE, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
      return;
   FileWrite(h, "server_time", "ny_time", "event", "dir", "lots", "price", "profit", "atr_stop", "note");
   FileClose(h);
  }

void WriteLog(string evt, int dir, double lots, double price, double profit, double atr, string note)
  {
   if(!InpWriteLog)
      return;
   int h = FileOpen(LOG_FILE, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ',');
   if(h == INVALID_HANDLE)
      return;
   FileSeek(h, 0, SEEK_END);
   datetime now = TimeCurrent();
   FileWrite(h, TimeToString(now, TIME_DATE | TIME_SECONDS), TimeToString(NYTime(now), TIME_DATE | TIME_MINUTES),
             evt, dir > 0 ? "BUY" : "SELL", DoubleToString(lots, 2), DoubleToString(price, _Digits),
             DoubleToString(profit, 2), DoubleToString(atr, 2), note);
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| Grafik paneli                                                    |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION))
      return;
   datetime ny = NYTime(TimeCurrent());
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   string status = equity < InpMinEquity ? StringFormat("DURDU: equity %.2f$ < %.2f$", equity, InpMinEquity) : g_status;
   string trend = g_ema > 0 ? (g_close > g_ema ? "YUKARI (sadece BUY)" : "ASAGI (sadece SELL)") : "-";
   string vol   = g_volPct >= InpMinVolPercent ? "YETERLI" : "DUSUK (islem yok)";
   Comment(StringFormat(
              "XAU Trend Breakout v1.00\n"
              "Durum: %s\n"
              "NY saati: %s   (kapanis %02d:00)   Bugun islem: %d/%d\n"
              "Trend: %s   Volatilite: %.2f%% %s\n"
              "Son H1 kapanis: %.2f   Kanal: %.2f / %.2f\n"
              "Stop mesafesi: %.2f   Son sinyal: %s\n"
              "Acik pozisyon: %d   K/Z: %.2f$   Equity: %.2f$",
              status, TimeToString(ny, TIME_MINUTES), InpExitHourNY, TradesTodayCached(), InpMaxTradesPerDay,
              trend, g_volPct, vol, g_close, g_hh, g_ll, InpStopATRMult * g_atrStop, g_lastSignal,
              CountPositions(), OpenProfit(), equity));
  }
//+------------------------------------------------------------------+
