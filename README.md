# XAU Trend Breakout (MT5 altın botu)

Bot: [`MQL5/Experts/XAU_TrendBreakout.mq5`](MQL5/Experts/XAU_TrendBreakout.mq5)
Araştırma ve test sonuçları: [`research/SONUCLAR.md`](research/SONUCLAR.md)

## Bot ne yapar?

1. Her saat başı, yeni kapanan **1 saatlik (H1) mumu** inceler.
2. Kapanış **son 10 saatin en yükseğini** geçtiyse ve uzun vadeli trend yukarıysa **BUY** açar. **En düşüğünün** altına indiyse ve trend aşağıysa **SELL** açar.
3. Sadece **piyasa hareketliyken** işlem açar. Piyasa sakinse beklemeye devam eder.
4. **Stop** her işlemde var: son saatlerin ortalama hareketinin yarısı kadar uzakta. Bu, 0.01 lot için genelde 5–10 $ zarar demek. Stop 10 $'dan geniş olacaksa işlem açılmaz.
5. **Kâr hedefi yok.** Kazanan işlem trend boyunca açık kalır ve **New York saatiyle 16:00'da** kapanır.
6. **Günde en fazla 1 işlem** açar.

## Neden 1–3 dakikalık küçük işlemler değil?

Gerçek altın verisinde (2020–2026, yaklaşık 2 milyon dakikalık mum) **yüzlerce ayarı** test ettim.

- 1–3 dakikalık işlemlerin **hepsi zarar etti.** İşlem başına spread ve kayma yaklaşık 0.40 $ tutuyor. Dakikalık hareketlerden gelen ortalama kâr bunu karşılamıyor.
- Kârlı çıkan tek yapı: **büyük trend günlerini yakalayıp kazananı gün sonuna kadar taşımak.**

Ayrıntılar: [`research/SONUCLAR.md`](research/SONUCLAR.md)

## Test sonuçları (0.01 lot, spread 0.30 $ + kayma dahil)

| Dönem | İşlem | Net kâr | Günlük ortalama | Kazanma oranı | Max düşüş |
|---|---|---|---|---|---|
| 2020–2025 | 234 | +123 $ | ~0.1 $ | %19 | 72 $ |
| 2026 (Mart–Eylül) | 68 | **+379 $** | **~2.9 $** | %21 | 80 $ |

- 100 $ ile başlayan test hesabı, başlangıç tarihine göre en kötü noktasında **33–76 $**'a düştü ve sonunda **480–600 $**'a çıktı.
- İşlemlerin yaklaşık **5'te 4'ü küçük zararla** kapanıyor (0.01 lot için ortalama −8 $). Kârı ayda 1–3 büyük gün getiriyor (+50 $ ile +140 $ arası). **Üst üste 10 zarar normal.**
- Kâr, piyasa hareketliyken geliyor (2026 gibi). Sakin dönemlerde bot az işlem açar ve başabaşa yakın kalır.
- Bunlar geçmiş veri sonuçları; gelecek için garanti değil.

## Kurulum

1. MT5 masaüstü → **Dosya → Veri Klasörünü Aç** → `MQL5` → `Experts` klasörüne `XAU_TrendBreakout.mq5` dosyasını kopyala.
2. MT5'te **F4** ile MetaEditor'ü aç, dosyayı aç ve **F7** ile derle. Alttaki "Hatalar" sekmesinde `0 errors` görünmeli. Hata çıkarsa ekran görüntüsünü gönder.
3. **XAUUSD** grafiğini aç (zaman dilimi önemli değil, H1 öneririm). Gezgin'den botu grafiğe sürükle ve "Algo Trading"e izin ver.
4. Grafiğin sol üstünde bot paneli görünür: durum, NY saati, trend, volatilite, son sinyal.

## Önce Strategy Tester (5 dakika sürer)

**Görünüm → Strateji Test Cihazı** (Ctrl+R):

- **Uzman:** XAU_TrendBreakout
- **Sembol:** altın sembolün (örn. `XAUUSD.s`), **Periyot:** H1
- **Tarih:** 2025.10.01 – bugün. Bot ilk ~2.5 ayı hesaplama için kullanır, işlemler sonra başlar.
- **Modelleme:** "Gerçek ticklere dayalı her tick"
- **Başlangıç bakiyesi:** 100 USD, **kaldıraç:** kendi hesabındaki
- **Girdiler → Broker saat dilimi:** Brokerın GMT+0 ise `GMT+0` seç, değilse `Otomatik` bırak.

Bitince **Backtest** ve **Grafik** sekmelerinin ekran görüntüsünü bana gönder.

## Sonra demo

- Botu demo hesapta en az **3–4 hafta** çalıştır. Bilgisayar ve MT5 açık kalmalı.
- **Bot her gün işlem açmaz.** Sadece şartlar oluşunca girer, işlem olmayan günler normaldir.
- Bir sorun görürsen şunların ekran görüntüsünü gönder:
  - grafik paneli (sol üstteki yazılar)
  - **Araç Kutusu → Geçmiş** sekmesi
  - **Araç Kutusu → Uzmanlar** sekmesi (hata mesajları burada çıkar)
- Bot her işlemi `MQL5/Files/XAU_TrendBreakout_log.csv` dosyasına da yazar.

## Ayarlar

| Ayar | Varsayılan | Açıklama |
|---|---|---|
| Lot | 0.01 | Pozisyon başı lot |
| Sinyal başına pozisyon | 1 | 100 $ hesapta 1'de bırak |
| Pozisyon başı max zarar | 10 $ | Stop daha genişse işlem açılmaz |
| Min equity | 40 $ | Hesap bunun altına inerse bot yeni işlem açmaz |
| Günlük max işlem | 1 | Testte en iyi sonuç 1 ile alındı |
| Kanal | 10 | Kaç saatlik tepe/dip kırılmalı |
| Trend EMA | 1150 | H1 EMA, yaklaşık 50 günlük trend |
| Min volatilite | %0.30 | Piyasa bundan sakinse işlem açılmaz |
| Stop | 0.5 × ATR(14) | H1 ortalama hareketin yarısı |
| Kapanış saati | 16 | New York saati |
| Max spread | 0.60 $ | Spread yüksekse 10 dk boyunca düşmesini bekler |

Stratejiyi değiştiren ayarlara (kanal, EMA, volatilite, stop) testten önce dokunma. Önce varsayılan ayarlarla sonuç görelim.
