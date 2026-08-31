
% =====================================================================
% DIAGNOSTIC CLONE (ASSUMED_DIAGNOSTIC) -- comparison-only, NOT production.
% Identical to eecon49_dual_mode_model except the DC-source closure, which reverts to the
% retired ideal EECON49 law (dVdc/dt=(Vdc0-Vdc)/Tdc, Tdc=0.10 s). The
% non-ideal Thevenin closure collapses Vdc->0 in an all-GFL island
% (constant-power-load singularity, Pac/vdc -> Inf), which is why the
% delivered locked_gfl arm cannot integrate past t=22.08 s. The EECON49
% paper's Fixed-GFL figure used the ideal closure, so this clone
% reproduces that comparison. Production builds are untouched: this file
% is reachable only through scenario_opt.ibr_factory_override in a
% diagnostic runner.
% =====================================================================

function dev = eecon49_dual_mode_ideal_dc(device_id,bus_id,bus_position, ...
    bus_ids,V0,params,P_ref_pu,Q_ref_pu,E_ref_pu,mode)
%EECON49_DUAL_MODE_MODEL  Fixed-layout EECON49 GFL/GFM IBR.
%
% Source model: docs/text/EECON49_[Nui].pdf, Eqs. (6)--(29), Fig. 2.
% The electrical plant is shared while the two controller branches remain
% distinct.  This corrects the former source mismatch in which the EECON49
% case dispatched to WECC GFL (no PLL) + REGFM_B1 GFM (with PLL).
%
% Superset state (16, fixed):
%   common plant 1:3
%     [i_d i_q V_dc]
%   GFL controller 4:9 (PLL present)
%     [delta_PLL xi_PLL xi_P xi_Q xi_Id xi_Iq]
%   GFM controller 10:16 (NO PLL)
%     [delta_VSG omega_VSG E xi_Vd xi_Vq xi_Id xi_Iq]
%
% Active states are 9 in GFL and 10 in GFM. The two command-delay states per
% branch (source Eqs. 20-21) are reduced out by singular perturbation: the
% physical actuation delay T_d = 1.5/f_sw ~= 0.3 ms (f_sw = 5 kHz) is >300x
% below the phasor step dt = 0.10 s, so v_del = v_cmd algebraically and the
% AC current dynamics use the commanded voltage directly (defect
% TD-2026-08-12-01). The source publishes the DC energy balance but not its
% I_dc law, so the shared V_dc state is closed by a project-derived NON-IDEAL
% DC source: an EMF behind its internal resistance with an overvoltage chopper,
% Idc = (Edc - Vdc)/Rdc, derived in ibr.dc_source_thevenin_params and evaluated
% by ibr.dc_source_thevenin_rhs. Both controller branches call the same helper
% with the same arguments, so Edc agrees between them and a runtime transfer
% preserves dVdc/dt as well as V_dc. This replaces an earlier closure whose
% exact power feed-forward made V_dc identically constant (measured range 0 over
% 250 s) and made the case capacitance Cdc cancel out of every residual.
%
% Fixed input ABI:
%   u = [P_ref; Q_ref; E_ref].
% Both branches consume P_ref,Q_ref.  In GFM mode E_ref is the external
% terminal-voltage reference in the VSG amplitude-state equation; it is not
% the measured terminal-voltage magnitude.
%
% Runtime transfer is PROJECT_DERIVED.  It preserves terminal V/I/P/Q and
% V_dc, initializes only the target controller from the same terminal port,
% and verifies current continuity before the event transaction may proceed.

arguments
    device_id (1,1) string
    bus_id (1,1) double
    bus_position (1,1) double
    bus_ids (1,:) double
    V0 (1,1) double
    params struct
    P_ref_pu (1,1) double
    Q_ref_pu (1,1) double
    E_ref_pu (1,1) double
    mode (1,1) string {mustBeMember(mode,["gfl","GFM","tripped"])}
end

