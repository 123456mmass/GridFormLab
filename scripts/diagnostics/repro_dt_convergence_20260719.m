%REPRO_DT_CONVERGENCE_20260719  dt-convergence diagnostic on the FAILING case
%Zf=0.1i, profile-B RMS10. Runs the SAME frozen equations at dt =
%0.01/0.005/0.0025/0.00125 to distinguish a numerical step-size / Newton
%globalization failure from a genuine physical domain violation.
%
% Read-only w.r.t. production code: dt is a caller-supplied option. Every run
% keeps the SAME equations, parameters, tolerances, guard thresholds, and Zf.
% Results appended to output/diagnostics/dt_convergence_20260719.log
%
% Decision criteria (user-directed):
%  - If a smaller dt converges and the trajectory approaches the same physical
%    answer -> numerical step-size / Newton globalization defect; the runtime
%    fix is step rejection + adaptive substepping confined to fault/clear.
%  - If every dt still fails at the SAME physical state -> measure per-device
%    residual (SG, each GFL) and KCL to identify which equation has no
%    solution; only direct evidence of a domain violation / current-limit
%    incompatibility may justify an LVRT requirement.
restoredefaultpath; cd(fileparts(fileparts(fileparts(mfilename('fullpath'))))); pf_init_paths;
logdir = fullfile(pwd,'output','diagnostics');
if ~exist(logdir,'dir'), mkdir(logdir); end
fh = fopen(fullfile(logdir,'dt_convergence_20260719.log'),'w');
if fh < 0, error('repro:cannotOpenLog','cannot open log file'); end
c = onCleanup(@() fclose(fh));

dt_list = [0.01, 0.005, 0.0025, 0.00125];
fprintf(fh,'%-9s %-10s %-9s %-10s %-9s %-9s %-10s %-9s %s\n', ...
    'dt','converged','fail_t','minV@end','SG_I@end','IBR2_I@end','max|V|dev','resid@end','failure_id');
ref_last = [];   % dt=0.005 reference end-state for trajectory-closeness
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
        sgI = NaN; ib2I = NaN; resE = NaN; minV = NaN;
        if isfield(ts,'device_current_magnitude') && ~isempty(ts.device_current_magnitude)
            sgI = ts.device_current_magnitude(1,end);
            ib2I = ts.device_current_magnitude(2,end);
        end
        if isfield(ts,'residual_per_step') && ~isempty(ts.residual_per_step)
            resE = max(abs(ts.residual_per_step));
        end
        vm = abs(complex(ts.y_traj(1:2:end,end), ts.y_traj(2:2:end,end)));
        minV = min(vm);
        if conv
            fprintf(fh,'%-9.5g %-10d %-9s %-10.4f %-9.3f %-9.3f %-10s %-9.2e %s\n', ...
                dt, 1, '-', minV, sgI, ib2I, '-', resE, 'OK');
            if isempty(ref_last) && dt < 0.01
                ref_last = ts.y_traj(:,end);
            end
        else
            ft = NaN; fr = '';
            if isfield(r,'failure_reason'), fr = r.failure_reason; end
            tok = regexp(fr,'t=([\d.e+-]+)','tokens','once');
            if ~isempty(tok), ft = str2double(tok{1}); end
            fprintf(fh,'%-9.5g %-10d %-9.4f %-10.4f %-9.3f %-9.3f %-10s %-9.2e %s\n', ...
                dt, 0, ft, minV, sgI, ib2I, '-', resE, fid);
        end
    catch ME
        fprintf(fh,'%-9.5g ERROR %s: %s\n', dt, ME.identifier, ME.message);
    end
end
fprintf(fh,'DONE\n');
