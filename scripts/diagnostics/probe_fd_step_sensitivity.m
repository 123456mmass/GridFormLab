function out = probe_fd_step_sensitivity(varargin)
%PROBE_FD_STEP_SENSITIVITY Falsify the two competing explanations for the slow
% Newton convergence in the switched hybrid TS run.
%
% Observation being explained (measured, not inferred): in the 200 s
% production run an accepted half-step leaf needs ~44 Newton iterations and
% the parent full step exhausts max_iter=50. A short sustained-fault
% surrogate reproduces the same growth cheaply: with the fault held, the
% per-step iteration count climbs monotonically (4 -> 19 over 2.5 s at
% dt=0.20) with no subdivision at all.
%
% Competing hypotheses:
%   H1  The FD step is absolute (fd_eps=3e-6) while this repository's own
%       derivation for the coupled Jacobian scales it
%       (6e-6*(1+|v_j|), stability/ts_coupled_jacobian.m:32-51). A badly
%       scaled step leaves truncation error (states much smaller than 1) or
%       cancellation error (states much larger than 1) in the Jacobian, and
%       Newton then converges linearly.
%   H2  The hard current limiter (sat = r>m in gfl_eecon49_full_model.m:111
%       and gfm_eecon49_full_model.m:158) together with conditional_hold
%       anti-windup makes the residual non-smooth, so Newton converges
%       linearly even with an exact Jacobian.
%
% Discriminators produced here, all measured:
%   (a) fd_eps sweep at one recorded stiff state: iterations, terminal
%       residual, rcond. H1 predicts a clear optimum away from 3e-6;
%       H2 predicts a flat profile.
%   (b) the scaled rule h_j = fd_eps*(1+|z_j|) at the same state.
%   (c) the per-iteration Newton trace (residual, alpha, rcond) captured from
%       composite_newton's verbose output. alpha<1 means the line search is
%       rejecting the full Newton step, the H2 signature; alpha==1 with a
%       slow monotone residual decrease is the H1 signature.
%   (d) the magnitude distribution of the unknown vector z, which decides
%       whether an absolute 3e-6 step is relatively large or small.
%
% Read-only with respect to production defaults: every call uses the option
% set the hybrid supervisor builds (ts_simulate_ibr_hybrid.m:189-193) and
% varies only fd_eps / fd_perturbation.
%
% Usage:
%   out = probe_fd_step_sensitivity();
%   out = probe_fd_step_sensitivity('dt',0.20,'t_end',3.0,'Zf',0.05);

p = local_options(varargin{:});
pf_init_paths();
fprintf('PROBE_FD_STEP start tag=%s dt=%.3f t_end=%.3f Zf=%.4gi bus=%d\n', ...
    p.tag, p.dt, p.t_end, p.Zf, p.fault_bus);

scen = cases.scenario_ieee14_1sg_4ibr();
[devices0,~] = stability.build_mixed_resource_devices( ...
    scen.case_data, scen.resources, scen.scenario_opt);
eq = stability.mixed_equilibrium_solve(scen.case_data, ...
    struct('devices',devices0), struct('verbose',false));
if ~eq.converged
    error('probe_fd_step_sensitivity:equilibrium', ...
        'Mixed equilibrium did not converge: %s', eq.failure_reason);
end
dae = stability.composite_dae(scen.case_data, eq.devices, ...
    struct('load_model','cz_p_cz_q'));

% --- Stage 1: drive the case into the sustained current-limited transient --
ev = struct('enabled',true,'fault_bus',p.fault_bus,'Zf',1i*p.Zf, ...
    'fault_on',p.fault_on,'fault_clear',p.t_end, ...
    'sg_trip',NaN,'sg_on',NaN,'selected_gfm_indices',2:5, ...
    'reference_resource_index',2,'event_profile','fault_only');