if ~isfinite(V0) || abs(V0)<=0
    error('ibr:eecon49_dual_mode_model:badV0', ...
        'V0 must be finite and nonzero.');
end
if any(~isfinite([P_ref_pu Q_ref_pu E_ref_pu])) || E_ref_pu<=0
    error('ibr:eecon49_dual_mode_model:badRef', ...
        'P_ref and Q_ref must be finite; E_ref must be finite and positive.');
end

gfl_dev=ibr.gfl_eecon49_full_model_ideal_dc(device_id,bus_id,bus_position, ...
    bus_ids,V0,params,P_ref_pu,Q_ref_pu);
gfm_dev=ibr.gfm_eecon49_full_model_ideal_dc(device_id,bus_id,bus_position, ...
    bus_ids,V0,params,P_ref_pu,Q_ref_pu,E_ref_pu);

% Both branches expose 10 states without the DC-source current and 11 with it
% (dc_source.source_state). They must agree, because the superset is sized from
% them and the source coordinate is shared plant.
if ~ismember(gfl_dev.nx,[10 11]) || gfl_dev.nx~=gfm_dev.nx
    error('ibr:eecon49_dual_mode_model:branchLayout', ...
        ['EECON49 branch adapters must each expose 10 or 11 states and must ' ...
         'agree; got GFL %d and GFM %d.'],gfl_dev.nx,gfm_dev.nx);
end
n_src=double(gfl_dev.nx==11);   % 1 when the DC-source current is a state
nx_dev=16+n_src;

gx=gfl_dev.x0(:); mx=gfm_dev.x0(:);
% Both DC plant coordinates must agree between the branches, not just the
% voltage: the source current is shared too, and a disagreement would step
% dIdc/dt across a mode transfer.
if abs(gx(3)-mx(3))>1e-12 || (n_src==1 && abs(gx(11)-mx(11))>1e-12)
    error('ibr:eecon49_dual_mode_model:commonPlantInit', ...
        'GFL/GFM DC plant initial states disagree (V_dc and/or I_dc).');
end
x0=merge_branches(gx,mx,mode);
u0=[P_ref_pu;Q_ref_pu;E_ref_pu];

% Index 17 is the DC-source current, a PLANT coordinate appended after the two
% controller blocks so that every published index 1..16 keeps its meaning. It is
% always active, exactly like indices 1..3.
gfl_active=1:9; gfm_active=[1:3 10:16];
if n_src==1, gfl_active=[gfl_active 17]; gfm_active=[gfm_active 17]; end

% Runtime hybrid_state field key. This is a pure function of the constant
% device_id, but resolve_status used to rebuild it with
% matlab.lang.makeValidName on EVERY closure call. Profiling the compressed
% chronology arm (3.5 s of simulated time) measured 2,025,509 resolve_status
% calls costing 157.3 s of a 400.8 s profiled run, because the coupled FD
% Jacobian evaluates the residual once per unknown column and each residual
% evaluation calls both dual_f and dual_current for every device. Hoisting the
% key changes no value anywhere: the same string is now computed once here and
% threaded into the closures.
status_key=matlab.lang.makeValidName(char(device_id), ...
    'ReplacementStyle','underscore');

f=@(t,x,y,u,ec) dual_f(t,x,y,u,ec,status_key,mode,gfl_dev,gfm_dev,u0);
current=@(t,x,y,u,ec) dual_current(t,x,y,u,ec,status_key,mode,gfl_dev,gfm_dev,u0);
power=@(t,x,y,u,ec) real(bus_voltage(y,bus_position)*conj( ...
    current(t,x,y,u,ec)));
recon=@(t,x,y,u,ec) dual_reconstruct(t,x,y,u,ec,status_key,mode, ...
    gfl_dev,gfm_dev,u0,bus_position);
eq=@(V,P,Q,ec) equilibrium_initialize(V,P,Q,ec,status_key,mode, ...
    gfl_dev,gfm_dev,x0);
