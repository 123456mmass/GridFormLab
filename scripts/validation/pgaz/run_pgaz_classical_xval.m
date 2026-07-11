function out = run_pgaz_classical_xval(case_loader, scenario)
%RUN_PGAZ_CLASSICAL_XVAL Reference cross-validation: PGAz vs Ours (classical).
%   PGAz 1.1.1 supports ONLY the classical 2nd-order model, so this is a
%   classical-vs-classical comparison (never an EMF6 validation). PGAz is a
%   reference tool only; it is added to the path here and restored after.
if nargin<2, scenario=struct(); end
sc = struct('fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1, ...
    'dt',0.01,'t_end',15.0,'corrector_iter',3);
fn = fieldnames(scenario);
for k=1:numel(fn), sc.(fn{k})=scenario.(fn{k}); end

pf_init_paths;
pgaz_root = '/home/birds/Documents/PGAz_V1.1.1';
if ~exist(pgaz_root,'dir'), error('run_pgaz_classical_xval:noPGAz','PGAz not found at %s',pgaz_root); end
oldp = path; addpath(pgaz_root); cl = onCleanup(@() path(oldp)); %#ok<NASGU>

c = case_loader();
sys = case_to_pgaz_sys(c);
optp = struct('t_end',sc.t_end,'dt',sc.dt,'method','trapezoidal', ...
    'corrector_iter',sc.corrector_iter,'make_plots',false, ...
    'fault',struct('enable',true,'bus',sc.fault_bus,'t_fault',sc.t_fault, ...
    't_clear',sc.t_clear,'Rf',real(sc.Zf),'Xf',imag(sc.Zf)));
TS = pgaz_ts(sys,1e-10,50,optp);

% --- Ours: classical, same scenario ---
opt = struct('t_end',sc.t_end,'dt',sc.dt,'fault_bus',sc.fault_bus, ...
    't_fault',sc.t_fault,'t_clear',sc.t_clear,'Zf',sc.Zf, ...
    'method','trapezoidal','corrector_mode','fixed','corrector_iter',sc.corrector_iter, ...
    'pm_mode','balanced','model','classical','verbose',false);
r = stability.ts_simulate(c,opt);

% --- Align generators by bus ---
[gb,oo] = sort(r.gen_buses);
d_ours = rad2deg(r.delta(:,oo)); w_ours = r.omega(:,oo); pe_ours = r.Pe_MW(:,oo);
d_pg = TS.delta_deg; w_pg = TS.omega; pe_pg = TS.Pg_MW;
% PGAz gen order = sys.Gen(:,1) = TS.gen_bus; sort to match gb
[~,op] = sort(TS.gen_bus);
d_pg = d_pg(:,op); w_pg = w_pg(:,op); pe_pg = pe_pg(:,op);
assert(isequal(TS.gen_bus(op), gb), 'gen bus mapping mismatch PGAz vs Ours.');

% --- Common time grid (ours) ---
tg = r.t;
d_pg = interp1(TS.t, d_pg, tg, 'linear'); w_pg = interp1(TS.t, w_pg, tg, 'linear');
pe_pg = interp1(TS.t, pe_pg, tg, 'linear');
v_pg = interp1(TS.t, TS.Vm, tg, 'linear');

% --- COI frame (equal H=5 for case14; RTS-24 uses r.H) ---
if isfield(r,'H') && numel(r.H)==numel(gb), H=r.H(oo).'; else, H=5*ones(numel(gb),1); end
coi_o = sum(H.*d_ours,2)/sum(H); drel_o = d_ours - coi_o; wrel_o = w_ours - mean(w_ours,2);
coi_p = sum(H.*d_pg,2)/sum(H);   drel_p = d_pg - coi_p;    wrel_p = w_pg - mean(w_pg,2);

fb = find(r.pf.external_bus_ids==sc.fault_bus,1);
v_ours_fault = r.Vbus(:,fb);
v_pg_fault = v_pg(:,fb);

fprintf('=== PGAz vs Ours (classical) ===\n');
fprintf('  gen buses (mapped): %s\n', mat2str(gb));
fprintf('  PF: ours conv=%d iter=%d ; PGAz PF ran\n', r.pf.converged, r.pf.iterations);
fprintf('  TS: ours nonconv=%d/%d ; PGAz nt=%d (fixed ci=%d)\n', ...
    r.nonconverged_step_count, numel(r.t)-1, numel(TS.t), sc.corrector_iter);
fprintf('  TS max|dCOI angle|  PGAz-Ours = %.6g deg\n', max(abs(drel_p-drel_o),[],'all'));
fprintf('  TS max|dCOI speed|  PGAz-Ours = %.6g pu\n', max(abs(wrel_p-wrel_o),[],'all'));
fprintf('  TS max|Pe|          PGAz-Ours = %.6g MW\n', max(abs(pe_pg-pe_ours),[],'all'));
fprintf('  TS max|Vm faultbus| PGAz-Ours = %.6g pu\n', max(abs(v_pg_fault-v_ours_fault),[],'all'));

out = struct();
out.scenario = sc; out.gen_buses = gb;
out.max_dCOI_angle_deg = max(abs(drel_p-drel_o),[],'all');
out.max_dCOI_speed_pu  = max(abs(wrel_p-wrel_o),[],'all');
out.max_Pe_MW          = max(abs(pe_pg-pe_ours),[],'all');
out.max_Vm_faultbus_pu = max(abs(v_pg_fault-v_ours_fault),[],'all');
out.ours_nonconv = r.nonconverged_step_count;
out.pf_converged = r.pf.converged;
end
