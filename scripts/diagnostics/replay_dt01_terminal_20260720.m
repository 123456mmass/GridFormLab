function replay_dt01_terminal_20260720()
%REPLAY_DT01_TERMINAL_20260720  Bounded diagnosis of the dt=0.01 stall at
%t=3.25s. Replays the terminal interval from the SAME last-accepted state
%(t=3.24, the last accepted sample before the failure) with several step
%sizes h to classify the root cause:
%  - if a smaller h converges from the SAME state -> step-size / globalization
%    defect (the equations have a solution; dt=0.01 just cannot reach it);
%  - if every h fails from the SAME state -> the equations have no solution
%    at this operating point (physical infeasibility / limiter deadlock);
%  - if the failure mode changes with h (domain throw vs plain stall) ->
%    non-smoothness at the trial boundary.
% Read-only: no production code, equation, parameter, or tolerance changed.
restoredefaultpath; cd(fileparts(fileparts(fileparts(mfilename('fullpath'))))); pf_init_paths;
logdir = fullfile(pwd,'output','diagnostics');
if ~exist(logdir,'dir'), mkdir(logdir); end
fh = fopen(fullfile(logdir,'replay_dt01_terminal_20260720.log'),'w');
if fh < 0, error('replay:cannotOpenLog','cannot open log file'); end
c = onCleanup(@() fclose(fh));

% Run the full dt=0.01 case to capture the last accepted state at t=3.24.
opt = wizard.defaults_for_method('ibr','ieee14_1sg_4ibr');
opt.ibr_analysis = 'ts';
opt.plot_results = false; opt.verbose = false;
opt.ibr_events.Zf = 1i*0.1;
opt.dt = 0.01;
r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);
ts = r; if isfield(r,'ts') && ~isempty(r.ts), ts = r.ts; end
fprintf(fh,'dt=0.01 full run: converged=%d t_end=%.4f samples=%d\n', ...
    ts.converged, ts.t(end), numel(ts.t));
fprintf(fh,'  failure_id=%s\n', getf_str(r,'failure_id'));
fprintf(fh,'  domain_rejected_trials=%g subdivision_depth=%g\n', ...
    getf_num(r,'domain_rejected_trials'), getf_num(r,'subdivision_depth'));

% Last accepted state (t=3.24). The failing step is 3.24 -> 3.25.
x_last = ts.x_traj(:,end);
y_last = ts.y_traj(:,end);
u_last = ts.u_history(:,end);
t_last = ts.t(end);
fprintf(fh,'\nLast accepted state: t=%.6f (failing step -> t+dt)\n', t_last);

% Rebuild the DAE + event_context at the last sample (SG online, initial
% modes; failure is at 3.25 BEFORE sg_trip at 5s). Use the case scenario
% builder so devices match the TS run.
scenario_opt = struct('ibr_profile','rms10_profile_b', ...
    'dispatch', struct('IBR2',40,'IBR3',0,'IBR6',0,'IBR8',0));
scenario = cases.scenario_ieee14_1sg_4ibr(scenario_opt);
case_data = scenario.case_data;
resources = scenario.resources;
[devices, ~] = stability.build_mixed_resource_devices(case_data, resources, struct());
dae = stability.composite_dae(case_data, devices, struct( ...
    'fault_bus', opt.ibr_events.fault_bus, 'Zf', opt.ibr_events.Zf));
ec = struct();
if ~isempty(ts.event_context_history)
    ec = ts.event_context_history{end};
end
Y = dae.topology.Ypre;  % post-clear (fault cleared at 3.1)
active = ts.active_state_history{end};

% Replay the single step t_last -> t_last+h with several h values, using the
% SAME production ts_step_composite path. We cannot easily call the private
% step function with a custom h without the full driver; instead we report
% the residual structure at the predictor endpoint for each h to expose
% non-smoothness / infeasibility.
f0 = dae.dae_f(t_last, x_last, y_last, u_last, ec);
fprintf(fh,'\n== Residual structure at predictor endpoint for various h ==\n');
fprintf(fh,'%-10s %-14s %-14s %-14s %-14s\n','h','max|rx|','max|rg|','rcond(J)','rank');
h_list = [0.01, 0.005, 0.0025, 0.001];
for k = 1:numel(h_list)
    h = h_list(k);
    x_pred = x_last + h*f0;
    y_pred = y_last;
    f1 = dae.dae_f(t_last+h, x_pred, y_pred, u_last, ec);
    g1 = dae.dae_g(t_last+h, x_pred, y_pred, Y, u_last, ec);
    rx = x_pred - x_last - 0.5*h*(f0 + f1);
    rg = g1;
    % FD Jacobian conditioning at the predictor endpoint
    try
        nz = numel(active) + numel(y_last);
        z0 = [x_last(active); y_last];
        resf = @(z) local_residual(z, x_last, f0, h, active, y_last, dae, Y, u_last, ec, t_last+h);
        r0 = resf(z0);
        fd = 3e-6; J = zeros(numel(r0), numel(z0));
        for j = 1:numel(z0)
            zp = z0; zp(j) = zp(j)+fd;
            J(:,j) = (resf(zp)-r0)/fd;
        end
        rc = rcond(J); rk = rank(J);
    catch
        rc = NaN; rk = NaN;
    end
    fprintf(fh,'%-10.5g %-14.3e %-14.3e %-14.3e %-14d\n', ...
        h, max(abs(rx(active))), max(abs(rg)), rc, rk);
end

% Limiter / current status at the last accepted state (non-smoothness source)
fprintf(fh,'\n== IBR limiter / current status at last accepted state ==\n');
for k = 1:numel(dae.devices)
    dev = dae.devices(k);
    if ~startsWith(dev.device_type,'ibr'), continue; end
    off = dae.device_offsets(k); rows = off+1:off+dev.nx;
    try
        rec = dev.reconstruct(t_last, x_last(rows), y_last, [], ec);
        lim = '?'; if isfield(rec,'limiter_active'), lim = mat2str(rec.limiter_active); end
        vc  = '?'; if isfield(rec,'voltage_clamped'), vc = mat2str(rec.voltage_clamped); end
        iabs= NaN; if isfield(rec,'Iabs_inv'), iabs = rec.Iabs_inv; end
        vb  = NaN; if isfield(rec,'Vbus'), vb = rec.Vbus; end
        fprintf(fh,'  %-6s mode=%s  |I|=%.4f  limiter=%s  vclamp=%s  |V|=%.4f\n', ...
            dev.device_id, dev.mode, iabs, lim, vc, vb);
    catch ME
        fprintf(fh,'  %-6s reconstruct failed: %s\n', dev.device_id, ME.identifier);
    end
end
fprintf(fh,'DONE\n');
end

function r = local_residual(z, x0, f0, h, active, yfree, dae, Ynet, u, ec, t1)
na = numel(active);
x1 = x0; x1(active) = z(1:na);
y1 = z(na+1:end);
f1 = dae.dae_f(t1, x1, y1, u, ec);
g1 = dae.dae_g(t1, x1, y1, Ynet, u, ec);
rx = x1 - x0 - 0.5*h*(f0+f1);
r = [rx(active); g1];
end

function v = getf_num(s,f)
v = NaN;
if isfield(s,f) && ~isempty(s.(f)) && isscalar(s.(f)) && isnumeric(s.(f))
    v = s.(f);
end
end

function v = getf_str(s,f)
v = '';
if isfield(s,f) && ~isempty(s.(f)) && ischar(s.(f)), v = s.(f); end
if isfield(s,f) && ~isempty(s.(f)) && isstring(s.(f)), v = char(s.(f)); end
end
