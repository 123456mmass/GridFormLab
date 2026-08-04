function candidates = et_fcs_predict(snapshot, candidates, provider, policy)
%ET_FCS_PREDICT  Run isolated short-horizon candidate trials and dynamic gates.
%   Prediction horizon and tolerance are mandatory CASE_DEFINED inputs. Trials
%   run only for candidates that passed et_fcs_screen. Provider failures and
%   incomplete trajectories reject the candidate fail closed.

arguments
    snapshot struct
    candidates struct
    provider
    policy struct
end

[Tp, time_tol, allow_diag] = validate_policy(policy);
validate_provider(provider, allow_diag);
lim = snapshot.limits;
for i = 1:numel(candidates)
    ev = blank_prediction();
    if ~isfield(candidates(i),'screen_pass') || ~candidates(i).screen_pass
        ev.failure_id = 'stability:et_fcs_predict:screenRejected';
        candidates(i).prediction = ev;
        candidates(i).prediction_pass = false;
        continue;
    end
    before = snapshot.fingerprint;
    try
        raw = feval(provider, snapshot, candidates(i), candidates(i).screen, Tp);
    catch me
        ev.failure_id = 'stability:et_fcs_predict:providerException';
        ev.details = sprintf('%s: %s', me.identifier, me.message);
        candidates(i).prediction = ev;
        candidates(i).prediction_pass = false;
        continue;
    end
    if ~strcmp(snapshot.fingerprint, before)
        error('stability:et_fcs_predict:snapshotMutation', ...
            'The accepted snapshot fingerprint changed during prediction.');
    end
    [ev, ok] = validate_prediction(raw, snapshot.t, Tp, time_tol, lim);
    candidates(i).prediction = ev;
    candidates(i).prediction_pass = ok;
end
end

function [Tp, time_tol, allow_diag] = validate_policy(p)
required = {'prediction_horizon','prediction_time_tol','allow_diagnostic_callback'};
for k = 1:numel(required)
    if ~isfield(p,required{k}) || isempty(p.(required{k}))
        error('stability:et_fcs_predict:missingPolicy', ...
            'Mandatory policy field "%s" is missing.', required{k});
    end
end
Tp = p.prediction_horizon;
time_tol = p.prediction_time_tol;
allow_diag = p.allow_diagnostic_callback;
if ~isnumeric(Tp) || ~isscalar(Tp) || ~isfinite(Tp) || Tp <= 0 || ...
        ~isnumeric(time_tol) || ~isscalar(time_tol) || ~isfinite(time_tol) || ...
        time_tol < 0 || ~islogical(allow_diag) || ~isscalar(allow_diag)
    error('stability:et_fcs_predict:badPolicy', ...
        'Prediction horizon/tolerance and callback classification are invalid.');
end
end

function [ev, ok] = validate_prediction(raw, t0, Tp, tol, lim)
ev = blank_prediction(); ok = false;
required = {'converged','t','voltage_abs','frequency_hz','rocof_hz_s', ...
    'current_abs','reserve_known','delta_p_available','delta_q_available','handback'};
if ~isstruct(raw) || ~isscalar(raw)
    ev.failure_id = 'stability:et_fcs_predict:malformedEvidence'; return;
end
for k = 1:numel(required)
    if ~isfield(raw,required{k}) || isempty(raw.(required{k}))
        ev.failure_id = 'stability:et_fcs_predict:incompleteEvidence'; return;
    end
end
ev = raw; ev.passed = false; ev.failure_id = ''; ev.details = '';
if ~islogical(raw.converged) || ~isscalar(raw.converged) || ~raw.converged
    ev.failure_id = 'stability:et_fcs_predict:notConverged'; return;
end
numeric_fields = {'t','voltage_abs','frequency_hz','rocof_hz_s','current_abs', ...
    'delta_p_available','delta_q_available'};
for k = 1:numel(numeric_fields)
    v = raw.(numeric_fields{k});
    if ~isnumeric(v) || any(~isfinite(v(:)))
        ev.failure_id = 'stability:et_fcs_predict:nonFiniteEvidence'; return;
    end
