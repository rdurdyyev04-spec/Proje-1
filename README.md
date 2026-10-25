# XAUUSD Scalper Basket (MT5 Botu)

M1 grafikte trend yönünü bulur, o yöne **aynı anda 4–5 adet 0.01 lot** işlem açar.
Her işlem **0.30–0.60 $** kârda kapanır; sepetin toplam kârı **2 $** olunca hepsini birden kapatır.
İşlemler en fazla **3 dakika** açık kalır. Zarar hem işlem başına hem de sepet ve gün bazında sınırlıdır.

Dosya: [`MQL5/Experts/XAUUSD_ScalperBasket.mq5`](MQL5/Experts/XAUUSD_ScalperBasket.mq5)

## Nasıl çalışır

1. **Trend (M1):** EMA9 > EMA21 > EMA50, EMA9 yukarı eğimli, son mum yeşil ve EMA9 üstünde kapandıysa → **BUY**.
   Tersi → **SELL**. M5 EMA50 filtresi de aynı yönü onaylamalı.
2. **Oynak saat:** Sadece Londra ve New York açılış saatlerinde işlem açar. M1 ATR düşükse (piyasa sakinse) işlem açmaz.
3. **Sepet:** 5 işlem açar. Kâr hedefleri 0.30 / 0.375 / 0.45 / 0.525 / 0.60 $ olarak sıralanır.
4. **Çıkış:**
   - Her işlemin TP'si ve SL'i broker tarafında duruyor (internet kopsa bile çalışır).
   - Sepet toplamı **+2.00 $** → hepsi kapanır.
   - Sepet toplamı **−3.00 $** → hepsi kapanır.
   - 180 saniyeyi geçen işlem kapanır.
5. **Koruma:** Günlük zarar **6 $**'ı geçerse bot o gün durur. Equity **60 $**'ın altına inerse bot durur.

## Kurulum

1. MT5 → **Dosya → Veri klasörünü aç** → `MQL5/Experts/` içine `XAUUSD_ScalperBasket.mq5` dosyasını kopyala.
2. MT5'te **MetaEditor**'ü aç (F4), dosyayı aç ve **Derle (F7)**. Hata çıkmamalı.
3. **XAUUSD M1** grafiğini aç, Gezgin'den botu grafiğe sürükle.
4. "Algo Trading" (AutoTrading) butonunu aç.
5. Sağ üstte veya grafikte bot durumu yazısını görmelisin.

## Önemli ayarlar

| Ayar | Varsayılan | Açıklama |
|---|---|---|
| `InpLot` | 0.01 | Her işlemin lotu |
| `InpTradesPerBasket` | 5 | Aynı anda kaç işlem |
| `InpTPMinUSD` / `InpTPMaxUSD` | 0.30 / 0.60 | İşlem başı kâr aralığı ($) |
| `InpSLUSD` | 0.80 | İşlem başı maks zarar ($) |
| `InpBasketTPUSD` | 2.00 | Sepet toplam kâr hedefi ($) |
| `InpBasketSLUSD` | 3.00 | Sepet toplam zarar limiti ($) |
| `InpMaxHoldSeconds` | 180 | İşlemi en fazla tutma süresi |
| `InpMaxSpread` | 0.40 | Spread bundan büyükse işlem açmaz |
| `InpMinATR` | 0.60 | Piyasa bundan sakinse işlem açmaz |
| `InpSession1Start/End` | 10–13 | Londra seansı (**sunucu saati**) |
| `InpSession2Start/End` | 15–19 | New York seansı (**sunucu saati**) |
| `InpDailyLossLimit` | 6.00 | Günlük maks zarar ($) |
| `InpDailyProfitTarget` | 0 | Günlük hedefe ulaşınca dur (0 = kapalı) |
| `InpMinEquity` | 60 | Equity bunun altına inerse dur |

### Seans saatleri
Saatler **broker sunucu saatine** göredir (MT5 "Piyasa Gözlemi"ndeki saat).
Çoğu broker GMT+2 (yaz: GMT+3) kullanır. Bu brokerlarda Londra açılışı yaklaşık 10:00, New York açılışı yaklaşık 15:30–16:30'dur.
Senin brokerın farklıysa saatleri ona göre değiştir.

## ⚠️ Mutlaka oku

- **Önce test et:** Strategy Tester'da (Ctrl+R) "Every tick based on real ticks" ile test et. Sonra en az 1–2 hafta **demo hesapta** çalıştır.
- **Spread:** Gold'da spread genelde 0.15–0.40 $ civarındadır. 0.30 $ TP'ye ulaşmak için fiyatın spread + 0.30 $ hareket etmesi gerekir.
  Raw/ECN gibi düşük spreadli hesap çok daha iyi sonuç verir. Spread yüksekse `InpTPMinUSD` değerini artır.
- **Teminat:** 100 $ hesapta 5 × 0.01 gold için genelde **1:500 veya üstü kaldıraç** gerekir. Teminat yetmezse bot işlem sayısını kendisi azaltır.
- **Haberler:** Botta haber filtresi yok. NFP, CPI ve FOMC günlerinde haberden 15 dk önce ve 15 dk sonra botu kapat.
- **Beklenti:** Bu ayarlarla kazançlı bir günde birkaç dolar kâr beklenebilir. Hiçbir bot günde 20–50 $'ı garanti edemez. Lotu büyütmek kârı artırır ama hesabı yakma riskini de aynı oranda artırır.
