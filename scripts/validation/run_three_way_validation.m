function out = run_three_way_validation(case_name, scenario, plateau_ci, return_raw)
%RUN_THREE_WAY_VALIDATION  Fresh Ours + PSAT + PGAz three-way cross-validation.
%   All three tools run FRESH (no saved trajectories). PSAT/PGAz are reference
%   tools only (never production deps). Generators mapped by bus ID. COI frame
%   is INERTIA-WEIGHTED for BOTH angle and speed (coi_relative). Interpolation
%   onto the common grid uses NO zero-fill/extrapolation; coverage is checked.
%   PGAz is run at the plateau corrector count (default 8, confirmed by
%   run_pgaz_convergence_study: ci8-ci12 ~ 1e-9) and reported as COMPLETED with
%   a fixed corrector, NOT "converged" (PGAz exposes no convergence residual).
%
%   Gate semantics (Phase B): PGAz is a SECONDARY DIAGNOSTIC ONLY. PGAz
%   missing/not-run/plateau-not-reached does NOT fail the gate. PSAT is the
%   required cross-validation reference. PGAz metrics are still REPORTED
%   honestly (gates.pgaz_status) when available. The plateau-PGAz-vs-Ours
%   comparison uses a TIGHT tolerance (0.05 deg COI) justified a priori by
%   the PSAT-Ours converged-trapezoidal baseline (~0.01 deg at dt=0.01).
%
%   RETURN_RAW (optional, 4th arg, default false): when true, the output struct
%   additionally carries raw trajectories (out.raw) for the report generator to
%   plot without re-running the tools. This is a mechanical, structured-output
%   addition only — no duplicate mapping/interpolation/metric logic, no change
%   to gates, tolerances, mappings, or acceptance criteria. The raw block is
%   populated only for tools that ran successfully (ran=true); on failure the
%   corresponding raw fields are empty and the failure metadata is preserved.
%
%   Fail-soft: when PSAT/PGAz execution is caught as a failure, NO reference-
%   tool trajectory field (ps.t, TS.t, etc.) is dereferenced afterward. The
%   ran=false status and failure metadata are returned; the caller (report
%   orchestrator) explicitly selects a metadata-validated SAVED artifact.
%
%   MATLAB path safety: the MATLAB path is snapshotted before any PSAT/PGAz
%   addpath and restored on exit (onCleanup), so external PSAT/PGAz paths
%   cannot contaminate the regression suite or test_no_external_solver_dependency.
if nargin<2, scenario=struct(); end
if nargin<3 || isempty(plateau_ci), plateau_ci=8; end
if nargin<4, return_raw=false; end
sc = struct('fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1, ...
    'dt',0.01,'t_end',15.0);
fn = fieldnames(scenario); for k=1:numel(fn), sc.(fn{k})=scenario.(fn{k}); end
root = pf_init_paths;

% --- MATLAB path snapshot (restored on exit, even on PSAT/PGAz throw) -------
path_snapshot = path();
path_cleanup = onCleanup(@() path(path_snapshot)); %#ok<NASGU>

% --- PSAT/PGAz temp-file cleanup (registered as files are created) ----------
temp_files = {};
temp_cleanup = onCleanup(@() remove_temp_files(temp_files)); %#ok<NASGU>

c = cases.(case_name)();
if ~isfield(c,'machines') || isempty(c.machines)
    gbus0 = unique(c.mpc.gen(c.mpc.gen(:,8)~=0,1));
    units = struct('gen_id',num2cell(gbus0),'bus',num2cell(gbus0), ...
        'H',num2cell(5*ones(numel(gbus0),1)),'D',num2cell(zeros(numel(gbus0),1)), ...
        'Xdp',num2cell(0.3*ones(numel(gbus0),1)), ...
        'is_sync_condenser',num2cell(false(numel(gbus0),1)));
    c.machines = struct('units',units);
end
bd = c.bus_data; nb = size(bd,1);
tg = (0:sc.dt:sc.t_end).';   % common comparison grid

