function folder=probe_ne39_controller_profile()
%PROBE_NE39_CONTROLLER_PROFILE เปลี่ยนเฉพาะ IBR controller; SG/DC/limits คงเดิม.
root=pf_init_paths();
folder=fullfile(root,'output','diagnostics', ...
    ['ne39_controller_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder);
s=cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
scr=stability.ibr_scr_metrics(s.case_data,s.resources,struct(),struct());
ii=find(strcmp({s.resources.resource_type},'ibr'));
sel=find(ismember({s.resources.resource_id},{'IBR33','IBR36'}));
owner=find(strcmp({s.resources.resource_id},'SG31'));
rows={};
for M=[.02 .04 .08]
    for Dv=[.5 1 2 5 10]
        r=s.resources;
        for k=ii
            r(k).dynamic_params.gfm_eecon49.M=M;
            r(k).dynamic_params.gfm_eecon49.Dv=Dv;
        end
        cand=struct('selected_gfm_indices',sel,'n_gfm_required',numel(sel), ...
            'reference_resource_index',owner);
        c=stability.ibr_candidate_evaluate(s.case_data,r,cand,scr, ...
            s.case_data.selector.gamma_req_rad_per_s,struct('sg_online',true));
        rows{end+1}=struct('M',M,'Dv',Dv,'sg_on',c); %#ok<AGROW>
        fprintf('[NE39-profile] M=%g Dv=%g on feasible=%d zeta=%g omega=%g reason=%s\n', ...
            M,Dv,c.feasible,val(c,'zeta_worst'),val(c,'omega'),c.reason);
        if c.feasible
            cand.reference_resource_index=sel(1);
            off=stability.ibr_candidate_evaluate(s.case_data,r,cand,scr, ...
                s.case_data.selector.gamma_req_rad_per_s,struct('sg_online',false));
            rows{end}.sg_off=off;
            fprintf('[NE39-profile] off feasible=%d zeta=%g reason=%s\n', ...
                off.feasible,val(off,'zeta_worst'),off.reason);
        end
        save(fullfile(folder,'sweep.mat'),'s','scr','rows','-v7.3');
    end
end
fprintf('artifact=%s\n',folder);
end
function v=val(s,n)
v=NaN; if isfield(s,n) && ~isempty(s.(n)), v=s.(n); end
end
