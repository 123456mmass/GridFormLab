function dae = composite_dae(case_data, devices, opt)
%COMPOSITE_DAE  Single-owner composite DAE assembler (R3).
%   DAE = composite_dae(CASE_DATA, DEVICES, OPT) builds a composite DAE where
%   the composite is the SINGLE owner of: shared interleaved y, topology/Y
%   selection, external-bus-ID mapping, network KCL residual (g = Y*V - Ibus),
%   slack/reference constraint replacement, and state/input offsets.
%
%   Each device owns ONLY: its differential state slice, input slice/provider,
%   f_device, positive current injection (INTO network), and device outputs.
%   Devices NEVER return or modify the global network residual.
%
%   Canonical KCL (R3): g = Y*V - Ibus, where Ibus = sum of device positive
%   current injections by mapped bus. SG DAEs use g = -Y*V + Ibus (-YV+I); the
%   composite canonical is YV-I. The sign relation g_composite = -g_sg is
%   asserted ONLY in the legacy equivalence test (no production adapter).
%
%   Device contract (frozen signatures, R3 Revision 2):
%     device.name, device_id, bus_id, nx, nu
%     device.f                  = @(t,x_dev,y,u_dev,event_context) dx
%     device.current_injection = @(t,x_dev,y,u_dev,event_context) Iinj (complex)
%     device.electrical_power   = @(t,x_dev,y,u_dev,event_context) Pe
%     device.x0, device.u0
%     device.state_names, device.reconstruct = @(t,x_dev,y,u_dev,event_context) struct
%
%   State/input ordering: device-contiguous (caller-provided ORDERED list).
%   x = [x_dev1; x_dev2; ...]; u = [u_dev1; u_dev2; ...]. Offsets are 1-based
%   inclusive via cumulative sums. Slicing uses nx (ns is optional metadata).
%
%   Source: project R3 design (docs/project/plans/ibr_interface_foundation.md).
%
%   B5 case schema: MATPOWER-mpc-only. case_data MUST be a scalar struct
%   with a scalar .mpc MATPOWER struct (baseMVA, bus, gen, branch). The
%   schema is validated at entry BEFORE any PF call or field access; an
%   invalid schema fails with composite_dae:unsupportedCaseSchema. Non-mpc
%   case schemas are NOT supported here (extracting shared normalize_case
%   is separate refactoring, out of scope).

if nargin < 3 || isempty(opt), opt = struct(); end
if isempty(devices)
    error('composite_dae:emptyDevices', ...
        'Cannot build a composite with zero devices.');
end
% --- B5: MATPOWER-mpc-only schema validation at ENTRY ---------------------
% Validate case_data is a scalar struct containing a scalar mpc struct with
% the required MATPOWER fields (baseMVA, bus, gen, branch) and valid basic
% dimensions BEFORE any PF solver call and BEFORE any case_data.mpc access.
% This corrects the ordering bug where mpc = case_data.mpc (L42) preceded
% the isfield guard (L43). composite_dae is MATPOWER-mpc-only; extracting
% shared normalize_case is separate refactoring (out of scope).
if ~isstruct(case_data) || ~isscalar(case_data)
    error('composite_dae:unsupportedCaseSchema', ...
        'case_data must be a scalar struct with a .mpc MATPOWER field.');
end
if ~isfield(case_data,'mpc') || ~isstruct(case_data.mpc) || ~isscalar(case_data.mpc)
    error('composite_dae:unsupportedCaseSchema', ...
        'case_data.mpc must be a scalar MATPOWER mpc struct.');
end
mpc = case_data.mpc;
mpc_req = {'baseMVA','bus','gen','branch'};
for k = 1:numel(mpc_req)
    if ~isfield(mpc, mpc_req{k})
        error('composite_dae:unsupportedCaseSchema', ...
            'case_data.mpc missing required MATPOWER field "%s".', mpc_req{k});
    end
end
if ~isscalar(mpc.baseMVA) || ~isfinite(mpc.baseMVA) || mpc.baseMVA <= 0
    error('composite_dae:unsupportedCaseSchema', ...
        'case_data.mpc.baseMVA must be a positive finite scalar.');
