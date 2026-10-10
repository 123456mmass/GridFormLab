function report = verify_ne39_study_no_event()
%VERIFY_NE39_STUDY_NO_EVENT รัน production entry บน design assumptions ที่ประกาศ.
% ไม่เปิด switching และไม่ถือว่า no-event ผ่านเป็น transition certificate.
pf_init_paths();
rows = struct([]);
for ns = [5 1]
    if ns==5
        s = cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
    else
        s = cases.scenario_ne39_1sg_9ibr(struct('study_capability',true));
    end
    tic;
    r = stability.run_hybrid_case(s,struct('t_end',.1,'dt',.01, ...
        'verbose',false,'automatic_gfm_switching',false));
    elapsed = toc;
    if ~r.converged
        error('ne39Study:noEvent','%s ไม่ผ่าน no-event production entry',s.scenario_id);
    end
    row = struct('scenario_id',s.scenario_id,'t_end_s',.1,'dt_s',.01, ...
        'runtime_s',elapsed,'converged',r.converged, ...
        'capability_classification',s.case_data.study_capability.classification, ...
        'source_hardware_verified',false,'switching_certified',false, ...
        'state_deviation_max',max(abs(r.x_traj-r.equilibrium.x0),[],'all'), ...
        'voltage_coordinate_deviation_max',max(abs(r.y_traj-r.equilibrium.y0),[],'all'));
    rows = [rows;row]; %#ok<AGROW>
    fprintf('%s: no-event=%d, runtime=%.3fs, dx=%.3g, dy=%.3g\n', ...
        row.scenario_id,row.converged,row.runtime_s,row.state_deviation_max, ...
        row.voltage_coordinate_deviation_max);
end
report = struct('scope','short no-event smoke test only','cases',rows);
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
out = fullfile(root,'output','diagnostics','ne39_tamu');
if ~exist(out,'dir'), mkdir(out); end
fid = fopen(fullfile(out,'study_no_event_verification.json'),'w');
if fid<0, error('ne39Study:write','เขียนผลตรวจไม่ได้'); end
cleanup = onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(report,PrettyPrint=true),'char');
end