% --- Contract: Ybus (Ours vs PGAz, Ours vs PSAT) ---
cc = check_conversion_contract(case_name, sc);
contract_ybus_pgaz = cc.Ybus_max_dY_pgaz < 1e-10;
contract_ybus_psat = cc.Ybus_max_dY_psat < 1e-10;

% --- Ours: production adaptive/event-aware engine ---
opt = struct('t_end',sc.t_end,'dt',sc.dt,'fault_bus',sc.fault_bus, ...
    't_fault',sc.t_fault,'t_clear',sc.t_clear,'Zf',sc.Zf, ...
    'method','trapezoidal','corrector_mode','adaptive', ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8, ...
    'max_corrector_iter',10,'corrector_failure','error', ...
    'pm_mode','balanced','model','classical','verbose',false);
r = stability.ts_simulate(c,opt);
[~,oo] = sort(r.gen_buses);
d_ours = rad2deg(r.delta(:,oo)); w_ours = r.omega(:,oo); pe_ours = r.Pe_MW(:,oo);
gbus_ours = r.gen_buses(oo);
bus_ids_ours = r.pf.external_bus_ids(:);
fi_ours = find(bus_ids_ours==sc.fault_bus,1); v_ours_fault = r.Vbus(:,fi_ours);
ours_nonconv = r.nonconverged_step_count;
ours_completed = (numel(r.t) == numel(tg)) && abs(r.t(end)-tg(end))<1e-9;
ours_pf = r.pf;
Hu = arrayfun(@(b) c.machines.units(find([c.machines.units.bus]==b,1)).H, gbus_ours);
ro = coi_relative(d_ours, w_ours, Hu, gbus_ours);

% --- PSAT (fresh) ---
% Fail-soft: ps is initialized empty; on catch, ps stays empty and psat.ran
% remains false. NO dereference of ps.t after a failed catch.
psat = struct('ran',false,'completed',false,'pf_conv',false,'td_points',NaN, ...
    'failure_metadata', struct('failed',false,'error_id','','error_message','', ...
    'adapter','','attempt_time',''));
ps = []; gbus_ps=[];
try
    if strcmp(case_name,'case_matpower6_case14')
        ps = run_psat_case14(sc);
    else
        pc = rts24_to_psat_case(c,'Zf',sc.Zf,'fault_bus',sc.fault_bus, ...
            't_fault',sc.t_fault,'t_clear',sc.t_clear);
        % Register any temp PSAT case files for cleanup (rts24_to_psat_case
        % may write temp .m files into the PSAT working dir).
        temp_files = register_temp_files(temp_files, pc);
        ps = run_psat_rts24(pc);
    end
    if isfield(ps,'syn_bus') && ~isfield(ps,'delta_bus'), ps.delta_bus = ps.syn_bus; end
    if isfield(ps,'pf_Vm') && ~isfield(ps,'pf_vmag'), ps.pf_vmag = ps.pf_Vm; ps.pf_angle_deg = ps.pf_Va_deg; end
    if ~isfield(ps,'td_points'), ps.td_points = numel(ps.t); end
    psat.ran = ps.pf_conv ~= 0;
    psat.pf_conv = ps.pf_conv ~= 0;
    psat.completed = ~isempty(ps.t) && ps.t(end)>=sc.t_end-1e-6;
    psat.td_points = ps.td_points;
    gbus_ps = sort(ps.delta_bus);
catch e
    warning('PSAT failed: %s', e.message);
    psat.failure_metadata = struct('failed',true, ...
        'error_id',e.identifier,'error_message',e.message, ...
        'adapter','run_psat_case14/run_psat_rts24', ...
        'attempt_time',datestr(now,'yyyy-mm-dd HH:MM:SS'));
    ps = [];   % ensure no downstream dereference of ps.t
end

% --- PGAz (fresh, plateau corrector count) ---
pgaz = struct('ran',false,'completed',false,'corrector_iter',plateau_ci, ...
    'converged',false,'residual_available',false,'nt',NaN, ...
    'failure_metadata', struct('failed',false,'error_id','','error_message','', ...
    'adapter','','attempt_time',''));
