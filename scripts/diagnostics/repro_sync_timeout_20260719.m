function repro_sync_timeout_20260719()
%REPRO_SYNC_TIMEOUT_20260719  Read-only reproduction of natural SG-reclose
%SYNC_TIMEOUT on the public IEEE14 1-SG + 4-IBR full-simulation route.
%
% Diagnostic-only script (AGENTS.md: read-only inspection). It changes no
% production state, parameter, tolerance, guard threshold, or event time.
% Defaults come from wizard.defaults_for_method (Profile B RMS10, events on).
%
% Ledger breadcrumbs (already documented, to be re-verified):
%   - Tm-frozen coast: omega_inf = Tm/D ~ 0.164 pu -> df gate (0.001 pu) can
%     never pass after the trip -> 0/501 samples eligible -> SYNC_TIMEOUT.
%   - Frozen thresholds: dV_max=0.05 pu, df_max=1e-3 pu, dtheta_max=10 deg,
%     dwell=0.5 s (synchronism_guard.m:33-36, CASE_DEFINED).

restoredefaultpath;
cd(fileparts(fileparts(fileparts(mfilename('fullpath'))))); % repo root
pf_init_paths;

opt = wizard.defaults_for_method('ibr','ieee14_1sg_4ibr');
opt.ibr_analysis = 'full';
opt.plot_results = false;
opt.verbose = false;
fprintf('Events: enabled=%d fault_on=%.2f fault_clear=%.2f sg_trip=%.2f sg_on=%.2f t_end=%.2f dt=%.3f\n', ...
    opt.ibr_events.enabled, opt.ibr_events.fault_on, opt.ibr_events.fault_clear, ...
    opt.ibr_events.sg_trip, opt.ibr_events.sg_on, opt.t_end, opt.dt);

r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);

% --- Top-level schema dump (read-only) --------------------------------------
fprintf('\n== result schema ==\n');
disp(r);
if isfield(r,'execution_summary'), fprintf('-- execution_summary --\n'); disp(r.execution_summary); end

% --- Failure anatomy (stepNewton) -------------------------------------------
if isfield(r,'failure_id') && ~isempty(r.failure_id)
    fprintf('\n== FAILURE: %s ==\n%s\n', r.failure_id, r.failure_reason);
