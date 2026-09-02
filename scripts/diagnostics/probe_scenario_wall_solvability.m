function out = probe_scenario_wall_solvability(varargin)
%PROBE_SCENARIO_WALL_SOLVABILITY Classify a scenario-suite adaptiveDtMin stop.
%
% Three of the four scenarios in run_ieee14_scenario_suite stop before their
% requested horizon with ts_simulate_ibr_hybrid:adaptiveDtMin. Two explanations
% fit that symptom and they call for opposite conclusions:
%
%   H1  PHYSICAL. The island genuinely cannot hold the disturbance -- too little
%       converter capacity behind a bolted fault, or a power deficit after losing
%       a unit -- and the DAE has no solution at the state the run reached.
%   H2  NUMERICAL. A solution exists at that state, but damped Newton with
%       forward-FD columns cannot find it because the trajectory arrived at the
%       current-reference limiter / anti-windup switching surface. This is the
%       wall classified in TS-2026-08-13-03, whose evidence covers only the
%       post-line-trip topology with four grid-forming converters.
%
% The discriminator is the one TS-2026-08-13-03 finding 5 already validated: from
% the EXACT accepted final state and its own topology, replay ONE coupled step at
% decreasing h. Convergence at any h falsifies H1 AT THAT STATE. Sustained
% failure with no state movement, an exhausted line search and a residual that
% tracks h linearly is the H2 signature -- the residual of an iterate the search
% never left.
%
% The reconstruction is self-checked BEFORE anything is read from it: the DAE is
% rebuilt by composite_dae from the case profile, the admittance is rebuilt from
% the sample's own topology_history label, and the accepted sample must satisfy
% KCL on the rebuild. A rebuild that fails that check is refused rather than
% reported, because every number downstream would describe a different system.
%
%   out = probe_scenario_wall_solvability()
%   out = probe_scenario_wall_solvability('scenarios',{'former_outage'})
%   out = probe_scenario_wall_solvability('h',[1e-2 1e-4 1e-6])
%
% Options:
%   scenarios  cache basenames under output/diagnostics/ieee14_scenario_suite
%              (default: the three that stop early)
%   h          step sizes to replay (default: 1e-2 down to 1e-9)
%   cache_dir  where the .mat caches live
%
% Returns one struct per scenario carrying the rebuild residual, the per-h
% replay table, the worst residual row BY NAME, and the current-limit ratios.
%
% What this probe does NOT establish, and must not be read as establishing: that
% the trajectory INTO the wall is healthy. Falsifying H1 at the final accepted
% state says nothing about whether the seconds before it were a collapse. Read
% the P and f_COI traces for that; they are printed here for exactly that reason.
%
% Classification: DIAGNOSTIC over recorded production runs. Nothing computed here
% feeds PF, SSSA, TS, a selector, a controller or an acceptance decision, and no
% production option is changed. The domain-guard control below is diagnostic too:
% production keeps the guard on.
%
% Evidence for: TS-2026-09-03-01. Related: TS-2026-08-13-03, DOC-2026-08-28-02.

p = inputParser;
p.addParameter('scenarios',{'sg_fault_bus9','line_fault_9_14','former_outage'});
p.addParameter('h',[1e-2 5e-3 1e-3 1e-4 1e-5 6.104e-6 1e-6 1e-7 1e-8 1e-9]);
p.addParameter('cache_dir',fullfile('output','diagnostics','ieee14_scenario_suite'));
p.parse(varargin{:});
a = p.Results;

pf_init_paths();
out = struct([]);

