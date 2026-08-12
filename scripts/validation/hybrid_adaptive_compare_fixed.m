function out = hybrid_adaptive_compare_fixed(varargin)
%HYBRID_ADAPTIVE_COMPARE_FIXED  Quantify fixed-vs-adaptive agreement (G-COI).
%   OUT = HYBRID_ADAPTIVE_COMPARE_FIXED() runs the switching arm twice --
%   once with the production fixed stepper and once with the opt-in
%   error-controlled stepper -- and reports (a) whether the two runs reach the
%   SAME OPERATIONAL DECISIONS and (b) how far apart their trajectories are.
%
%   This is a VALIDATION script, not an acceptance oracle. The two runs solve
%   the same DAE with different step sequences, so exact agreement is not
%   expected and is not required; what must agree is every discrete decision
%   (event order, reclose/reselection outcome, mode commitments), because those
%   are what the report claims. The trajectory bound below is declared in the
%   adaptive-hybrid plan as ASSUMED_DIAGNOSTIC and is reported, never tuned to
%   whatever the run happens to produce.
%
%   Pre-declared comparison bounds (plan, G-COI):
%       max |Vmag_fixed - Vmag_adaptive|   <= 1e-3 pu
%       max |COI angle difference|         <= 1.0 deg
%
%   Name-value options:
%       't_end'        (default 3.5)  arm horizon in seconds
%       'rtol_x'       (default 1e-4) adaptive differential relative tolerance
%       'dt_max'       (default 0.5)  adaptive coarsening ceiling
%       'save_path'    (default '')   optional .mat destination for both runs
%
%   Returns a struct with the decision comparison, the trajectory metrics, the
%   wall-clock of each run, and a PASS/FAIL verdict per declared bound.

p = inputParser;
p.addParameter('t_end',3.5,@(v)isscalar(v)&&isfinite(v)&&v>0);
p.addParameter('rtol_x',1e-4,@(v)isscalar(v)&&isfinite(v)&&v>0);
p.addParameter('dt_max',0.5,@(v)isscalar(v)&&isfinite(v)&&v>0);
p.addParameter('save_path','',@(v)ischar(v)||isstring(v));
p.parse(varargin{:});
o = p.Results;

% Pre-declared bounds (ASSUMED_DIAGNOSTIC; frozen before the runs).
bound_V   = 1e-3;    % pu
bound_COI = 1.0;     % degrees

pf_init_paths();
[scenario,opt] = build_arm(o.t_end);

fprintf('== fixed ==\n');
tf = tic; r_fix = stability.run_hybrid_case(scenario,opt); wall_fix = toc(tf);
fprintf('converged=%d t(end)=%.4f samples=%d wall=%.1fs\n', ...
    r_fix.converged,last_t(r_fix),numel(r_fix.t),wall_fix);

opt_a = opt;
opt_a.stepper = 'adaptive';
opt_a.atol_x = 1e-6; opt_a.rtol_x = o.rtol_x;
opt_a.atol_y = 1e-5; opt_a.rtol_y = 1e-4;
opt_a.dt_max = o.dt_max; opt_a.dt_max_armed = 0.05;
opt_a.reject_limit = 12;

fprintf('== adaptive ==\n');
ta = tic; r_ad = stability.run_hybrid_case(scenario,opt_a); wall_ad = toc(ta);
fprintf('converged=%d t(end)=%.4f samples=%d wall=%.1fs\n', ...
    r_ad.converged,last_t(r_ad),numel(r_ad.t),wall_ad);

out = struct();
out.wall_fixed = wall_fix;
out.wall_adaptive = wall_ad;
out.speedup = wall_fix/max(wall_ad,eps);
out.samples_fixed = numel(r_fix.t);
out.samples_adaptive = numel(r_ad.t);
out.bound_V = bound_V;
out.bound_COI_deg = bound_COI;

