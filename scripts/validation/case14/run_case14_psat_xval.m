function out = run_case14_psat_xval(scenario)
%RUN_CASE14_PSAT_XVAL  Fresh PSAT-vs-Ours cross-validation for IEEE case14.
%   Regenerates PSAT results in THIS session (no saved .mat). PSAT is a
%   reference tool only. Classical model, bus-4 fault, Zf=j0.1, 1.0-1.1 s.
if nargin<1, scenario=struct(); end
sc = struct('fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1, ...
    'dt',0.01,'t_end',15.0);
fn = fieldnames(scenario); for k=1:numel(fn), sc.(fn{k})=scenario.(fn{k}); end

pf_init_paths;
ps = run_psat_case14(sc);   % fresh PSAT

c = cases.case_matpower6_case14();
opt = struct('t_end',sc.t_end,'dt',sc.dt,'fault_bus',sc.fault_bus, ...
    't_fault',sc.t_fault,'t_clear',sc.t_clear,'Zf',sc.Zf, ...
    'method','trapezoidal','corrector_mode','adaptive', ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8, ...
    'max_corrector_iter',10,'corrector_failure','error', ...
    'pm_mode','balanced','model','classical','verbose',false);
r = stability.ts_simulate(c,opt);

% --- Map generators by bus (PSAT Syn.con vs ours gen_buses) ---
[gb,oo] = sort(r.gen_buses);
[~,po] = sort(ps.delta_bus);
assert(isequal(ps.delta_bus(po), gb), 'gen bus mapping mismatch PSAT vs Ours.');
tg = r.t;
dps = rad2deg(interp1(ps.t, ps.delta(:,po), tg, 'linear', 0));
wps = interp1(ps.t, ps.omega(:,po), tg, 'linear', 0);
peps = 100*interp1(ps.t, ps.Pe_pu(:,po), tg, 'linear', 0);   % MW (base 100)
vps_all = interp1(ps.t, ps.Vbus, tg, 'linear', 0);
d_ours = rad2deg(r.delta(:,oo)); w_ours = r.omega(:,oo); pe_ours = r.Pe_MW(:,oo);
fi_ps = find(ps.vbus_ids==sc.fault_bus,1); vps_fault = vps_all(:,fi_ps);
fi_ours = find(r.pf.external_bus_ids==sc.fault_bus,1); v_ours_fault = r.Vbus(:,fi_ours);

% COI frame (classical H=5 for case14).
H = 5*ones(numel(gb),1);
coi_p = sum(H'.*dps,2)/sum(H);   drel_p = dps - coi_p;   wrel_p = wps - mean(wps,2);
coi_o = sum(H'.*d_ours,2)/sum(H); drel_o = d_ours - coi_o; wrel_o = w_ours - mean(w_ours,2);

fprintf('=== Case14: PSAT (fresh) vs Ours (classical, adaptive) ===\n');
fprintf('  gen buses (mapped): %s\n', mat2str(gb));
fprintf('  PF: ours conv=%d iter=%d ; PSAT conv=%d\n', r.pf.converged, r.pf.iterations, ps.pf_conv);
fprintf('  PF max|dV|   PSAT-Ours = %.6g pu\n', max(abs(ps.pf_vmag - r.pf.bus_voltage)));
fprintf('  PF max|dAng| PSAT-Ours = %.6g deg\n', max(abs(ps.pf_angle_deg - r.pf.bus_angle_deg)));
fprintf('  TS: ours nonconv=%d/%d ; PSAT TD pts=%d\n', r.nonconverged_step_count, numel(r.t)-1, ps.td_points);
fprintf('  TS max|dCOI angle|  PSAT-Ours = %.6g deg\n', max(abs(drel_p-drel_o),[],'all'));
fprintf('  TS max|dCOI speed|  PSAT-Ours = %.6g pu\n', max(abs(wrel_p-wrel_o),[],'all'));
fprintf('  TS max|Pe|          PSAT-Ours = %.6g MW\n', max(abs(peps-pe_ours),[],'all'));
fprintf('  TS max|Vm bus%d|     PSAT-Ours = %.6g pu\n', sc.fault_bus, max(abs(vps_fault-v_ours_fault),[],'all'));

out = struct();
out.gen_buses = gb;
out.pf_max_dV = max(abs(ps.pf_vmag - r.pf.bus_voltage));
out.pf_max_dAng = max(abs(ps.pf_angle_deg - r.pf.bus_angle_deg));
out.max_dCOI_angle = max(abs(drel_p-drel_o),[],'all');
out.max_dCOI_speed = max(abs(wrel_p-wrel_o),[],'all');
out.max_Pe_MW = max(abs(peps-pe_ours),[],'all');
out.max_Vm_faultbus = max(abs(vps_fault-v_ours_fault),[],'all');
out.ours_nonconv = r.nonconverged_step_count;
out.psat_td_points = ps.td_points;
out.pf_converged = r.pf.converged && ps.pf_conv;
end