active=@(ec) active_indices(ec,status_key,mode,gfl_active,gfm_active);
transfer=@(x,y,u,ecl,target,ecr,varargin) transfer_state( ...
    x,y,u,ecl,target,ecr,status_key,mode,gfl_dev,gfm_dev,u0, ...
    bus_position,varargin{:});

state_names={'i_d','i_q','V_dc', ...
    'gfl_delta_PLL','gfl_xi_PLL','gfl_xi_P','gfl_xi_Q', ...
    'gfl_xi_Id','gfl_xi_Iq', ...
    'gfm_delta_VSG','gfm_omega_VSG','gfm_E','gfm_xi_Vd','gfm_xi_Vq', ...
    'gfm_xi_Id','gfm_xi_Iq'};
if n_src==1, state_names{17}='I_dc'; end

dev=struct();
dev.name=char(device_id); dev.device_id=char(device_id);
dev.bus_id=bus_id; dev.bus_position=bus_position; dev.bus_ids=bus_ids(:).';
dev.device_type='ibr_eecon49_dual';
dev.mode=char(mode); dev.initial_mode=char(mode); dev.initial_online=true;
dev.nx=nx_dev; dev.nu=3; dev.state_names=state_names;
dev.input_names={'P_ref','Q_ref','E_ref'};
dev.x0=x0; dev.u0=u0; dev.f=f; dev.current_injection=current;
dev.electrical_power=power; dev.reconstruct=recon;
dev.equilibrium_initialize=eq;
dev.active_state_indices_for_context=active;
dev.dynamic_state_indices_for_context=active;
dev.equilibrium_constraint_specs=[];
dev.mode_transfer_state=transfer; dev.transfer_state=transfer;
dev.mode_transfer=transfer;
switch char(mode)
case 'gfl', dev.active_state_indices=gfl_active;
case 'GFM', dev.active_state_indices=gfm_active;
otherwise, dev.active_state_indices=[];
end
dev.frozen_state_indices=[];
dev.frozen_state_values=[];
dev.frozen_state_source='';
dev.frozen_state_classification='';
dev.provenance=struct( ...
    'model','EECON49_GFL_GFM_SHARED_PLANT_DUAL', ...
    'source','EECON49-P4 Eqs.(6)-(29), Figs.1-2 and parameter table', ...
    'classification','SOURCE_MAPPED AC/control equations; PROJECT_DERIVED fixed superset/transfer/DC regulator', ...
    'details',[sprintf('%d states',nx_dev) ' = common plant 3 or 4 (i_d,i_q,V_dc, I_dc at index ' ...
        '17) + GFL controller 6 (PLL) + GFM controller 7 (VSG, no PLL); ' ...
        'active GFL=10 and active GFM=11; command-delay states reduced ' ...
        '(v_del=v_cmd, T_d<<dt); Tdc retired, DC source is Thevenin with ' ...
        'a current state, tau_s=Ls/Rdc']);
end

% -------------------------------------------------------------------------
function dx=dual_f(t,x,y,u,ec,id,default_mode,gfl,gfm,u0)
validate_state(x); u=resolve_u(u,u0);
[online,m]=resolve_status(ec,id,default_mode);
dx=zeros(numel(x),1);
if ~online || strcmp(m,'tripped'), return; end
switch m
case 'gfl'
    dg=gfl.f(t,to_gfl(x),y,u(1:2),ec);
    dx(1:3)=dg(1:3); dx(4:9)=dg(4:9);
    % The DC-source current is shared plant at superset index 17 and branch
    % index 11. Omitting this row leaves it identically zero, which makes the
    % reduced equilibrium Jacobian singular rather than merely wrong.
    if numel(dx)>=17, dx(17)=dg(11); end
case 'GFM'
    dm=gfm.f(t,to_gfm(x),y,u,ec);
    dx(1:3)=dm(1:3); dx(10:16)=dm(4:10);
    if numel(dx)>=17, dx(17)=dm(11); end
end
if any(~isfinite(dx))
    error('ibr:eecon49_dual_mode_model:nonfiniteRhs','Non-finite EECON49 RHS.');