end
if isfield(r,'ts') && ~isempty(r.ts) && isstruct(r.ts)
    tsf = r.ts;
    fprintf('-- ts product fields --\n'); disp(fieldnames(tsf));
    % Trajectory tails: what did the network/algebraic state look like near death?
    if isfield(tsf,'t') && isfield(tsf,'y_traj')
        tt = tsf.t; yy = tsf.y_traj;
        nb = size(yy,1)/2;
        fprintf('samples recorded: %d, last t=%.4f\n', numel(tt), tt(end));
        ktail = max(1,numel(tt)-8):numel(tt);
        fprintf('\n t       min|V|    argmin bus   max|V|\n');
        for kk = ktail
            vm = abs(complex(yy(1:2:end,kk), yy(2:2:end,kk)));
            [vmin, bmin] = min(vm);
            fprintf('%7.3f  %.5f   bus %-3d      %.5f\n', tt(kk), vmin, bmin, max(vm));
        end
        % Full per-bus snapshot at the final sample
        vmf = abs(complex(yy(1:2:end,end), yy(2:2:end,end)));
        fprintf('\nfinal-sample |V| per bus (1..%d):\n', nb);
        fprintf('%.4f ', vmf); fprintf('\n');
    end
    % residual / iteration history near the end
    if isfield(tsf,'residual_per_step') && ~isempty(tsf.residual_per_step)
        rs = tsf.residual_per_step;
        fprintf('\nresidual tail: '); fprintf('%.2e ', rs(max(1,end-9):end)); fprintf('\n');
    end
    if isfield(tsf,'iter_per_step') && ~isempty(tsf.iter_per_step)
        it = tsf.iter_per_step;
        fprintf('iter tail:     '); fprintf('%d ', it(max(1,end-9):end)); fprintf('\n');
    end
    % device modes / online status at the end
    if isfield(tsf,'status_log') && ~isempty(tsf.status_log)
        sl = tsf.status_log(end);
        fprintf('\n-- last status_log record --\n'); disp(sl);
    end
    % --- Device currents near the failing steps (limiter evidence) ---------
    if isfield(tsf,'device_current_magnitude') && ~isempty(tsf.device_current_magnitude)
        dcm = tsf.device_current_magnitude;   % [n_dev x n_samples] (system base?)
        ids = tsf.device_ids;
        fprintf('\n-- device current magnitude tail (system base pu) --\n');
        fprintf('%-8s', 't'); for di = 1:numel(ids), fprintf('%10s', ids{di}); end; fprintf('\n');
        ktail2 = max(1,numel(tsf.t)-6):numel(tsf.t);
        for kk = ktail2
            fprintf('%8.3f', tsf.t(kk));
            for di = 1:numel(ids)
                v = NaN; if size(dcm,2) >= kk, v = dcm(di,kk); end
                fprintf('%10.4f', v);
            end
            fprintf('\n');
        end
    end
    if isfield(tsf,'device_current_limit_sys') && ~isempty(tsf.device_current_limit_sys)
        fprintf('\n-- device_current_limit_sys --\n'); disp(tsf.device_current_limit_sys);
    end
    if isfield(tsf,'device_modes_history') && ~isempty(tsf.device_modes_history)
        fprintf('\n-- device_modes at final sample --\n');
        mh = tsf.device_modes_history;
        if iscell(mh), disp(mh{end}); else disp(mh(:,end)); end
    end
    if isfield(tsf,'coi_frequency_Hz') && ~isempty(tsf.coi_frequency_Hz)
        cf = tsf.coi_frequency_Hz;
        fprintf('\ncoi_frequency_Hz tail: '); fprintf('%.4f ', cf(max(1,end-9):end)); fprintf('\n');
    end
    if isfield(tsf,'sg_freq') && ~isempty(tsf.sg_freq)
        sf = tsf.sg_freq;
        fprintf('sg_freq_Hz tail:      '); fprintf('%.4f ', sf(max(1,end-9):end)); fprintf('\n');
    end
    % --- Active-state partition tail (bound-locking evidence) --------------
    if isfield(tsf,'active_state_history') && ~isempty(tsf.active_state_history)
        ash = tsf.active_state_history;
        fprintf('\n-- active_state_history: class=%s --\n', class(ash));
        if iscell(ash)
            a0 = ash{1}; aE = ash{end};
            fprintf('first: n=%d  last: n=%d\n', numel(a0), numel(aE));
            if ~isequal(a0,aE)
                fprintf('state indices dropped by final sample: ');
                fprintf('%d ', setdiff(a0,aE)); fprintf('\n');
                fprintf('state indices added by final sample:   ');
                fprintf('%d ', setdiff(aE,a0)); fprintf('\n');
            end
        elseif isnumeric(ash) && ismatrix(ash)
            fprintf('size=%s; unique row-counts over time: ', mat2str(size(ash)));
            u = unique(sum(ash~=0,1));
            fprintf('%s\n', mat2str(u));
        end
    end
    % x_traj tail for GFM IBR2 dynamic-angle states (bound approach evidence)
    if isfield(tsf,'x_traj') && ~isempty(tsf.x_traj)
        xT = tsf.x_traj;
        fprintf('\nx_traj size=%s\n', mat2str(size(xT)));
    end
    if isfield(tsf,'failure_reason')
        fprintf('\nfailure_reason (verbatim): %s\n', tsf.failure_reason);
    end
end

% --- Locate the TS product on the full-analysis route ----------------------
ts = [];
if isfield(r,'ts') && ~isempty(r.ts), ts = r.ts; end
if isempty(ts) && isfield(r,'result'), ts = r.result; end
assert(~isempty(ts),'repro:noTsProduct','No TS product found in result.');

