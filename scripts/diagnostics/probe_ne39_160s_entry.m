function folder = probe_ne39_160s_entry(composition)
%PROBE_NE39_160S_ENTRY เก็บ spectrum/constraints จริงก่อนเลือก initial profile.
arguments
    composition (1,1) string = "5sg_5ibr"
end
root=pf_init_paths();
folder=fullfile(root,'output','diagnostics', ...
    ['ne39_entry_' char(composition) '_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder);
if composition=="5sg_5ibr"
    s=cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
else
    s=cases.scenario_ne39_1sg_9ibr(struct('study_capability',true));
end
scr=stability.ibr_scr_metrics(s.case_data,s.resources,struct(),struct());
ii=find(strcmp({s.resources.resource_type},'ibr'));
owner=find(strcmp({s.resources.resource_id},'SG31'),1);
sets={};
for k=ii, sets{end+1}=k; end %#ok<AGROW>
if numel(ii)==5
    pairs=nchoosek(ii,2);
    for k=1:size(pairs,1), sets{end+1}=pairs(k,:); end %#ok<AGROW>
end
sets{end+1}=ii;
rows={};
for online=[true false]
    for k=1:numel(sets)
        sel=sets{k}; ref=owner;
        if ~online, ref=sel(1); end
        cand=struct('selected_gfm_indices',sel,'n_gfm_required',numel(sel), ...
            'reference_resource_index',ref);
        timer=tic;
        c=stability.ibr_candidate_evaluate(s.case_data,s.resources,cand,scr, ...
            s.case_data.selector.gamma_req_rad_per_s,struct('sg_online',online));
        elapsed=toc(timer);
        rows{end+1}=struct('sg_online',online,'candidate',c,'elapsed_s',elapsed); %#ok<AGROW>
        fprintf('[NE39-entry] %s online=%d GFM=%s feasible=%d zeta=%.7g omega=%.7g stage=%s reason=%s elapsed=%.2fs\n', ...
            composition,online,strjoin(string({s.resources(sel).resource_id}),','), ...
            c.feasible,value(c,'zeta_worst'),value(c,'omega'),c.failure_id,c.reason,elapsed);
        save(fullfile(folder,'candidates.mat'),'s','scr','rows','-v7.3');
    end
end
fprintf('[NE39-entry] artifact=%s\n',folder);
end

function v=value(s,name)
v=NaN;
if isfield(s,name) && ~isempty(s.(name)), v=s.(name); end
end
