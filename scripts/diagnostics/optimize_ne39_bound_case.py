"""หา design จาก pre-event PF ผูกกับ fixed dispatch/DC sizing; diagnostic เท่านั้น."""
import argparse
from datetime import datetime
import json
from pathlib import Path

import numpy as np
from scipy.optimize import minimize

from screen_ne39_chronology_design import screen


def optimize(raw_file, seed=None):
    history=[]
    cache={}
    phases=('post_trip','loaded','line_open','load_right','restore_right','fault_right','line_right')

    def evaluate(z):
        key=tuple(z)
        if key in cache:
            return cache[key]
        try:
            result=screen(raw_file,np.r_[z[0],z[1:10]],port_reactor_MVAr=z[10:19]*1000,include_bound=False)
            inequalities=[]
            for phase in phases:
                r=result[phase]
                inequalities.extend([r['Vmin']-.905,1.095-r['Vmax']])
                if phase in ('post_trip','loaded','line_open'):
                    inequalities.extend([min(r['P_MW'])/100,.49-abs(r['common_frequency_Hz']-60)])
            error=None
        except Exception as exc:
            result={}; inequalities=[-10]*20; error=str(exc)
        out=np.array(inequalities),result
        cache[key]=out
        history.append({'parameters':z.tolist(),'inequality_min':float(min(inequalities)),'error':error})
        return out

    def objective(z):
        return sum(z[10:19]**2)+.001*sum((z[:10]-1.04)**2)

    z0=np.r_[1.02*np.ones(10),2*np.ones(9)] if seed is None else np.asarray(seed,dtype=float)
    solved=minimize(objective,z0,method='SLSQP',bounds=[(.95,1.08)]*10+[(0,3)]*9,
                    constraints={'type':'ineq','fun':lambda z:evaluate(z)[0]},
                    options={'ftol':1e-9,'maxiter':100,'eps':1e-5})
    constraints,result=evaluate(solved.x)
    failed_constraints=[n for n in phases if n in result and not result[n]['pass']]
    return {'status':'CASE_SCREEN_FEASIBLE' if min(constraints)>=-1e-7 and not failed_constraints else 'CASE_SCREEN_FAILED',
            'production_certified':False,'optimizer_success':bool(solved.success),'message':str(solved.message),
            'voltage_setpoints_pu':solved.x[:10].tolist(),'reactor_MVAr':(solved.x[10:]*1000).tolist(),
            'history':history,'screen':result,'scope':'pre-event PF + fixed proportional redispatch + canonical-equation steady oracle; MATLAB confirmation required'}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('raw_file',type=Path)
    parser.add_argument('--seed-design',type=Path)
    args=parser.parse_args()
    folder=Path(__file__).resolve().parents[2]/'output'/'diagnostics'/('ne39_bound_case_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    folder.mkdir(parents=True)
    (folder/'request.json').write_text(json.dumps({'source_raw':str(args.raw_file),'production_certified':False}),encoding='utf-8')
    seed=None
    if args.seed_design:
        previous=json.loads(args.seed_design.read_text(encoding='utf-8'))
        seed=np.r_[previous['voltage_setpoints_pu'],np.array(previous['reactor_MVAr'])/1000]
    try:
        result=optimize(args.raw_file,seed)
    except Exception as exc:
        result={'status':'CASE_SCREEN_ERROR','production_certified':False,'message':str(exc),'screen':{}}
    (folder/'design.json').write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
    print(result['status'],result['message'],flush=True)
    if result['screen']:
        print({n:[result['screen'][n]['Vmin'],result['screen'][n]['Vmax']] for n in ('load_right','restore_right','fault_right','line_right')},flush=True)
    print('artifact='+str(folder),flush=True)


if __name__=='__main__':
    main()