% ---- Decision parity (the gate that actually matters) --------------------
d = struct();
d.converged        = [r_fix.converged, r_ad.converged];
d.reclose_status   = {char(getf(r_fix,'reclose_status','')), ...
                      char(getf(r_ad ,'reclose_status',''))};
d.reclose_time     = [getf(r_fix,'actual_reclose_time',NaN), ...
                      getf(r_ad ,'actual_reclose_time',NaN)];
d.reselection      = {char(getf(r_fix,'reselection_status','')), ...
                      char(getf(r_ad ,'reselection_status',''))};
d.event_types_fixed    = {r_fix.event_log.type};
d.event_types_adaptive = {r_ad.event_log.type};
d.event_times_fixed    = [r_fix.event_log.t];
d.event_times_adaptive = [r_ad.event_log.t];
d.same_converged  = isequal(d.converged(1),d.converged(2));
d.same_reclose    = strcmp(d.reclose_status{1},d.reclose_status{2});
d.same_reselect   = strcmp(d.reselection{1},d.reselection{2});
d.same_event_seq  = isequal(d.event_types_fixed,d.event_types_adaptive) && ...
    numel(d.event_times_fixed)==numel(d.event_times_adaptive) && ...
    all(abs(d.event_times_fixed-d.event_times_adaptive) <= 1e-9);
d.parity_pass = d.same_converged && d.same_reclose && d.same_reselect && ...
    d.same_event_seq;
out.decision = d;

fprintf('\n== decision parity ==\n');
fprintf('converged      fixed=%d  adaptive=%d   %s\n', ...
    d.converged(1),d.converged(2),verdict(d.same_converged));
fprintf('reclose        fixed=%-18s adaptive=%-18s %s\n', ...
    d.reclose_status{1},d.reclose_status{2},verdict(d.same_reclose));
fprintf('reselection    fixed=%-18s adaptive=%-18s %s\n', ...
    d.reselection{1},d.reselection{2},verdict(d.same_reselect));
fprintf('event sequence %d vs %d events                        %s\n', ...
    numel(d.event_types_fixed),numel(d.event_types_adaptive), ...
    verdict(d.same_event_seq));

% ---- Trajectory agreement -------------------------------------------------
out.traj = struct('evaluated',false,'max_dV',NaN,'max_dCOI_deg',NaN, ...
    'V_pass',false,'COI_pass',false);
if r_fix.converged && r_ad.converged
    tc = linspace(0, min(last_t(r_fix),last_t(r_ad)), 400).';
    Vf = interp_matrix(r_fix.t, bus_vmag(r_fix), tc);
    Va = interp_matrix(r_ad.t , bus_vmag(r_ad) , tc);
    out.traj.max_dV = max(abs(Vf(:)-Va(:)));
    out.traj.V_pass = out.traj.max_dV <= bound_V;

    cf = getf(r_fix,'coi_frequency_Hz',[]);
    ca = getf(r_ad ,'coi_frequency_Hz',[]);
    if ~isempty(cf) && ~isempty(ca)
        % Compare the COI frequency deviation directly; the plan's angle bound
        % is reported as the integrated equivalent only when both runs expose
        % an angle series, so the frequency series is the honest primary metric.
        % Event samples share a timestamp (left/right limit), so dedupe before
        % interp1 (which requires strictly unique sample points).
        [tf1,i1] = unique(r_fix.t(:),'stable'); cf1 = cf(:); cf1 = cf1(i1);
        [tf2,i2] = unique(r_ad.t(:) ,'stable'); ca1 = ca(:); ca1 = ca1(i2);
        f1 = interp1(tf1,cf1,tc,'linear','extrap');
        f2 = interp1(tf2,ca1,tc,'linear','extrap');
        out.traj.max_dCOI_Hz = max(abs(f1-f2));
        % Angle proxy: cumulative 360*integral(df) over the compared window.
        dphi = cumtrapz(tc, 360*(f1-f2));
        out.traj.max_dCOI_deg = max(abs(dphi));
        out.traj.COI_pass = out.traj.max_dCOI_deg <= bound_COI;
    end
    out.traj.evaluated = true;

    fprintf('\n== trajectory agreement (400 common times) ==\n');
    fprintf('max |dVmag|      = %.3e pu   (bound %.1e)  %s\n', ...
        out.traj.max_dV,bound_V,verdict(out.traj.V_pass));
    if isfinite(out.traj.max_dCOI_deg)
        fprintf('max |dCOI angle| = %.3e deg  (bound %.1f)   %s\n', ...
            out.traj.max_dCOI_deg,bound_COI,verdict(out.traj.COI_pass));
    end