end
if ~ismatrix(mpc.bus) || size(mpc.bus,1) < 1
    error('composite_dae:unsupportedCaseSchema', ...
        'case_data.mpc.bus must have at least one row.');
end
if ~ismatrix(mpc.branch) || size(mpc.branch,1) < 1
    error('composite_dae:unsupportedCaseSchema', ...
        'case_data.mpc.branch must have at least one row.');
end
% --- Power flow (in-house Newton) for the shared network ------------------
pf = pfsolver.powerflow_newton_raphson(case_data, struct('verbose',false, ...
    'plot_results',false,'max_iter',50,'tolerance',1e-10,'enforce_q_limits',false));
if ~pf.converged
    error('composite_dae:powerFlow','In-house Newton PF did not converge.');
end
bus_ids = pf.external_bus_ids(:);
nb = numel(bus_ids);
% --- Build Ybus + load admittance (shared network) -----------------------
Ynet = build_ybus_local(mpc, pf);

% --- Validate devices and assign deterministic offsets --------------------
nd = numel(devices);
device_ids = cell(nd,1);
offsets = zeros(nd,1);   % 0-based start offset for x
u_offsets = zeros(nd,1);
nx_total = 0; nu_total = 0;
bus_map = zeros(nd,1);
for k = 1:nd
    dev = devices(k);
    % Required fields.
    req = {'name','device_id','bus_id','nx','nu','f','current_injection', ...
        'electrical_power','x0','u0','state_names','reconstruct'};
    for r = 1:numel(req)
        if ~isfield(dev, req{r})
            error('composite_dae:missingDeviceField', ...
                'Device %d missing required field "%s".', k, req{r});
        end
    end
    % Unique device_id.
    if any(strcmp(device_ids, dev.device_id))
        error('composite_dae:duplicateDeviceId', ...
            'Duplicate device_id "%s".', dev.device_id);
    end
    device_ids{k} = dev.device_id;
    % Finite x0.
    if ~all(isfinite(dev.x0(:)))
        error('composite_dae:nonFiniteX0', ...
            'Device "%s" has non-finite x0.', dev.device_id);
    end
    % Map bus_id (external) to internal index.
    bidx = find(bus_ids == dev.bus_id, 1);
    if isempty(bidx)
        error('composite_dae:badBusId', ...
            'Device "%s" bus_id %d not found in network bus_ids.', ...
            dev.device_id, dev.bus_id);
    end
    bus_map(k) = bidx;
    % Offsets (1-based inclusive ranges stored in metadata).
    offsets(k) = nx_total;
    u_offsets(k) = nu_total;
    nx_total = nx_total + dev.nx;
    nu_total = nu_total + dev.nu;
end

% --- Composite x0, u0 -----------------------------------------------------
x0 = zeros(nx_total,1);
u0 = zeros(nu_total,1);
for k = 1:nd
    dev = devices(k);
    x0(offsets(k)+1 : offsets(k)+dev.nx) = dev.x0(:);
    if dev.nu > 0
        u0(u_offsets(k)+1 : u_offsets(k)+dev.nu) = dev.u0(:);
    end
end

% --- Shared y0 from PF ----------------------------------------------------
V0 = pf.bus_voltage(:).*exp(1i*deg2rad(pf.bus_angle_deg(:)));
y0 = zeros(2*nb,1);
y0(1:2:end) = real(V0); y0(2:2:end) = imag(V0);

% --- Topology (Ypre/Yfault/Ypost) ----------------------------------------
Ypre = Ynet;
Yfault = Ypre; Ypost = Ypre;
fault_bus = [];
if isfield(opt,'fault_bus') && ~isempty(opt.fault_bus)
    fault_bus = opt.fault_bus;
end
Zf = [];
if isfield(opt,'Zf') && ~isempty(opt.Zf), Zf = opt.Zf; end
if ~isempty(fault_bus) && ~isempty(Zf)
    fb = find(bus_ids == fault_bus, 1);
    if ~isempty(fb)
        Yfault(fb,fb) = Yfault(fb,fb) + 1/Zf;
    end
