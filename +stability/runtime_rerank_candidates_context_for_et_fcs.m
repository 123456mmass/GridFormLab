function rc = runtime_rerank_candidates_context_for_et_fcs(hs,dae,event_time)
%RUNTIME_RERANK_CANDIDATES_CONTEXT_FOR_ET_FCS Materialize hybrid timers.
%   Identity-aligned read-only adapter for the accepted ET-FCSPS snapshot.
%   Missing timer keys mean unblocked, matching the production runtime.

n=numel(dae.devices); hold=zeros(1,n); lockout=-inf(1,n);
for k=1:n
    key=matlab.lang.makeValidName(char(dae.devices(k).device_id), ...
        'ReplacementStyle','underscore');
    if isfield(hs,'hold_timers') && isstruct(hs.hold_timers) && ...
            isfield(hs.hold_timers,key)
        v=hs.hold_timers.(key);
        if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v)
            error('stability:et_fcs_production_trip_decision:malformedTimer', ...
                'Malformed hold timer for %s.',dae.devices(k).device_id);
        end
        hold(k)=v;
    end
    if isfield(hs,'lockouts') && isstruct(hs.lockouts) && isfield(hs.lockouts,key)
        v=hs.lockouts.(key);
        if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v)
            error('stability:et_fcs_production_trip_decision:malformedTimer', ...
                'Malformed lockout timer for %s.',dae.devices(k).device_id);
        end
        lockout(k)=v;
    end
end
rc=struct('hold_timers',hold,'lockout_timers',lockout, ...
    'event_time',event_time);
end
