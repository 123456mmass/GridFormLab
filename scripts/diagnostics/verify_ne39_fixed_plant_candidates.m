function report = verify_ne39_fixed_plant_candidates()
%VERIFY_NE39_FIXED_PLANT_CANDIDATES ตรวจ steady endpoints แบบจำกัด budget ไม่รับรอง transition.
pf_init_paths();
s = cases.scenario_ne39_1sg_9ibr(struct('study_capability',true));
report = struct('classification','PROJECT_DERIVED_STEADY_DIAGNOSTIC', ...
    'transition_certified',false,'rows',struct([]));
for counts = [0 9;9 1]'
    o = struct('lazy_gfm_search',true, ...
        'sg_on',struct('n_gfm_required',counts(1),'reference_resource_index',1), ...
        'sg_off',struct('n_gfm_required',counts(2)), ...
        'budget',struct('max_full_evaluations',1,'stop_on_first_certified',true), ...
        'certificate',struct('require_physical_evidence',true,'require_dc_reserve',true));
    timer = tic;
    table = stability.ibr_selector_search_lazy(s.case_data,s.resources,s,o);
    elapsed = toc(timer);
    for name = {'sg_on','sg_off'}
        ctx = table.(name{1});
        row = struct('context',name{1},'requested_counts',ctx.counts, ...
            'status',ctx.selection_status,'elapsed_search_s',elapsed, ...
            'reason',ctx.selection_reason,'candidate_reason','', ...
            'KCL_pu',NaN,'zeta_worst',NaN,'omega_rad_s',NaN,'dc_reserve_MW',NaN);
        if ~isempty(ctx.configurations)
            c = ctx.configurations(1);
            row.candidate_reason = c.reason;
            row.KCL_pu = c.physical_kcl_norm;
            row.zeta_worst = c.zeta_worst;
            row.omega_rad_s = c.omega;
            if isfield(c,'dc_reserve_MW'), row.dc_reserve_MW=c.dc_reserve_MW; end
        end
        report.rows = [report.rows;row]; %#ok<AGROW>
    end
end
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
out = fullfile(root,'output','diagnostics','ne39_tamu');
if ~isfolder(out), mkdir(out); end
save(fullfile(out,'fixed_plant_candidates.mat'),'report','s');
fid = fopen(fullfile(out,'fixed_plant_candidates.json'),'w');
if fid<0, error('ne39:reportWrite','เปิดไฟล์รายงานไม่ได้'); end
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',jsonencode(report,'PrettyPrint',true));
disp(struct2table(report.rows));
end
