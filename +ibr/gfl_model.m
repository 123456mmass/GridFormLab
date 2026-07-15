function dev = gfl_model(device_id, bus_id, bus_position, bus_ids, V0, ...
    params, P_ref_pu, Q_ref_pu)
%GFL_MODEL  Compatibility entry point for the production WECC GFL model.
%   The former Ding-derived six-state diagnostic model depended on unsourced
%   Kps/Kis gains and is no longer reachable from production.  Existing
%   callers retain this function signature; the canonical implementation is
%   IBR.WECC_REGCA_REECA_MODEL.
dev = ibr.wecc_regca_reeca_model(device_id,bus_id,bus_position,bus_ids, ...
    V0,params,P_ref_pu,Q_ref_pu);
end
