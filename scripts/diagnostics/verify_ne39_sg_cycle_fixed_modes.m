function report = verify_ne39_sg_cycle_fixed_modes()
%VERIFY_NE39_SG_CYCLE_FIXED_MODES short SG cycle; ไม่ใช่ mode-switch certificate.
pf_init_paths(); rehash;
s = cases.scenario_ne39_1sg_9ibr(struct('study_capability',true, ...
    'initial_modes',struct('device_id','IBR32','mode','gfm')));
e = struct('enabled',true,'event_profile','sg_cycle','sg_trip',.02, ...
    'sg_on',.70,'automatic_gfm_switching',false);
o = struct('t_end',.8,'dt',.0025,'verbose',false,'ibr_events',e, ...
    'automatic_support_supervision',false,'lazy_gfm_search',true, ...
    'sg_on_n_gfm_required',1,'budget',struct('max_full_evaluations',2, ...
    'stop_on_first_certified',true),'online_rate_measurement',true);
timer=tic;
r = stability.run_hybrid_case(s,o);
report = struct('classification','PROJECT_DERIVED_SHORT_FIXED_MODE_DIAGNOSTIC', ...
    'mode_switching_certified',false,'converged',r.converged, ...
    'elapsed_s',toc(timer),'failure_id',r.failure_id,'failure_reason',r.failure_reason, ...
    't_reached_s',NaN,'events',r.event_log,'actual_reclose_time',r.actual_reclose_time, ...
    'reclose_status',r.reclose_status,'min_voltage_pu',NaN,'max_voltage_pu',NaN);
if ~isempty(r.t), report.t_reached_s=r.t(end); end
if ~isempty(r.bus_voltage_magnitude)
    report.min_voltage_pu=min(r.bus_voltage_magnitude,[],'all');
    report.max_voltage_pu=max(r.bus_voltage_magnitude,[],'all');
end
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
out=fullfile(root,'output','diagnostics','ne39_tamu');
if ~isfolder(out), mkdir(out); end
save(fullfile(out,'sg_cycle_fixed_modes.mat'),'r','s','o','report');
fid=fopen(fullfile(out,'sg_cycle_fixed_modes.json'),'w');
if fid<0, error('ne39:reportWrite','เปิดไฟล์รายงานไม่ได้'); end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',jsonencode(report,'PrettyPrint',true));
disp(report);
end
