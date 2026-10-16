# Extraction pipeline for report_ne39_160s_reclose_en_cpp.tex
# Source of truth: C++ run stage2_smoke_ne39_008_gfm160s_golden (read-only)
# plus the canonical case.json the engine consumed (read-only).
# Outputs: CSV data files for the LaTeX report tables/figures (figures/ne39_160s_reclose_cpp/)
#          + extract_summary.json with every number quoted in the report.
# Run: py -3.12 -I extract_ne39_cpp_report_data.py
import json, struct, math, csv, os, sys
import numpy as np

RUN = r'D:/4-year-project/GridFormLab-port/runs/stage2_smoke_ne39_008_gfm160s_golden'
CASE = r'D:/4-year-project/GridFormLab-experiment/output/diagnostics/canonical_parity_20261014/ne39_reclose_baseline/case.json'
OUT_CSV = r'D:/4-year-project/GridFormLab/docs/source/figures/ne39_160s_reclose_cpp'
OUT_SUM = r'D:/4-year-project/GridFormLab/docs/source/tools/rep160_cpp/extract_summary.json'
REF_CSV = r'D:/4-year-project/GridFormLab/docs/source/figures/ne39_160s_reclose'  # shared input CSVs (format reference)

os.makedirs(OUT_CSV, exist_ok=True)

def h(x):
    return struct.unpack('>d', struct.pack('>Q', int(x, 16)))[0]

S = {}  # summary

# ---------------------------------------------------------------- manifest
man = json.load(open(os.path.join(RUN, 'manifest.json')))
S['manifest'] = {
    'engine': man['engine'], 'engine_metadata': man['engine_metadata'],
    'run_kind': man['run_kind'],
    'horizon_s': h(man['horizon_s']), 'h_s': h(man['h_s']),
    'elapsed_wall_s': h(man['elapsed_wall_s']),
    'counters': man['counters'], 'format_version': man['format_version'],
}
ev = json.load(open(os.path.join(RUN, 'events_stage2.json')))
S['events'] = [{'type': e['type'], 't_s': h(e['t']), 'applied': e['applied'],
                'device_index': e['device_index']} for e in ev['events']]
gr = json.load(open(os.path.join(RUN, 'guard_reclose.json')))
S['guard'] = gr
T_CLOSE = gr['closes'][0]['t']          # 100.499 s
S['t_close'] = T_CLOSE

# ---------------------------------------------------------------- case
cj = json.load(open(CASE))
def colmajor(flat, nrows, ncols):
    cols = [flat[c*nrows:(c+1)*nrows] for c in range(ncols)]
    return np.array(cols).T          # rows x ncols

bd = colmajor([h(x) for x in cj['pf_case']['bus_data']], 39, 12)
ld = colmajor([h(x) for x in cj['pf_case']['line_data']], 46, 7)
bus_id = bd[:, 0].astype(int)
V_spec, A_spec_deg = bd[:, 2].copy(), bd[:, 3].copy()
Pg_case, Qg_case = bd[:, 4].copy(), bd[:, 5].copy()
Pd, Qd = bd[:, 6].copy(), bd[:, 7].copy()
Gs, Bs = bd[:, 8].copy(), bd[:, 9].copy()
fbus = ld[:, 0].astype(int); tbus = ld[:, 1].astype(int)
r_pu, x_pu, b_half = ld[:, 2].copy(), ld[:, 3].copy(), ld[:, 4].copy()
tap, phi = ld[:, 5].copy(), ld[:, 6].copy()
assert np.allclose(phi, 0.0)          # phase-shifter angles all zero; taps real

# verify the shared input CSVs against the canonical case
bus_ref = list(csv.DictReader(open(os.path.join(REF_CSV, 'case_bus_data.csv'))))
ok_bus = all(abs(float(row['Pd_pu']) - Pd[i]) < 5e-4 and abs(float(row['Qd_pu']) - Qd[i]) < 5e-4
             and abs(float(row['Bs_pu']) - Bs[i]) < 5e-4 for i, row in enumerate(bus_ref))
ln_ref = list(csv.DictReader(open(os.path.join(REF_CSV, 'case_line_data.csv'))))
ok_line = all(abs(float(row['r_pu']) - r_pu[i]) < 5e-5 and abs(float(row['x_pu']) - x_pu[i]) < 5e-5
              and abs(float(row['b_pu']) - 2*b_half[i]) < 5e-5 for i, row in enumerate(ln_ref))
