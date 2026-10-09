function policy = et_fcs_policy_ieee14()
%ET_FCS_POLICY_IEEE14  Frozen project-derived ET-FCSPS prototype policy.
%   BACKWARD-COMPATIBLE ALIAS: this is the historical IEEE14-named entry point.
%   It returns EXACTLY the same frozen, case-agnostic contract as
%   stability.et_fcs_policy_generic (identical fields and values), so any
%   fingerprint computed over this policy is unchanged. New callers should use
%   stability.et_fcs_policy_generic directly; a case (e.g. NE39) overrides the
%   policy only through stability.et_fcs_production_trip_decision(..., opt.policy).

policy = stability.et_fcs_policy_generic();
end
