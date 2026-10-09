"""คัดกรองสมการ PF/CZ/endpoint แบบอิสระ ไม่ใช่ MATLAB production certificate."""
from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path

import h5py
import numpy as np
from scipy.optimize import minimize, nnls, root


def network(bus, branch):
    """MATPOWER stamp รวม tap/shift/charging/shunt บนฐาน 100 MVA."""
    y = np.zeros((len(bus), len(bus)), dtype=complex)
    positions = {int(row[0]): i for i, row in enumerate(bus)}
    for row in branch:
        if row[10] == 0:
            continue
        i, j = positions[int(row[0])], positions[int(row[1])]
        a = (row[8] or 1) * np.exp(1j * np.deg2rad(row[9]))
        ys = 1 / complex(row[2], row[3])
        y[i, i] += (ys + 1j * row[4] / 2) / abs(a) ** 2
        y[j, j] += ys + 1j * row[4] / 2
        y[i, j] -= ys / a.conjugate()
        y[j, i] -= ys / a
    return y + np.diag((bus[:, 4] + 1j * bus[:, 5]) / 100)


def solve_pv(y, generators, reference, voltages, pnet, qnet, seed):
    """Newton oracle ของ PV PF; residual ทุกแถวที่ไม่ใช่ reference/PV-Q."""
    free = np.setdiff1d(np.arange(len(y)), reference)
    pq = np.setdiff1d(np.arange(len(y)), generators)

    def unpack(z):
        angle = np.zeros(len(y))
        angle[free] = z[: len(free)]
        mag = voltages.copy()
        mag[pq] = z[len(free) :]
        return mag * np.exp(1j * angle)

    def residual(z):
        v = unpack(z)
        s = v * np.conj(y @ v)
        return np.r_[s.real[free] - pnet[free], s.imag[pq] - qnet[pq]]

    z0 = np.r_[np.angle(seed[free] / seed[reference]), abs(seed[pq])]
    solved = root(residual, z0, tol=1e-10)
    error = float(max(abs(residual(solved.x))))
    if not solved.success or error > 1e-7:
        raise RuntimeError(f"PV PF ไม่ converged: {solved.message}; residual={error}")
    return unpack(solved.x), error


def solve_gfm(y, buses, reference, p_schedule, q_schedule, e_reference, rating, droop, seed, dv=None):
    """base solve float reference P; loaded solve ใช้ common droop frequency จริง."""
    free = np.setdiff1d(np.arange(len(y)), reference)
    online = np.zeros(len(y), dtype=bool)
    online[buses] = True

    def unpack(z):
        angle = np.zeros(len(y))
        angle[free] = z[: len(free)]
        return z[len(free) : len(free)+len(y)] * np.exp(1j * angle)

    def residual(z):
        v = unpack(z)
        s = v * np.conj(y @ v)
        q = np.zeros(len(y))
        q[buses] = q_schedule + rating * (e_reference - abs(v[buses])) / droop
        p = np.zeros(len(y))
        p[buses] = p_schedule
        if dv is None:
            return np.r_[s.real[free] - p[free], s.imag - q]
        # M ไม่เข้า steady swing: ทุกเครื่องมี absolute speed 1+w เดียวกัน.
        p[buses] -= rating*dv*z[-1]
        return np.r_[s.real - p, s.imag - q]

    z0 = np.r_[np.angle(seed[free] / seed[reference]), abs(seed)]
    if dv is not None:
        z0 = np.r_[z0, 0.0]
    solved = root(residual, z0, tol=1e-10)
    error = float(max(abs(residual(solved.x))))
    if not solved.success or error > 1e-7:
        raise RuntimeError(f"GFM equilibrium ไม่ converged: {solved.message}; residual={error}")
    v = unpack(solved.x)
    current = np.zeros(len(y), dtype=complex)
    # คงเฉพาะ resource injections; numerical residual ที่ load buses ไม่ใช่ source.
    current[online] = (y @ v)[online]
    kcl = float(max(abs(y @ v - current)))
    if kcl > 1e-7:
        raise RuntimeError(f"GFM full KCL ไม่ผ่าน: {kcl}")
    return v, current, error, float(solved.x[-1]) if dv is not None else 0.0


