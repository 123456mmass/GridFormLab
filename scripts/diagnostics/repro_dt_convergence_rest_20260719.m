%REPRO_DT_CONVERGENCE_REST_20260719  Complete the dt-convergence sweep:
%dt = 0.0025 and 0.00125 on the FAILING Zf=0.1i case. Appends to
%output/diagnostics/dt_convergence_rest_20260719.log
restoredefaultpath; cd(fileparts(fileparts(fileparts(mfilename('fullpath'))))); pf_init_paths;
logdir = fullfile(pwd,'output','diagnostics');
if ~exist(logdir,'dir'), mkdir(logdir); end
fh = fopen(fullfile(logdir,'dt_convergence_rest_20260719.log'),'w');
c = onCleanup(@() fclose(fh));
dt_list = [0.0025, 0.00125];
fprintf(fh,'%-9s %-10s %-9s %-10s %-9s %-9s %s\n','dt','converged','fail_t','minV@end','SG_I@end','IBR2_I@end','failure_id');
for k = 1:numel(dt_list)
    dt = dt_list(k);
    opt = wizard.defaults_for_method('ibr','ieee14_1sg_4ibr');
    opt.ibr_analysis = 'ts';
    opt.plot_results = false; opt.verbose = false;
    opt.ibr_events.Zf = 1i*0.1;
    opt.dt = dt;
    try
        r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);
        ts = r; if isfield(r,'ts') && ~isempty(r.ts), ts = r.ts; end
        conv = ts.converged;
        fid = ''; if isfield(r,'failure_id') && ~isempty(r.failure_id), fid = char(r.failure_id); end
        sgI = NaN; ib2I = NaN; minV = NaN;
        if isfield(ts,'device_current_magnitude') && ~isempty(ts.device_current_magnitude)
            sgI = ts.device_current_magnitude(1,end);
            ib2I = ts.device_current_magnitude(2,end);
        end
        vm = abs(complex(ts.y_traj(1:2:end,end), ts.y_traj(2:2:end,end)));
        minV = min(vm);
        if conv
            fprintf(fh,'%-9.5g %-10d %-9s %-10.4f %-9.3f %-9.3f %s\n', dt, 1, '-', minV, sgI, ib2I, 'OK');
        else
            ft = NaN; fr = '';
            if isfield(r,'failure_reason'), fr = r.failure_reason; end
            tok = regexp(fr,'t=([\d.e+-]+)','tokens','once');
            if ~isempty(tok), ft = str2double(tok{1}); end
            fprintf(fh,'%-9.5g %-10d %-9.4f %-10.4f %-9.3f %-9.3f %s\n', dt, 0, ft, minV, sgI, ib2I, fid);
        end
    catch ME
        fprintf(fh,'%-9.5g ERROR %s: %s\n', dt, ME.identifier, ME.message);
    end
end
fprintf(fh,'DONE\n');