end

% --- B4: Optional explicit vcon (voltage constraint) input contract --------
% vcon is OPTIONAL. When present, it declares KCL residual rows to be
% REPLACED by FIXED y-only constraint equations (e.g. slack-bus voltage
% specification). Explicit, declared — never inferred from bus type.
%
% Contract (frozen):
%   opt.vcon.vars - algebraic variable indices constrained (1-based into y)
%   opt.vcon.rows - KCL residual rows replaced (1-based into g, length 2*nb)
%   opt.vcon.eq  - USER-FACING constraint residual eq(y, ref), FIXED y-only
%   opt.vcon.ref - reference value(s) bound into eq (scalar or vector)
%
% Cardinality: numel(vars)==numel(rows) REQUIRED (one replaced row per
% constraint). INDEX VALUES may differ (vars=[1,2],rows=[3,4] is VALID).
% The runtime handle stored is vcon_eq(x,y) = eq(y,ref) (adapter drops x,
% binds ref); the user-facing eq(y,ref) is NEVER called by multimachine_ssa.
% Serializable metadata dae.vcon stores vars/rows/kind only (NO handle).
vcon = struct('vars',[],'rows',[],'eq',[],'ref',[],'kind','');
has_vcon = isfield(opt,'vcon') && ~isempty(opt.vcon) && ...
    (~isempty(opt.vcon.vars) || ~isempty(opt.vcon.rows));
if has_vcon
    v = opt.vcon;
    if ~isstruct(v) || ~isfield(v,'vars') || ~isfield(v,'rows') || ~isfield(v,'eq')
        error('composite_dae:partialVcon', ...
            'vcon requires fields vars, rows, eq (and ref for eq(y,ref)).');
    end
    vcon.vars = v.vars(:).';
    vcon.rows = v.rows(:).';
    if ~isa(v.eq,'function_handle')
        error('composite_dae:badVconEq', 'vcon.eq must be a function handle eq(y,ref).');
    end
    if isfield(v,'ref') && ~isempty(v.ref)
        vcon.ref = v.ref;
    else
        vcon.ref = [];
    end
    % Cardinality: numel(vars)==numel(rows) REQUIRED.
    if numel(vcon.vars) ~= numel(vcon.rows)
        error('composite_dae:vconCardinality', ...
            'vcon.vars (%d) and vcon.rows (%d) must have EQUAL cardinality (index values may differ).', ...
            numel(vcon.vars), numel(vcon.rows));
    end
    % Validate indices: unique, finite integers, in range.
    nr = 2*nb; ny = 2*nb;
    all_idx = [vcon.vars, vcon.rows];
    if any(all_idx ~= floor(all_idx)) || any(all_idx < 1) || ...
       any(vcon.vars > ny) || any(vcon.rows > nr) || ...
       numel(unique(vcon.vars)) ~= numel(vcon.vars) || ...
       numel(unique(vcon.rows)) ~= numel(vcon.rows)
        error('composite_dae:badVconIndex', ...
            'vcon indices must be unique finite integers in range.');
    end
    % Build the runtime adapter @(x,y) eq(y, ref). FIXED y-only: drops x,
    % binds ref. The runtime handle keeps the (x,y) ABI so the SAME SSSA
    % checker path works for any future non-y-only variant (B6 verifies
    % dvcon_eq/dx==0 at runtime).
    ref_bound = vcon.ref;
    vcon_eq_handle = @(x,y) v.eq(y, ref_bound);
    vcon.eq = vcon_eq_handle;
    vcon.kind = 'fixed_y_only';
    vcon.ref_serializable = ref_bound;   % for metadata (no handle)
end

% --- Composite closures ---------------------------------------------------
% dae_f(t,x,y,u,event_context): concatenate device differential RHS.
dae_f = @(t,x,y,u,event_context) composite_f(t, x, y, u, event_context, ...
    devices, offsets, u_offsets);
% dae_g(t,x,y,Y,u,event_context): network KCL g = Y*V - Ibus (canonical YV-I),
% with declared vcon rows REPLACED by vcon_eq components (B4).
dae_g = @(t,x,y,Y,u,event_context) composite_g(t, x, y, Y, u, event_context, ...
    devices, offsets, u_offsets, bus_map, nb, vcon);
