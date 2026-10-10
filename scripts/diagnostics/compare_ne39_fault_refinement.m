function report = compare_ne39_fault_refinement()
%COMPARE_NE39_FAULT_REFINEMENT เปรียบเทียบที่เวลาและ side เดียวกัน ไม่ interpolate jumps.
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
out = fullfile(root,'output','diagnostics','ne39_tamu','fault_refinement');
rows = struct([]);
for ns = [5 1]
    stem = sprintf('%dsg_%dibr',ns,10-ns);
    a = load(fullfile(out,[stem '_dt_0.005_end_1.mat']),'r');
    b = load(fullfile(out,[stem '_dt_0.0025_end_1.mat']),'r');
    ra = a.r; rb = b.r; ix = zeros(size(ra.t));
    for j = 1:numel(ra.t)
        candidates = find(abs(rb.t-ra.t(j))<1e-10);
        same = candidates(strcmp(rb.sample_side(candidates),ra.sample_side{j}));
        if isempty(same)
            error('ne39Study:refinementTime','ไม่มีเวลาและ event side ตรงกัน');
        end
        ix(j) = same(end);
    end
    row = struct('scenario_id',sprintf('ne39_%dsg_%dibr',ns,10-ns), ...
        'coarse_dt_s',.005,'fine_dt_s',.0025, ...
        'common_samples',numel(ix), ...
        'max_state_difference',max(abs(ra.x_traj-rb.x_traj(:,ix)),[],'all'), ...
        'max_voltage_coordinate_difference',max(abs(ra.y_traj-rb.y_traj(:,ix)),[],'all'), ...
        'max_voltage_magnitude_difference',max(abs(ra.bus_voltage_magnitude-rb.bus_voltage_magnitude(:,ix)),[],'all'), ...
        'interpretation','two-grid difference only; not converged-order or switching certificate');
    rows = [rows;row]; %#ok<AGROW>
    fprintf('%s: dx=%.3g, dV=%.3g\n',row.scenario_id, ...
        row.max_state_difference,row.max_voltage_magnitude_difference);
end
report = struct('cases',rows);
fid = fopen(fullfile(out,'refinement_comparison.json'),'w');
if fid<0, error('ne39Study:write','เขียนผล refinement ไม่ได้'); end
cleanup = onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(report,PrettyPrint=true),'char');
end
