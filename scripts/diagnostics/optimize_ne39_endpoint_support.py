"""หา endpoint operating design ด้วย KCL/droop; ไม่ใช่ production certificate."""
from datetime import datetime
import argparse
import json
from pathlib import Path

import h5py
import numpy as np
from scipy.optimize import minimize

from screen_ne39_chronology_design import network, solve_pv, solve_gfm, screen


def optimize(raw_file, reactor=500.0, qdrop=.025, optimize_placement=False):
    with h5py.File(raw_file) as f:
        c = f['request/scenario/case_data']
        b = np.array(c['bus_data']).T
        bus = np.array(c['mpc/bus']).T
        br = np.array(c['mpc/branch']).T
    ib = np.array([29,31,32,33,34,35,36,37,38])
    source_y = network(bus, br)
    vg = b[:,2].copy(); vg[np.r_[30,ib]] = 1.04
    seed = b[:,2]*np.exp(1j*np.deg2rad(b[:,3]))
    vpf, _ = solve_pv(source_y, np.r_[30,ib], 30, vg, b[:,4]-b[:,6], b[:,5]-b[:,7], seed)
    load_y = np.diag(np.conj((bus[:,2]+1j*bus[:,3])/100)/abs(vpf)**2)
    hit = ((br[:,0]==16)&(br[:,1]==17))|((br[:,0]==17)&(br[:,1]==16))
    if np.count_nonzero(hit) != 1:
        raise ValueError('line16-17 ไม่ unique')
    opened = br.copy(); opened[hit,10] = 0
    trip_y = source_y-network(bus, opened)
    ports = np.eye(39)[:,ib]
    # capability เป็น design ceiling ก่อน optimize ไม่ปรับ limit ย้อนหลัง.
    sized = screen(raw_file,1.04,port_reactor_MVAr=reactor)
    rating = np.array(sized['Mbase_MVA'])/100
    pmax = np.array(sized['Pmax_MW'])/100
    qmax = rating*.9
    dv = 60*max(550,.2*sum(bus[:,2]*(1.1/abs(vpf))**2)*1.2)/(100*sum(rating))/.4
    gp = vpf*np.conj(source_y@vpf)+b[:,6]+1j*b[:,7]
    p = gp[ib].real+gp[30].real*gp[ib].real/sum(gp[ib].real)
    q = gp[ib].imag+reactor/100

    def matrices(qr):
        qr=np.broadcast_to(qr,(9,))
        y = source_y+load_y-1j*ports@np.diag(qr/100)@ports.T
        yl = y+.2*load_y
        yo = yl-trip_y
        yf=yl.copy(); yf[15,15]+=1/(1j*.1)
        def reduction(yy):
            a = np.linalg.solve(yy,ports)
            j = np.linalg.inv(a[ib,:])
            return a@j, j
        kl,jl = reduction(y)
        ko,jo = reduction(yo)
        kd,jd=reduction(yl)
        return (kl,jl,ko,jo,np.linalg.solve(yl,ports)@jl,np.linalg.solve(y,ports)@jo,
                kd,jd,np.linalg.solve(yf,ports)@jd,np.linalg.solve(yo,ports)@jd)


    fixed = matrices(reactor)
    y0 = source_y+load_y-1j*(reactor/100)*ports@ports.T
    vl,_,_,_ = solve_gfm(y0,ib,ib[0],p,q,abs(vpf[ib]),rating,qdrop,vpf)
    pl = (vl*np.conj(y0@vl))[ib].real
    ql = (vl*np.conj(y0@vl))[ib].imag
    vo,_,_,w = solve_gfm(y0+.2*load_y-trip_y,ib,ib[0],pl,ql,abs(vl[ib]),rating,qdrop,vl,dv)
    vd,_,_,wd = solve_gfm(y0+.2*load_y,ib,ib[0],pl,ql,abs(vl[ib]),rating,qdrop,vl,dv)

    def pack(v):
        v = v[ib]*np.exp(-1j*np.angle(v[ib[0]]))
        return np.r_[abs(v),np.angle(v[1:])]

    def unpack(z):
        return z[:9]*np.exp(1j*np.r_[0,z[9:17]])

    def values(z):
        a,b,d = unpack(z[:17]),unpack(z[17:34]),unpack(z[35:52])
        kl,jl,ko,jo,tl,to,kd,jd,tf,tline = matrices(z[53:]*1000) if optimize_placement else fixed
        sl,so,sd = a*np.conj(jl@a),b*np.conj(jo@b),d*np.conj(jd@d)
        volt = np.r_[kl@a,ko@b,tl@a,to@b,kd@d,tf@d,tline@d]
        eq = np.r_[(so.real-sl.real+rating*dv*z[34])/rating,
                   (so.imag-sl.imag-rating*(abs(a)-abs(b))/qdrop)/rating,
                   (sd.real-sl.real+rating*dv*z[52])/rating,
                   (sd.imag-sl.imag-rating*(abs(a)-abs(d))/qdrop)/rating]
        ineq = np.r_[abs(volt)-.905,1.095-abs(volt),
                     sl.real/rating,so.real/rating,sd.real/rating,
                     (pmax-sl.real)/rating,(pmax-so.real)/rating,(pmax-sd.real)/rating,
                     (qmax-abs(sl.imag))/rating,(qmax-abs(so.imag))/rating,(qmax-abs(sd.imag))/rating,
                     1.1-abs(jl@a)/rating,1.1-abs(jo@b)/rating,1.1-abs(jd@d)/rating,
                     .49-abs(60*z[34]),.49-abs(60*z[52])]
        return eq,ineq,volt,sl,so

    z0 = np.r_[pack(vl),pack(vo),w,pack(vd),wd]
    if optimize_placement:
        z0=np.r_[z0,np.full(9,reactor/1000)]
    constraints = [{'type':'eq','fun':lambda z:values(z)[0]},
                   {'type':'ineq','fun':lambda z:values(z)[1]}]
    vb=[(.9,1.1)]*9+[(-1,1)]*8
    bounds=vb+vb+[(-.008,.008)]+vb+[(-.008,.008)]
    if optimize_placement:
        bounds += [(-.5,reactor/1000)]*9
    def objective(z):
        regularizer=np.sum((z[:9]-1.04)**2)+np.sum((z[17:26]-1.04)**2)
        return np.sum(z[53:]**2)+.01*regularizer if optimize_placement else regularizer
    result = minimize(objective,z0,method='SLSQP',constraints=constraints,
                      bounds=bounds,options={'ftol':1e-10,'maxiter':250})
    eq,ineq,volt,sl,so = values(result.x)
    passed = max(abs(eq))<=1e-7 and min(ineq)>=-1e-7
    return {'status':'ENDPOINT_FEASIBLE' if passed else 'OPTIMIZATION_NOT_FEASIBLE',
            'production_certified':False,'source_raw':str(raw_file),'reactor_each_MVAr':reactor,
            'shunt_MVAr_at_1pu':(result.x[53:]*1000 if optimize_placement else np.full(9,reactor)).tolist(),
            'optimize_placement':optimize_placement,
            'optimizer_success':bool(result.success),'message':str(result.message),
            'iterations':int(result.nit),'equality_residual':float(max(abs(eq))),
            'inequality_min':float(min(ineq)),'Dv':float(dv),'Qdroop':qdrop,
            'rating_MVA':(rating*100).tolist(),'Pmax_MW':(pmax*100).tolist(),
            'post_trip_port_Vmag':result.x[:9].tolist(),
            'post_trip_port_angle_rad':np.r_[0,result.x[9:17]].tolist(),
            'line_port_Vmag':result.x[17:26].tolist(),
            'line_port_angle_rad':np.r_[0,result.x[26:34]].tolist(),
            'frequency_line_Hz':float(60*(1+result.x[34])),
            'post_trip_P_MW':(sl.real*100).tolist(),'post_trip_Q_MVAr':(sl.imag*100).tolist(),
            'line_P_MW':(so.real*100).tolist(),'line_Q_MVAr':(so.imag*100).tolist(),
            'voltage_envelopes':{name:[float(min(abs(v))),float(max(abs(v)))]
                                 for name,v in zip(['post_trip','line_open','load_right','restore_right','loaded','fault_right','line_right'],volt.reshape(7,39))},
            'scope':'สาม relative equilibria + load/restore/fault/line right limits; ไม่มี SG_ON/DC/dynamics/SSSA certificate',
            'warning':'arbitrary dispatch witness; ต้องผูก pre-event P/Q/V และ shared DC ใหม่ก่อน production'}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('raw_file',type=Path)
    parser.add_argument('--reactor',type=float,default=500)
    parser.add_argument('--voltage-droop',type=float,default=.025)
    parser.add_argument('--optimize-placement',action='store_true')
    args=parser.parse_args()
    if not np.isfinite(args.reactor) or args.reactor<0:
        parser.error('reactor ต้อง finite และไม่ติดลบ')
    folder=Path(__file__).resolve().parents[2]/'output'/'diagnostics'/('ne39_endpoint_support_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    folder.mkdir(parents=True)
    if not 0<args.voltage_droop<=.1:
        parser.error('voltage droop ต้องอยู่ใน (0,.1]')
    (folder/'request.json').write_text(json.dumps({'source_raw':str(args.raw_file),
        'reactor_ceiling_MVAr':args.reactor,'Qdroop':args.voltage_droop,
        'optimize_placement':args.optimize_placement,'production_certified':False}),encoding='utf-8')
    result=optimize(args.raw_file,args.reactor,args.voltage_droop,args.optimize_placement)
    (folder/'design.json').write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
    print(result['status'],result['message'],result['equality_residual'],result['inequality_min'],flush=True)
    print(result['voltage_envelopes'],flush=True)
    print('artifact='+str(folder),flush=True)


if __name__=='__main__':
    main()
