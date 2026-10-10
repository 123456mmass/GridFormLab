function folder=probe_ne39_inertia_design(composition)
%PROBE_NE39_INERTIA_DESIGN diagnostic sweep ของ IBR เท่านั้น; ไม่ติดตั้ง profile.
arguments
    composition (1,1) string = "5sg_5ibr"
end
root=pf_init_paths();
folder=fullfile(root,'output','diagnostics', ...
    ['ne39_inertia_' char(composition) '_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder);
if composition=="5sg_5ibr"
    s=cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
else
    s=cases.scenario_ne39_1sg_9ibr(struct('study_capability',true));
end
scr=stability.ibr_scr_metrics(s.case_data,s.resources,struct(),struct());
ii=find(strcmp({s.resources.resource_type},'ibr'));
owner=find(strcmp({s.resources.resource_id},'SG31'));
rows={};
% M=2H ใน swing ABI ของ converter. Dv=1/R ที่ R เป็น pu-speed/pu-power.
% H=.25/1/4 s และ R=.05/.02/.01; DC plant, SG, limits และ FD set คงเดิม.
for M=[.5 2 8]
    for Dv=[20 50 100]
        r=s.resources;
        for k=ii
            r(k).dynamic_params.gfm_eecon49.M=M;
            r(k).dynamic_params.gfm_eecon49.Dv=Dv;
        end
        sel=ii;
        cand=struct('selected_gfm_indices',sel,'n_gfm_required',numel(sel), ...
            'reference_resource_index',owner);
        timer=tic;
        c=stability.ibr_candidate_evaluate(s.case_data,r,cand,scr, ...
            s.case_data.selector.gamma_req_rad_per_s,struct('sg_online',true));
        rows{end+1}=struct('M',M,'Dv',Dv,'sg_on',c,'elapsed_s',toc(timer)); %#ok<AGROW>
        fprintf('[NE39-inertia] %s M=%g Dv=%g on feasible=%d zeta=%g omega=%g reason=%s\n', ...
            composition,M,Dv,c.feasible,val(c,'zeta_worst'),val(c,'omega'),c.reason);
        save(fullfile(folder,'sweep.mat'),'s','scr','rows','-v7.3');
    end
end
fprintf('artifact=%s\n',folder);
end
function v=val(s,n)
v=NaN; if isfield(s,n) && ~isempty(s.(n)), v=s.(n); end
end