TS = []; gbus_pg=[];
try
    sys = case_to_pgaz_sys(c);
    optp = struct(); optp.t_end=sc.t_end; optp.dt=sc.dt; optp.method='trapezoidal';
    optp.corrector_iter=plateau_ci; optp.make_plots=false;
    optp.fault=struct('enable',true,'bus',sc.fault_bus,'t_fault',sc.t_fault, ...
        't_clear',sc.t_clear,'Rf',real(sc.Zf),'Xf',imag(sc.Zf));
    TS = pgaz_ts(sys,1e-10,50,optp);
    pgaz.ran = ~isempty(TS.t);
    pgaz.completed = pgaz.ran && TS.t(end)>=sc.t_end-1e-6;
    pgaz.nt = size(TS.delta_deg,1);
    % PGAz uses a FIXED corrector iteration count with NO convergence residual
    % check (pgaz_ts.m). It is COMPLETED, not "converged" in the residual sense.
    pgaz.converged = false;
    pgaz.residual_available = false;
    gbus_pg = sort(TS.gen_bus);
catch e
    warning('PGAz failed: %s', e.message);
    pgaz.failure_metadata = struct('failed',true, ...
        'error_id',e.identifier,'error_message',e.message, ...
        'adapter','pgaz_ts', ...
        'attempt_time',datestr(now,'yyyy-mm-dd HH:MM:SS'));
    TS = [];   % ensure no downstream dereference of TS.t
end

% --- Time-grid semantics ---
% Safe dereference: only access ps.t / TS.t when the tool ran successfully.
grid = struct();
grid.common_tg = tg;
grid.ours_nt = numel(r.t);
grid.psat_nt = psat.td_points;
grid.pgaz_nt = pgaz.nt;
grid.raw_grid_equal_ours_psat = psat.ran && ~isempty(ps) && isequaln(r.t, ps.t);
grid.raw_grid_equal_ours_pgaz = pgaz.ran && ~isempty(TS) && numel(r.t)==numel(TS.t) && isequaln(r.t, TS.t);
% comparison_grid_valid: common grid monotonic, covers [0,t_end], events on grid
grid.comparison_grid_valid = all(diff(tg)>0) && abs(tg(1))<1e-12 && abs(tg(end)-sc.t_end)<1e-9 ...
    && any(abs(tg-sc.t_fault)<sc.dt/2) && any(abs(tg-sc.t_clear)<sc.dt/2);
% event_grid_valid: t_fault and t_clear present in common grid
grid.event_grid_valid = any(abs(tg-sc.t_fault)<sc.dt/2) && any(abs(tg-sc.t_clear)<sc.dt/2);

% --- Interpolate (NO zero-fill/extrapolation) + sample alignment ---
% Safe: interp_tool guards on isempty(t_raw) internally.
[dps,wps,peps,vps_fault,psat_interp_ok] = interp_tool(safe_t(ps), safe_delta(ps), ...
    safe_omega(ps), safe_pe(ps), safe_vbus(ps), safe_vbus_ids(ps), safe_delta_bus(ps), ...
    tg, sc.fault_bus, @rad2deg, 100);
[dpg,wpg,pepg,vpg_fault,pgaz_interp_ok] = interp_tool(safe_t(TS), safe_delta_deg(TS), ...
    safe_omega(TS), safe_pe_pgaz(TS), safe_vm(TS), [], safe_gen_bus(TS), ...
    tg, sc.fault_bus, @(x)x, 1);
grid.sample_alignment_psat = psat.ran && psat_interp_ok;
grid.sample_alignment_pgaz = pgaz.ran && pgaz_interp_ok;
% extrapolation_used is always false (interp_tool errors instead of extrapolating)
grid.extrapolation_used = false;

psat_map_ok = psat.ran && ~isempty(gbus_ps) && isequal(gbus_ps(:), gbus_ours(:));
pgaz_map_ok = pgaz.ran && ~isempty(gbus_pg) && isequal(gbus_pg(:), gbus_ours(:));

% --- COI frame (inertia-weighted, both angle and speed) ---
drel_p=[]; wrel_p=[]; drel_g=[]; wrel_g=[];
if psat.ran && psat_interp_ok
    rp = coi_relative(dps, wps, Hu, gbus_ps); drel_p=rp.delta_rel; wrel_p=rp.omega_rel;
