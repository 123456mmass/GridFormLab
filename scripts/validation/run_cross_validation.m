function run_cross_validation()
%RUN_CROSS_VALIDATION Evidence-first cross-validation summary.
%   Runs every cross-validation that is reproducible on THIS machine from
%   saved reference data + the in-house production solvers. Reference tools
%   (PSAT/PGAz) are NOT production dependencies; where they are not
%   installed and no saved reference exists, that comparison is reported as
%   "not re-verified here" rather than fabricated.

pf_init_paths;
fprintf('\n##########################################################\n');
fprintf('# CROSS-VALIDATION SUMMARY (reproduced on this machine)   #\n');
fprintf('##########################################################\n\n');

case14_psat_vs_ours();
kundur6_psat_vs_ours();
rts24_inhouse_metrics();
end

function case14_psat_vs_ours()
fprintf('=== IEEE 14-bus: PSAT (saved) vs Ours ===\n');
mat = fullfile(pwd,'docs','source','figures','case14_ts','psat_case14_ts_raw.mat');
if ~exist(mat,'file')
    fprintf('  PSAT case14 raw data not found -> NOT VERIFIED.\n\n'); return;
end
S = load(mat); ps = S.ps_save;
tg = (0:0.01:15).';
dps = rad2deg(interp1(ps.t, ps.delta, tg, 'linear'));
wps = interp1(ps.t, ps.omega, tg, 'linear');
peps = 100*interp1(ps.t, ps.Pe_pu, tg, 'linear');
vps_all = interp1(ps.t, ps.Vbus, tg, 'linear');
[~,ord] = sort(ps.delta_bus); dps=dps(:,ord); wps=wps(:,ord); peps=peps(:,ord);
fi_ps = find(ps.bus_ids==4,1); vps_fault = vps_all(:,fi_ps);

% Same scenario as the PSAT run: bus-4 fault, Zf=j0.1, 1.0-1.1 s, dt=0.01, 15 s.
c = cases.case_matpower6_case14();
opt = struct('t_end',15.0,'dt',0.01,'fault_bus',4,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1,'method','trapezoidal','corrector_mode','adaptive', ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8,'max_corrector_iter',10, ...
    'corrector_failure','error','pm_mode','balanced','model','classical','verbose',false);
