function dev = gfl_model(device_id, bus_id, bus_position, bus_ids, V0, ...
    params, P_ref_pu, Q_ref_pu)
%GFL_MODEL  Production GFL dispatcher (WECC default, RMS10 opt-in).
%   dev = gfl_model(DEVICE_ID, BUS_ID, BUS_POSITION, BUS_IDS, V0, PARAMS,
%       P_REF_PU, Q_REF_PU) returns a GFL device struct conforming to the
%       stability.composite_dae ABI.
%
%   Family selection is CONSTRUCTION-TIME via params.gfl_family:
%     missing | 'wecc_regca_reeca'  -> ibr.wecc_regca_reeca_model (default, 7-state)
%     'rms10'                      -> ibr.gfl_rms10_model (10-state opt-in)
%     (anything else)             -> fail-closed ibr:gfl_model:unknownFamily
%
%   RMS10-specific overrides live under params.gfl_rms10 (nested), never
%   top-level, to avoid accidental REGFM_B1 override. A constructed device
%   cannot switch WECC<->RMS10. Runtime mode vocabulary stays {gfl,GFM,tripped};
%   this dispatcher does not introduce a new runtime mode.
%
%   The former Ding-derived six-state diagnostic model depended on unsourced
%   Kps/Kis gains and is no longer reachable from production.
%
%   Source: docs/project/IEEE14_IBR_GFL_RMS10_PROVENANCE.md (RMS10);
%           docs/project/IEEE14_IBR_GFL_WECC_PROVENANCE.md (WECC).
family = 'wecc_regca_reeca';
if isfield(params,'gfl_family') && ~isempty(params.gfl_family)
    family = char(params.gfl_family);
end
switch lower(strtrim(family))
case 'wecc_regca_reeca'
    dev = ibr.wecc_regca_reeca_model(device_id,bus_id,bus_position,bus_ids, ...
        V0,params,P_ref_pu,Q_ref_pu);
case 'rms10'
    dev = ibr.gfl_rms10_model(device_id,bus_id,bus_position,bus_ids, ...
        V0,params,P_ref_pu,Q_ref_pu);
otherwise
    error('ibr:gfl_model:unknownFamily', ...
        'Unknown GFL family "%s". Supported: wecc_regca_reeca (default), rms10.', family);
end
end