end
if pgaz.ran && pgaz_interp_ok
    rg = coi_relative(dpg, wpg, Hu, gbus_pg); drel_g=rg.delta_rel; wrel_g=rg.omega_rel;
end

% --- Pairwise TS metrics ---
ts = struct();
ts.ps_ours = pair(drel_p,ro.delta_rel,wrel_p,ro.omega_rel,peps,pe_ours,vps_fault,v_ours_fault,psat.ran&&psat_interp_ok);
ts.pg_ours = pair(drel_g,ro.delta_rel,wrel_g,ro.omega_rel,pepg,pe_ours,vpg_fault,v_ours_fault,pgaz.ran&&pgaz_interp_ok);
ts.ps_pg   = pair(drel_p,drel_g,wrel_p,wrel_g,peps,pepg,vps_fault,vpg_fault,psat.ran&&pgaz.ran&&psat_interp_ok&&pgaz_interp_ok);

% --- Pairwise PF metrics ---
pf = struct();
pf.ps_ours = pf_pair(ps,ours_pf,psat.ran);
pf.pg_ours = pf_pair_pg(TS,ours_pf,pgaz.ran);
pf.ps_pg   = pf_pair_both(ps,TS,psat.ran&&pgaz.ran);

% --- Gates ---
% Tolerances (predeclared, justified a priori):
%  PF: all tools solve the same nonlinear equations -> machine precision.
%  TS converged pairs (PSAT-Ours): both converged trapezoidal at dt=0.01;
%       PSAT-Ours baseline ~0.01 deg -> 0.05 deg is conservative.
%  TS PGAz plateau pair: PGAz plateau (ci=8) is a converged trapezoidal
%       solution at dt=0.01; the SAME justification applies (two converged
%       trapezoidal solutions of the same problem at the same dt must agree
%       to <0.05 deg). NO method-aware relaxation (1.0 deg was unjustified).
TOL = struct();
TOL.pf = struct('dV',1e-6,'dAng',1e-4);
TOL.ts_conv = struct('dCOI',0.05,'domega',1e-4,'dPe',0.1,'dVm',1e-3);
gates = struct();
gates.contract_ybus_pgaz = contract_ybus_pgaz;
gates.contract_ybus_psat = contract_ybus_psat;
gates.gen_mapping_psat = psat_map_ok;
gates.gen_mapping_pgaz = pgaz_map_ok;
gates.comparison_grid_valid = grid.comparison_grid_valid;
gates.event_grid_valid = grid.event_grid_valid;
gates.sample_alignment_psat = grid.sample_alignment_psat;
gates.sample_alignment_pgaz = grid.sample_alignment_pgaz;
gates.extrapolation_used = grid.extrapolation_used;   % must be false
gates.psat_execution = psat.ran && psat.completed && psat.pf_conv;
gates.pgaz_execution = pgaz.ran && pgaz.completed;   % completed, NOT converged
gates.pgaz_plateau = pgaz.ran;   % plateau ci set; full study in artifact
gates.ours_convergence = ours_completed && (ours_nonconv == 0);
gates.psat_comparison = gates.psat_execution && ts_ok(ts.ps_ours,TOL.ts_conv) && pf_ok(pf.ps_ours,TOL.pf);
gates.pgaz_comparison = gates.pgaz_execution && ts_ok(ts.pg_ours,TOL.ts_conv) && pf_ok(pf.pg_ours,TOL.pf);
gates.tol = TOL;
gates.all_gates_pass = all([gates.contract_ybus_psat, ...
    gates.gen_mapping_psat, gates.comparison_grid_valid, ...
    gates.event_grid_valid, gates.sample_alignment_psat, ...
    ~gates.extrapolation_used, gates.psat_execution, ...
    gates.ours_convergence, gates.psat_comparison]);
