function m = ne39_event_metrics(r,row,requested_horizon)
%NE39_EVENT_METRICS request ไม่ใช่ applied event และ convergence ไม่ใช่ certificate.
m=struct('id',row.id,'requested_horizon_s',requested_horizon, ...
    'reached_horizon_s',0,'numerically_converged',false,'samples',numel(r.t), ...
    'defining_event',row.defining_event,'defining_event_executed',false, ...
    'events_applied',{{}},'events_refused',{{}},'actual_reclose_time',NaN, ...
    'mode_commits',0,'failure_id','','failure_reason','', ...
    'physical_switching_certified',false);
if ~isempty(r.t), m.reached_horizon_s=max(r.t); end
m.numerically_converged=isequal(r.converged,true);
if isfield(r,'failure_id'), m.failure_id=r.failure_id; end
if isempty(m.failure_id) && isfield(r,'metadata') && isfield(r.metadata,'failure')
    m.failure_id=r.metadata.failure;
end
if isfield(r,'failure_reason'), m.failure_reason=r.failure_reason; end
if isempty(m.failure_reason) && isfield(r,'metadata') && ...
        isfield(r.metadata,'equilibrium') && ...
        isfield(r.metadata.equilibrium,'failure_reason')
    m.failure_reason=r.metadata.equilibrium.failure_reason;
end
if isempty(m.failure_reason) && isfield(r,'metadata') && isfield(r.metadata,'error')
    m.failure_reason=r.metadata.error;
end
if isfield(r,'actual_reclose_time'), m.actual_reclose_time=r.actual_reclose_time; end
if isfield(r,'event_log')
    for k=1:numel(r.event_log)
        e=r.event_log(k);
        if e.applied
            m.events_applied{end+1}=e.type;
            if strcmp(e.type,row.defining_event)
                if strcmp(e.type,'sg_reclose')
                    m.defining_event_executed=isfinite(m.actual_reclose_time);
                else
                    m.defining_event_executed=true;
                end
            end
            if any(strcmp(e.type,{'gfm_support_augment','gfm_support_release','sg_reselection'}))
                m.mode_commits=m.mode_commits+1;
            end
        else
            m.events_refused{end+1}=e.type;
        end
    end
end
if isfield(r,'device_modes_history') && size(r.device_modes_history,2)>1
    % mode commits นับจาก accepted histories รวม SG-trip formation ที่ไม่ได้ชื่อ support.
    modes=r.device_modes_history;
    changes=false(1,size(modes,2)-1);
    for j=2:size(modes,2)
        changes(j-1)=~isequal(modes(:,j),modes(:,j-1));
    end
    m.accepted_mode_change_samples=sum(changes);
else
    m.accepted_mode_change_samples=0;
end
if isempty(row.defining_event)
    m.defining_event_executed=m.numerically_converged && ...
        m.reached_horizon_s>=requested_horizon-1e-10;
end
m.horizon_reached=m.reached_horizon_s>=requested_horizon-1e-10;
% ยังไม่มี end-to-end producer ผูก event-left/right/context; ห้ามอนุมานจาก trajectory.
m.certificate_status='NOT_END_TO_END_CERTIFIED';
if isfield(r,'ne39_decision_log') && ~isempty(r.ne39_decision_log)
    log=r.ne39_decision_log;
    m.policy_valid_samples=sum(cellfun(@(d)d.valid,log));
    m.si_trigger_samples=sum(cellfun(@(d)d.si_trigger,log));
    m.rocof_trigger_samples=sum(cellfun(@(d)d.rocof_trigger,log));
    m.rocov_trigger_samples=sum(cellfun(@(d)d.rocov_trigger,log));
    m.prediction_trigger_samples=sum(cellfun(@(d)d.prediction_trigger,log));
else
    m.policy_valid_samples=0; m.si_trigger_samples=0;
    m.rocof_trigger_samples=0; m.rocov_trigger_samples=0; m.prediction_trigger_samples=0;
end
end
