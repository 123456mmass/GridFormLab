function candidates = et_fcs_metrics(snapshot, candidates, policy)
%ET_FCS_METRICS  Compute dimensionless predictive ranking terms.
%   All targets and normalizers are mandatory CASE_DEFINED inputs. Values are
%   not clipped or smoothed; terms above one remain visible evidence.

arguments
    snapshot struct
    candidates struct
    policy struct
end

[norms, targets] = validate_contract(policy);
neligible = sum(snapshot.eligible_mask);
for i = 1:numel(candidates)
    m = blank_metrics();
    if ~isfield(candidates(i),'prediction_pass') || ~candidates(i).prediction_pass
        m.failure_id = 'stability:et_fcs_metrics:predictionRejected';
        candidates(i).metrics = m;
        candidates(i).metrics_pass = false;
        continue;
    end
    p = candidates(i).prediction;
    m.voltage = max(abs(p.voltage_abs(:)-targets.voltage))/norms.voltage;
    m.frequency = max(abs(p.frequency_hz(:)-targets.frequency))/norms.frequency;
    m.rocof = max(abs(p.rocof_hz_s(:)))/norms.rocof;
    min_p = min(p.delta_p_available(:));
    min_q = min(p.delta_q_available(:));
    m.reserve_p = max(0,targets.reserve_p-min_p)/norms.reserve_p;
    m.reserve_q = max(0,targets.reserve_q-min_q)/norms.reserve_q;
    imax = snapshot.limits.i_max;
    if isscalar(imax)
        m.current = max(p.current_abs(:))/imax;
    elseif numel(imax) == size(p.current_abs,1)
        ratio = p.current_abs ./ repmat(reshape(imax,[],1),1,size(p.current_abs,2));
        m.current = max(ratio(:));
    elseif isequal(size(imax),size(p.current_abs))
        ratio = p.current_abs ./ imax;
        m.current = max(ratio(:));
    else
        m.failure_id = 'stability:et_fcs_metrics:currentLimitAlignment';
        candidates(i).metrics = m;
        candidates(i).metrics_pass = false;
        continue;
    end
    h = p.handback;
    m.handback = max([h.delta_p/norms.handback_p, ...
        h.delta_q/norms.handback_q, h.delta_i/norms.handback_i, ...
        h.delta_theta/norms.handback_theta]);
    if neligible > 0
        m.n_gfm = candidates(i).n_gfm/neligible;
        m.n_switch = candidates(i).n_switch/neligible;
    else
        m.n_gfm = 0; m.n_switch = 0;
    end
    vals = struct2array_ordered(m);
    if any(~isfinite(vals)) || any(vals < 0)
        m.failure_id = 'stability:et_fcs_metrics:nonFiniteMetric';
        candidates(i).metrics = m;
        candidates(i).metrics_pass = false;
        continue;
    end
    m.reserve_margin = min(min_p/norms.reserve_p, min_q/norms.reserve_q);
    m.kcl_norm = candidates(i).screen.kcl_norm;
    m.passed = true;
    candidates(i).metrics = m;
    candidates(i).metrics_pass = true;
end
end

function [n,t] = validate_contract(p)
if ~isfield(p,'normalization') || ~isstruct(p.normalization) || ...
        ~isfield(p,'targets') || ~isstruct(p.targets)
    error('stability:et_fcs_metrics:missingContract', ...
        'CASE_DEFINED normalization and targets structs are mandatory.');
end
n = p.normalization; t = p.targets;
nf = {'voltage','frequency','rocof','reserve_p','reserve_q', ...
    'handback_p','handback_q','handback_i','handback_theta'};
tf = {'voltage','frequency','reserve_p','reserve_q'};
for k = 1:numel(nf)
    f = nf{k};
    if ~isfield(n,f) || ~isnumeric(n.(f)) || ~isscalar(n.(f)) || ...
            ~isfinite(n.(f)) || n.(f) <= 0
        error('stability:et_fcs_metrics:badNormalization', ...
            'Positive finite normalizer "%s" is mandatory.', f);
    end
end
for k = 1:numel(tf)
    f = tf{k};
    if ~isfield(t,f) || ~isnumeric(t.(f)) || ~isscalar(t.(f)) || ~isfinite(t.(f))
        error('stability:et_fcs_metrics:badTargets', ...
            'Finite target "%s" is mandatory.', f);
    end
end
if t.voltage <= 0 || t.frequency <= 0 || t.reserve_p < 0 || t.reserve_q < 0
    error('stability:et_fcs_metrics:badTargets', 'Targets are physically inconsistent.');
end
end

function m = blank_metrics()
m = struct('passed',false,'failure_id','','voltage',NaN,'frequency',NaN, ...
    'rocof',NaN,'reserve_p',NaN,'reserve_q',NaN,'current',NaN, ...
    'handback',NaN,'n_gfm',NaN,'n_switch',NaN,'reserve_margin',NaN, ...
    'kcl_norm',NaN);
end

function v = struct2array_ordered(m)
v = [m.voltage,m.frequency,m.rocof,m.reserve_p,m.reserve_q,m.current, ...
    m.handback,m.n_gfm,m.n_switch];
end