% PGAz is a SECONDARY DIAGNOSTIC ONLY (Phase B). The PGAz-dependent gates
% below are REPORTED honestly when PGAz runs, but are NOT required for
% all_gates_pass. PSAT is the required cross-validation reference. PGAz
% execution/completion is never a production PF acceptance criterion.
gates.pgaz_status = struct( ...
    'execution',        gates.pgaz_execution, ...
    'plateau',          gates.pgaz_plateau, ...
    'comparison',       gates.pgaz_comparison, ...
    'contract_ybus',    gates.contract_ybus_pgaz, ...
    'gen_mapping',      gates.gen_mapping_pgaz, ...
    'sample_alignment', gates.sample_alignment_pgaz, ...
    'required_for_gate', false);

out = struct('case',case_name,'scenario',sc,'gen_buses',gbus_ours, ...
    'contract',cc,'pf',pf,'ts',ts,'gates',gates,'grid',grid, ...
    'psat',psat,'pgaz',pgaz,'ours_nonconv',ours_nonconv,'ours_completed',ours_completed, ...
    'tol',TOL);

% --- Structured raw-trajectory return (for report generator plotting) -------
% Populated only when return_raw=true. Raw fields are empty for tools that
% did not run (ran=false); failure_metadata is preserved on the psat/pgaz
% structs above. No duplicate mapping/interpolation/metric logic here —
% the generator reuses coi_relative/interp_no_extrapolate on these raw arrays.
if return_raw
    out.raw = struct();
    out.raw.common_tg = tg;
    out.raw.ours = struct('t',r.t,'delta_deg',d_ours,'omega',w_ours, ...
        'Pe_MW',pe_ours,'Vbus_fault',v_ours_fault,'gen_buses',gbus_ours, ...
        'bus_ids',bus_ids_ours,'H',Hu,'fresh',true);
    out.raw.psat = struct('t',safe_t(ps),'delta',safe_delta(ps),'omega',safe_omega(ps), ...
        'Pe_pu',safe_pe(ps),'Vbus',safe_vbus(ps),'vbus_ids',safe_vbus_ids(ps), ...
        'delta_bus',safe_delta_bus(ps),'gen_buses',gbus_ps,'H',Hu, ...
        'fresh',psat.ran,'ran',psat.ran,'failure_metadata',psat.failure_metadata);
    out.raw.pgaz = struct('t',safe_t(TS),'delta_deg',safe_delta_deg(TS), ...
        'omega',safe_omega(TS),'Pe_pu',safe_pe_pgaz(TS),'Vm',safe_vm(TS), ...
        'gen_buses',gbus_pg,'H',Hu,'baseMVA',safe_basemva(TS), ...
        'fresh',pgaz.ran,'ran',pgaz.ran,'failure_metadata',pgaz.failure_metadata);
    out.raw.mappings = struct('gen_buses_ours',gbus_ours, ...
        'gen_buses_psat',gbus_ps,'gen_buses_pgaz',gbus_pg, ...
        'bus_ids_ours',bus_ids_ours,'fault_bus',sc.fault_bus);
    out.raw.status = struct('ours_fresh',true,'psat_fresh',psat.ran, ...
        'pgaz_fresh',pgaz.ran,'psat_failed',psat.failure_metadata.failed, ...
        'pgaz_failed',pgaz.failure_metadata.failed);
end

fprintf('\n=== Three-way validation: %s (fault bus %d, PGAz ci=%d) ===\n', case_name, sc.fault_bus, plateau_ci);
fprintf('Contract Ybus: PGAz %s (%.2e)  PSAT %s (%.2e)\n', gate(contract_ybus_pgaz),cc.Ybus_max_dY_pgaz,gate(contract_ybus_psat),cc.Ybus_max_dY_psat);
fprintf('Gen mapping: PSAT %s  PGAz %s\n', gate(psat_map_ok), gate(pgaz_map_ok));
fprintf('Grid: raw_equal(Ours-PSAT)=%d raw_equal(Ours-PGAz)=%d comparison_valid=%s event_valid=%s align(PSAT)=%s align(PGAz)=%s extrap=%d\n', ...
    grid.raw_grid_equal_ours_psat, grid.raw_grid_equal_ours_pgaz, gate(grid.comparison_grid_valid), gate(grid.event_grid_valid), gate(grid.sample_alignment_psat), gate(grid.sample_alignment_pgaz), grid.extrapolation_used);
