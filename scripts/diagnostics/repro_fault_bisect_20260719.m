%REPRO_FAULT_BISECT_20260719  Diagnostic-only fault-impedance bisection.
%Read-only w.r.t. production; varies ONLY the case-defined Zf input to map
%the feasible fault-depth domain of the frozen profile-B RMS10 slice.
%Writes incremental results to output/diagnostics/fault_bisect_20260719.log
restoredefaultpath; cd(fileparts(fileparts(fileparts(mfilename('fullpath'))))); pf_init_paths;
logdir = fullfile(pwd,'output','diagnostics');
if ~exist(logdir,'dir'), mkdir(logdir); end
fh = fopen(fullfile(logdir,'fault_bisect_20260719.log'),'w');
if fh < 0, error('repro:cannotOpenLog','cannot open log file'); end
c = onCleanup(@() fclose(fh));
zf_list = [1i*0.1, 1i*0.15, 1i*0.2, 1i*0.3, 1i*0.5, 1i*1.0];
fprintf(fh,'%-10s %-10s %-9s %-10s %-9s %-9s %-9s %s\n', ...
    'Zf','converged','fail_t','minV@end','SG_I@end','IBR2_I@end','resid@end','failure_id');
for k = 1:numel(zf_list)
    opt = wizard.defaults_for_method('ibr','ieee14_1sg_4ibr');
    opt.ibr_analysis = 'ts';
    opt.plot_results = false; opt.verbose = false;
    opt.ibr_events.Zf = zf_list(k);
    try
        r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);
        ts = r; if isfield(r,'ts') && ~isempty(r.ts), ts = r.ts; end
        conv = ts.converged;
        fid = ''; if isfield(r,'failure_id') && ~isempty(r.failure_id), fid = char(r.failure_id); end
        sgI = NaN; ib2I = NaN; resE = NaN;
        if isfield(ts,'device_current_magnitude') && ~isempty(ts.device_current_magnitude)
            sgI = ts.device_current_magnitude(1,end);
            ib2I = ts.device_current_magnitude(2,end);
        end
        if isfield(ts,'residual_per_step') && ~isempty(ts.residual_per_step)
            resE = ts.residual_per_step(end);
        end
        if conv
            fprintf(fh,'%-10s %-10d %-9s %-10s %-9.3f %-9.3f %-9.2e %s\n', ...
                mat2str(zf_list(k)), 1, '-', '-', sgI, ib2I, resE, 'OK');
        else
            ft = NaN; fr = '';
            if isfield(r,'failure_reason'), fr = r.failure_reason; end
            tok = regexp(fr,'t=([\d.e+-]+)','tokens','once');
            if ~isempty(tok), ft = str2double(tok{1}); end
            vm = abs(complex(ts.y_traj(1:2:end,end), ts.y_traj(2:2:end,end)));
            fprintf(fh,'%-10s %-10d %-9.3f %-10.4f %-9.3f %-9.3f %-9.2e %s\n', ...
                mat2str(zf_list(k)), 0, ft, min(vm), sgI, ib2I, resE, fid);
        end
    catch ME
        fprintf(fh,'%-10s ERROR %s: %s\n', mat2str(zf_list(k)), ME.identifier, ME.message);
    end
end
fprintf(fh,'DONE\n');
