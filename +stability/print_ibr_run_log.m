function print_ibr_run_log(result)
%PRINT_IBR_RUN_LOG Print index-auditable IBR configuration and work counts.

fprintf('\n---------------- IBR EXECUTION SUMMARY ----------------\n');
if isfield(result,'execution_summary')
    q=result.execution_summary;
    fprintf('PF stage invocations       : %d\n',q.pf_stage_invocations);
    fprintf('Equilibrium invocations    : %d (Newton iterations %d)\n', ...
        q.equilibrium_invocations,q.equilibrium_newton_iterations);
    fprintf('SSSA invocations           : %d\n',q.sssa_invocations);
    fprintf('Selector candidates        : %d\n',q.selector_candidate_evaluations);
    fprintf('TS invocations             : %d\n',q.ts_invocations);
    fprintf('TS steps attempted/accepted: %d / %d\n', ...
        q.ts_step_attempts,q.ts_accepted_steps);
    fprintf('TS Newton iterations       : %d\n',q.ts_newton_iterations);
    fprintf('Event transactions         : %d\n',q.event_transactions);
end
if isfield(result,'selector_log') && isstruct(result.selector_log) && ...
        isfield(result.selector_log,'source')
    s=result.selector_log;
    fprintf('Initial-mode source        : %s\n',s.source);
    fprintf('Initial GFM requested/used : %s / %s\n', ...
        value_text(s.requested_count),mat2str(s.selected_gfm_indices));
    if isfield(s,'requested_gfl_count')
        fprintf('Initial GFL requested      : %s\n',value_text(s.requested_gfl_count));
    end
    fprintf('Initial selector ready     : %d\n',s.ready);
    if ~isempty(s.failure_id), fprintf('Initial selector failure   : %s -- %s\n',s.failure_id,s.failure_reason); end
end

if isfield(result,'status_log') && ~isempty(result.status_log)
    fprintf('\n---------------- RESOURCE/STATE INDEX STATUS ------------\n');
    for j=1:numel(result.status_log)
        s=result.status_log(j);
        fprintf('[%s] t=%.6f  SG=%d GFM=%d GFL=%d online=%d/%d KCL=%.3e\n', ...
            s.stage,s.t,s.n_sg_online,s.n_gfm,s.n_gfl,s.n_online,s.n_devices,s.kcl_norm);
        fprintf('  SG idx=%s | GFM idx=%s | GFL idx=%s | active states=%d/%d\n', ...
            index_text(s.sg_online_indices),index_text(s.gfm_indices), ...
            index_text(s.gfl_indices),s.active_state_count,s.total_state_count);
        for k=1:numel(s.device_entries)
            d=s.device_entries(k);
            fprintf('  %02d %-8s bus=%-4g %-3s mode=%-12s online=%d x=%03d:%03d active_local=%s\n', ...
                d.device_index,d.device_id,d.bus_id,upper(d.resource_type), ...
                d.mode,d.online,d.state_start,d.state_end,mat2str(d.active_local_indices));
        end
    end
end

if isfield(result,'event_log') && ~isempty(result.event_log)
    fprintf('\n---------------- IBR EVENT TRANSACTIONS ------------------\n');
    for k=1:numel(result.event_log)
        e=result.event_log(k);
        fprintf('%02d %-20s t=%.6f applied=%d preKCL=%.3e rightKCL=%.3e', ...
            k,e.type,e.t,e.applied,e.pre_kcl_norm,e.right_kcl_norm);
        if ~isempty(e.selected_gfm_indices)
            fprintf(' selected=%s ref=%s',mat2str(e.selected_gfm_indices), ...
                value_text(e.reference_resource_index));
        end
        if ~isempty(e.failure_id), fprintf(' failure=%s',e.failure_id); end
        fprintf('\n');
        if ~isempty(e.details), fprintf('     %s\n',e.details); end
    end
end
if isfield(result,'reclose_status')
    fprintf('Reclose status             : %s (requested=%s actual=%s)\n', ...
        result.reclose_status,value_text(result.requested_sg_on_time), ...
        value_text(result.actual_reclose_time));
end
if isfield(result,'converged') && ~logical(result.converged)
    fprintf('\n---------------- FAIL-CLOSED DIAGNOSTIC ------------------\n');
    if isfield(result,'failure_id') && ~isempty(result.failure_id)
        fprintf('Failure ID                  : %s\n',char(string(result.failure_id)));
    end
    if isfield(result,'failure_reason') && ~isempty(result.failure_reason)
        fprintf('Failure reason              : %s\n',char(string(result.failure_reason)));
    end
    if isfield(result,'t') && ~isempty(result.t)
        fprintf('Last published time         : %.12g s\n',result.t(end));
        fprintf('Published samples           : %d\n',numel(result.t));
    end
end
end

function text=value_text(value)
if isempty(value), text='[]';
elseif isnumeric(value) && isscalar(value), text=sprintf('%.12g',value);
else, text=mat2str(value); end
end

function text=index_text(value)
if isempty(value), text='[]'; else, text=mat2str(value); end
end