S['case_verify'] = {'case_bus_data_csv_matches_case_json': bool(ok_bus),
                    'case_line_data_csv_matches_case_json': bool(ok_line),
                    'branch_count': 46, 'bus_count': 39,
                    'branches_with_offnominal_tap': int(np.sum(tap != 1.0)),
                    'tap_range': [float(tap[tap != 1.0].min()), float(tap[tap != 1.0].max())]}
print('case verify bus/line:', ok_bus, ok_line)

DEV_BUSES = [31, 30, 32, 33, 34, 35, 36, 37, 38, 39]   # SG31 then IBR30,32..39
DEV_IDS = ['SG31', 'IBR30', 'IBR32', 'IBR33', 'IBR34', 'IBR35', 'IBR36', 'IBR37', 'IBR38', 'IBR39']
S_RATING = {'IBR30': 44.0, 'IBR32': 44.4, 'IBR33': 36.7, 'IBR34': 11.8, 'IBR35': 43.5,
            'IBR36': 35.3, 'IBR37': 18.2, 'IBR38': 35.3, 'IBR39': 33.1}   # pu on 100 MVA (= console Mbase/100)
S['ibr_rating_pu'] = S_RATING

# ---------------------------------------------------------------- trajectory
hdr = open(os.path.join(RUN, 'traj_stage2.csv')).readline().strip().split(',')
col = {name: i for i, name in enumerate(hdr)}
use = [col['t'], col['delta_SG31'], col['omega_SG31']]
use += [col[f'bus_voltage_bus{b}'] for b in range(1, 40)]
use += [col[f'bus_angle_bus{b}'] for b in range(1, 40)]
idq = []
for d in DEV_IDS[1:]:
    idq += [col[f'id_{d}'], col[f'iq_{d}']]
use += idq
use = sorted(use)
inv = {c: k for k, c in enumerate(use)}
print('loading traj, %d columns ...' % len(use))
A = np.loadtxt(os.path.join(RUN, 'traj_stage2.csv'), delimiter=',', skiprows=1,
               usecols=use, dtype=np.float64)
print('traj shape', A.shape)
t = A[:, inv[col['t']]]
delta = A[:, inv[col['delta_SG31']]]
omega = A[:, inv[col['omega_SG31']]]
V = np.stack([A[:, inv[col[f'bus_voltage_bus{b}']]] for b in range(1, 40)], axis=1)   # N x 39
ANG = np.stack([A[:, inv[col[f'bus_angle_bus{b}']]] for b in range(1, 40)], axis=1)   # N x 39
ID = np.stack([A[:, inv[col[f'id_{d}']]] for d in DEV_IDS[1:]], axis=1)               # N x 9
IQ = np.stack([A[:, inv[col[f'iq_{d}']]] for d in DEV_IDS[1:]], axis=1)
S['traj'] = {'rows': int(A.shape[0]), 'cols_total': len(hdr), 't0': float(t[0]),
             't_end': float(t[-1]), 'sample_idx_semantics': man['sample_idx_semantics']}

# angle unit: C++ stores rad (manifest units_map); detect and convert
ang_unit_rad = float(np.max(np.abs(ANG[0]))) < 7.0
ANGdeg = np.degrees(ANG) if ang_unit_rad else ANG.copy()
S['traj']['bus_angle_unit'] = 'rad (converted to degrees for the report)' if ang_unit_rad else 'deg'

i0 = 0   # equilibrium row = t = 0
V0 = V[i0]; A0 = ANGdeg[i0]

# ---------------------------------------------------------- network & fold
Ypre = np.zeros((39, 39), dtype=complex)
def ystamp(Y, i, j, ys, bh, a=1.0):
    Y[i, i] += ys / (a * np.conj(a)) + 1j * bh
    Y[j, j] += ys + 1j * bh
    Y[i, j] -= ys / np.conj(a)
    Y[j, i] -= ys / a
for k in range(46):
    i, j = fbus[k] - 1, tbus[k] - 1
    ys = 1.0 / complex(r_pu[k], x_pu[k])
    ystamp(Ypre, i, j, ys, b_half[k], tap[k])   # a = tau (13 branches carry taps 0.993..1.07)
for b in range(39):
    Ypre[b, b] += complex(Gs[b], Bs[b])
Sload = Pd + 1j * Qd
V0c = V0 * np.exp(1j * np.radians(A0))
Yload = np.where(np.abs(V0c) > 0, np.conj(Sload) / np.abs(V0c)**2, 0.0)