% --- Event log summary (schema-agnostic) -----------------------------------
if isfield(ts,'event_log') && ~isempty(ts.event_log)
    fprintf('\n== event_log (first record field dump) ==\n');
    ev1 = ts.event_log(1);
    if iscell(ts.event_log), ev1 = ts.event_log{1}; end
    disp(ev1);
    fprintf('== event_log records ==\n');
    for k = 1:numel(ts.event_log)
        ev = ts.event_log(k);
        if iscell(ts.event_log), ev = ts.event_log{k}; end
        if ~isstruct(ev), fprintf('%2d <non-struct>\n', k); continue; end
        tv = NaN; if isfield(ev,'time'), tv = ev.time; elseif isfield(ev,'t'), tv = ev.t; end
        tp = '?'; if isfield(ev,'type'), tp = char(string(ev.type)); end
        ap = NaN; if isfield(ev,'applied'), ap = double(ev.applied); end
        fid = ''; if isfield(ev,'failure_id') && ~isempty(ev.failure_id), fid = char(string(ev.failure_id)); end
        det = ''; if isfield(ev,'details'), det = char(string(ev.details)); end
        fprintf('%2d t=%6.2f %-24s applied=%d %s %s\n', k, tv, tp, ap, fid, det);
    end
end

% --- Per-sample resync diagnostics ----------------------------------------
assert(isfield(ts,'resync_diagnostics') && ~isempty(ts.resync_diagnostics), ...
    'repro:noResyncDiag','resync_diagnostics missing on the public route.');
d = ts.resync_diagnostics;
fprintf('\n== resync_diagnostics: %d samples ==\n', numel(d));
elig = [d.eligible];
fprintf('eligible samples: %d / %d\n', nnz(elig), numel(d));

% Gate-wise pass fractions over the monitored window
dV_ok   = [d.margin_V]      >= 0;
df_ok   = [d.margin_f]      >= 0;
dth_ok  = [d.margin_theta]  >= 0;
fprintf('margin_V>=0:     %4d/%4d (max dV       = %.4f pu)\n', nnz(dV_ok),  numel(d), max([d.dV]));
fprintf('margin_f>=0:     %4d/%4d (min |omega|  = %.6f pu)\n', nnz(df_ok),  numel(d), min(abs([d.sg_omega])));
fprintf('margin_theta>=0: %4d/%4d (min dtheta   = %.2f deg)\n', nnz(dth_ok), numel(d), min([d.dtheta]));

% Analytical coast oracle (independent): omega(t) = (Tm/D)(1-exp(-Dt/2H))
i_trip = find([d.t] <= 5.0 + 1e-9, 1, 'last');
if ~isempty(i_trip)
    om0 = d(i_trip).sg_omega; Tm = d(i_trip).Tm;
    H = 5.148; D = 2.0; % Kodsi Table A.2 (CASE_DEFINED); D as per manifest
    om_inf = Tm/D;
    fprintf('\nCoast oracle: omega(t_trip)=%.6e, Tm=%.6f, omega_inf=Tm/D=%.6f pu\n', om0, Tm, om_inf);
    fprintf('Analytic dwell-eligibility: need |omega|<df_max=1e-3 -> t_wait = %.1f s (2H/D*ln(Tm/(D*1e-3)))\n', ...
        (2*H/D)*log(abs(Tm)/(D*1e-3)));
end

% Limiting-gate histogram
gates = string({d.limiting_gate});
fprintf('\nlimiting_gate histogram: V=%d f=%d theta=%d none=%d\n', ...
    nnz(gates=="V"), nnz(gates=="f"), nnz(gates=="theta"), nnz(gates=="none"));

% First/last few records around sg_on=8 s
fprintf('\n t      omega(pu)   dV(pu)   dtheta(deg) elig limiting_gate\n');
for k = 1:numel(d)
    if d(k).t >= 7.98 && d(k).t <= 8.06
        fprintf('%5.2f  %+.6f  %.4f  %8.2f   %d   %s\n', ...
            d(k).t, d(k).sg_omega, d(k).dV, d(k).dtheta, d(k).eligible, d(k).limiting_gate);
    end
end
k_end = numel(d);
fprintf('%5.2f  %+.6f  %.4f  %8.2f   %d   %s   (final)\n', ...
    d(k_end).t, d(k_end).sg_omega, d(k_end).dV, d(k_end).dtheta, d(k_end).eligible, d(k_end).limiting_gate);
end
