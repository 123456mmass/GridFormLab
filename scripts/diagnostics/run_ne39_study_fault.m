function summary = run_ne39_study_fault(dt,t_end)
%RUN_NE39_STUDY_FAULT รันทั้งสอง composition พร้อม online accepted-step rates.
% แต่ละ dt มี cache ของตนเอง ไม่ทับการทดลองเดิมและไม่เปิด switching.
arguments
    dt (1,1) double {mustBePositive} = .005
    t_end (1,1) double {mustBePositive} = 1
end
pf_init_paths();
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
out = fullfile(root,'output','diagnostics','ne39_tamu','fault_refinement');
if ~exist(out,'dir'), mkdir(out); end
summary = struct([]);
for ns = [5 1]
    if ns==5
        s = cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
    else
        s = cases.scenario_ne39_1sg_9ibr(struct('study_capability',true));
    end
    e = struct('enabled',true,'event_profile','fault_only','fault_bus',16, ...
        'Zf',1i*.1,'fault_on',.5,'fault_clear',.7,'automatic_gfm_switching',false);
    opt = struct('t_end',t_end,'dt',dt,'verbose',false,'ibr_events',e, ...
        'online_rate_measurement',true);
    tic;
    r = stability.run_hybrid_case(s,opt);
    elapsed = toc;
    if ~r.converged
        error('ne39Study:faultFailed','%s fault-only ไม่ converge',s.scenario_id);
    end
    tag = sprintf('%dsg_%dibr_dt_%g_end_%g',ns,10-ns,dt,t_end);
    save(fullfile(out,[tag '.mat']),'r','s','e','opt','elapsed');
    row = struct('scenario_id',s.scenario_id,'dt_s',dt,'t_end_s',t_end, ...
        'runtime_s',elapsed,'converged',r.converged, ...
        'online_rate_samples',numel(r.online_rate_log), ...
        'max_residual',max(r.accepted_residual_per_step,[],'all'), ...
        'voltage_min',min(r.bus_voltage_magnitude,[],'all'), ...
        'voltage_max',max(r.bus_voltage_magnitude,[],'all'), ...
        'switching_certified',false);
    summary = [summary;row]; %#ok<AGROW>
    fprintf('%s dt=%g: runtime=%.3fs, residual=%.3g, rates=%d\n', ...
        row.scenario_id,dt,elapsed,row.max_residual,row.online_rate_samples);
end
end
