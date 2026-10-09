function [decision, state] = ne39_rate_policy(t, sample, state, policy)
%NE39_RATE_POLICY ข้อเสนอ causal เท่านั้น ไม่ใช่อำนาจอนุมัติ mode commit.
% sample มี severity, v_pu, f_hz, rocof_hz_s, rocov_pu_s, valid
% ทุก vector เรียงตาม online IBR ชุดเดียวกัน; เปลี่ยน epoch ให้ caller reset state.
arguments
    t (1,1) double {mustBeFinite}
    sample (1,1) struct
    state (1,1) struct
    policy (1,1) struct
end
names = {'si_on','si_off','rocof_max','rocov_max','v_min','v_max', ...
    'f_min','f_max','prediction_horizon','on_dwell','off_dwell'};
for k=1:numel(names)
    if ~isfield(policy,names{k})
        error('stability:ne39_rate_policy:badPolicy','ขาด policy.%s',names{k});
    end
    v=policy.(names{k});
    validateattributes(v,{'numeric'},{'scalar','real','finite'});
end
if policy.si_off<0 || policy.si_on>1 || policy.si_off>=policy.si_on || ...
        policy.v_min<=0 || policy.f_min<=0 || policy.v_min>=policy.v_max || ...
        policy.f_min>=policy.f_max || any([policy.rocof_max policy.rocov_max]<=0) || ...
        any([policy.prediction_horizon policy.on_dwell policy.off_dwell]<0)
    error('stability:ne39_rate_policy:badPolicy','ขอบเขต policy ไม่ถูกต้อง');
end
fields={'severity','v_pu','f_hz','rocof_hz_s','rocov_pu_s','valid'};
if ~all(isfield(sample,fields))
    error('stability:ne39_rate_policy:shape','sample มีข้อมูลไม่ครบ');
end
n=numel(sample.severity);
for k=1:numel(fields)
    a=sample.(fields{k});
    if ~(isnumeric(a) || islogical(a)) || (~isvector(a) && ~isempty(a))
        error('stability:ne39_rate_policy:shape','sample ต้องเป็น numeric/logical vector');
    end
    if numel(a)~=n
        error('stability:ne39_rate_policy:shape','sample vectors ต้องมีขนาดเท่ากัน');
    end
end
if isempty(fieldnames(state))
    state=struct('last_t',-Inf,'up_since',NaN,'down_since',NaN);
end
decision=struct('augment',false,'release',false,'valid',false, ...
    'si_trigger',false,'rocof_trigger',false,'rocov_trigger',false, ...
    'prediction_trigger',false,'projected_v',[],'projected_f',[], ...
    'reason','NONADVANCING_TIME');
% duplicate time ไม่กิน dwell และไม่สร้าง proposal ซ้ำ.
if t<=state.last_t, return; end
state.last_t=t;
s=sample.severity(:); v=sample.v_pu(:); f=sample.f_hz(:);
rf=sample.rocof_hz_s(:); rv=sample.rocov_pu_s(:);
valid=n>0 && all(sample.valid(:)==1) && ...
    all(isfinite([s;v;f;rf;rv])) && isreal([s;v;f;rf;rv]) && ...
    all(s>=0 & s<=1) && all(v>0 & f>0);
decision.valid=valid;
if ~valid
    state.up_since=NaN; state.down_since=NaN;
    decision.reason='EVIDENCE_UNAVAILABLE'; return;
end
decision.si_trigger=any(s>=policy.si_on);
decision.rocof_trigger=any(abs(rf)>policy.rocof_max);
decision.rocov_trigger=any(abs(rv)>policy.rocov_max);
vp=v+policy.prediction_horizon*rv;
fp=f+policy.prediction_horizon*rf;
decision.projected_v=vp; decision.projected_f=fp;
outward=(rv<0 & vp<policy.v_min) | (rv>0 & vp>policy.v_max) | ...
    (rf<0 & fp<policy.f_min) | (rf>0 & fp>policy.f_max);
decision.prediction_trigger=any(outward);
up=decision.si_trigger || decision.rocof_trigger || ...
    decision.rocov_trigger || decision.prediction_trigger;
safe=all(v>=policy.v_min & v<=policy.v_max & ...
    f>=policy.f_min & f<=policy.f_max & ...
    abs(rf)<=policy.rocof_max & abs(rv)<=policy.rocov_max);
down=all(s<policy.si_off) && safe && ~decision.prediction_trigger;
if up
    if ~isfinite(state.up_since), state.up_since=t; end
    state.down_since=NaN;
    decision.augment=t-state.up_since>=policy.on_dwell;
    decision.reason='AUGMENT_PENDING_CERTIFICATE';
elseif down
    state.up_since=NaN;
    if ~isfinite(state.down_since), state.down_since=t; end
    decision.release=t-state.down_since>=policy.off_dwell;
    decision.reason='RELEASE_PENDING_CERTIFICATE';
else
    state.up_since=NaN; state.down_since=NaN;
    decision.reason='HYSTERESIS_OR_RATE_HOLD';
end
end
