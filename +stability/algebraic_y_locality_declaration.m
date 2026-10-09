function [declared, info] = algebraic_y_locality_declaration(dev)
%ALGEBRAIC_Y_LOCALITY_DECLARATION  Registered own-bus y-locality for a device.
%
%   [DECLARED, INFO] = ALGEBRAIC_Y_LOCALITY_DECLARATION(DEV) answers whether a
%   device's differential RHS f(x_dev,y,u,ec) and its current injection
%   current_injection(x_dev,y,u,ec) read the shared algebraic vector y ONLY at
%   the two entries of its own mapped bus (bus_position -> y(2*b-1), y(2*b)).
%
%   WHY A DECLARATION AND NOT JUST A PROBE
%   --------------------------------------
%   A numerical probe at one operating point cannot PROVE locality: a nonlinear
%   device may happen to have zero foreign-bus response at the sampled state and
%   a nonzero one elsewhere.  The engine therefore requires an explicit,
%   REGISTERED structural declaration, and treats any device that is not on the
%   registry as UNDECLARED -> the caller falls back to the conservative
%   per-column FD.  The probe in stability.ts_fd_y_locality remains only as an
%   additional (never sufficient) cross-check on the declared set.
%
%   DECLARATION SOURCES (in order):
%     1. dev.algebraic_locality == 'own_bus' (explicit per-device field, so a
%        future model can self-declare without touching this registry).
%     2. dev.device_type is a registered constant below.  Each entry is an
%        audited claim over that model's published RHS:
%          sg_emf6_composite - f/current read V(bus_position) only.
%          sg_classical      - E - V(bus_position) behind X'd; read V only there.
%          ibr_eecon49_dual  - GFL/GFM RHS + current read V(bus_position) only
%                              (PLL/VSG/DC/filter all keyed on the terminal V).
%     3. dev.provenance.model is one of the registered provenance names.
%
%   A device that declares 'global' (or any other value) is treated as
%   undeclared.  Classification: SOURCE_AUDITED structural contract.

info = struct('declared',false,'source','','key','','classification', ...
    'SOURCE_AUDITED_STRUCTURAL_CONTRACT');

% --- 1. explicit per-device field -----------------------------------------
if isfield(dev,'algebraic_locality') && ~isempty(dev.algebraic_locality)
    v = lower(string(dev.algebraic_locality));
    info.source = 'device_field';
    info.key = char(v);
    declared = (v == "own_bus");
    info.declared = declared;
    return;
end

% --- 2. registered device_type --------------------------------------------
types = {'sg_emf6_composite','sg_classical','ibr_eecon49_dual'};
if isfield(dev,'device_type') && ~isempty(dev.device_type)
    t = char(string(dev.device_type));
    info.source = 'device_type';
    info.key = t;
    declared = any(strcmp(t,types));
    info.declared = declared;
    return;
end

% --- 3. registered provenance.model ---------------------------------------
prov_models = {'sg_emf6_composite_phaseB_structural_only', 'sg_classical_composite', ...
    'EECON49_GFL_GFM_SHARED_PLANT_DUAL'};
if isfield(dev,'provenance') && isstruct(dev.provenance) && ...
        isfield(dev.provenance,'model') && ~isempty(dev.provenance.model)
    m = char(string(dev.provenance.model));
    info.source = 'provenance_model';
    info.key = m;
    declared = any(strcmp(m,prov_models));
    info.declared = declared;
    return;
end

declared = false;
info.source = 'none';
info.key = '';
info.declared = false;
end
