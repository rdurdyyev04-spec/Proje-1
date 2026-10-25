# Araştırma sonuçları (XAUUSD, 2020–2026)

## Veri

- **2020-01 → 2025-10:** dakikalık altın verisi (parshant65-lang/Gold-XAUUSD-1m-2020-2025-Historical-Data). Broker sunucu saatindeydi (GMT+2/+3). NFP açıklamaları 08:30 New York'a denk gelecek şekilde UTC'ye çevrildi.
- **2026-03-26 → 2026-09-25:** dakikalık altın verisi (getdata-finance/xauusd-1m-ohlcv-metals-historical-data), UTC.
- Toplam yaklaşık **2.1 milyon** dakikalık mum. 2025'te bazı aylar eksik.

## Maliyet varsayımı

Her işlemde **0.30 $ spread** (kullanıcının brokerında görülen değer) ve her market emrinde **0.05 $ kayma**. Toplam maliyet 0.01 lot için işlem başına yaklaşık **0.40 $**.

Bir mumda hem stop hem hedef varsa her zaman **önce stop** sayıldı (temkinli varsayım).

## Denenen strateji aileleri

| Strateji | Sonuç (kâr faktörü, >1 = kârlı) | Yorum |
|---|---|---|
| M1 momentum ("trend nereye giderse hemen o yöne gir") | Sert hareketten sonraki 5 dk ortalaması **negatif** | Fiyat sert hareketten sonra biraz geri dönüyor; spread üstüne zarar |
| M1 ortalamaya dönüş (EMA'dan uzaklaşınca ters işlem) | 192 ayar, en iyisi **0.87** | Bütün yıllarda zarar |
| Seans açılış kırılımı (Londra, NY, 08:30 haber) | 54 ayar, **0.65–0.93** | Altında açılış kırılımları çoğu zaman başarısız |
| Asya seansı yükseliş eğilimi | ≈ **1.0** | Görünen etki, gece açılışındaki geniş spread'in veri izi çıktı |
| Önceki gün tepe/dip tuzağı | En iyisi **1.17**, yıllara göre karışık | Güvenilir değil |
| Haber sonrası momentum (08:30 / 10:00 NY) | **1.1–1.8** | 6 yılda sadece 60–160 işlem; örnek çok küçük |
| H1 trend + M1 geri çekilme girişi (dar stop) | **0.80–0.85** | Dar stop dakikalık gürültüde sürekli patlıyor |
| H1 trend kırılımı, sabit kâr hedefi / iz süren stop ile | **0.86–1.05** | Kârı erken almak, kârı getiren büyük trend günlerini kesiyor |
| **H1 kırılım + uzun trend + volatilite filtresi, hedefsiz, NY 16:00 çıkış (seçilen)** | **1.43**, 7 yılın 7'si kârlı | Bot bu stratejiyi kullanıyor |

### Temel sonuç

1–3 dakikalık küçük kârlı işlemlerin ortalama getirisi, işlem başına yaklaşık 0.40 $'lık maliyetten küçük. Bu yüzden işlem sayısı arttıkça zarar da artıyor.

Kâr eden tek yapı şu: piyasa hareketliyken, uzun vadeli trend yönünde saatlik kırılıma girmek ve kazananı gün sonuna kadar taşımak.

## Seçilen strateji: test sonuçları (0.01 lot)

`python3 backtest_final.py` çıktısı:

| Yıl | İşlem | Net | Günlük ort. | Kazanma | Ort. kazanç | Ort. kayıp | Max düşüş |
|---|---|---|---|---|---|---|---|
| 2020 | 88 | +24 $ | 0.09 $ | %18 | 17.4 $ | −3.5 $ | 69 $ |
| 2021 | 24 | +26 $ | 0.10 $ | %21 | 15.8 $ | −2.8 $ | 24 $ |
| 2022 | 41 | +2 $ | 0.01 $ | %22 | 10.8 $ | −3.0 $ | 41 $ |
| 2023 | 10 | +34 $ | 0.13 $ | %10 | 60.3 $ | −2.9 $ | 18 $ |
| 2024 | 36 | +31 $ | 0.12 $ | %19 | 21.2 $ | −4.0 $ | 49 $ |
| 2025* | 35 | +5 $ | 0.05 $ | %17 | 28.9 $ | −5.8 $ | 72 $ |
| 2026** | 68 | **+379 $** | **2.87 $** | %21 | 58.8 $ | −8.2 $ | 80 $ |

\* 2025'te veri eksik (yaklaşık 5 ay). \*\* 2026: 26 Mart – 25 Eylül.

2026 aylık sonuçları: Nisan +5, Mayıs +47, Haziran +137, Temmuz −14, Ağustos +201, Eylül +2.

Kârın büyük kısmı ayda 1–3 büyük trend gününden geliyor. Diğer günler çoğunlukla küçük zararla geçiyor.

**Stres testi:** spread 0.50 $ + kayma 0.10 $ ile kâr faktörü 1.33. Spread 0.70 $ + kayma 0.20 $ ile 1.16. Maliyetler artınca bile strateji kârda kalıyor.

**100 $ hesap simülasyonu (0.01 lot):**

| Başlangıç | Bitiş bakiyesi | En düşük bakiye |
|---|---|---|
| 2020-01 | 601 $ | 33 $ |
| 2026-03 | 479 $ | 76 $ |
| 2025-01 | 484 $ | 52 $ |
| 2024-01 | 515 $ | 69 $ |

## Dürüst uyarılar

- İstatistiksel güç sınırlı. Kârın çoğu 2026'nın yüksek volatilitesinden geliyor. Sakin yıllarda strateji başabaşa yakın.
- Stop sınırı (10 $) ve volatilite eşiği, test edilen birkaç değer arasından seçildi. Gelecekte sonuçlar daha kötü olabilir.
- Kazanma oranı yaklaşık %20. Üst üste 10–18 zarar normal. Bot buna göre değerlendirilmeli.
- Bunlar geçmiş veri sonuçları; gelecek için garanti değil.

## Tekrar üretmek için

```bash
cd research
./fetch_data.sh            # ~175 MB veri indirir
pip install numpy pandas numba
python3 prepare_data.py
python3 backtest_final.py
```