fprintf('Execution: PSAT ran=%d completed=%d pf=%d (nt=%g) | PGAz ran=%d completed=%d corrector=%d converged=%d residual_avail=%d (nt=%g) | Ours nonconv=%d completed=%d\n', ...
    psat.ran,psat.completed,psat.pf_conv,psat.td_points, pgaz.ran,pgaz.completed,pgaz.corrector_iter,pgaz.converged,pgaz.residual_available,pgaz.nt, ours_nonconv,ours_completed);
if psat.ran, fprintf('PSAT vs Ours : PF dV=%.3e dAng=%.3e | TS dCOI=%.4f dw=%.3e dPe=%.4f dVm=%.3e\n', pf.ps_ours.dV,pf.ps_ours.dAng,ts.ps_ours.dCOI,ts.ps_ours.domega,ts.ps_ours.dPe,ts.ps_ours.dVm); end
if pgaz.ran, fprintf('PGAz vs Ours : PF dV=%.3e dAng=%.3e | TS dCOI=%.4f dw=%.3e dPe=%.4f dVm=%.3e\n', pf.pg_ours.dV,pf.pg_ours.dAng,ts.pg_ours.dCOI,ts.pg_ours.domega,ts.pg_ours.dPe,ts.pg_ours.dVm); end
if psat.ran&&pgaz.ran, fprintf('PSAT vs PGAz : PF dV=%.3e dAng=%.3e | TS dCOI=%.4f dw=%.3e dPe=%.4f dVm=%.3e\n', pf.ps_pg.dV,pf.ps_pg.dAng,ts.ps_pg.dCOI,ts.ps_pg.domega,ts.ps_pg.dPe,ts.ps_pg.dVm); end
fprintf('GATES: psat_comparison=%s pgaz_comparison=%s | ALL_GATES_PASS=%s\n', gate(gates.psat_comparison), gate(gates.pgaz_comparison), gate(gates.all_gates_pass));
end

% =========================================================================
% Safe accessors: return empty when the reference-tool struct is empty (failed
% or not run), so no downstream code dereferences a missing .t field.
% =========================================================================
function v = safe_t(s)
if isempty(s) || ~isfield(s,'t'), v = []; else, v = s.t; end
end
function v = safe_delta(s)
if isempty(s) || ~isfield(s,'delta'), v = []; else, v = s.delta; end
end
function v = safe_delta_deg(s)
if isempty(s) || ~isfield(s,'delta_deg'), v = []; else, v = s.delta_deg; end
end
function v = safe_omega(s)
if isempty(s) || ~isfield(s,'omega'), v = []; else, v = s.omega; end
end
function v = safe_pe(s)
if isempty(s) || ~isfield(s,'Pe_pu'), v = []; else, v = s.Pe_pu; end
end
function v = safe_pe_pgaz(s)
if isempty(s) || ~isfield(s,'Pe_pu'), v = []; else, v = s.Pe_pu; end
end
function v = safe_vbus(s)
if isempty(s) || ~isfield(s,'Vbus'), v = []; else, v = s.Vbus; end
end
function v = safe_vbus_ids(s)
if isempty(s) || ~isfield(s,'vbus_ids'), v = []; else, v = s.vbus_ids; end
end
function v = safe_delta_bus(s)
if isempty(s) || ~isfield(s,'delta_bus'), v = []; else, v = s.delta_bus; end
end
function v = safe_gen_bus(s)
if isempty(s) || ~isfield(s,'gen_bus'), v = []; else, v = s.gen_bus; end
end
function v = safe_vm(s)
if isempty(s) || ~isfield(s,'Vm'), v = []; else, v = s.Vm; end
end
function v = safe_basemva(s)
if isempty(s) || ~isfield(s,'baseMVA'), v = []; else, v = s.baseMVA; end
end

function files = register_temp_files(files, pc)
% Register temp PSAT case files for onCleanup removal. pc may carry a
% .temp_files field (cell of paths) from rts24_to_psat_case; if so, append.
if isempty(pc), return; end
if isstruct(pc) && isfield(pc,'temp_files') && ~isempty(pc.temp_files)
    files = [files; pc.temp_files];
end
end

