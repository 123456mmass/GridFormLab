function decompose_stall_residual_20260719()
%DECOMPOSE_STALL_RESIDUAL_20260719  Decompose the stalled trapezoidal residual
%at the failing step (Zf=0.1i, dt=0.01, t~3.24->3.25) into per-device and KCL
%components to identify WHICH equation has no solution / is non-smooth.
%
% Context: verbose trace shows composite_newton stalls at residual=1.811e-04
%with rcond~7e-7 (near-singular), NO domain throw. This is a globalization/
%non-smoothness failure, not a trial-voltage violation. We evaluate the coupled
%residual at the last accepted state and report the largest residual rows by
%owner (SG / GFM IBR2 / each GFL-RMS10 / KCL per bus).
restoredefaultpath; cd(fileparts(fileparts(fileparts(mfilename('fullpath'))))); pf_init_paths;
logdir = fullfile(pwd,'output','diagnostics');
if ~exist(logdir,'dir'), mkdir(logdir); end
fh = fopen(fullfile(logdir,'decompose_stall_residual_20260719.log'),'w');
c = onCleanup(@() fclose(fh));

opt = wizard.defaults_for_method('ibr','ieee14_1sg_4ibr');
opt.ibr_analysis = 'full';
opt.plot_results = false; opt.verbose = false;
opt.ibr_events.Zf = 1i*0.1;
opt.dt = 0.01;
r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);
ts = r.ts;

% Rebuild dae + the exact x0,y0,Y,u,ec at the last accepted sample.
req = wizard.build_request('ibr','ieee14_1sg_4ibr','options',opt);
req = wizard.validate_request(req);
entries = wizard.discover_cases('ibr');
ie = find(strcmp('ieee14_1sg_4ibr',{entries.id}),1);
case_data = entries(ie).loader();
hs = stability.ts_hybrid_state_init(case_data, req.options);
devices = hs.devices;
dae = stability.composite_dae(case_data, devices, struct( ...
    'fault_bus', req.options.ibr_events.fault_bus, 'Zf', req.options.ibr_events.Zf));

x = ts.x_traj(:,end);
y = ts.y_traj(:,end);
u = ts.u_history(:,end);
% ec: reconstruct the event_context at the last sample (SG still online; the
% failure is at 3.25 BEFORE sg_trip at 5s, so all devices online, modes initial).
ec = struct();
if ~isempty(ts.event_context_history)
    ec = ts.event_context_history{end};
end
t0 = ts.t(end);          % 3.24
h  = 0.01;               % the failing step 3.24 -> 3.25
Y  = dae.topology.Ypre;  % post-clear (fault cleared at 3.1)
active = ts.active_state_history{end};

fprintf(fh,'Last accepted t=%.4f, failing step h=%.3f, active states=%d\n', t0, h, numel(active));

% --- Reproduce the coupled trapezoidal residual at the step START (z0) -----
f0 = dae.dae_f(t0, x, y, u, ec);
g0 = dae.dae_g(t0, x, y, Y, u, ec);

% Trapezoidal residual evaluated at the CORRECTED endpoint guess. At the step
% start the initial guess is z0 = [x(active); y] (predictor = hold), so f1=f0.
% But the meaningful residual is at the Newton-stalled point. We don't have the
% stalled z; instead evaluate the residual STRUCTURE at a predictor step using
% an explicit-Euler predicted endpoint to expose which rows dominate.
dt_ = h;
x_pred = x + dt_*f0;   % explicit predictor
y_pred = y;            % hold
f1 = dae.dae_f(t0+h, x_pred, y_pred, u, ec);
g1 = dae.dae_g(t0+h, x_pred, y_pred, Y, u, ec);
rx = x_pred - x - 0.5*h*(f0 + f1);   % differential residual (full)
rg = g1;                              % algebraic residual

fprintf(fh,'\n== Residual magnitudes (explicit-predictor endpoint) ==\n');
fprintf(fh,'max |rx| (differential): %.3e\n', max(abs(rx)));
fprintf(fh,'max |rg| (algebraic KCL): %.3e\n', max(abs(rg)));

% Per-device differential residual via device offsets
fprintf(fh,'\n== Per-device differential residual (max |rx| within device) ==\n');
for k = 1:numel(dae.devices)
    off = dae.device_offsets(k);
    nx = dae.devices(k).nx;
    rows = off+1:off+nx;
    [mx, j] = max(abs(rx(rows)));
    sn = '';
    if isfield(dae.devices(k),'state_names'), sn = dae.devices(k).state_names{j}; end
    fprintf(fh,'  %-6s %-22s nx=%2d  max|rx|=%.3e  state=%s\n', ...
        dae.devices(k).device_id, dae.devices(k).device_type, nx, mx, sn);
end

% KCL residual per bus (Re/Im)
fprintf(fh,'\n== KCL residual per bus (max of |Re|,|Im|) ==\n');
nb = dae.nb; bus_ids = dae.bus_ids;
gR = rg(1:2:end); gI = rg(2:2:end);
[gs, order] = sort(max(abs(gR),abs(gI)), 'descend');
for ii = 1:min(8, nb)
    b = order(ii);
    fprintf(fh,'  bus %-3d  |gRe|=%.3e |gIm|=%.3e\n', bus_ids(b), abs(gR(b)), abs(gI(b)));
end

% Limit / limiter status of each IBR at the last accepted state
fprintf(fh,'\n== IBR limiter / current status at last accepted state ==\n');
for k = 1:numel(dae.devices)
    dev = dae.devices(k);
    if ~startsWith(dev.device_type,'ibr'), continue; end
    off = dae.device_offsets(k); rows = off+1:off+dev.nx;
    try
        rec = dev.reconstruct(t0, x(rows), y, [], ec);
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

% Jacobian conditioning at the step start (FD on the coupled residual)
fprintf(fh,'\n== Jacobian conditioning at step start (coupled residual) ==\n');
try
    nz = numel(active) + numel(y);
    z0 = [x(active); y];
    resf = @(z) local_residual(z, x, f0, h, active, y, dae, Y, u, ec, t0+h);
    r0 = resf(z0);
    fd = 3e-6; J = zeros(numel(r0), numel(z0));
    for j = 1:numel(z0)
        zp = z0; zp(j) = zp(j)+fd;
        J(:,j) = (resf(zp)-r0)/fd;
    end
    fprintf(fh,'  residual size=%d  rcond(J)=%.3e  rank=%d/%d\n', ...
        numel(r0), rcond(J), rank(J), numel(z0));
catch ME
    fprintf(fh,'  Jacobian eval failed: %s\n', ME.message);
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