sched = stability.ibr_event_schedule(scen.case_data,eq.devices,ev,p.t_end,p.dt);
run_opt = struct('t_end',p.t_end,'dt',p.dt,'verbose',false, ...
    'load_model','cz_p_cz_q','u_eq',eq.u_eq, ...
    'event_context',eq.equilibrium_context, ...
    'dynamic_state_indices',eq.dynamic_state_indices,'full_kcl',true, ...
    'ibr_event_schedule',sched,'max_step_subdivisions',4);
t_run = tic;
[r,~] = stability.ts_simulate_ibr_hybrid(scen.case_data,eq.devices, ...
    eq.x0,eq.y0,run_opt);
wall_run = toc(t_run);
if ~r.converged
    error('probe_fd_step_sensitivity:driveRun', ...
        'Surrogate drive run failed: %s', r.failure_reason);
end
fprintf(['STAGE1 wall=%.2f s steps=%d attempts=%d depth=%d ' ...
    'iters=%d first=%d last=%d\n'], wall_run, r.accepted_steps, ...
    r.step_attempts, r.subdivision_depth, sum(r.iter_per_step), ...
    r.iter_per_step(1), r.iter_per_step(end));
fprintf('STAGE1 iter_per_step = %s\n', mat2str(r.iter_per_step));

% --- Stage 2: select the stiffest recorded sample inside the fault ---------
topo = r.Y_log(:)';
if ~iscell(topo), topo = {}; end
in_fault = cellfun(@(s) ischar(s) && strcmpi(s,'fault'), topo);
idx = find(in_fault);
if isempty(idx)
    error('probe_fd_step_sensitivity:noFaultSample', ...
        'No published sample carries the fault topology label.');
end
k = idx(end);
x_k = r.x_traj(:,k);
y_k = r.y_traj(:,k);
u_k = r.u_history(:,k);
ec_k = r.event_context_history{k};
act_k = r.active_state_history{k};
Yf = dae.Ynet;
fp = sched.fault_bus_position;
Yf(fp,fp) = Yf(fp,fp)+1/sched.Zf;
fprintf('STAGE2 sample k=%d t=%.4f side=%s topology=%s n_active=%d ny=%d\n', ...
    k, r.t(k), r.sample_side{k}, topo{k}, numel(act_k), numel(y_k));

% --- Stage 3: option set identical to the supervisor's, fd_eps varied ------
base_step_opt = struct('newton_tol',1e-8,'max_iter',50,'fd_eps',3e-6, ...
    'verbose',false,'full_kcl',true,'t_now',r.t(k), ...
    'domain_preserving_trials',true,'state_predictor','hold');