def record(v, current, y, buses, rating, pmax, qmax, dc):
    s = v[buses] * np.conj(current[buses]) * 100
    inv_current = abs(current[buses]) * 100 / rating
    pac = s.real / rating + .015 * inv_current**2
    disc = dc[:, 0] ** 2 - 4 * .1 * pac
    vdc = (dc[:, 0] + np.sqrt(np.maximum(disc, 0))) / 2
    idc = pac / vdc
    failures = []
    if min(abs(v)) < .9 or max(abs(v)) > 1.1:
        failures.append("network_voltage")
    for k, bus in enumerate(buses):
        if s[k].real < 0 or s[k].real > pmax[k]:
            failures.append(f"IBR{bus+1}:active_power")
        if abs(s[k].imag) > qmax[k]:
            failures.append(f"IBR{bus+1}:reactive_power")
        if inv_current[k] > 1.2:
            failures.append(f"IBR{bus+1}:ac_current")
        if disc[k] <= 0 or idc[k] < 0 or idc[k] > dc[k, 1]:
            failures.append(f"IBR{bus+1}:dc_steady_envelope")
    return {
        "Vmin": float(min(abs(v))), "Vmax": float(max(abs(v))),
        "kcl": float(max(abs(y @ v - current))),
        "P_MW": s.real.tolist(), "Q_MVAr": s.imag.tolist(),
        "current_converter_pu": inv_current.tolist(),
        "failures": failures, "pass": not failures,
        "scope": "AC endpoint/steady DC envelope; ไม่รวม transient DC RHS หรือ dynamics",
    }


def voltage_bound(yleft, yright, buses, target=7):
    """Dual inequality |Vright_k|<=1.1*(||h||1+||t-hK||1), ไม่อาศัย local optimum."""
    ports = np.eye(len(yleft))[:, buses]
    a = np.linalg.solve(yleft, ports)
    b = np.linalg.solve(yright, ports)
    inverse = np.linalg.inv(a[buses, :])
    k = a @ inverse
    t = (b @ inverse)[target]

    def voltages(z):
        return k @ (z[:len(buses)] + 1j*z[len(buses):])

    solved = minimize(
        lambda z: -(t @ (z[:len(buses)] + 1j*z[len(buses):])).real,
        np.zeros(2*len(buses)), method="SLSQP",
        constraints={"type": "ineq", "fun": lambda z: 1.1**2-abs(voltages(z))**2},
        options={"ftol": 1e-12, "maxiter": 1000},
    )
    v = voltages(solved.x)
    active = np.flatnonzero(abs(abs(v)-1.1) < 1e-6)
    if len(active) == 0:
        raise RuntimeError("ไม่มี active rows สำหรับ dual bound")
    gradient = np.column_stack([
        2*np.r_[(np.conj(v[j])*k[j]).real, -(np.conj(v[j])*k[j]).imag]
        for j in active
    ])
    mu, stationarity = nnls(gradient, np.r_[t.real, -t.imag])
    h = np.zeros(len(yleft), dtype=complex)
    h[active] = 2*mu*np.conj(v[active])
    residual = t-h@k
    upper = float(1.1*(sum(abs(h))+sum(abs(residual))))
    return {
        "target_bus": target+1, "upper_bound_pu": upper,
        "bound_below_gate": upper+1e-7 < .9,
        "numerical_allowance_pu": 1e-7,
        "primal_candidate_pu": float(-solved.fun),
        "stationarity_residual": float(stationarity),
        "identity_residual_l1": float(sum(abs(residual))),
        "h_real": h.real.tolist(), "h_imag": h.imag.tolist(),
        "scope": "Y คงที่; current injection เฉพาะ IBR buses; all-left-bus |V|<=1.1; ไม่จำกัด ratings/dispatch",
        "derivation": "t=hK+r; |t vports|<=1.1*(sum(abs(h))+sum(abs(r))) เพราะทุก bus/port left voltage <=1.1",
    }