function remove_temp_files(files)
% Remove temp PSAT/PGAz case files, ignoring errors (best-effort cleanup).
for i = 1:numel(files)
    if exist(files{i}, 'file')
        try, delete(files{i}); catch, end
    end
end
end

function [d,w,pe,vf,ok] = interp_tool(t_raw, delta_raw, omega_raw, pe_raw, V_raw, vbus_ids, gen_bus, tg, fault_bus, degfun, pe_scale)
% Interpolate raw trajectory onto common grid tg. NO zero-fill/extrapolation:
% if tg extends beyond t_raw, or NaN appears, ok=false (gate fails).
d=[];w=[];pe=[];vf=[];ok=false;
if isempty(t_raw), return; end
% coverage check: common grid must lie within raw grid
if min(t_raw) > min(tg) + 1e-12 || max(t_raw) < max(tg) - 1e-12, return; end
% monotonic check (non-strict ok; interp1 needs strictly increasing -> dedupe)
[tu,ui] = unique(t_raw);
if numel(tu) < 2, return; end
[~,po] = sort(gen_bus);
d  = degfun(interp1(tu, delta_raw(ui,po), tg, 'linear'));
w  = interp1(tu, omega_raw(ui,po), tg, 'linear');
pe = pe_scale * interp1(tu, pe_raw(ui,po), tg, 'linear');
if ~isempty(vbus_ids)
    fi = find(vbus_ids==fault_bus,1);
    vf = interp1(tu, V_raw(ui,fi), tg, 'linear');
else
    vf = interp1(tu, V_raw(ui,fault_bus), tg, 'linear');
end
ok = all(isfinite(d(:))) && all(isfinite(w(:))) && all(isfinite(pe(:))) && all(isfinite(vf(:)));
end

function m = pair(dr1,dr2,wr1,wr2,pe1,pe2,v1,v2,ok)
if ~ok, m=struct('dCOI',NaN,'domega',NaN,'dPe',NaN,'dVm',NaN); return; end
m.dCOI=max(abs(dr1-dr2),[],'all'); m.domega=max(abs(wr1-wr2),[],'all');
m.dPe=max(abs(pe1-pe2),[],'all'); m.dVm=max(abs(v1-v2),[],'all');
end
function p = pf_pair(ps,pf_ours,ok)
if ~ok||isempty(ps), p=struct('dV',NaN,'dAng',NaN); return; end
[~,si]=sort(ps.bus_ids); [~,oi]=sort(pf_ours.external_bus_ids);
p.dV=max(abs(ps.pf_vmag(si)-pf_ours.bus_voltage(oi)));
p.dAng=max(abs(ps.pf_angle_deg(si)-pf_ours.bus_angle_deg(oi)));
end
function p = pf_pair_pg(TS,pf_ours,ok)
if ~ok||isempty(TS), p=struct('dV',NaN,'dAng',NaN); return; end
vpg=TS.Vm(1,:).'; apg=TS.Va_deg(1,:).'; [~,oi]=sort(pf_ours.external_bus_ids);
p.dV=max(abs(vpg-pf_ours.bus_voltage(oi))); p.dAng=max(abs(apg-pf_ours.bus_angle_deg(oi)));
end
function p = pf_pair_both(ps,TS,ok)
if ~ok||isempty(ps)||isempty(TS), p=struct('dV',NaN,'dAng',NaN); return; end
[~,si]=sort(ps.bus_ids);
p.dV=max(abs(ps.pf_vmag(si)-TS.Vm(1,:).')); p.dAng=max(abs(ps.pf_angle_deg(si)-TS.Va_deg(1,:).'));
end
function ok = ts_ok(m,T)
ok = isfinite(m.dCOI) && m.dCOI<=T.dCOI && isfinite(m.domega) && m.domega<=T.domega && ...
     isfinite(m.dPe) && m.dPe<=T.dPe && isfinite(m.dVm) && m.dVm<=T.dVm;
end
function ok = pf_ok(m,T)
ok = isfinite(m.dV) && m.dV<=T.dV && isfinite(m.dAng) && m.dAng<=T.dAng;
end
function s = gate(c), if c, s='PASS'; else, s='FAIL'; end, end
