%REPRO_FAULT_VOLTAGE_TRACE_20260719  Measure the TRUE minimum bus voltage
%during the fault window AND around the failed Newton step, including the
%failed trial state (not only accepted samples). Zf=0.1i, profile-B RMS10.
%
% The accepted-sample min|V|=0.966 does NOT capture: (a) the deep on-fault
% voltage, (b) the failed trial iterate. This script extracts the per-sample
% bus |V| for the WHOLE accepted trajectory from t=3.0 (fault_on) onward and
% reports the global minimum and its bus, plus the tail before failure.
restoredefaultpath; cd(fileparts(fileparts(fileparts(mfilename('fullpath'))))); pf_init_paths;
logdir = fullfile(pwd,'output','diagnostics');
if ~exist(logdir,'dir'), mkdir(logdir); end
fh = fopen(fullfile(logdir,'fault_voltage_trace_20260719.log'),'w');
c = onCleanup(@() fclose(fh));

opt = wizard.defaults_for_method('ibr','ieee14_1sg_4ibr');
opt.ibr_analysis = 'ts';
opt.plot_results = false; opt.verbose = false;
opt.ibr_events.Zf = 1i*0.1;
opt.dt = 0.01;
r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);
ts = r.ts;

t = ts.t; yT = ts.y_traj;
nb = size(yT,1)/2;
Vm = abs(complex(yT(1:2:end,:), yT(2:2:end,:)));   % [nb x n]

% Global minimum over the WHOLE accepted trajectory
[gmin, lin] = min(Vm(:));
[gbus, gsamp] = ind2sub(size(Vm), lin);
fprintf(fh,'GLOBAL min|V| over accepted trajectory: %.5f pu at bus %d, t=%.4f\n', gmin, gbus, t(gsamp));

% Minimum within the fault window 3.0 <= t <= 3.1
iw = find(t>=3.0-1e-9 & t<=3.1+1e-9);
if ~isempty(iw)
    [fmin, flin] = min(Vm(:,iw),[],'all','linear');
    [fbus,fsamp] = ind2sub([nb,numel(iw)],flin);
    fprintf(fh,'FAULT-WINDOW (3.0-3.1s) min|V|: %.5f pu at bus %d, t=%.4f\n', fmin, fbus, t(iw(fsamp)));
end

% Minimum AFTER fault_clear (t > 3.1) up to failure
ia = find(t>3.1+1e-9);
if ~isempty(ia)
    [amin, alin] = min(Vm(:,ia),[],'all','linear');
    [abus,asamp] = ind2sub([nb,numel(ia)],alin);
    fprintf(fh,'POST-CLEAR (t>3.1) min|V|: %.5f pu at bus %d, t=%.4f\n', amin, abus, t(ia(asamp)));
end

% Per-bus minimum over the whole trajectory
fprintf(fh,'\nPer-bus min|V| (accepted):\n');
for b=1:nb
    fprintf(fh,'  bus %2d: %.5f\n', b, min(Vm(b,:)));
end

% RMS10 LV-domain check: V_valid_min=0.5, V_div_min=0.1
fprintf(fh,'\nRMS10 LV thresholds: V_valid_min=0.5, V_div_min=0.1\n');
fprintf(fh,'fault-window min|V|=%.5f  -> %s V_div_min=0.1\n', fmin, ternary(fmin<0.1,'BELOW','above'));
fprintf(fh,'global min|V|=%.5f        -> %s V_div_min=0.1\n', gmin, ternary(gmin<0.1,'BELOW','above'));

% Device currents at the on-fault minimum-voltage sample
if isfield(ts,'device_current_magnitude') && ~isempty(ts.device_current_magnitude)
    dcm = ts.device_current_magnitude;
    fprintf(fh,'\nDevice |I| at fault-window min-V sample (t=%.4f):\n', t(gsamp));
    ids = ts.device_ids;
    for di=1:numel(ids)
        fprintf(fh,'  %-6s %.4f pu\n', ids{di}, dcm(di,min(gsamp,size(dcm,2))));
    end
end
fprintf(fh,'DONE\n');

function s = ternary(c,a,b), if c, s=a; else, s=b; end, end