# per-sample device injection by bus KCL:  I_dev = (Ypre V) + Yload*V   (load fold constant)
Vc = V * np.exp(1j * ANG if ang_unit_rad else 1j * np.radians(ANG))
Iinj = Vc @ Ypre.T + Vc * Yload[None, :]
Sbus = Vc * np.conj(Iinj)                     # N x 39 complex, device = only source at its bus
P_dev = np.stack([Sbus[:, b-1].real for b in DEV_BUSES], axis=1)   # N x 10 pu
Q_dev = np.stack([Sbus[:, b-1].imag for b in DEV_BUSES], axis=1)

# cross-check 1: aligned-frame identity from raw id/iq at t = 0  (v_q = 0 in the locked frame)
kappa = {d: 1.0 / S_RATING[d] for d in DEV_IDS[1:]}   # S_base/M_base
dev_bus_idx = {d: b - 1 for d, b in zip(DEV_IDS[1:], DEV_BUSES[1:])}
chk = {}
for k, d in enumerate(DEV_IDS[1:]):
    bi = dev_bus_idx[d]
    P_al = V0[bi] * ID[i0, k] / kappa[d]
    Q_al = -V0[bi] * IQ[i0, k] / kappa[d]
    chk[d] = {'P_kcl': float(P_dev[i0, k+1]), 'P_aligned': float(P_al),
              'Q_kcl': float(Q_dev[i0, k+1]), 'Q_aligned': float(Q_al)}
S['equilibrium_crosscheck_t0'] = {
    'devices': chk,
    'max_abs_P_diff_pu': float(max(abs(c['P_kcl'] - c['P_aligned']) for c in chk.values())),
    'max_abs_Q_diff_pu': float(max(abs(c['Q_kcl'] - c['Q_aligned']) for c in chk.values())),
    'SG31_P_pu': float(P_dev[i0, 0]), 'SG31_Q_pu': float(Q_dev[i0, 0]),
    'case_Pg_bus31': float(Pg_case[30]), 'case_Qg_bus31': float(Qg_case[30]),
}

# cross-check 2: aligned identity over the whole run vs KCL series (disclosure number)
dev_cols = [b - 1 for b in DEV_BUSES[1:]]
P_al_all = V[:, dev_cols] * ID / np.array([kappa[d] for d in DEV_IDS[1:]])[None, :]
Q_al_all = -V[:, dev_cols] * IQ / np.array([kappa[d] for d in DEV_IDS[1:]])[None, :]
S['series_crosscheck'] = {
    'max_abs_P_diff_pu': float(np.max(np.abs(P_al_all - P_dev[:, 1:]))),
    'max_abs_Q_diff_pu': float(np.max(np.abs(Q_al_all - Q_dev[:, 1:]))),
    'rms_P_diff_pu': float(np.sqrt(np.mean((P_al_all - P_dev[:, 1:]) ** 2))),
}

# close instant detection from SG31 KCL injection (raw evidence)
sgP = P_dev[:, 0]
pre = np.where((t > 60.5) & (t < 99.0), np.abs(sgP), np.nan)
S['sg_inject_island_max_pu'] = float(np.nanmax(pre))
after = np.where(t > T_CLOSE + 0.5, np.abs(sgP), np.nan)
S['sg_inject_post_min_pu'] = float(np.nanmin(after))
jump = np.where((t > 99.5) & (t < 101.5) & (np.abs(sgP) > 0.5))[0]
S['t_close_detected_first_sample_s'] = float(t[jump[0]]) if len(jump) else None

# ---------------------------------------------------------------- equilibrium tables
Vpu0 = V0.copy()
rows = '\n'.join(f'{bus_id[b]},{Vpu0[b]:.15g},{A0[b]:.15g}' for b in range(39))
open(os.path.join(OUT_CSV, 'normal_pf_bus.csv'), 'w').write(
    'bus_id,V_pu,angle_deg\n' + rows + '\n')

Pgen0 = np.zeros(39); Qgen0 = np.zeros(39)
for k, b in enumerate(DEV_BUSES):
    Pgen0[b-1] = P_dev[i0, k]; Qgen0[b-1] = Q_dev[i0, k]
