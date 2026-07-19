function instrument_trial_vs_endpoint_20260719()
%INSTRUMENT_TRIAL_VS_ENDPOINT_20260719  Distinguish physical endpoint vs trial
%violation for the Zf=0.1i fault using the FULL accepted trajectory.
% Read-only: runs the SAME production route and only reads accepted samples.
restoredefaultpath; cd(fileparts(fileparts(fileparts(mfilename('fullpath'))))); pf_init_paths;
logdir = fullfile(pwd,'output','diagnostics');
if ~exist(logdir,'dir'), mkdir(logdir); end
fh = fopen(fullfile(logdir,'trial_vs_endpoint_20260719.log'),'w');
c = onCleanup(@() fclose(fh));

opt = wizard.defaults_for_method('ibr','ieee14_1sg_4ibr');
opt.ibr_analysis = 'full';
opt.plot_results = false; opt.verbose = false;
opt.ibr_events.Zf = 1i*0.1;
opt.dt = 0.01;
r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);
ts = r.ts;

t = ts.t; yT = ts.y_traj; bus_ids = ts.bus_ids;
Vm = abs(complex(yT(1:2:end,:), yT(2:2:end,:)));
ibr_buses = [2,3,6,8];
ibr_pos = arrayfun(@(b) find(bus_ids==b,1), ibr_buses);

fprintf(fh,'Accepted samples: %d, last t=%.4f, converged=%d\n', numel(t), t(end), ts.converged);
fprintf(fh,'failure: %s | %s\n\n', char(r.failure_id), char(r.failure_reason));

w_prefault  = t < 3.0-1e-9;
w_fault     = t >= 3.0-1e-9 & t <= 3.1+1e-9;
w_postclear = t > 3.1+1e-9;

fprintf(fh,'Window        accepted-sample voltage minima\n');
report(fh,'pre-fault',  Vm(:,w_prefault),  Vm(ibr_pos,w_prefault),  bus_ids, ibr_buses);
report(fh,'on-fault',   Vm(:,w_fault),     Vm(ibr_pos,w_fault),     bus_ids, ibr_buses);
report(fh,'post-clear', Vm(:,w_postclear), Vm(ibr_pos,w_postclear), bus_ids, ibr_buses);
report(fh,'ALL',        Vm,                Vm(ibr_pos,:),           bus_ids, ibr_buses);

V_div_min = 0.10;
onfault_ibr_min = min(Vm(ibr_pos,w_fault),[],'all');
onfault_gmin    = min(Vm(:,w_fault),[],'all');
fprintf(fh,'\nV_div_min = %.2f (RMS10 balanced-LVRT division floor)\n', V_div_min);
fprintf(fh,'on-fault IBR min|V| = %.5f  below V_div_min? %d\n', onfault_ibr_min, onfault_ibr_min < V_div_min);
fprintf(fh,'on-fault GLOBAL min|V| = %.5f  below V_div_min? %d\n', onfault_gmin, onfault_gmin < V_div_min);

fprintf(fh,'\non-fault per-IBR-bus min|V| (which IBR dips lowest / triggers LVRT):\n');
for k = 1:numel(ibr_buses)
    fprintf(fh,'  bus %d: min|V|=%.5f  |V|@(fault_on)=%.5f  |V|@(clear)=%.5f\n', ...
        ibr_buses(k), min(Vm(ibr_pos(k),w_fault)), Vm(ibr_pos(k),find(w_fault,1)), Vm(ibr_pos(k),find(w_fault,1,'last')));
end

fprintf(fh,'\non-fault samples (t, global min|V|, IBR min|V|, IBR argmin bus, SG|I|, IBR2|I|):\n');
idx = find(w_fault);
dcm = [];
if isfield(ts,'device_current_magnitude') && ~isempty(ts.device_current_magnitude)
    dcm = ts.device_current_magnitude;
end
for j = idx(:).'
    sgI = NaN; ibI = NaN;
    if ~isempty(dcm) && size(dcm,2) >= j
        sgI = dcm(1,j); ibI = dcm(2,j);
    end
    [ibrmin, ibrk] = min(Vm(ibr_pos,j));
    fprintf(fh,'  t=%.3f  gmin=%.4f  ibrmin=%.4f(bus%d)  SG_I=%.3f  IBR2_I=%.3f\n', ...
        t(j), min(Vm(:,j)), ibrmin, ibr_buses(ibrk), sgI, ibI);
end

% Post-clear tail: residual spikes correlate with IBR2 limiter entry/exit?
fprintf(fh,'\npost-clear tail (t, IBR2|I|, IBR2@limit(2.1)?, IBR min|V|):\n');
ip = find(w_postclear);
for j = ip(:).'
    ibI = NaN; if ~isempty(dcm) && size(dcm,2)>=j, ibI = dcm(2,j); end
    fprintf(fh,'  t=%.3f  IBR2_I=%.4f  atlimit=%d  ibrmin=%.4f\n', ...
        t(j), ibI, double(~isnan(ibI)&&ibI>2.09), min(Vm(ibr_pos,j)));
end
fprintf(fh,'DONE\n');
end

function report(fh,name,Gall,Gibr,bus_ids,ibr_buses)
[gmin,k] = min(Gall(:)); [r,~] = ind2sub(size(Gall),k);
[imin,j] = min(Gibr(:)); [ri,~] = ind2sub(size(Gibr),j);
fprintf(fh,'%-14s global min|V|=%.5f (bus %d)  IBR min|V|=%.5f (bus %d)\n', ...
    name, gmin, bus_ids(r), imin, ibr_buses(ri));
end
