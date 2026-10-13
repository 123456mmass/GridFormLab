function resolved = ne39_resolve_threshold_pairs(opt, policy, gamma_on, gamma_off, T_on, T_off)
%NE39_RESOLVE_THRESHOLD_PAIRS  Resolve the SI thresholds and dwells as ONE contract.
%   The NE39 weighted supervisor can read the same scalar from two spellings:
%     threshold: policy.si_on / policy.si_off      and  opt.severity_gamma_on/off
%     dwell:     policy.on_dwell / policy.off_dwell and opt.severity_T_d_on/off
%   OPT is the raw caller option struct (it contains severity_* only when the
%   caller supplied them explicitly). POLICY is the raw caller ne39_policy
%   struct (it contains a field only when the caller supplied it explicitly).
%   GAMMA_ON/GAMMA_OFF/T_ON/T_OFF are the kernel's already-defaulted values and
%   are used only when neither spelling was supplied.
%
%   When both spellings are supplied and they disagree, this raises an error.
%   It never silently picks one. Supplying one spelling uses that value.
%
%   RESOLVED fields: si_on, si_off, on_dwell, off_dwell, and a source struct
%   recording which spelling supplied each value (for logging).

arguments
    opt struct
    policy struct
    gamma_on (1,1) double
    gamma_off (1,1) double
    T_on (1,1) double
    T_off (1,1) double
end

[si_on,src_si_on]     = pick_pair(opt,policy,'si_on','severity_gamma_on',gamma_on);
[si_off,src_si_off]   = pick_pair(opt,policy,'si_off','severity_gamma_off',gamma_off);
[on_dwell,src_on]     = pick_pair(opt,policy,'on_dwell','severity_T_d_on',T_on);
[off_dwell,src_off]   = pick_pair(opt,policy,'off_dwell','severity_T_d_off',T_off);

if si_off>=si_on
    error('stability:ne39_resolve_threshold_pairs:badOrder', ...
        'Resolved si_off (%g) must be below si_on (%g).', si_off, si_on);
end

resolved = struct('si_on',si_on,'si_off',si_off, ...
    'on_dwell',on_dwell,'off_dwell',off_dwell, ...
    'source',struct('si_on',src_si_on,'si_off',src_si_off, ...
    'on_dwell',src_on,'off_dwell',src_off));
end

function [value, source] = pick_pair(opt, policy, policy_name, severity_name, legacy_value)
%PICK_PAIR  Return the single agreed value or raise on conflict.
has_policy = isfield(policy,policy_name) && ~isempty(policy.(policy_name));
has_severity = isfield(opt,severity_name) && ~isempty(opt.(severity_name));
if has_policy
    validateattributes(policy.(policy_name),{'numeric'},{'scalar','real','finite','nonnegative'});
end
if has_severity
    validateattributes(opt.(severity_name),{'numeric'},{'scalar','real','finite','nonnegative'});
end
if has_policy && has_severity
    if double(policy.(policy_name)) ~= double(opt.(severity_name))
        error('stability:ne39_resolve_threshold_pairs:conflict', ...
            ['%s (policy) = %g and %s (severity option) = %g disagree; ' ...
             'supply one spelling or make them equal.'], ...
            policy_name, double(policy.(policy_name)), ...
            severity_name, double(opt.(severity_name)));
    end
    value = double(policy.(policy_name));
    source = 'both_equal';
elseif has_policy
    value = double(policy.(policy_name));
    source = 'policy';
elseif has_severity
    value = double(opt.(severity_name));
    source = 'severity';
else
    value = legacy_value;
    source = 'legacy_default';
end
if ~isscalar(value) || ~isfinite(value) || value < 0
    error('stability:ne39_resolve_threshold_pairs:badValue', ...
        '%s must be a finite nonnegative scalar.', policy_name);
end
end