for q = 1:numel(a.scenarios)
    nm = char(string(a.scenarios{q}));
    f = fullfile(a.cache_dir,[nm '.mat']);
    fprintf('\n================ %s ================\n',nm);
    if ~isfile(f)
        fprintf('  cache %s absent; skipping.\n',f);
        continue;
    end
    S = load(f,'result');
    r = S.result;

    o = struct('id',nm,'cache',f,'t_wall',r.t(end), ...
        'converged',logical(r.converged), ...
        'failure_id',char(string(getfield_or(r,'failure_id',''))), ...
        'topology','','rebuild_residual',NaN,'reconstructible',false, ...
        'algebraic_converged',false,'h',[],'step_converged',[], ...
        'iterations',[],'residual',[],'max_dx',[],'rcond',[], ...
        'line_search_exhausted',[],'domain_rejected',[], ...
        'worst_row','','h_first_converged',NaN, ...
        'device_ids',{r.device_ids},'current_ratio',[]);

    % --- Rebuild the system the wall sample lived on ----------------------
    scenario = cases.scenario_ieee14_1sg_4ibr( ...
        struct('case_profile','eecon49_figure4'));
    devices = stability.build_mixed_resource_devices(scenario.case_data, ...
        scenario.resources,scenario.scenario_opt);
    dae = stability.composite_dae(scenario.case_data,devices, ...
        struct('load_model','cz_p_cz_q'));

    o.topology = char(string(r.topology_history{end}));
    Y = dae.Ynet;
    switch o.topology
        case 'pre'
            % nothing to add
        case 'fault'
            fp = r.sched.fault_bus_position;
            Y(fp,fp) = Y(fp,fp)+1/r.sched.Zf;
        otherwise
            fprintf(['  topology "%s" is not reconstructible by this probe ' ...
                '(it handles ''pre'' and ''fault''); skipping.\n'],o.topology);
            out = append_struct(out,o);
            continue;
    end

    n  = numel(r.t);
    t0 = r.t(n);
    x0 = r.x_traj(:,n);
    y0 = r.y_traj(:,n);
    u0 = r.u_history(:,n);
    ec = r.event_context_history{n};
    active = r.active_state_history{n};

    o.rebuild_residual = norm(dae.dae_g(t0,x0,y0,Y,u0,ec),inf);
    fprintf('  topology            %s\n',o.topology);
    fprintf('  wall t              %.9f s   (failure %s)\n',t0,o.failure_id);
    fprintf('  active rows         %d of %d states\n',numel(active),numel(x0));
    fprintf('  REBUILD CHECK       |g|inf = %.4g at the accepted sample',o.rebuild_residual);
    if ~(o.rebuild_residual <= 1e-6)
        fprintf('  <-- EXCEEDS kcl_tol, reconstruction rejected\n');
        out = append_struct(out,o);
        continue;
    end
    fprintf('   (ok)\n');
    o.reconstructible = true;

    % --- Is the algebraic subsystem alone solvable here? ------------------
    gh = @(xx,yy,YY) dae.dae_g(t0,xx,yy,YY,u0,ec);
    [ya,ia] = stability.ts_algebraic_solve(x0,y0,Y,gh,@stability.ts_jac_y_fd,1e-6);
    o.algebraic_converged = logical(ia.converged);
    fprintf('  algebraic only      converged=%d iters=%d residual=%.4g\n', ...
        ia.converged,ia.iterations,norm(gh(x0,ya,Y),inf));

    % --- The discriminator ------------------------------------------------
    names = state_name_list(dae);
    step_opt = struct('newton_tol',1e-8,'max_iter',50,'fd_eps',3e-6, ...
        'verbose',false,'full_kcl',true,'t_now',t0, ...
        'domain_preserving_trials',true,'fd_grouping','auto', ...
        'fd_structure_check',false,'fd_perturbation','absolute', ...
        'state_predictor','hold');

    fprintf('  %-10s %-4s %-5s %-11s %-11s %-9s %-6s %-5s %s\n', ...
        'h','cv','iter','residual','max|dx|','rcond','domRej','lsEx','worst row');
    o.h = a.h(:).';
    nh = numel(o.h);
    [o.step_converged,o.iterations,o.residual,o.max_dx,o.rcond, ...
        o.line_search_exhausted,o.domain_rejected] = deal(nan(1,nh));
    for k = 1:nh
        h = o.h(k);
        st = stability.ts_step_composite(x0,y0,h,dae,Y,u0,ec,active,step_opt);
        cv = st.converged && st.finite;
        o.step_converged(k) = cv;
        o.iterations(k) = st.iterations;
        o.residual(k) = st.residual_norm;
        o.max_dx(k) = max(abs(st.x_full-x0));
        o.rcond(k) = st.rcond;
        o.domain_rejected(k) = num_or(st,'domain_rejected_trials',NaN);
        o.line_search_exhausted(k) = ...
            num_or(st.newton_info,'line_search_exhausted',NaN);
        wr = worst_row(st,names);
        if k == 1, o.worst_row = wr; end
        if cv && ~isfinite(o.h_first_converged), o.h_first_converged = h; end
        fprintf('  %-10.4g %-4d %-5d %-11.4g %-11.4g %-9.3g %-6g %-5g %s\n', ...
            h,cv,st.iterations,st.residual_norm,o.max_dx(k),st.rcond, ...
            o.domain_rejected(k),o.line_search_exhausted(k),wr);
    end

    % --- Control: is the domain guard what blocks progress? ---------------
    % If it were, these rows converge where the guarded ones do not. Diagnostic
    % only; the production run keeps the guard on.
    ctrl = step_opt; ctrl.domain_preserving_trials = false;
    fprintf('  -- control: domain_preserving_trials=false --\n');
    for h = a.h(a.h >= 1e-6)
        st = stability.ts_step_composite(x0,y0,h,dae,Y,u0,ec,active,ctrl);
        fprintf('  %-10.4g %-4d %-5d %-11.4g %-11.4g\n',h, ...
            st.converged && st.finite,st.iterations,st.residual_norm, ...
            max(abs(st.x_full-x0)));
    end

    % --- Proximity to the limiter surface, and the trajectory in ----------
    fprintf('  device |I| against its limit at the wall:\n');
    o.current_ratio = nan(1,numel(r.device_ids));
    for d = 1:numel(r.device_ids)
        lim = r.device_current_limit_sys(d,n);
        mag = r.device_current_magnitude(d,n);
        o.current_ratio(d) = mag/max(lim,eps);
        fprintf('   %-6s |I|=%8.5f limit=%8.5f ratio=%7.4f%s\n', ...
            char(string(r.device_ids{d})),mag,lim,o.current_ratio(d), ...
            iif(lim > 0 && mag >= 0.995*lim,'   ON the limiter surface',''));
    end
    % Printed because falsifying H1 at the final state says NOTHING about the
    % seconds before it. A rising P on the survivors with a falling f_COI is a
    % power deficit whatever the solver then does.
    %
    % The window is a fixed SPAN OF TIME, not a fixed number of samples. The last
    % handful of accepted steps sit at the collapsed step size and span only
    % milliseconds, so they read as flat and would hide the very trend this block
    % exists to expose. A rate over the span is printed for the same reason.
    span = 0.5;
    k0 = find(r.t >= t0-span,1);
    if isempty(k0) || k0 == n, k0 = max(1,n-40); end
    dt_win = r.t(n)-r.t(k0);
    fprintf('  trajectory over the last %.3f s (%d samples):\n',dt_win,n-k0+1);
    fc = r.coi_frequency_Hz;
    fprintf('   f_COI  %.4f -> %.4f Hz',fc(k0),fc(n));
    if dt_win > 0
        fprintf('   (%+.3f Hz/s)',(fc(n)-fc(k0))/dt_win);
    end
    fprintf('\n');
    for d = 1:numel(r.device_ids)
        if all(r.device_P_pu(d,k0:n) == 0), continue; end
        fprintf('   %-6s P  %.4f -> %.4f pu',char(string(r.device_ids{d})), ...
            r.device_P_pu(d,k0),r.device_P_pu(d,n));
        if dt_win > 0
            fprintf('   (%+.4f pu/s)', ...
                (r.device_P_pu(d,n)-r.device_P_pu(d,k0))/dt_win);
        end
        fprintf('\n');
    end

    out = append_struct(out,o);