end
end

function I=dual_current(t,x,y,u,ec,id,default_mode,gfl,gfm,u0)
validate_state(x); u=resolve_u(u,u0);
[online,m]=resolve_status(ec,id,default_mode);
if ~online || strcmp(m,'tripped'), I=0+0i; return; end
if strcmp(m,'gfl')
    I=gfl.current_injection(t,to_gfl(x),y,u(1:2),ec);
else
    I=gfm.current_injection(t,to_gfm(x),y,u,ec);
end
if ~isscalar(I) || ~isfinite(I)
    error('ibr:eecon49_dual_mode_model:nonfiniteCurrent', ...
        'EECON49 current injection must be one finite scalar.');
end
end

function out=dual_reconstruct(t,x,y,u,ec,id,default_mode,gfl,gfm,u0,bp)
validate_state(x); u=resolve_u(u,u0);
[online,m]=resolve_status(ec,id,default_mode);
out=struct('mode',char(m),'online',online,'bus_position',bp);
if ~online
    out.current=0+0i; out.electrical_power=0; out.breaker_open=true; return;
end
switch m
case 'gfl'
    b=gfl.reconstruct(t,to_gfl(x),y,u(1:2),ec);
    b.kappa=gfl.provenance.params.kappa;
    out.gfl=b;
case 'GFM'
    b=gfm.reconstruct(t,to_gfm(x),y,u,ec);
    p=gfm.provenance.params;
    b.omega_m=b.omega-1;
    b.delta_VSM=b.delta;
    b.delta_IT=b.delta;
    b.H_system=0.5*p.M/p.kappa;
    b.ImaxF_sys=p.Imax/p.kappa;
    b.kappa=p.kappa;
    out.gfm=b;
case 'tripped'
    out.tripped=true;
end
end

function xeq=equilibrium_initialize(V,P,Q,ec,id,default_mode,gfl,gfm,xwarm)
[online,m]=resolve_status(ec,id,default_mode);
xeq=xwarm(:);
if ~online || strcmp(m,'tripped')
    if any(~isfinite([P Q])) || abs(P)>64*eps(max(1,abs(P))) || ...
            abs(Q)>64*eps(max(1,abs(Q)))
        error('ibr:eecon49_dual_mode_model:offlineEquilibriumPower', ...
            'Offline/tripped equilibrium requires zero terminal P and Q.');
    end
    return;
end
if strcmp(m,'gfl')
    xeq=put_gfl(xeq,gfl.equilibrium_initialize(V,P,Q,ec));
else
    xeq=put_gfm(xeq,gfm.equilibrium_initialize(V,P,Q,ec));
end
end

function idx=active_indices(ec,id,default_mode,gfl_idx,gfm_idx)
[online,m]=resolve_status(ec,id,default_mode);
if ~online || strcmp(m,'tripped'), idx=[]; return; end
if strcmp(m,'gfl'), idx=gfl_idx; else, idx=gfm_idx; end
end

function [xr,info]=transfer_state(xl,y,u,ecl,target,ecr,id,default_mode, ...
    gfl,gfm,u0,bp,varargin)
tol=1e-10;
if ~isempty(varargin)
    a=varargin{1};
    if isstruct(a) && isfield(a,'AbsTol'), tol=a.AbsTol;
    elseif isstruct(a) && isfield(a,'tol'), tol=a.tol;
    elseif isnumeric(a) && isscalar(a), tol=a;
    end
end
if ~isscalar(tol) || ~isfinite(tol) || tol<=0
    error('ibr:transfer_maps:badTol','Transfer tolerance must be finite positive.');
