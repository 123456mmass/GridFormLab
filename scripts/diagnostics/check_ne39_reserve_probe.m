function report = check_ne39_reserve_probe()
%CHECK_NE39_RESERVE_PROBE ตรวจตัวเลข reserve จริงของทั้งสอง composition.
% 1. P0 ของ SG31 และ headroom IBR ต่อ composition
% 2. post_trip dispatch ที่ ne39_study_capability แจกจริง (proportional)
% 3. ทดสอบรวม deficit ซ้ำ: pre_fault ของ reference GFM หลัง trip
% ผลลัพธ์เขียน JSON ที่ output/diagnostics/ne39_tamu/reserve_probe.json
pf_init_paths();
rows = struct([]);
for ns = [5 1]
    if ns==5
        s = cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
    else
        s = cases.scenario_ne39_1sg_9ibr(struct('study_capability',true));
    end
    dc = s.case_data.dispatch_contract;
    post = dc.post_trip;
    names = fieldnames(dc.pre_fault);
    pre = zeros(1,numel(names));
    for k=1:numel(names), pre(k)=dc.pre_fault.(names{k}); end
    row = struct('composition',s.scenario_id, ...
        'sg_buses',s.case_data.sg_buses(:).', ...
        'pre_fault_MW',pre, ...
        'pmax_MW',structfun(@(v)v,dc.pmax_MW), ...
        'post_trip_sg_ids',{{string(post.sg_ids)}}, ...
        'post_trip_remaining_sg_ids',{{}}, ...
        'post_trip_Pg_MW_total',0, ...
        'deficit_MW',0, ...
        'headroom_sum_MW',0, ...
        'headroom_enough',false);
    if isfield(post,'remaining_sg_ids')
        row.post_trip_remaining_sg_ids = {string(post.remaining_sg_ids)};
    end
    row.post_trip_sg_ids = string(post.sg_ids);
    if isfield(post,'remaining_sg_ids')
        row.post_trip_remaining_sg_ids = string(post.remaining_sg_ids);
    end
    row.deficit_MW = post.deficit_MW;
    if isfield(post,'post_trip_Pg_MW')
        row.post_trip_Pg_MW_total = sum(structfun(@(v)v,post.post_trip_Pg_MW));
    end
    % headroom รวมของ IBR = sum(Pmax-P0)
    ibr_ids = {s.resources(strcmpi({s.resources.resource_type},'ibr')).resource_id};
    hr = 0;
    for k=1:numel(ibr_ids)
        id = ibr_ids{k};
        hr = hr + (dc.pmax_MW.(id) - dc.pre_fault.(id));
    end
    row.headroom_sum_MW = hr;
    row.headroom_enough = (hr >= post.deficit_MW);
    rows = [rows;row]; %#ok<AGROW>
    fprintf('%s: deficit=%.4f MW, IBR headroom=%.4f MW, enough=%d\n', ...
        s.scenario_id,post.deficit_MW,hr,hr>=post.deficit_MW);
    rem_txt = ''; if isfield(post,'remaining_sg_ids') && ~isempty(post.remaining_sg_ids), ...
            rem_txt = strjoin(cellstr(string(post.remaining_sg_ids)),','); end
    fprintf('  post_trip_sg_ids=%s remaining_sg=%s post_Pg_total=%.4f MW\n', ...
        strjoin(cellstr(string(post.sg_ids)),','), rem_txt, ...
        row.post_trip_Pg_MW_total);
    pre_txt = cellstr(names); for k=1:numel(pre_txt), pre_txt{k}=sprintf('%s=%.2f',pre_txt{k},pre(k)); end
    fprintf('  pre_fault: %s\n', strjoin(pre_txt,', '));
end
report = struct('scope','read-only reserve probe; no gate changed','cases',rows);
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
out = fullfile(root,'output','diagnostics','ne39_tamu');
if ~exist(out,'dir'), mkdir(out); end
fid = fopen(fullfile(out,'reserve_probe.json'),'w');
if fid<0, error('ne39Reserve:write','เขียนผลตรวจไม่ได้'); end
cleanup = onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(report,PrettyPrint=true),'char');
end