end
t = reshape(raw.t, 1, []);
if any(diff(t) <= 0) || abs(t(1)-t0) > tol || t(end) < t0+Tp-tol
    ev.failure_id = 'stability:et_fcs_predict:incompleteHorizon'; return;
end
nt = numel(t);
if ~time_aligned(raw.voltage_abs,nt) || ~time_aligned(raw.frequency_hz,nt) || ...
        ~time_aligned(raw.rocof_hz_s,nt) || ~time_aligned(raw.current_abs,nt) || ...
        ~time_aligned(raw.delta_p_available,nt) || ~time_aligned(raw.delta_q_available,nt)
    ev.failure_id = 'stability:et_fcs_predict:timeAlignment'; return;
end
if any(raw.voltage_abs(:) < lim.v_min) || any(raw.voltage_abs(:) > lim.v_max)
    ev.failure_id = 'stability:et_fcs_predict:voltageViolation'; return;
end
if any(raw.frequency_hz(:) < lim.f_min) || any(raw.frequency_hz(:) > lim.f_max)
    ev.failure_id = 'stability:et_fcs_predict:frequencyViolation'; return;
end
if any(abs(raw.rocof_hz_s(:)) > lim.rocof_max)
    ev.failure_id = 'stability:et_fcs_predict:rocofViolation'; return;
end
imax = lim.i_max;
if isscalar(imax), imax = repmat(imax, size(raw.current_abs)); end
if ~isequal(size(imax),size(raw.current_abs)) && numel(imax) ~= size(raw.current_abs,1)
    ev.failure_id = 'stability:et_fcs_predict:currentLimitAlignment'; return;
end
if isvector(imax) && numel(imax) == size(raw.current_abs,1)
    imax = repmat(reshape(imax,[],1),1,nt);
end
if any(raw.current_abs(:) < 0) || any(raw.current_abs(:) > imax(:))
    ev.failure_id = 'stability:et_fcs_predict:currentViolation'; return;
end
if ~islogical(raw.reserve_known) || ~isscalar(raw.reserve_known) || ~raw.reserve_known
    ev.failure_id = 'stability:et_fcs_predict:reserveUnknown'; return;
end
if any(raw.delta_p_available(:) < 0) || any(raw.delta_q_available(:) < 0)
    ev.failure_id = 'stability:et_fcs_predict:reserveViolation'; return;
end
if ~valid_handback(raw.handback)
    ev.failure_id = 'stability:et_fcs_predict:badHandbackEvidence'; return;
end
ev.passed = true; ok = true;
end

function tf = time_aligned(v, nt)
tf = isscalar(v) || (ismatrix(v) && size(v,2) == nt) || (isvector(v) && numel(v) == nt);
end

function tf = valid_handback(h)
tf = isstruct(h) && isscalar(h);
names = {'delta_p','delta_q','delta_i','delta_theta'};
for k = 1:numel(names)
    if ~tf || ~isfield(h,names{k}) || ~isnumeric(h.(names{k})) || ...
            ~isscalar(h.(names{k})) || ~isfinite(h.(names{k})) || h.(names{k}) < 0
        tf = false; return;
    end
end
end

function ev = blank_prediction()
ev = struct('passed',false,'failure_id','','details','','converged',false, ...
    't',[],'voltage_abs',[],'frequency_hz',[],'rocof_hz_s',[], ...
    'current_abs',[],'reserve_known',false,'delta_p_available',[], ...
    'delta_q_available',[],'handback',struct());
end

function validate_provider(provider, allow_diagnostic)
if ~(isa(provider,'function_handle') || ischar(provider) || ...
        (isstring(provider) && isscalar(provider)))
    error('stability:et_fcs_predict:badProvider', 'Prediction provider must be callable.');
end
if ischar(provider) || isstring(provider)
    name = char(provider);
else
    name = func2str(provider);
end
if ~startsWith(name,'stability.') && ~allow_diagnostic
    error('stability:et_fcs_predict:nonProjectProvider', ...
        'Production prediction provider must be an in-repo stability.* function.');
end
end