Qshunt0 = Bs * Vpu0**2
Pnet0 = Pgen0 - Pd
Qnet0 = Qgen0 - Qd + Qshunt0
with open(os.path.join(OUT_CSV, 'normal_pf_power.csv'), 'w') as f:
    f.write('bus_id,P_gen_pu,Q_gen_pu,P_load_pu,Q_load_pu,Q_shunt_pu,P_net_pu,Q_net_pu\n')
    for b in range(39):
        f.write(f'{bus_id[b]},{Pgen0[b]:.15g},{Qgen0[b]:.15g},{Pd[b]:.15g},{Qd[b]:.15g},'
                f'{Qshunt0[b]:.15g},{Pnet0[b]:.15g},{Qnet0[b]:.15g}\n')
S['bookkeeping_closure'] = {
    'sum_P_net_pu': float(Pnet0.sum()), 'sum_Q_net_pu': float(Qnet0.sum()),
    'sum_P_gen_minus_load_minus_losses_pu': float(Pgen0.sum() - Pd.sum()),
    'P_loss_total_pu': None, 'Q_loss_total_pu': None,   # filled after branch flows
}

# branch flows from equilibrium voltages (pi model with off-nominal tap a at the from side)
ys_all = 1.0 / (r_pu + 1j * x_pu)
a_c = tap.astype(complex) * np.exp(1j * phi)
Iij = ys_all * V0c[fbus-1] / (a_c * np.conj(a_c)) - ys_all * V0c[tbus-1] / np.conj(a_c) + 1j * b_half * V0c[fbus-1]
Iji = -ys_all * V0c[fbus-1] / a_c + ys_all * V0c[tbus-1] + 1j * b_half * V0c[tbus-1]
Sfrom = V0c[fbus-1] * np.conj(Iij)
Sto = V0c[tbus-1] * np.conj(Iji)
Sloss = Sfrom + Sto
with open(os.path.join(OUT_CSV, 'normal_pf_line_flow.csv'), 'w') as f:
    f.write('line,from_bus,to_bus,P_from_pu,Q_from_pu,P_loss_pu,Q_loss_pu\n')
    for k in range(46):
        f.write(f'{k+1},{fbus[k]},{tbus[k]},{Sfrom[k].real:.15g},{Sfrom[k].imag:.15g},'
                f'{Sloss[k].real:.15g},{Sloss[k].imag:.15g}\n')
S['bookkeeping_closure']['P_loss_total_pu'] = float(Sloss.real.sum())
S['bookkeeping_closure']['Q_loss_total_pu'] = float(Sloss.imag.sum())
S['bookkeeping_closure']['sum_branch_Q_from_plus_shunt_minus_load_pu'] = float(
    Sfrom.imag.sum() + Qshunt0.sum() - Qd.sum())
S['equilibrium'] = {
    'V_min_pu': float(Vpu0.min()), 'V_max_pu': float(Vpu0.max()),
    'V_bus31_pu': float(Vpu0[30]), 'ang_bus31_deg': float(A0[30]),
    'V_min_bus': int(bus_id[int(np.argmin(Vpu0))]),
    'V_max_bus': int(bus_id[int(np.argmax(Vpu0))]),
    'sum_Qr_pu': float(-Bs[[b-1 for b in DEV_BUSES[1:]]].sum()),
}

# device injection table (equilibrium)
with open(os.path.join(OUT_CSV, 'normal_resource_pf.csv'), 'w') as f:
    f.write('device_index,device_id,bus_id,mode,P_pu,Q_pu,V_pu\n')
    for k, (did, b) in enumerate(zip(DEV_IDS, DEV_BUSES)):
        mode = 'SYNCHRONOUS' if k == 0 else 'GFM'
        f.write(f'{k+1},{did},{b},{mode},{P_dev[i0,k]:.15g},{Q_dev[i0,k]:.15g},{Vpu0[b-1]:.15g}\n')

# ---------------------------------------------------------------- SCR diagnostic
Ypass = Ypre + np.diag(Yload)
Zth = np.linalg.inv(Ypass)
S['scr'] = []
for d, b in zip(DEV_IDS[1:], DEV_BUSES[1:]):
    z = abs(Zth[b-1, b-1])
    ssc = Vpu0[b-1]**2 / z
    S['scr'].append({'bus': b, 'Zth': z, 'S_sc': ssc,
                     'S_rating': S_RATING[d], 'SCR': ssc / S_RATING[d]})
S['scr_range'] = [min(r['SCR'] for r in S['scr']), max(r['SCR'] for r in S['scr'])]

