"""M1 bar backtest motoru (numba). Fiyatlar bid OHLC; ask = bid + spread.
Sinyal i. mumun kapanisinda -> giris i+1. mumun acilisinda. Ayni mumda SL ve TP varsa once SL (temkinli).
Per-trade arrays for SL, TP(parts), BE trigger, trailing (ATR-based). One position (multi-part) at a time.
P/L in $ per 1 oz per part (0.01 lot each)."""
import numpy as np
from numba import njit

@njit(cache=True)
def run_bt2(o, h, l, c, sig, sl_d, tp_d, tp_mult, trail_d, trail_start_r, be_r, max_bars, spread, slip,
            day_id, force_flat, daily_stop, max_losses_day, max_trades_day):
    n = o.shape[0]; nparts = tp_mult.shape[0]
    cap = n // 2 + 10
    t_entry = np.empty(cap, np.int64); t_exit = np.empty(cap, np.int64)
    t_dir = np.empty(cap, np.int8); t_pnl = np.empty(cap, np.float64); t_risk = np.empty(cap, np.float64)
    nt = 0
    in_pos = False
    d = 0; entry = 0.0; sl = 0.0; ei = 0; R = 0.0; tdist = 0.0
    tp = np.zeros(nparts); open_part = np.zeros(nparts, np.bool_)
    pnl_acc = 0.0; best = 0.0
    cur_day = -1; day_pnl = 0.0; day_losses = 0; day_trades = 0
    for i in range(1, n):
        if day_id[i] != cur_day:
            cur_day = day_id[i]; day_pnl = 0.0; day_losses = 0; day_trades = 0
        if (not in_pos) and sig[i-1] != 0 and (not force_flat[i]) and day_id[i-1] == day_id[i] \
           and day_pnl > -daily_stop and day_losses < max_losses_day and day_trades < max_trades_day:
            d = sig[i-1]
            entry = o[i] + spread + slip if d > 0 else o[i] - slip
            R = sl_d[i-1]; sl = entry - d * R; tdist = trail_d[i-1]
            for k in range(nparts):
                tp[k] = entry + d * tp_d[i-1] * tp_mult[k]; open_part[k] = True
            in_pos = True; ei = i; pnl_acc = 0.0; best = entry; day_trades += 1
        if not in_pos:
            continue
        if d > 0:
            hi = h[i]; lo = l[i]; op = o[i]
        else:
            hi = h[i] + spread; lo = l[i] + spread; op = o[i] + spread
        done = False
        if (lo <= sl) if d > 0 else (hi >= sl):
            if d > 0:
                px = (min(sl, op) if i > ei else sl) - slip
            else:
                px = (max(sl, op) if i > ei else sl) + slip
            for k in range(nparts):
                if open_part[k]:
                    pnl_acc += d * (px - entry); open_part[k] = False
            done = True
        else:
            for k in range(nparts):
                if open_part[k] and ((hi >= tp[k]) if d > 0 else (lo <= tp[k])):
                    pnl_acc += d * (tp[k] - entry); open_part[k] = False
            anyopen = False
            for k in range(nparts):
                if open_part[k]: anyopen = True
            if not anyopen:
                done = True
            else:
                # update best excursion and stops (effective from next bar)
                if d > 0:
                    if hi > best: best = hi
                else:
                    if lo < best or best == entry: best = min(best, lo)
                fav = d * (best - entry)
                if be_r > 0 and fav >= be_r * R:
                    nsl = entry + d * 0.1
                    if (d > 0 and nsl > sl) or (d < 0 and nsl < sl): sl = nsl
                if tdist > 0 and fav >= trail_start_r * R:
                    nsl = best - d * tdist
                    if (d > 0 and nsl > sl) or (d < 0 and nsl < sl): sl = nsl
                if (i - ei + 1) >= max_bars or force_flat[i] or (i + 1 < n and day_id[i+1] != day_id[i]):
                    px = (c[i] - slip) if d > 0 else (c[i] + spread + slip)
                    for k in range(nparts):
                        if open_part[k]:
                            pnl_acc += d * (px - entry); open_part[k] = False
                    done = True
        if done:
            t_entry[nt] = ei; t_exit[nt] = i; t_dir[nt] = d; t_pnl[nt] = pnl_acc; t_risk[nt] = R * nparts
            nt += 1; in_pos = False; day_pnl += pnl_acc
            if pnl_acc < 0: day_losses += 1
    return t_entry[:nt], t_exit[:nt], t_dir[:nt], t_pnl[:nt], t_risk[:nt]