nsw = numel(p.eps_list);
sweep = struct('fd_eps',num2cell(p.eps_list(:)'),'mode',[], ...
    'iterations',[],'residual',[],'rcond',[],'converged',[],'wall',[]);
for j = 1:nsw
    so = base_step_opt;
    so.fd_eps = p.eps_list(j);
    sweep(j) = local_measure(so,'absolute',x_k,y_k,p.dt,dae,Yf,u_k,ec_k,act_k);
end
scaled = struct([]);
for j = 1:numel(p.scaled_list)
    so = base_step_opt;
    so.fd_eps = p.scaled_list(j);
    so.fd_perturbation = 'scaled';
    m = local_measure(so,'scaled',x_k,y_k,p.dt,dae,Yf,u_k,ec_k,act_k);
    if isempty(scaled), scaled = m; else, scaled(end+1) = m; end %#ok<AGROW>
end

fprintf('\nFD STEP SWEEP at t=%.4f (h=%.3f)\n', r.t(k), p.dt);
fprintf('%-10s %-9s %6s %12s %12s %6s %8s\n', ...
    'rule','fd_eps','iters','residual','rcond','conv','wall_s');
all_rows = [sweep(:)', scaled(:)'];
for j = 1:numel(all_rows)
    a = all_rows(j);
    fprintf('%-10s %-9.3g %6d %12.4e %12.4e %6d %8.3f\n', ...
        a.mode, a.fd_eps, a.iterations, a.residual, a.rcond, ...
        a.converged, a.wall);
end

% --- Stage 4: per-iteration Newton trace at the default and best steps -----
[~,best_abs] = min([sweep.iterations]);
trace_specs = {struct('mode','absolute','fd_eps',3e-6), ...
    struct('mode','absolute','fd_eps',sweep(best_abs).fd_eps)};
if ~isempty(scaled)
    [~,best_sc] = min([scaled.iterations]);
    trace_specs{end+1} = struct('mode','scaled','fd_eps',scaled(best_sc).fd_eps);
end
traces = struct([]);
for j = 1:numel(trace_specs)
    spec = trace_specs{j};
    so = base_step_opt;
    so.fd_eps = spec.fd_eps;
    so.verbose = true;
    if strcmp(spec.mode,'scaled'), so.fd_perturbation = 'scaled'; end
    txt = evalc(['stability.ts_step_composite(x_k,y_k,p.dt,dae,Yf,u_k,' ...
        'ec_k,act_k,so);']);
    tr = local_parse_trace(txt);
    tr.mode = spec.mode;
    tr.fd_eps = spec.fd_eps;
    if isempty(traces), traces = tr; else, traces(end+1) = tr; end %#ok<AGROW>
    fprintf('\nNEWTON TRACE rule=%s fd_eps=%.3g  (%d iterations)\n', ...
        spec.mode, spec.fd_eps, numel(tr.residual));
    fprintf('%5s %12s %8s %12s %10s\n','iter','residual','alpha','rcond','ratio');
    for m = 1:numel(tr.residual)
        if m == 1
            ratio = NaN;
        else
            ratio = tr.residual(m)/tr.residual(m-1);
        end
        fprintf('%5d %12.4e %8.4f %12.4e %10.4f\n', ...
            tr.iter(m), tr.residual(m), tr.alpha(m), tr.rcond(m), ratio);
    end
    if numel(tr.residual) >= 2
        ratios = tr.residual(2:end)./tr.residual(1:end-1);
    else
        ratios = NaN;
    end
    fprintf('  full-step fraction (alpha==1): %.3f   median ratio: %.4f\n', ...
        mean(tr.alpha==1), median(ratios));
end

% --- Stage 5: magnitude distribution of the unknown vector ----------------
z_k = [x_k(act_k(:)); y_k];
az = abs(z_k);
fprintf('\nUNKNOWN MAGNITUDES nz=%d\n', numel(z_k));
fprintf(['  |z|: min=%.3e p25=%.3e median=%.3e p75=%.3e max=%.3e\n' ...
    '  |z|<1e-3: %d   |z|>1e1: %d   3e-6/(1+|z|) span: [%.2e, %.2e]\n'], ...
    min(az), prctile_local(az,25), median(az), prctile_local(az,75), ...
    max(az), sum(az<1e-3), sum(az>10), ...
    3e-6/(1+max(az)), 3e-6/(1+min(az)));

% --- Stage 6: how far does the ACCEPTED point move when the Jacobian rule --
% changes? This is the number that decides whether any Jacobian-side change
% (analytic network block, scaled FD step, column grouping across a
% non-exact boundary) can stay inside a declared trajectory budget. Both
% solves stop at the same newton_tol, so the difference is the tolerance
% ball, not a modelling difference.
ref_opt = base_step_opt;
ref_step = stability.ts_step_composite(x_k,y_k,p.dt,dae,Yf,u_k,ec_k,act_k,ref_opt);
accept = struct([]);
alt_specs = {struct('mode','absolute','fd_eps',1e-6), ...
    struct('mode','absolute','fd_eps',1e-5), ...
    struct('mode','absolute','fd_eps',1e-9), ...
    struct('mode','scaled','fd_eps',3e-6), ...
    struct('mode','scaled','fd_eps',6e-6)};
fprintf('\nACCEPTED-POINT SENSITIVITY (reference: absolute fd_eps=3e-6)\n');
fprintf('%-10s %-9s %6s %12s %12s %12s\n', ...
    'rule','fd_eps','iters','residual','max|dx|','max|dy|');
fprintf('%-10s %-9.3g %6d %12.4e %12s %12s\n','absolute',3e-6, ...
    ref_step.iterations,ref_step.residual_norm,'--','--');
for j = 1:numel(alt_specs)
    spec = alt_specs{j};
    so = base_step_opt;
    so.fd_eps = spec.fd_eps;
    if strcmp(spec.mode,'scaled'), so.fd_perturbation = 'scaled'; end
    st = stability.ts_step_composite(x_k,y_k,p.dt,dae,Yf,u_k,ec_k,act_k,so);
    dx = max(abs(st.x_full-ref_step.x_full));
    dy = max(abs(st.y_full-ref_step.y_full));
    rec = struct('mode',spec.mode,'fd_eps',spec.fd_eps, ...
        'iterations',st.iterations,'residual',st.residual_norm, ...
        'max_dx',dx,'max_dy',dy);
    if isempty(accept), accept = rec; else, accept(end+1) = rec; end %#ok<AGROW>
    fprintf('%-10s %-9.3g %6d %12.4e %12.4e %12.4e\n', ...
        spec.mode,spec.fd_eps,st.iterations,st.residual_norm,dx,dy);
end

% --- Stage 7: does the INITIAL GUESS explain the crawl? -------------------
% The trace shows the line search rejecting the full Newton step for most of
% the solve, then converging quadratically in 4-5 iterations once alpha=1 is
% accepted. That is a starting-point/smoothness signature, not a Jacobian
% signature. state_predictor is an already-audited option of the same kernel
% (ts_step_composite.m: hold | explicit_euler | explicit_euler_kcl |
% linear_kcl), so its effect on iteration count and on the accepted point is
% directly measurable here.
pred_list = {'hold','explicit_euler','explicit_euler_kcl'};
predictors = struct([]);
fprintf('\nPREDICTOR SENSITIVITY (reference: hold, absolute fd_eps=3e-6)\n');
fprintf('%-20s %6s %12s %12s %12s %8s\n', ...
    'state_predictor','iters','residual','max|dx|','max|dy|','alpha1');
for j = 1:numel(pred_list)
    so = base_step_opt;
    so.state_predictor = pred_list{j};
    st = stability.ts_step_composite(x_k,y_k,p.dt,dae,Yf,u_k,ec_k,act_k,so);
    so.verbose = true;
    txt = evalc(['stability.ts_step_composite(x_k,y_k,p.dt,dae,Yf,u_k,' ...
        'ec_k,act_k,so);']);
    tr = local_parse_trace(txt);
    dx = max(abs(st.x_full-ref_step.x_full));
    dy = max(abs(st.y_full-ref_step.y_full));
    rec = struct('state_predictor',pred_list{j},'iterations',st.iterations, ...
        'residual',st.residual_norm,'max_dx',dx,'max_dy',dy, ...
        'alpha_full_fraction',mean(tr.alpha==1),'converged', ...
        double(st.converged&&st.finite));
    if isempty(predictors), predictors = rec; else, predictors(end+1) = rec; end %#ok<AGROW>
    fprintf('%-20s %6d %12.4e %12.4e %12.4e %8.3f\n', ...
        pred_list{j},st.iterations,st.residual_norm,dx,dy,mean(tr.alpha==1));
end

% --- Stage 8: iteration count versus the step length ----------------------
fprintf('\nSTEP-LENGTH SENSITIVITY (state fixed, absolute fd_eps=3e-6)\n');
fprintf('%8s %6s %12s\n','h','iters','residual');
hsweep = struct([]);
for hh = p.h_list
    so = base_step_opt;
    st = stability.ts_step_composite(x_k,y_k,hh,dae,Yf,u_k,ec_k,act_k,so);
    rec = struct('h',hh,'iterations',st.iterations, ...
        'residual',st.residual_norm,'converged',double(st.converged&&st.finite));
    if isempty(hsweep), hsweep = rec; else, hsweep(end+1) = rec; end %#ok<AGROW>
    fprintf('%8.4f %6d %12.4e\n',hh,st.iterations,st.residual_norm);
end

out = struct('tag',p.tag,'options',p,'sample_index',k,'t_sample',r.t(k), ...
    'sweep',sweep,'scaled',scaled,'traces',traces,'accept',accept, ...
    'predictors',predictors,'hsweep',hsweep, ...
    'state',struct('x',x_k,'y',y_k,'u',u_k,'active',act_k, ...
        'event_context',ec_k,'Ynet',Yf,'h',p.dt), ...
    'drive_iter_per_step',r.iter_per_step,'drive_wall_s',wall_run, ...
    'z_abs_summary',struct('min',min(az),'median',median(az),'max',max(az), ...
        'n_small',sum(az<1e-3),'n_large',sum(az>10)));
if ~isempty(p.save_dir)
    if ~isfolder(p.save_dir), mkdir(p.save_dir); end
    fn = fullfile(p.save_dir,sprintf('fd_step_probe_%s.mat',p.tag));
    save(fn,'out','-v7.3');
    fprintf('\nSAVED %s\n', fn);
end
fprintf('PROBE_FD_STEP done\n');
end

% =========================================================================
function p = local_options(varargin)
p = struct('dt',0.20,'t_end',3.0,'Zf',0.05,'fault_bus',4,'fault_on',0.5, ...
    'eps_list',[1e-9 1e-8 1e-7 1e-6 3e-6 1e-5 3e-5 1e-4 1e-3], ...
    'scaled_list',[1e-7 1e-6 3e-6 6e-6 1e-5], ...
    'h_list',[0.2 0.1 0.05 0.025 0.0125], ...
    'tag','fd1','save_dir',fullfile('output','diagnostics'));
if numel(varargin)==1 && isstruct(varargin{1})
    given = varargin{1};
    names = fieldnames(given);
    for k = 1:numel(names), p.(names{k}) = given.(names{k}); end
    return;
end
if mod(numel(varargin),2)~=0
    error('probe_fd_step_sensitivity:badArgs','Expected name/value pairs.');
end
for k = 1:2:numel(varargin)
    p.(char(varargin{k})) = varargin{k+1};
end
end

% =========================================================================
function m = local_measure(step_opt,mode,x0,y0,h,dae,Ynet,u,ec,active)
%LOCAL_MEASURE One coupled step from the recorded state, timed.
tw = tic;
step = stability.ts_step_composite(x0,y0,h,dae,Ynet,u,ec,active,step_opt);
w = toc(tw);
m = struct('fd_eps',step_opt.fd_eps,'mode',mode, ...
    'iterations',step.iterations,'residual',step.residual_norm, ...
    'rcond',step.rcond,'converged',double(step.converged&&step.finite), ...
    'wall',w);
end

% =========================================================================
function tr = local_parse_trace(txt)
%LOCAL_PARSE_TRACE Read composite_newton's verbose per-iteration lines.
%   Line format (composite_newton.m):
%   '  composite_newton iter %d: residual=%.3e alpha=%.3f rcond=%.3e'
tok = regexp(txt, ...
    'composite_newton iter (\d+): residual=([^\s]+) alpha=([^\s]+) rcond=([^\s]+)', ...
    'tokens');
n = numel(tok);
tr = struct('iter',zeros(1,n),'residual',zeros(1,n),'alpha',zeros(1,n), ...
    'rcond',zeros(1,n),'mode','','fd_eps',NaN);
for k = 1:n
    tr.iter(k) = str2double(tok{k}{1});
    tr.residual(k) = str2double(tok{k}{2});
    tr.alpha(k) = str2double(tok{k}{3});
    tr.rcond(k) = str2double(tok{k}{4});
end
end

% =========================================================================
function v = prctile_local(a,q)
%PRCTILE_LOCAL Nearest-rank percentile (no Statistics Toolbox dependency).
a = sort(a(:));
if isempty(a), v = NaN; return; end
idx = max(1,min(numel(a),ceil(q/100*numel(a))));
v = a(idx);
end