end

if ~isempty(out)
    fprintf('\n--- reading ---\n');
    for k = 1:numel(out)
        o = out(k);
        if ~o.reconstructible
            fprintf('  %-16s NOT CLASSIFIED (rebuild refused)\n',o.id); continue;
        end
        moved = any(o.max_dx(isfinite(o.max_dx)) > 0 & ~o.step_converged);
        fprintf('  %-16s solvable at h=%s | zero-progress signature=%d | worst row %s\n', ...
            o.id,num2str(o.h_first_converged),~moved,o.worst_row);
    end
    fprintf(['  "solvable at h" BELOW the stepper floor 6.104e-6 means a solution\n' ...
        '  exists at the accepted state but the run may not legally step small\n' ...
        '  enough to reach it. It does NOT mean the trajectory into it was healthy.\n']);
end
end

% ==========================================================================
function s = worst_row(st,names)
%WORST_ROW  Name the largest terminal residual row, mapping through the active set.
s = '';
v = [];
if isfield(st,'terminal_residual_vector'), v = st.terminal_residual_vector; end
if isempty(v) || ~isnumeric(v), return; end
[~,i] = max(abs(v(:)));
act = st.active_state_indices(:).';
if i <= numel(act)
    gi = act(i);
    if gi >= 1 && gi <= numel(names)
        s = sprintf('%s (x row %d)',names{gi},gi);
    else
        s = sprintf('x row %d',gi);
    end
else
    s = sprintf('algebraic row %d',i-numel(act));
end
end

function names = state_name_list(dae)
names = {};
for k = 1:numel(dae.devices)
    d = dae.devices(k);
    id = char(string(d.device_id));
    sn = {};
    if isfield(d,'state_names') && ~isempty(d.state_names)
        sn = cellstr(d.state_names);
    end
    for j = 1:numel(sn)
        names{end+1} = sprintf('%s.%s',id,sn{j}); %#ok<AGROW>
    end
end
end

function v = num_or(s,f,d)
v = d;
if isstruct(s) && isfield(s,f) && isscalar(s.(f)) && ...
        (isnumeric(s.(f)) || islogical(s.(f)))
    v = double(s.(f));
end
end

function v = getfield_or(s,f,d)
v = d;
if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); end
end

function s = iif(c,a,b)
if c, s = a; else, s = b; end
end

function A = append_struct(A,s)
if isempty(A), A = s; else, A(end+1) = s; end
end