def screen(raw_file, voltage, loading_fraction=1.0, voltage_droop=.025, reactor_ratio=0.0,
           port_reactor_MVAr=0.0, network_parallel_factor=1.0, include_bound=True):
    with h5py.File(raw_file) as f:
        c = f["request/scenario/case_data"]
        b = np.array(c["bus_data"]).T
        bus = np.array(c["mpc/bus"]).T
        br = np.array(c["mpc/branch"]).T
    # operating envelope ใหม่: คง power factor/ตำแหน่งโหลดและแบ่ง dispatch เท่าเดิม.
    # chronology ยังคงเพิ่ม 20% ของโหลด study; ไม่แก้ source raw/archive.
    bus[:, 2:4] *= loading_fraction
    b[:, 4:8] *= loading_fraction
    # fixed shunt reactors ดูด Q ตาม V^2 ไม่ใช่ active/current injection ใหม่.
    # ratio อ้างอิง Qload ต้นทางที่ 1 pu; ทั้ง pre/loaded/restore ใช้ reactor เดิม.
    bus[:, 5] -= reactor_ratio * bus[:, 3]
    b[:, 9] -= reactor_ratio * bus[:, 3] / 100
    ib = np.array([29, 31, 32, 33, 34, 35, 36, 37, 38])
    # port reactors เพิ่ม physical voltage-dependent admittance ที่ IBR ports.
    bus[ib, 5] -= port_reactor_MVAr
    b[ib, 9] -= port_reactor_MVAr/100
    # continuous reinforcement relaxation: n เท่าของทุก branch stamp.
    # เปิด line16-17 เพียงหนึ่ง source circuit ตามเหตุการณ์เดิม ไม่เปิดทั้ง corridor.
    extra = br.copy()
    extra[:, 2:4] /= network_parallel_factor
    extra[:, 4] *= network_parallel_factor
    y = network(bus, extra)
    generators = np.r_[30, ib]
    reference = ib[0]
    vg = b[:, 2].copy()
    vg[generators] = voltage
    seed = b[:, 2] * np.exp(1j * np.deg2rad(b[:, 3]))
    vpf, pf_error = solve_pv(y, generators, 30, vg, b[:, 4]-b[:, 6], b[:, 5]-b[:, 7], seed)
    generation = vpf * np.conj(y @ vpf) + b[:, 6] + 1j*b[:, 7]
    p0, q0 = generation[ib].real*100, generation[ib].imag*100
    psg = float(generation[30].real*100)
    weights = p0/p0.sum()
    loadmax = float(sum(1.2*bus[:, 2]*(1.1/abs(vpf))**2))
    required = loadmax*1.05*1.1
    pmax = 10*np.ceil(required*weights/10)
    qenv = abs(q0)
    opened = br.copy()
    hit = ((br[:, 0] == 16) & (br[:, 1] == 17)) | ((br[:, 0] == 17) & (br[:, 1] == 16))
    if np.count_nonzero(hit) != 1:
        raise RuntimeError("line 16-17 ไม่ unique")
    opened[hit, 10] = 0
    # base source-circuit stamp ที่ trip; parallel support circuits ไม่ถูก trip.
    tripped = network(bus, br)-network(bus, opened)
    yopened = y-tripped
    load = 1.2*b[:, 6:8]*(1.1/abs(vpf[:, None]))**2
    pp = np.zeros(39)
    pp[ib] = loadmax*1.05*weights/100
    for yy in (y, yopened):
        vv, _ = solve_pv(yy, ib, reference, vg, pp-load[:, 0], -load[:, 1], vpf)
        ss = vv*np.conj(yy@vv)
        qenv = np.maximum(qenv, abs((ss.imag+load[:, 1])[ib]*100))
    qmax = 10*np.ceil(1.2*qenv/10)
    rating = 10*np.ceil(np.hypot(pmax, qmax)/.9/10)
    imax = np.hypot(pmax, qmax)/(rating*.9)
    pac0 = p0/rating+.015*(np.hypot(p0, q0)/(rating*abs(vpf[ib])))**2
    pacmax = pmax/rating+.015*imax**2
    edc = 1+.1*pac0
    vdc = (edc+np.sqrt(edc**2-4*.1*pacmax))/2
    dc = np.c_[edc, 1.05*pacmax/vdc]
    capacitor = 2*pacmax*.02/(1-.9**2)
    a = pac0/capacitor
    k = (10-pac0)/capacitor
    tau = 1/(np.sqrt(k/2)+np.sqrt(k/2+a))**2
    imbalance = max(psg, .2*loadmax)/sum(rating)
    yl = np.diag(np.conj((bus[:, 2]+1j*bus[:, 3])/100)/(abs(vpf)**2+np.finfo(float).eps))
    yp = y+yl
    loaded = yp+.2*yl
    line = yopened+1.2*yl
    ps = (p0+psg*weights)/100
    qs = q0/100
    result = {
        "classification": "INDEPENDENT_PROJECT_DERIVED_DESIGN_SCREEN",
        "source_raw": str(raw_file), "production_certified": False,
        "voltage_setpoint_pu": np.asarray(voltage).tolist(), "pf_residual": pf_error,
        "operating_load_fraction": loading_fraction, "voltage_droop_pu": voltage_droop,
        "event_load_multiplier": 1.2, "fixed_reactor_Qload_ratio": reactor_ratio,
        "fixed_reactor_MVAr_at_1pu": (reactor_ratio*bus[:, 3]).tolist(),
        "port_reactor_MVAr_at_1pu_each": np.asarray(port_reactor_MVAr).tolist(),
        "network_parallel_factor": network_parallel_factor,
        "line_event_scope": "หนึ่ง source circuit16-17; reinforcement circuits คง online",
        "Pload_envelope_MW": loadmax, "Pcapacity_required_MW": required,
        "M_s": 60*imbalance, "H_s": 30*imbalance, "Dv": 60*imbalance/.4,
        "resource_buses": (ib+1).tolist(), "Pmax_MW": pmax.tolist(),
        "Qmax_MVAr": qmax.tolist(), "Mbase_MVA": rating.tolist(),
        "Cdc_pu_s": capacitor.tolist(), "tau_s_s": tau.tolist(),
        "SG_P_MW": psg,
    }
    steady = {}
    for name, yy in (("post_trip", yp), ("loaded", loaded), ("line_open", line)):
        dv = None if name == "post_trip" else result["Dv"]
        v, current, err, speed = solve_gfm(yy, ib, reference, ps, qs, abs(vpf[ib]), rating/100, voltage_droop, vpf, dv)
        steady[name] = (v, current)
        result[name] = record(v, current, yy, ib, rating, pmax, qmax, dc)
        result[name]["equilibrium_residual"] = err
        result[name]["common_frequency_Hz"] = 60*(1+speed)
        if abs(60*speed) > .5:
            result[name]["failures"].append("frequency")
            result[name]["pass"] = False
        if name == "post_trip":
            # production trip ติดตั้ง reference P ที่ solve แล้ว; โหลดภายหลังคง u นี้.
            ps[0] = (v[reference]*np.conj(current[reference])).real
    for name, left, yy in (("load_right", "post_trip", loaded), ("restore_right", "line_open", yp)):
        _, current = steady[left]
        right = np.linalg.solve(yy, current)
        result[name] = record(right, current, yy, ib, rating, pmax, qmax, dc)
        result[name]["current_continuity_exact"] = True
        result[name]["warning"] = "DC ค่า steady envelope เท่านั้น: current/DC states ไม่ถูก initialize ใหม่"
    fault = loaded.copy()
    fault[15, 15] += 1/(1j*.1)
    for name, yy in (("fault_right", fault), ("line_right", line)):
        _, current = steady["loaded"]
        right = np.linalg.solve(yy, current)
        result[name] = record(right, current, yy, ib, rating, pmax, qmax, dc)
        result[name]["current_continuity_exact"] = True
    result["load_restore_pass"] = all(result[n]["pass"] for n in ("load_right", "restore_right"))
    result["endpoint_pass"] = all(result[n]["pass"] for n in ("load_right", "restore_right", "fault_right", "line_right"))
    if include_bound:
        result["load_right_necessary_bound"] = voltage_bound(yp, loaded, ib)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("raw_file", type=Path)
    parser.add_argument("--voltage", type=float, default=1.04)
    parser.add_argument("--loading-fraction", type=float, default=1.0)
    parser.add_argument("--voltage-droop", type=float, default=.025)
    parser.add_argument("--reactor-ratio", type=float, default=0.0)
    parser.add_argument("--port-reactor", type=float, default=0.0)
    parser.add_argument("--network-parallel-factor", type=float, default=1.0)
    args = parser.parse_args()
    if not .9 <= args.voltage <= 1.1:
        parser.error("voltage ต้องอยู่ใน .9-1.1 pu")
    if not 0 < args.loading_fraction <= 1 or not 0 < args.voltage_droop <= .1:
        parser.error("loading fraction ต้องอยู่ใน (0,1]; voltage droop ใน (0,.1]")
    root_dir = Path(__file__).resolve().parents[2]
    folder = root_dir/"output"/"diagnostics"/("ne39_independent_design_"+datetime.now().strftime("%Y%m%d_%H%M%S_%f"))
    folder.mkdir(parents=True)
    try:
        if not np.isfinite(args.reactor_ratio) or args.reactor_ratio < 0:
            raise ValueError("reactor ratio ต้อง finite และไม่ติดลบ")
        if not np.isfinite(args.port_reactor):
            raise ValueError("port shunt ต้อง finite; บวก=reactor ลบ=capacitor")
        if not np.isfinite(args.network_parallel_factor) or args.network_parallel_factor < 1:
            raise ValueError("network parallel factor ต้อง finite และ >=1")
        result = screen(args.raw_file, args.voltage, args.loading_fraction, args.voltage_droop,
                        args.reactor_ratio, args.port_reactor, args.network_parallel_factor)
    except Exception as exc:
        result = {"status": "SCREEN_FAILED", "reason": str(exc), "production_certified": False}
    (folder/"screen.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    for name in ("post_trip", "loaded", "line_open", "load_right", "restore_right", "fault_right", "line_right"):
        if name in result:
            row = result[name]
            print(name, f"V=[{row['Vmin']:.9g},{row['Vmax']:.9g}]", f"KCL={row['kcl']:.3g}", row["failures"], flush=True)
    print("artifact="+str(folder), flush=True)
    if "reason" in result:
        raise RuntimeError(result["reason"])


if __name__ == "__main__":
    main()