# ---------------------------------------------------------------- windows / tsstats
t_close = T_CLOSE
w_pre = t < 20.0
w_isl = (t >= 20.0) & (t < t_close)
w_post = t >= t_close
S['tsstats'] = []
for k, (did, b) in enumerate(zip(DEV_IDS, DEV_BUSES)):
    vb = V[:, b-1]
    P_MW = P_dev[:, k] * 100.0
    S['tsstats'].append({
        'device': did,
        'pre_V_mean': float(vb[w_pre].mean()),
        'isl_V_min': float(vb[w_isl].min()), 'isl_V_max': float(vb[w_isl].max()),
        'post_P_mean_MW': float(P_MW[w_post].mean()),
        'post_P_std_MW': float(P_MW[w_post].std()),
    })
# envelope + frequency facts
S['envelope'] = {'V_min_pu': float(V.min()), 'V_max_pu': float(V.max()),
                 't_at_min_s': float(t[int(np.argmin(V.min(axis=1)))]),
                 't_at_max_s': float(t[int(np.argmax(V.max(axis=1)))]),
                 'V_min_overall_bus': int(bus_id[int(np.argmin(V.min(axis=0)))]),
                 'V_max_overall_bus': int(bus_id[int(np.argmax(V.max(axis=0)))]),
                 'V_min_fault_window_pu': float(V[(t >= 60) & (t <= 60.15)].min()),
                 'V_max_fault_window_pu': float(V[(t >= 60) & (t <= 60.15)].max())}
f_sg = 60.0 * omega
S['sg_frequency'] = {
    'f_min_Hz': float(f_sg.min()), 'f_max_Hz': float(f_sg.max()),
    'f_min_fault_window_Hz': float(f_sg[(t >= 60) & (t <= 60.15)].min()),
    'f_max_fault_window_Hz': float(f_sg[(t >= 60) & (t <= 60.15)].max()),
    'omega_min_pu': float(omega.min()), 'omega_max_pu': float(omega.max()),
    'f_min_island_Hz': float(f_sg[w_isl].min()), 'f_max_island_Hz': float(f_sg[w_isl].max())}
# island dispatch check 40-55 s (correct mapping: P_dev col 0 = SG31, cols 1..9 = IBR30..39)
w_disp = (t >= 40.0) & (t <= 55.0)
S['island_dispatch_40_55s'] = {d: float(P_dev[w_disp, k+1].mean())
                               for k, d in enumerate(DEV_IDS[1:])}
S['island_dispatch_std'] = {d: float(P_dev[w_disp, k+1].std())
                            for k, d in enumerate(DEV_IDS[1:])}
S['island_dispatch_sum_pu'] = float(sum(S['island_dispatch_40_55s'].values()))
S['sg_transfer'] = {
    'P_prefault_pu': float(P_dev[w_pre][-1000:, 0].mean()),
    'P_island_max_abs_pu': float(np.abs(sgP[w_isl]).max()),
    'P_post_mean_pu': float(sgP[w_post].mean()),
    'P_post_mean_MW': float(sgP[w_post].mean() * 100),
    'P_post_std_MW': float(sgP[w_post].std() * 100),
    'P_post_min_MW': float(sgP[w_post].min() * 100),
    'P_post_max_MW': float(sgP[w_post].max() * 100),
}
w_tail = t >= 150.0
S['sg_transfer']['P_tail_150_160_MW'] = float(sgP[w_tail].mean() * 100)
S['sg_transfer']['Q_tail_150_160_MVAr'] = float(Q_dev[w_tail, 0].mean() * 100)
S['sg_frequency']['f_tail_150_160_Hz'] = float(f_sg[w_tail].mean())
S['sg_frequency']['f_at_max_s'] = float(t[int(np.argmax(f_sg))])
S['sg_frequency']['f_island_40_55_Hz'] = float(f_sg[w_disp].mean())
S['sg_frequency']['f_pre_mean_Hz'] = float(f_sg[w_pre].mean())

# ---------------------------------------------------------------- event marks CSV
with open(os.path.join(OUT_CSV, 'event_marks.csv'), 'w') as f:
    f.write('event_type,t_s,applied,pre_kcl_norm,right_kcl_norm\n')
    for e in S['events']:
        f.write(f"{e['type']},{e['t_s']:.15g},{e['applied']},n/e,n/e\n")
    f.write(f"sg_reclose,{T_CLOSE:.15g},1,n/e,n/e\n")