% current_injection(t,x,y,u,event_context): Ibus per bus (complex).
current_injection = @(t,x,y,u,event_context) composite_Ibus(t, x, y, u, ...
    event_context, devices, offsets, u_offsets, bus_map, nb);
% electrical_power(t,x,y,u,event_context): per-device Pe.
electrical_power = @(t,x,y,u,event_context) composite_Pe(t, x, y, u, ...
    event_context, devices, offsets, u_offsets);
% reconstruct(t,x,y,u,event_context): per-device outputs.
reconstruct = @(t,x,y,u,event_context) composite_reconstruct(t, x, y, u, ...
    event_context, devices, offsets, u_offsets);

% --- Assemble dae struct --------------------------------------------------
dae = struct();
dae.model = 'composite';
dae.pf = pf;
dae.bus_ids = bus_ids;
dae.nb = nb;
dae.nd = nd;
dae.devices = devices;
dae.device_offsets = offsets;
dae.u_offsets = u_offsets;
dae.bus_map = bus_map;
dae.x0 = x0; dae.y0 = y0; dae.u0 = u0;
dae.dae_f = dae_f;
dae.dae_g = dae_g;
dae.current_injection = current_injection;
dae.electrical_power = electrical_power;
dae.reconstruct = reconstruct;
dae.Ynet = Ynet;
dae.topology = struct('Ypre',Ypre,'Yfault',Yfault,'Ypost',Ypost);
dae.mapping = struct('bus_ids',bus_ids,'gen_buses',arrayfun(@(k) devices(k).bus_id, 1:nd));
% Per-device metadata (no function handles serialized). Build as a struct
% array (one entry per device) to avoid cell-field assignment ambiguity.
meta = repmat(struct('device_id','','device_type','','bus_id',0, ...
    'nx',0,'nu',0,'x_range',[],'u_range',[]), nd, 1);
for k = 1:nd
    dev = devices(k);
    meta(k).device_id = dev.device_id;
    meta(k).device_type = '';
    if isfield(dev,'device_type'), meta(k).device_type = dev.device_type; end
    meta(k).bus_id = dev.bus_id;
    meta(k).nx = dev.nx; meta(k).nu = dev.nu;
    meta(k).x_range = (offsets(k)+1):(offsets(k)+dev.nx);
    meta(k).u_range = (u_offsets(k)+1):(u_offsets(k)+dev.nu);
end
dae.metadata = meta;
% B4: vcon ownership. Store the runtime handle separately (NOT serialized
% with metadata). dae.vcon holds serializable ownership data only.
if has_vcon
    dae.vcon_eq = vcon.eq;   % runtime handle model.vcon_eq(x,y), for SSSA
    dae.vcon = struct('vars',vcon.vars,'rows',vcon.rows, ...
        'kind',vcon.kind,'ref',vcon.ref_serializable);
else
    dae.vcon = struct('vars',[],'rows',[],'kind','','ref',[]);
end
end

% =========================================================================
function dx = composite_f(t, x, y, u, event_context, devices, offsets, u_offsets)
nd = numel(devices);
dx = zeros(numel(x),1);
for k = 1:nd
    dev = devices(k);
    xr = offsets(k)+1 : offsets(k)+dev.nx;
    ur = u_offsets(k)+1 : u_offsets(k)+dev.nu;
    if dev.nu == 0
        u_dev = [];
    else
        u_dev = u(ur);
    end
    dx(xr) = dev.f(t, x(xr), y, u_dev, event_context);
end
end