end
validate_state(xl); u=resolve_u(u,u0);
V=bus_voltage(y,bp);
Ileft=dual_current(0,xl,y,u,ecl,id,default_mode,gfl,gfm,u0);
S=V*conj(Ileft); P=real(S); Q=imag(S);
[~,source]=resolve_status(ecl,id,default_mode);
target=canonical_mode(target);
xr=xl(:);
if strcmp(target,'GFM')
    mt=gfm.equilibrium_initialize(V,P,Q,ecr);
    % Carry physical frequency through the coordinate reset when available.
    if strcmp(source,'gfl')
        gr=gfl.reconstruct(0,to_gfl(xl),y,u(1:2),ecl);
        if isfield(gr,'omega_PLL_pu') && isfinite(gr.omega_PLL_pu)
            mt(5)=gr.omega_PLL_pu;
        end
    end
    % Both DC plant coordinates are carried across the transfer unchanged.
    vdc=xl(3); xr=put_gfm(xr,mt); xr(3)=vdc;
    if numel(xl)>=17, xr(17)=xl(17); end
elseif strcmp(target,'gfl')
    gt=gfl.equilibrium_initialize(V,P,Q,ecr);
    if strcmp(source,'GFM')
        mr=gfm.reconstruct(0,to_gfm(xl),y,u,ecl);
        p=gfl.provenance.params;
        if isfield(mr,'omega') && isfinite(mr.omega) && p.kiPLL>0
            gt(5)=p.omega_b*(mr.omega-1)/p.kiPLL;
        end
    end
    vdc=xl(3); xr=put_gfl(xr,gt); xr(3)=vdc;
    if numel(xl)>=17, xr(17)=xl(17); end
elseif ~strcmp(target,'tripped')
    error('ibr:transfer_maps:unsupportedMode','Unsupported target mode.');
end

ecr=set_context_mode(ecr,ecl,id,target);
if strcmp(target,'tripped')
    Iright=0+0i; Pright=0; Qright=0;
else
    Iright=dual_current(0,xr,y,u,ecr,id,default_mode,gfl,gfm,u0);
    Sr=V*conj(Iright); Pright=real(Sr); Qright=imag(Sr);
    if abs(Iright-Ileft)>tol
        error('ibr:transfer_maps:currentContinuity', ...
            'EECON49 transfer current jump %.3g exceeds %.3g.', ...
            abs(Iright-Ileft),tol);
    end
end
info=struct('Vbus',V,'I_left',Ileft,'I_right',Iright, ...
    'P_left',P,'Q_left',Q,'P_right',Pright,'Q_right',Qright, ...
    'tol',tol,'source_mode',source,'target_mode',target, ...
    'common_indices',1:3,'gfl_indices',4:9,'gfm_indices',10:16, ...
    'Vdc_left',xl(3),'Vdc_right',xr(3), ...
    'Idc_left',dc_coord(xl),'Idc_right',dc_coord(xr));
end

function ec=set_context_mode(ec,fallback,key,target)
% KEY is the sanitized hybrid_state field name produced once by the
% constructor (status_key). It is already a valid MATLAB name, and
% matlab.lang.makeValidName is idempotent on a valid name, so using it
% directly writes the identical field this function wrote before.
if isempty(ec) || ~isstruct(ec), ec=fallback; end
if isempty(ec) || ~isstruct(ec), ec=struct(); end
if ~isfield(ec,'hybrid_state') || ~isstruct(ec.hybrid_state)
    ec.hybrid_state=struct();
end
if ~isfield(ec.hybrid_state,'device_modes') || ...
        ~isstruct(ec.hybrid_state.device_modes)
    ec.hybrid_state.device_modes=struct();
end
if ~isfield(ec.hybrid_state,'device_online') || ...
        ~isstruct(ec.hybrid_state.device_online)
    ec.hybrid_state.device_online=struct();
end
ec.hybrid_state.device_modes.(key)=target;
ec.hybrid_state.device_online.(key)=true;
end