r = stability.ts_simulate(c, opt);
[~,oo] = sort(r.gen_buses);
d_ours = rad2deg(r.delta(:,oo)); w_ours = r.omega(:,oo); pe_ours = r.Pe_MW(:,oo);
bus_ids = r.pf.external_bus_ids(:); fi = find(bus_ids==4,1); v_ours_fault = r.Vbus(:,fi);
assert(isequal(ps.delta_bus(:), r.gen_buses(oo)),'gen bus mapping mismatch PSAT vs Ours.');
% COI frame (classical H=5).
H = 5*ones(5,1);
coi_ps=sum(H'.*dps,2)/sum(H); drel_ps=dps-coi_ps; wrel_ps=wps-mean(wps,2);
coi_o=sum(H'.*d_ours,2)/sum(H); drel_o=d_ours-coi_o; wrel_o=w_ours-mean(w_ours,2);
fprintf('  gen buses (mapped): %s\n', mat2str(r.gen_buses(oo).'));
fprintf('  PF: ours conv=%d iter=%d ; PSAT conv=%d\n', r.pf.converged, r.pf.iterations, ps.pf_conv);
fprintf('  PF max|dV|   PSAT-Ours = %.6g pu\n', max(abs(ps.pf_vmag - r.pf.bus_voltage)));
fprintf('  PF max|dAng| PSAT-Ours = %.6g deg\n', max(abs(ps.pf_angle_deg - r.pf.bus_angle_deg)));
fprintf('  TS: ours nonconv steps=%d (of %d), max corrector resid=%.3e\n', ...
    r.nonconverged_step_count, numel(r.t)-1, r.max_corrector_residual);
fprintf('  TS max|dCOI angle|  PSAT-Ours = %.6g deg\n', max(abs(drel_ps-drel_o),[],'all'));
fprintf('  TS max|dCOI speed|  PSAT-Ours = %.6g pu\n', max(abs(wrel_ps-wrel_o),[],'all'));
fprintf('  TS max|Pe|          PSAT-Ours = %.6g MW\n', max(abs(peps-pe_ours),[],'all'));
fprintf('  TS max|Vm bus4|     PSAT-Ours = %.6g pu\n', max(abs(vps_fault-v_ours_fault),[],'all'));
fprintf('  (PGAz not installed on this machine -> PGAz leg NOT VERIFIED)\n\n');
end

function kundur6_psat_vs_ours()
fprintf('=== Kundur 12.6 6th-order: PSAT (saved) vs Ours (EMF6) ===\n');
mat = fullfile(pwd,'docs','source','figures','kundur_ex126','psat_kundur6_ts_raw.mat');
if ~exist(mat,'file')
    fprintf('  PSAT Kundur6 raw data not found -> NOT VERIFIED.\n\n'); return;
end
S = load(mat); ps = S.ps_save;
opt = struct('model','emf6','t_end',min(ps.td_tend,6),'dt',1e-3,'fault_bus',8, ...
    't_fault',1.0,'t_clear',1.05,'Zf',[],'method','trapezoidal','corrector_iter',2, ...
    'load_model','cz','verbose',false);
r = stability.ts_simulate(cases.case_kundur_two_area_classical(), opt);
[~,oo] = sort(r.gen_buses);
do = rad2deg(r.delta(:,oo)); wo = r.omega(:,oo); H = r.H(:).'; tg = r.t;
dps = rad2deg(interp1(ps.t, ps.delta, tg)); wps = interp1(ps.t, ps.omega, tg);
[~,o] = sort(ps.delta_bus); dps = dps(:,o); wps = wps(:,o);
drel_p = dps - sum(H.*dps,2)/sum(H); drel_o = do - sum(H.*do,2)/sum(H);
wrel_p = wps - mean(wps,2); wrel_o = wo - mean(wo,2);
fprintf('  gen buses (mapped): ours=%s psat=%s\n', mat2str(r.gen_buses(oo).'), mat2str(ps.delta_bus(o).'));
fprintf('  TS: ours nonconv steps=%d (of %d), init DAE resid=%.2e, min V(8)=%.4f\n', ...
    r.nonconverged_step_count, numel(r.t)-1, r.initial_dae_residual, min(r.Vbus(:,find(r.bus_ids==8,1))));
fprintf('  TS max|dCOI angle| PSAT-Ours = %.6g deg (tol 5)\n', max(abs(drel_p-drel_o),[],'all'));
fprintf('  TS max|dCOI speed| PSAT-Ours = %.6g pu (tol 1e-3)\n', max(abs(wrel_p-wrel_o),[],'all'));
fprintf('  (EMF6 uses only published parameters; no calibration knobs)\n\n');
end

function rts24_inhouse_metrics()
fprintf('=== IEEE RTS-24: in-house TS metrics (PSAT not installed live) ===\n');
c = cases.case_ieee_rts24_pgaz();
opt = struct('t_end',15,'dt',0.01,'fault_bus',15,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',0+0.1j,'method','trapezoidal','corrector_mode','adaptive', ...
    'max_corrector_iter',10,'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8, ...
    'verbose',false,'model','classical','plot_results',false);
r = stability.ts_simulate(c, opt);
H = r.H(:).'; dcoi = sum(H.*r.delta,2)/sum(H); drel = r.delta - dcoi;
maxpair = 0;
for i=1:size(r.delta,2), for j=i+1:size(r.delta,2)
    maxpair = max(maxpair, max(rad2deg(r.delta(:,i)-r.delta(:,j))));
end, end
fprintf('  PF: conv=%d iter=%d\n', r.pf.converged, r.pf.iterations);
fprintf('  TS: pts=%d t_end=%.2f nonconv steps=%d max corrector resid=%.3e\n', ...
    numel(r.t), r.t(end), r.nonconverged_step_count, r.max_corrector_residual);
fprintf('  TS max|dCOI angle| = %.4f deg\n', max(abs(rad2deg(drel)),[],'all'));
fprintf('  TS max pairwise sep = %.4f deg\n', maxpair);
fprintf('  TS max|omega-1|     = %.4e pu\n', max(abs(r.omega-1),[],'all'));
fprintf('  TS min V (any bus)   = %.6f pu\n', min(r.Vbus,[],'all'));
fprintf('  PSAT not installed on this machine and no saved RTS-24 PSAT reference\n');
fprintf('  data exists here -> PSAT-vs-Ours for RTS-24 NOT RE-VERIFIED on this host.\n');
fprintf('  (The documented baseline in docs/project/AGENT_HANDOFF.md was produced\n');
fprintf('   in the original PSAT-available environment; it is not re-fabricated here.)\n\n');
end