# ---------------------------------------------------------------- figure series (decimated)
DEC = 10   # 1 kHz record -> 100 Hz plot cadence (disclosed in the report)
idx = np.arange(0, len(t), DEC)
if idx[-1] != len(t) - 1:
    idx = np.append(idx, len(t) - 1)
td = t[idx]

with open(os.path.join(OUT_CSV, 'mode_level_timeline.csv'), 'w') as f:
    f.write('time_s,SG31_level,' + ','.join(f'{d}_level' for d in DEV_IDS[1:]) + '\n')
    sg_level = np.where(t < 20.0, 2.0, np.where(t >= t_close, 2.0, 0.0))
    for n in idx:
        f.write(f'{t[n]:.9g},{sg_level[n]:.0f},' + ','.join('2' for _ in DEV_IDS[1:]) + '\n')

with open(os.path.join(OUT_CSV, 'ts_device_power.csv'), 'w') as f:
    f.write('time_s,' + ','.join(f'{d}_{q}' for d in DEV_IDS for q in ('P_MW', 'Q_MVAr')) + '\n')
    for n in idx:
        vals = [f'{t[n]:.9g}']
        for k in range(10):
            vals.append(f'{P_dev[n,k]*100:.15g}')
            vals.append(f'{Q_dev[n,k]*100:.15g}')
        f.write(','.join(vals) + '\n')

with open(os.path.join(OUT_CSV, 'ts_device_dq_currents.csv'), 'w') as f:
    f.write('time_s,' + ','.join(f'{d}_{q}' for d in DEV_IDS[1:] for q in ('id_pu', 'iq_pu')) + '\n')
    for n in idx:
        vals = [f'{t[n]:.9g}']
        for k in range(9):
            vals.append(f'{ID[n,k]:.15g}'); vals.append(f'{IQ[n,k]:.15g}')
        f.write(','.join(vals) + '\n')

with open(os.path.join(OUT_CSV, 'ts_sg_frequency.csv'), 'w') as f:
    f.write('time_s,f_Hz,omega_pu\n')
    for n in idx:
        f.write(f'{t[n]:.9g},{f_sg[n]:.15g},{omega[n]:.15g}\n')

with open(os.path.join(OUT_CSV, 'ts_bus_voltages_devices.csv'), 'w') as f:
    f.write('time_s,' + ','.join(f'{d}_V_pu' for d in DEV_IDS) + '\n')
    for n in idx:
        vals = [f'{t[n]:.9g}'] + [f'{V[n,b-1]:.15g}' for b in DEV_BUSES]
        f.write(','.join(vals) + '\n')

vmax = V.max(axis=1); vmin = V.min(axis=1)
with open(os.path.join(OUT_CSV, 'ts_bus_vmin_vmax.csv'), 'w') as f:
    f.write('time_s,v_min_pu,v_max_pu\n')
    for n in idx:
        f.write(f'{t[n]:.9g},{vmin[n]:.15g},{vmax[n]:.15g}\n')

# copy the two shared INPUT case tables (verified against case.json above)
import shutil
for name in ('case_bus_data.csv', 'case_line_data.csv'):
    shutil.copyfile(os.path.join(REF_CSV, name), os.path.join(OUT_CSV, name))

S['decimation'] = {'every_kth_sample': DEC, 'rows_plotted': int(len(idx)),
                   'record_rows': int(len(t)), 'record_rate_Hz': 1.0 / S['manifest']['h_s']}
json.dump(S, open(OUT_SUM, 'w'), indent=1)
print('wrote', OUT_SUM)
print('t_close', t_close, 'detected', S['t_close_detected_first_sample_s'])
print('equilibrium crosscheck max dP,dQ:', S['equilibrium_crosscheck_t0']['max_abs_P_diff_pu'],
      S['equilibrium_crosscheck_t0']['max_abs_Q_diff_pu'])
print('series crosscheck max dP,dQ:', S['series_crosscheck']['max_abs_P_diff_pu'],
      S['series_crosscheck']['max_abs_Q_diff_pu'])
print('SCR range:', S['scr_range'])
print('V range eq:', S['equilibrium']['V_min_pu'], S['equilibrium']['V_max_pu'])
print('envelope:', S['envelope']['V_min_pu'], S['envelope']['V_max_pu'])
print('f_sg range:', S['sg_frequency']['f_min_Hz'], S['sg_frequency']['f_max_Hz'])