function g = composite_g(t, x, y, Y, u, event_context, devices, offsets, u_offsets, bus_map, nb, vcon)
% Canonical KCL: g = Y*V - Ibus (YV-I). Devices return positive injection.
% B4: when vcon is declared, the KCL residual rows in vcon.rows are
% REPLACED (exactly once each) by the corresponding vcon_eq(x,y) components.
V = complex(y(1:2:end), y(2:2:end));
Ibus = composite_Ibus(t, x, y, u, event_context, devices, offsets, u_offsets, bus_map, nb);
gc = Y*V - Ibus;   % canonical YV-I
g = zeros(2*nb,1);
g(1:2:end) = real(gc); g(2:2:end) = imag(gc);
% B4: replace declared KCL rows with vcon_eq components (FIXED y-only).
if ~isempty(vcon.rows)
    gcon = vcon.eq(x, y);   % runtime adapter @(x,y) eq(y,ref)
    if numel(gcon) ~= numel(vcon.rows)
        error('composite_dae:vconEqDim', ...
            'vcon.eq output length %d must match vcon.rows length %d.', ...
            numel(gcon), numel(vcon.rows));
    end
    g(vcon.rows) = gcon(:);
end
end

function Ibus = composite_Ibus(t, x, y, u, event_context, devices, offsets, u_offsets, bus_map, nb)
Ibus = zeros(nb,1);
for k = 1:numel(devices)
    dev = devices(k);
    xr = offsets(k)+1 : offsets(k)+dev.nx;
    ur = u_offsets(k)+1 : u_offsets(k)+dev.nu;
    if dev.nu == 0
        u_dev = [];
    else
        u_dev = u(ur);
    end
    Iinj = dev.current_injection(t, x(xr), y, u_dev, event_context);
    Ibus(bus_map(k)) = Ibus(bus_map(k)) + Iinj;
end
end

function Pe = composite_Pe(t, x, y, u, event_context, devices, offsets, u_offsets)
nd = numel(devices);
Pe = zeros(nd,1);
for k = 1:nd
    dev = devices(k);
    xr = offsets(k)+1 : offsets(k)+dev.nx;
    ur = u_offsets(k)+1 : u_offsets(k)+dev.nu;
    if dev.nu == 0
        u_dev = [];
    else
        u_dev = u(ur);
    end
    Pe(k) = dev.electrical_power(t, x(xr), y, u_dev, event_context);
end
end

function out = composite_reconstruct(t, x, y, u, event_context, devices, offsets, u_offsets)
nd = numel(devices);
out.devices = cell(nd,1);
for k = 1:nd
    dev = devices(k);
    xr = offsets(k)+1 : offsets(k)+dev.nx;
    ur = u_offsets(k)+1 : u_offsets(k)+dev.nu;
    if dev.nu == 0
        u_dev = [];
    else
        u_dev = u(ur);
    end
    out.devices{k} = dev.reconstruct(t, x(xr), y, u_dev, event_context);
end
end

% =========================================================================
function Y = build_ybus_local(mpc, pf)
% Build Ybus + load admittance from mpc + PF result (mirrors classical_dae).
bus = mpc.bus; br = mpc.branch; nb = size(bus,1); Y = complex(zeros(nb));
for k = 1:size(br,1)
    if br(k,11) == 0, continue; end
    i = find(bus(:,1)==br(k,1),1); j = find(bus(:,1)==br(k,2),1);
    r = br(k,3); x = br(k,4); b = br(k,5); tap = br(k,9); shift = br(k,10);
    if tap == 0, tap = 1; end
    a = tap*exp(1i*deg2rad(shift)); yser = 1/(r+1i*x);
    Y(i,i) = Y(i,i) + yser/(a*conj(a)) + 1i*b/2;
    Y(j,j) = Y(j,j) + yser + 1i*b/2;
    Y(i,j) = Y(i,j) - yser/conj(a);
    Y(j,i) = Y(j,i) - yser/a;
end
% MATPOWER bus shunts: GS+jBS are specified in MW/MVAr at V=1 pu and enter
% Ybus directly on the system base. This is the same sourced network contract
% used by the in-house PF/classical PF-TS-SSSA builders.
Y = Y + diag((bus(:,5) + 1i*bus(:,6))/mpc.baseMVA);
V0 = pf.bus_voltage(:).*exp(1i*deg2rad(pf.bus_angle_deg(:)));
Sload = (bus(:,3) + 1i*bus(:,4))/mpc.baseMVA;
Yload = conj(Sload)./(abs(V0).^2 + eps);
Y = Y + diag(Yload);
end