else
    fprintf('\n== trajectory agreement skipped (a run did not converge) ==\n');
end

fprintf('\n== cost ==\n');
fprintf('wall fixed=%.1fs adaptive=%.1fs speedup=%.2fx  samples %d -> %d\n', ...
    wall_fix,wall_ad,out.speedup,out.samples_fixed,out.samples_adaptive);
if isfield(r_ad,'rejected_steps')
    fprintf('adaptive rejects=%d floor_accepted=%d dt in [%.3e, %.3e]\n', ...
        r_ad.rejected_steps,getf(r_ad,'floor_accepted_steps',NaN), ...
        min(r_ad.dt_history),max(r_ad.dt_history));
end

out.pass = d.parity_pass && (~out.traj.evaluated || ...
    (out.traj.V_pass && (~isfinite(out.traj.max_dCOI_deg) || out.traj.COI_pass)));
fprintf('\nG-COI/G-DECISION-PARITY: %s\n',verdict(out.pass));

if strlength(string(o.save_path))>0
    save(char(o.save_path),'r_fix','r_ad','out','-v7.3');
    fprintf('saved %s\n',char(o.save_path));
end
end

function [scenario,opt] = build_arm(t_end)
sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp", ...
    case_profile="eecon49_figure4", sg_H=2.5, sg_D=1.0, T_d_on=0.10, T_d_off=1.0);
scenario = cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
opt = struct('dt',0.10,'verbose',false,'plot_results',false, ...
    'max_step_subdivisions',9,'state_predictor','linear_kcl', ...
    'automatic_support_supervision',true, ...
    'severity_gamma_on',0.65,'severity_gamma_off',0.35, ...
    'severity_T_d_on',0.10,'severity_T_d_off',1.00, ...
    'healthy_pf_V',sys.pf.bus_voltage(:).', ...
    'healthy_pf_bus_ids',sys.pf.external_bus_ids(:).');
opt.t_end = t_end;
opt.ibr_events = struct('enabled',true,'event_profile','chronology', ...
    'sg_trip',1,'load_step',1.5,'load_step_factor',0.20, ...
    'fault_on',2,'fault_clear',2.15,'fault_bus',9,'Zf',0.01+0.01i, ...
    'line_trip',2.5,'line_from_bus',6,'line_to_bus',13, ...
    'restore_time',3,'sg_on',3,'coordinated_handback',false, ...
    'automatic_gfm_switching',true, ...
    'delays_overrides',struct('timeout_s',20,'dwell_s',0.5));
end

function V = bus_vmag(r)
V = complex(r.y_traj(1:2:end,:), r.y_traj(2:2:end,:));
V = abs(V);
end

function M = interp_matrix(t, X, tc)
% Event samples share a timestamp (left/right limit); interp1 needs strictly
% unique sample points, so collapse duplicates (keeping the first = left limit)
% before interpolating.
[tu,iu] = unique(t(:),'stable');
X = X(:,iu);
M = zeros(size(X,1),numel(tc));
for b = 1:size(X,1)
    M(b,:) = interp1(tu,X(b,:).',tc,'linear','extrap').';
end
end

function t = last_t(r)
if isempty(r.t), t = NaN; else, t = r.t(end); end
end

function s = verdict(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function v = getf(s,f,d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
