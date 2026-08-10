function dev = eecon49_dual_mode_model(device_id,bus_id,bus_position, ...
    bus_ids,V0,params,P_ref_pu,Q_ref_pu,E_ref_pu,mode)
%EECON49_DUAL_MODE_MODEL  Fixed-layout EECON49 GFL/GFM IBR.
%
% Source model: docs/text/EECON49_[Nui].pdf, Eqs. (6)--(29), Fig. 2.
% The electrical plant is shared while the two controller branches remain
% distinct.  This corrects the former source mismatch in which the EECON49
% case dispatched to WECC GFL (no PLL) + REGFM_B1 GFM (with PLL).
%
% Superset state (20, fixed):
%   common plant 1:3
%     [i_d i_q V_dc]
%   GFL controller 4:11 (PLL present)
%     [delta_PLL xi_PLL xi_P xi_Q xi_Id xi_Iq Vd_del Vq_del]
%   GFM controller 12:20 (NO PLL)
%     [delta_VSG omega_VSG E xi_Vd xi_Vq xi_Id xi_Iq Vd_del Vq_del]
%
% Active states are 11 in GFL and 12 in GFM. The source publishes the DC
% energy balance but not its I_dc law, so the shared V_dc state is closed by
% a project-derived current-source regulator: exact instantaneous converter-
% power feed-forward plus proportional voltage restoration with declared Tdc.
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

gfl_dev=ibr.gfl_eecon49_full_model(device_id,bus_id,bus_position, ...
    bus_ids,V0,params,P_ref_pu,Q_ref_pu);
gfm_dev=ibr.gfm_eecon49_full_model(device_id,bus_id,bus_position, ...
    bus_ids,V0,params,P_ref_pu,Q_ref_pu,E_ref_pu);

if gfl_dev.nx~=12 || gfm_dev.nx~=12
    error('ibr:eecon49_dual_mode_model:branchLayout', ...
        'EECON49 branch adapters must each expose 12 states.');
end

gx=gfl_dev.x0(:); mx=gfm_dev.x0(:);
if abs(gx(3)-mx(3))>1e-12
    error('ibr:eecon49_dual_mode_model:commonPlantInit', ...
        'GFL/GFM DC-link initial states disagree.');
end
x0=merge_branches(gx,mx,mode);
u0=[P_ref_pu;Q_ref_pu;E_ref_pu];

gfl_active=1:11;
gfm_active=[1:3 12:20];

f=@(t,x,y,u,ec) dual_f(t,x,y,u,ec,device_id,mode,gfl_dev,gfm_dev,u0);
current=@(t,x,y,u,ec) dual_current(t,x,y,u,ec,device_id,mode,gfl_dev,gfm_dev,u0);
power=@(t,x,y,u,ec) real(bus_voltage(y,bus_position)*conj( ...
    current(t,x,y,u,ec)));
recon=@(t,x,y,u,ec) dual_reconstruct(t,x,y,u,ec,device_id,mode, ...
    gfl_dev,gfm_dev,u0,bus_position);
eq=@(V,P,Q,ec) equilibrium_initialize(V,P,Q,ec,device_id,mode, ...
    gfl_dev,gfm_dev,x0);
active=@(ec) active_indices(ec,device_id,mode,gfl_active,gfm_active);
transfer=@(x,y,u,ecl,target,ecr,varargin) transfer_state( ...
    x,y,u,ecl,target,ecr,device_id,mode,gfl_dev,gfm_dev,u0, ...
    bus_position,varargin{:});

state_names={'i_d','i_q','V_dc', ...
    'gfl_delta_PLL','gfl_xi_PLL','gfl_xi_P','gfl_xi_Q', ...
    'gfl_xi_Id','gfl_xi_Iq','gfl_Vd_del','gfl_Vq_del', ...
    'gfm_delta_VSG','gfm_omega_VSG','gfm_E','gfm_xi_Vd','gfm_xi_Vq', ...
    'gfm_xi_Id','gfm_xi_Iq','gfm_Vd_del','gfm_Vq_del'};

dev=struct();
dev.name=char(device_id); dev.device_id=char(device_id);
dev.bus_id=bus_id; dev.bus_position=bus_position; dev.bus_ids=bus_ids(:).';
dev.device_type='ibr_eecon49_dual';
dev.mode=char(mode); dev.initial_mode=char(mode); dev.initial_online=true;
dev.nx=20; dev.nu=3; dev.state_names=state_names;
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
    'details',['20 states = common plant 3 + GFL controller 8 (PLL) + ' ...
        'GFM controller 9 (VSG, no PLL); active GFL=11 and active GFM=12']);
end

% -------------------------------------------------------------------------
function dx=dual_f(t,x,y,u,ec,id,default_mode,gfl,gfm,u0)
validate_state(x); u=resolve_u(u,u0);
[online,m]=resolve_status(ec,id,default_mode);
dx=zeros(20,1);
if ~online || strcmp(m,'tripped'), return; end
switch m
case 'gfl'
    dg=gfl.f(t,to_gfl(x),y,u(1:2),ec);
    dx(1:3)=dg(1:3); dx(4:11)=dg(4:11);
case 'GFM'
    dm=gfm.f(t,to_gfm(x),y,u,ec);
    dx(1:3)=dm(1:3); dx(12:20)=dm(4:12);
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
    vdc=xl(3); xr=put_gfm(xr,mt); xr(3)=vdc;
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
    'common_indices',1:3,'gfl_indices',4:11,'gfm_indices',12:20, ...
    'Vdc_left',xl(3),'Vdc_right',xr(3));
end

function ec=set_context_mode(ec,fallback,id,target)
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
key=matlab.lang.makeValidName(char(id),'ReplacementStyle','underscore');
ec.hybrid_state.device_modes.(key)=target;
ec.hybrid_state.device_online.(key)=true;
end

function [online,m]=resolve_status(ec,id,default_mode)
online=true; raw=char(default_mode);
key=matlab.lang.makeValidName(char(id),'ReplacementStyle','underscore');
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
if ~isvector(x) || numel(x)~=20 || any(~isfinite(x))
    error('ibr:eecon49_dual_mode_model:badState', ...
        'Expected 20 finite EECON49 superset states.');
end
end

function x=merge_branches(g,m,mode)
x=zeros(20,1);
if strcmpi(mode,'GFM'), x(1:3)=m(1:3); else, x(1:3)=g(1:3); end
x(4:11)=g(4:11); x(12:20)=m(4:12);
end
function g=to_gfl(x), g=[x(1:11);0]; end
function m=to_gfm(x), m=[x(1:3);x(12:20)]; end
function x=put_gfl(x,g), x(1:3)=g(1:3); x(4:11)=g(4:11); end
function x=put_gfm(x,m), x(1:3)=m(1:3); x(12:20)=m(4:12); end

function V=bus_voltage(y,bp)
if numel(y)<2*bp || any(~isfinite(y(2*bp-1:2*bp)))
    error('ibr:transfer_maps:badVoltage','Missing finite terminal voltage.');
end
V=complex(y(2*bp-1),y(2*bp));
if abs(V)<=1e-12
    error('ibr:transfer_maps:badVoltage','Terminal voltage is too small.');
end
end
