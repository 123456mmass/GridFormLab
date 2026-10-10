function folder=probe_ne39_voltage_bandwidth()
%PROBE_NE39_VOLTAGE_BANDWIDTH diagnostic design; คง SG/DC/limits และ damping floor.
root=pf_init_paths();
folder=fullfile(root,'output','diagnostics', ...
    ['ne39_voltage_bw_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder);
s=cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
scr=stability.ibr_scr_metrics(s.case_data,s.resources,struct(),struct());
ii=find(strcmp({s.resources.resource_type},'ibr'));
owner=find(strcmp({s.resources.resource_id},'SG31'));
rows={};
% โหมด SG-SG เดิมประมาณ 7.87 rad/s. PI zero=kiV/kpV ทดสอบที่ 10/30/100 rad/s.
% ตรวจ spectrum ทุก root ที่ FD factors .5/1/2 ไม่ตัด SG mode ออก.
for kiV=[12 36 120]
    for Dv=[5 20 50]
        r=s.resources;
        for k=ii
            r(k).dynamic_params.gfm_eecon49.kiV=kiV;
            r(k).dynamic_params.gfm_eecon49.Dv=Dv;
        end
        cand=struct('selected_gfm_indices',ii,'n_gfm_required',numel(ii), ...
            'reference_resource_index',owner);
        timer=tic;
        c=stability.ibr_candidate_evaluate(s.case_data,r,cand,scr, ...
            s.case_data.selector.gamma_req_rad_per_s,struct('sg_online',true));
        rows{end+1}=struct('kiV',kiV,'Dv',Dv,'sg_on',c,'elapsed_s',toc(timer)); %#ok<AGROW>
        fprintf('[NE39-voltage-bw] kiV=%g Dv=%g on feasible=%d zeta=%g omega=%g reason=%s\n', ...
            kiV,Dv,c.feasible,val(c,'zeta_worst'),val(c,'omega'),c.reason);
        save(fullfile(folder,'sweep.mat'),'s','scr','rows','-v7.3');
    end
end
fprintf('artifact=%s\n',folder);
end
function v=val(s,n)
v=NaN; if isfield(s,n) && ~isempty(s.(n)), v=s.(n); end
end
