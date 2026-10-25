"""XAU_TrendBreakout.mq5 botunun Python karsiligi: ayni kurallar, dakikalik veride test.

Kurallar (H1 = UTC saat basinda kapanan 1 saatlik mum):
  BUY : H1 kapanis > onceki 10 H1 mumun en yuksegi  ve  kapanis > H1 EMA(1150)
  SELL: H1 kapanis < onceki 10 H1 mumun en dusugu   ve  kapanis < H1 EMA(1150)
  Filtre: H1 ATR(120) / fiyat > %0.30 (piyasa hareketli)
  Stop: 0.5 x H1 ATR(14); stop > 10$ (0.01 lot) ise islem yok; kar hedefi yok
  Cikis: New York 16:00; gunde en fazla 1 islem; giris yok 16:00-19:00 NY
Maliyet: spread 0.30$ + her market emirde 0.05$ kayma.  P/L: 0.01 lot icin $.
Kullanim: ./fetch_data.sh && python3 prepare_data.py && python3 backtest_final.py
"""
import os, sys
import numpy as np, pandas as pd
from engine import run_bt2

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data')
SPREAD, SLIP = 0.30, 0.05

def h1_features(df):
    key = df.utc.dt.floor('1h')
    last = np.r_[key.values[1:] != key.values[:-1], True]          # saatin son M1 mumu
    g = df.groupby(key)
    H = pd.DataFrame({'h': g.high.max(), 'l': g.low.min(), 'c': g.close.last()})
    pc = H.c.shift(1)
    H['tr'] = np.maximum(H.h, pc) - np.minimum(H.l, pc)
    H['atr14'] = H.tr.rolling(14, min_periods=5).mean()
    H['atr120'] = H.tr.rolling(120, min_periods=60).mean()
    H['ema'] = H.c.ewm(span=1150, adjust=False).mean()
    H['hh'] = H.h.rolling(10).max().shift(1)
    H['ll'] = H.l.rolling(10).min().shift(1)
    idx = H.index.get_indexer(key)
    out = {c: np.where(last, H[c].values[idx], np.nan) for c in ['c', 'atr14', 'atr120', 'ema', 'hh', 'll']}
    out['last'] = last
    return out

def backtest(df, spread=SPREAD, slip=SLIP, max_stop_usd=10.0, stop_mult=0.5, min_vol=0.003):
    n = len(df)
    f = h1_features(df)
    ny = df.ny_min.values
    ok = f['last'] & (df.wday.values < 5) & (f['atr120'] / df.close.values > min_vol)
    ok &= np.nan_to_num(stop_mult * f['atr14'], nan=1e9) <= max_stop_usd
    sig = np.zeros(n, np.int8)
    sig[ok & (f['c'] > f['hh']) & (f['c'] > f['ema'])] = 1
    sig[ok & (f['c'] < f['ll']) & (f['c'] < f['ema'])] = -1
    sl = np.nan_to_num(stop_mult * f['atr14'], nan=99.0)
    ff = (ny >= 16 * 60) & (ny < 19 * 60)                           # 16:00 NY kapanis, 19:00'a kadar giris yok
    te, tx, td, tp, tr = run_bt2(df.open.values, df.high.values, df.low.values, df.close.values, sig, sl, sl,
                                 np.array([1e6]), np.zeros(n), 1.0, 0.0, 10**9, spread, slip,
                                 df.day_id.values, ff, 1e9, 99, 1)
    t = pd.DataFrame({'entry_utc': df.utc.values[te], 'exit_utc': df.utc.values[tx], 'dir': td, 'pnl': tp})
    t['year'] = df.year.values[te]
    t['day'] = df.tday.values[te]
    return t

def report(t, df):
    w = t.pnl[t.pnl > 0].sum(); l = -t.pnl[t.pnl < 0].sum()
    eq = t.pnl.cumsum().values
    dd = (np.maximum.accumulate(np.r_[0, eq]) - np.r_[0, eq]).max()
    print(f"Toplam: {len(t)} islem, kazanma %{100*(t.pnl>0).mean():.0f}, ort {t.pnl.mean():.2f}$, "
          f"kar faktoru {w/l:.2f}, net {t.pnl.sum():.0f}$, max dusus {dd:.0f}$  (0.01 lot)")
    for y, x in t.groupby('year'):
        days = df[df.year == y].tday.nunique()
        e = x.pnl.cumsum().values
        ydd = (np.maximum.accumulate(np.r_[0, e]) - np.r_[0, e]).max()
        print(f"  {y}: {len(x):3d} islem  net {x.pnl.sum():7.0f}$  gunluk ort {x.pnl.sum()/days:5.2f}$  "
              f"kazanma %{100*(x.pnl>0).mean():.0f}  ort kazanc {x.pnl[x.pnl>0].mean():5.1f}$  "
              f"ort kayip {x.pnl[x.pnl<=0].mean():5.1f}$  max dusus {ydd:.0f}$")

if __name__ == '__main__':
    df = pd.read_pickle(os.path.join(D, 'xau_all.pkl'))
    t = backtest(df)
    report(t, df)
    for sp, sl_ in [(0.5, 0.1), (0.7, 0.2)]:
        print(f"\nStres testi: spread {sp}$, kayma {sl_}$")
        report(backtest(df, spread=sp, slip=sl_), df)
    if len(sys.argv) > 1:
        t.to_csv(sys.argv[1], index=False)
