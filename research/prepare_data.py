"""Veriyi tek dosyada birlestirir: research/data/xau_all.pkl

- 2026 seti (getdata-finance) UTC zaman damgali.
- 2020-2025 seti (parshant) broker sunucu saatinde (GMT+2/+3 = New York + 7 saat);
  NFP aciklamalarinin 08:30 NY'ye denk gelmesiyle dogrulandi ve UTC'ye cevrildi.
"""
import glob, os
import numpy as np, pandas as pd

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data')

def main():
    files = sorted(glob.glob(os.path.join(D, 'parshant', 'XAUUSD', '1m', '*', '*', '*.csv')))
    b = pd.concat([pd.read_csv(f) for f in files], ignore_index=True)
    srv = pd.to_datetime(b['datetime_utc'])                       # aslinda sunucu saati
    ny = (srv - pd.Timedelta(hours=7)).dt.tz_localize('America/New_York', ambiguous='NaT', nonexistent='NaT')
    b['utc'] = ny.dt.tz_convert('UTC').dt.tz_localize(None)
    b = b.dropna(subset=['utc'])

    a = pd.read_csv(os.path.join(D, 'gdf', 'XAUUSD_1m.csv'))
    a['utc'] = pd.to_datetime(a['datetime'], utc=True).dt.tz_localize(None)

    cols = ['utc', 'open', 'high', 'low', 'close', 'volume']
    df = pd.concat([b[cols], a[cols]], ignore_index=True).sort_values('utc').drop_duplicates('utc').reset_index(drop=True)
    u = df.utc.dt.tz_localize('UTC')
    nyt = u.dt.tz_convert('America/New_York')
    df['ny_min'] = (nyt.dt.hour * 60 + nyt.dt.minute).astype(np.int32)
    srv = (nyt + pd.Timedelta(hours=7)).dt.tz_localize(None)      # islem gunu NY 17:00'da degisir
    df['tday'] = srv.dt.normalize()
    df['wday'] = srv.dt.dayofweek.astype(np.int8)
    df['year'] = df.utc.dt.year.astype(np.int16)
    df['day_id'] = pd.factorize(df.tday)[0].astype(np.int64)
    df.to_pickle(os.path.join(D, 'xau_all.pkl'))
    print(len(df), 'bar', df.utc.min(), '->', df.utc.max())

if __name__ == '__main__':
    main()