function [online,m]=resolve_status(ec,key,default_mode)
% KEY is the constructor's status_key (see the hoist note at the top of this
% file). Reading it straight from the argument removes the per-call
% matlab.lang.makeValidName that dominated the profile; the resolved field name
% is bit-for-bit the same string, so online/mode resolution is unchanged.
online=true; raw=char(default_mode);
if ~isempty(ec) && isstruct(ec) && isfield(ec,'hybrid_state') && ...
        isstruct(ec.hybrid_state)
    hs=ec.hybrid_state;
    if isfield(hs,'device_online') && isstruct(hs.device_online) && ...
            isfield(hs.device_online,key)
        v=hs.device_online.(key);
        if ~(islogical(v) && isscalar(v))
            error('ibr:eecon49_dual_mode_model:badRuntimeOnline', ...
                'Runtime online flag must be one logical scalar.');
        end
        online=v;
    end
    if isfield(hs,'device_modes') && isstruct(hs.device_modes) && ...
            isfield(hs.device_modes,key)
        raw=hs.device_modes.(key);
    end
end
m=canonical_mode(raw);
end

function m=canonical_mode(raw)
if ~(ischar(raw) || (isstring(raw) && isscalar(raw)))
    error('ibr:eecon49_dual_mode_model:badRuntimeMode', ...
        'Runtime mode must be text.');
end
switch lower(strtrim(char(raw)))
case 'gfl', m='gfl';
case 'gfm', m='GFM';
case 'tripped', m='tripped';
otherwise
    error('ibr:eecon49_dual_mode_model:badRuntimeMode', ...
        'Unsupported runtime mode %s.',char(raw));
end
end

function u=resolve_u(u,u0)
if isempty(u), u=u0; end
if ~isvector(u) || numel(u)~=3 || any(~isfinite(u))
    error('ibr:eecon49_dual_mode_model:badInput', ...
        'Expected three finite inputs [P_ref;Q_ref;E_ref].');
end
u=u(:);
if u(3)<=0
    error('ibr:eecon49_dual_mode_model:badInput', ...
        'E_ref must be positive.');
end
end

function validate_state(x)
if ~isvector(x) || ~ismember(numel(x),[16 17]) || any(~isfinite(x))
    error('ibr:eecon49_dual_mode_model:badState', ...
        'Expected 16 or 17 finite EECON49 superset states.');
end
end

function v=dc_coord(x)
% The source current when the layout has one, NaN when it does not. NaN is the
% repository convention for "not applicable", never a stand-in for a value.
if numel(x)>=17, v=x(17); else, v=NaN; end
end

% The DC-source current, when present, sits at branch index 11 and superset index
% 17. Every map below reads its own argument's length rather than a threaded flag,
% so a 16-state and a 17-state device use the same code with no configuration
% argument to keep in sync.
function x=merge_branches(g,m,mode)
ns=double(numel(g)>=11);
x=zeros(16+ns,1);
if strcmpi(mode,'GFM'), x(1:3)=m(1:3); else, x(1:3)=g(1:3); end
x(4:9)=g(4:9); x(10:16)=m(4:10);
if ns==1
    if strcmpi(mode,'GFM'), x(17)=m(11); else, x(17)=g(11); end
end
end
function g=to_gfl(x)
g=[x(1:9);0];
if numel(x)>=17, g(11)=x(17); end
end
function m=to_gfm(x)
m=[x(1:3);x(10:16)];
if numel(x)>=17, m(11)=x(17); end
end
function x=put_gfl(x,g)
x(1:3)=g(1:3); x(4:9)=g(4:9);
if numel(x)>=17 && numel(g)>=11, x(17)=g(11); end
end
function x=put_gfm(x,m)
x(1:3)=m(1:3); x(10:16)=m(4:10);
if numel(x)>=17 && numel(m)>=11, x(17)=m(11); end
end

function V=bus_voltage(y,bp)
if numel(y)<2*bp || any(~isfinite(y(2*bp-1:2*bp)))
    error('ibr:transfer_maps:badVoltage','Missing finite terminal voltage.');
end
V=complex(y(2*bp-1),y(2*bp));
if abs(V)<=1e-12
    error('ibr:transfer_maps:badVoltage','Terminal voltage is too small.');
end
end
