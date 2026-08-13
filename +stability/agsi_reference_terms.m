function out = agsi_reference_terms(res, dae, settings, Ylog)
%AGSI_REFERENCE_TERMS  Reference-only AGSI sub-indices for a completed run.
%
%   OUT = stability.agsi_reference_terms(RES, DAE, SETTINGS, YLOG) computes the
%   standard AGSI sub-indices that the switching supervisor does NOT consume,
%   normalizes each one by its declared band base, and reports whether it stayed
%   in band (J <= 1) at every published sample.
%
%   DECISION CONTRACT (unchanged by this function): the SG-off support
%   supervisor in ts_simulate_ibr_hybrid triggers on
%       severity = min(1, max(0, 0.5*J_V + 0.5*J_f))
%   ONLY. This function is pure post-processing over the recorded samples; it
%   cannot influence an accepted step, the severity scalar, the hysteresis, the
%   dwell timers, candidate selection, or any acceptance gate. Its output is
%   classified ASSUMED_DIAGNOSTIC and must never be cited to support a
%   readiness or production claim (AGENTS.md).
%
%   Terms, all normalized so that 1.0 is the band edge:
%     J_V    = |V - V_healthy| / dV_base                (also the trigger pair,
%     J_f    = |f_COI - f0|    / df_base_Hz              reported for context)
%     J_R    = |d f_COI/dt|    / rocof_base_Hz_s
%     J_P    = |P_ref - P|     / dP_base_pu
%     J_SCR  = max(0, scr_floor/SCR - 1)
%     J_lock = |v_q| / vq_base_pu     (GFL only; a GFM has no PLL, so 0)
%
%   No aggregate index is formed and no weights are applied: an aggregate would
%   be one step from a decision variable, which is exactly what this overlay
%   must not become.
%
%   d f_COI/dt is analytic: it is assembled from the device RHS speed rows
%   (dev.f evaluated at the recorded sample), NOT from a finite difference of
%   the sampled frequency, so it is independent of the output sample spacing.
%
%   SCR uses the topology in force at each sample:
%     SCR_i = |V_i|^2 / (|Z_th,ii| * S_rated,i),   Z_th = Y^-1 column solve
%   with Y taken from YLOG, the driver's record of (time, topology label, Y).
%   The full-state IBR families are classified
%   'not_applicable_full_state_source_model' for the production SCR GATE; that
%   classification is unchanged. SCR appears here only as a physical
%   grid-strength diagnostic.

arguments
    res struct
    dae struct
    settings struct
    Ylog struct = struct('t',{},'topology',{},'Y',{})
end

out = struct( ...
    'status','OK', ...
    'classification','ASSUMED_DIAGNOSTIC', ...
    'decision_contract',['switching consumes J_V and J_f only; every term ' ...
        'published here is reference-only and enters no gate'], ...
    'aggregate_index','NOT_FORMED_BY_DESIGN', ...
    'rocof_method','analytic_from_device_rhs_speed_rows', ...
    'bases',struct( ...
        'dV_pu',settings.severity_dV_base, ...
        'df_Hz',settings.severity_df_base_Hz, ...
        'rocof_Hz_s',settings.agsi_rocof_base_Hz_s, ...
        'dP_pu',settings.agsi_dP_base_pu, ...
        'scr_floor',settings.agsi_scr_floor, ...
        'vq_pu',settings.agsi_vq_base_pu, ...
        'f0_Hz',settings.severity_f0_Hz), ...
    'base_classification',['J_V/J_f bases are the production trigger bases; ' ...
        'ROCOF, dP and v_q bases are ASSUMED_DIAGNOSTIC band references and ' ...
        'are caller-overridable'], ...
    't',[],'device_ids',{{}},'device_indices',[], ...
    'terms',struct(),'in_band',struct(),'online',[],'mode',{{}}, ...
    'scr',[],'f_coi_Hz',[],'rocof_Hz_s',[],'summary',struct([]));

if ~isfield(res,'t') || isempty(res.t)
    out.status='NO_SAMPLES';
    return;
end
ns=numel(res.t);
nd=numel(dae.devices);

% --- identify the switchable IBR devices once ----------------------------
ibr_idx=[];
for k=1:nd
    dev=dae.devices(k);
    if isfield(dev,'capabilities') && isfield(dev.capabilities,'resource_type') && ...
            strcmpi(char(dev.capabilities.resource_type),'ibr')
        ibr_idx(end+1)=k; %#ok<AGROW>
    end
end
if isempty(ibr_idx)
    out.status='NO_IBR_DEVICES';
    return;
end
m=numel(ibr_idx);
out.device_indices=ibr_idx;
out.device_ids=cellfun(@(k)char(dae.devices(k).device_id),num2cell(ibr_idx), ...
    'UniformOutput',false);

% --- speed-state row per device (for the analytic ROCOF) -----------------
speed_row=nan(1,nd);
for k=1:nd
    nm=cellstr(string(dae.devices(k).state_names));
    j=find(strcmp(nm,'gfm_omega_VSG'),1);
    if isempty(j), j=find(strcmp(nm,'omega'),1); end
    if isempty(j), j=find(strcmp(nm,'omega_m'),1); end
    if ~isempty(j), speed_row(k)=j; end
end

% --- Thevenin self-impedance per topology, computed once each ------------
zth=containers.Map('KeyType','char','ValueType','any');
for q=1:numel(Ylog)
    key=sprintf('%s|%.12g',char(Ylog(q).topology),Ylog(q).t);
    zth(key)=thevenin_diagonal(Ylog(q).Y,arrayfun(@(k)dae.devices(k).bus_position,ibr_idx));
end

names={'J_V','J_f','J_R','J_P','J_SCR','J_lock'};
for f=names, out.terms.(f{1})=nan(ns,m); end
out.online=false(ns,m);
out.mode=repmat({''},ns,m);
out.scr=nan(ns,m);
out.f_coi_Hz=nan(ns,1);
out.rocof_Hz_s=nan(ns,1);
out.t=res.t(:);

has_ref=isfield(settings,'healthy_pf_V') && isfield(settings,'healthy_pf_bus_ids') && ...
    ~isempty(settings.healthy_pf_V);
f0=settings.severity_f0_Hz;

for i=1:ns
    t=res.t(i);
    x=res.x_traj(:,i); y=res.y_traj(:,i); u=res.u_history(:,i);
    ec=res.event_context_history{i};
    top=char(string(res.topology_history{i}));
    % Reconstruct + speed derivative for every device (needed for f_COI).
    H=nan(1,nd); fdev=nan(1,nd); dfdev=nan(1,nd); on=false(1,nd);
    rc=cell(1,nd);
    for k=1:nd
        dev=dae.devices(k);
        xi=dae.device_offsets(k)+(1:dev.nx);
        ui=dae.u_offsets(k)+(1:dev.nu);
        try
            rec=dev.reconstruct(t,x(xi),y,u(ui),ec);
        catch
            continue;
        end
        rc{k}=rec;
        if ~isfield(rec,'online') || ~isscalar(rec.online), continue; end
        on(k)=logical(rec.online);
        if ~on(k), continue; end
        [om,Hk]=speed_and_inertia(rec);
        if isnan(om) || isnan(Hk) || Hk<=0, continue; end
        H(k)=Hk; fdev(k)=f0*(1+om);
        if ~isnan(speed_row(k))
            try
                dxk=dev.f(t,x(xi),y,u(ui),ec);
                dfdev(k)=f0*dxk(speed_row(k));
            catch
                dfdev(k)=NaN;
            end
        end
    end
    use=on & isfinite(H) & H>0 & isfinite(fdev);
    if any(use)
        Hs=sum(H(use));
        out.f_coi_Hz(i)=sum(H(use).*fdev(use))/Hs;
        du=use & isfinite(dfdev);
        if any(du) && all(du(use))
            out.rocof_Hz_s(i)=sum(H(du).*dfdev(du))/Hs;
        end
    end
    % Per-IBR terms.
    zk=[];
    key=topology_key(Ylog,top,t);
    if ~isempty(key) && isKey(zth,key), zk=zth(key); end
    for q=1:m
        k=ibr_idx(q); dev=dae.devices(k); rec=rc{k};
        if isempty(rec) || ~isfield(rec,'mode'), continue; end
        out.mode{i,q}=char(rec.mode);
        out.online(i,q)=on(k);
        if ~on(k), continue; end
        bp=dev.bus_position;
        Vm=NaN;
        if isscalar(bp) && 2*bp<=numel(y)
            Vm=abs(complex(y(2*bp-1),y(2*bp)));
        end
        if has_ref && isfinite(Vm)
            ri=find(settings.healthy_pf_bus_ids==dev.bus_id);
            if numel(ri)==1
                out.terms.J_V(i,q)=abs(Vm-settings.healthy_pf_V(ri))/settings.severity_dV_base;
            end
        end
        if isfinite(out.f_coi_Hz(i))
            out.terms.J_f(i,q)=abs(out.f_coi_Hz(i)-f0)/settings.severity_df_base_Hz;
        end
        if isfinite(out.rocof_Hz_s(i))
            out.terms.J_R(i,q)=abs(out.rocof_Hz_s(i))/settings.agsi_rocof_base_Hz_s;
        end
        [Pmeas,vq,is_gfl]=branch_power_and_lock(rec);
        Pref=input_slot(dev,dae,u,k,'P_ref');
        if isfinite(Pmeas) && isfinite(Pref)
            out.terms.J_P(i,q)=abs(Pref-Pmeas)/settings.agsi_dP_base_pu;
        end
        if is_gfl
            if isfinite(vq)
                out.terms.J_lock(i,q)=abs(vq)/settings.agsi_vq_base_pu;
            end
        else
            % A grid-forming branch has no PLL, so there is no lock error to
            % report. This is 0 by structure, not a missing measurement.
            out.terms.J_lock(i,q)=0;
        end
        if ~isempty(zk) && isfinite(zk(q)) && zk(q)>0 && isfinite(Vm)
            srated=rated_power_pu(rec);
            if isfinite(srated) && srated>0
                scr=(Vm^2)/(zk(q)*srated);
                out.scr(i,q)=scr;
                out.terms.J_SCR(i,q)=max(0,settings.agsi_scr_floor/scr-1);
            end
        end
    end
end

% --- in-band flags and per-device summary --------------------------------
for f=names
    out.in_band.(f{1})=out.terms.(f{1})<=1;
end
summ=repmat(struct('device_id','','max',struct(),'in_band_fraction',struct(), ...
    'first_out_of_band_time',struct(),'evaluated_samples',struct()),1,m);
for q=1:m
    summ(q).device_id=out.device_ids{q};
    for f=names
        v=out.terms.(f{1})(:,q);
        ok=isfinite(v);
        summ(q).evaluated_samples.(f{1})=sum(ok);
        if any(ok)
            summ(q).max.(f{1})=max(v(ok));
            summ(q).in_band_fraction.(f{1})=sum(v(ok)<=1)/sum(ok);
            bad=find(ok & v>1,1);
            if isempty(bad)
                summ(q).first_out_of_band_time.(f{1})=NaN;
            else
                summ(q).first_out_of_band_time.(f{1})=out.t(bad);
            end
        else
            summ(q).max.(f{1})=NaN;
            summ(q).in_band_fraction.(f{1})=NaN;
            summ(q).first_out_of_band_time.(f{1})=NaN;
        end
    end
end
out.summary=summ;
if isempty(Ylog)
    out.status='OK_NO_SCR_TOPOLOGY_LOG';
end
end

% =========================================================================
function [om,H]=speed_and_inertia(rec)
%SPEED_AND_INERTIA  Per-unit speed DEVIATION and inertia constant.
om=NaN; H=NaN;
if strcmpi(char(rec.mode),'sg')
    if isfield(rec,'omega') && isfinite(rec.omega) && ...
            isfield(rec,'H_system') && isfinite(rec.H_system)
        om=rec.omega; H=rec.H_system;
    end
    return;
end
if strcmpi(char(rec.mode),'gfm') && isfield(rec,'gfm') && isstruct(rec.gfm)
    g=rec.gfm;
    if isfield(g,'omega_m') && isfinite(g.omega_m) && ...
            isfield(g,'H_system') && isfinite(g.H_system)
        om=g.omega_m; H=g.H_system;
    end
end
end

function [P,vq,is_gfl]=branch_power_and_lock(rec)
%BRANCH_POWER_AND_LOCK  Measured P (system base) and the PLL q-axis residual.
P=NaN; vq=NaN; is_gfl=false;
if isfield(rec,'gfl') && isstruct(rec.gfl)
    is_gfl=true;
    if isfield(rec.gfl,'Pe'), P=rec.gfl.Pe; end
    if isfield(rec.gfl,'v_q'), vq=rec.gfl.v_q; end
    return;
end
if isfield(rec,'gfm') && isstruct(rec.gfm)
    if isfield(rec.gfm,'Pe'), P=rec.gfm.Pe; end
    return;
end
if isfield(rec,'Pe'), P=rec.Pe; end
end

function v=input_slot(dev,dae,u,k,wanted)
v=NaN;
if ~isfield(dev,'input_names'), return; end
s=find(strcmpi(string(dev.input_names),wanted));
if numel(s)~=1, return; end
gi=dae.u_offsets(k)+s;
if gi>=1 && gi<=numel(u), v=u(gi); end
end

function s=rated_power_pu(rec)
%RATED_POWER_PU  Device rating on the system base, from the reconstruct payload.
%   The active branch publishes kappa = Sbase/Mbase, so the rating in system
%   per-unit is 1/kappa.  Reading it from the payload avoids depending on the
%   shared builder's provenance normalization, which reduces every device to
%   four text fields and therefore drops Mbase as a number.
s=NaN;
for f={'gfm','gfl'}
    if isfield(rec,f{1}) && isstruct(rec.(f{1})) && ...
            isfield(rec.(f{1}),'kappa') && isfinite(rec.(f{1}).kappa) && ...
            rec.(f{1}).kappa>0
        s=1/rec.(f{1}).kappa;
        return;
    end
end
if isfield(rec,'kappa') && isfinite(rec.kappa) && rec.kappa>0
    s=1/rec.kappa;
end
end

function z=thevenin_diagonal(Y,bus_positions)
%THEVENIN_DIAGONAL  |Z_th,ii| for the requested buses, one linear solve each.
n=size(Y,1); z=nan(1,numel(bus_positions));
for q=1:numel(bus_positions)
    bp=bus_positions(q);
    if ~isscalar(bp) || bp<1 || bp>n, continue; end
    e=zeros(n,1); e(bp)=1;
    try
        zc=Y\e;
    catch
        continue;
    end
    if all(isfinite(zc)), z(q)=abs(zc(bp)); end
end
end

function key=topology_key(Ylog,top,t)
%TOPOLOGY_KEY  Latest logged admittance whose label matches and whose time has
% already passed. Matching the label first keeps a left/right sample pair on the
% correct side of an atomic topology transaction.
key='';
best=-inf;
for q=1:numel(Ylog)
    if ~strcmp(char(string(Ylog(q).topology)),top), continue; end
    if Ylog(q).t<=t+1e-12 && Ylog(q).t>best
        best=Ylog(q).t;
        key=sprintf('%s|%.12g',char(Ylog(q).topology),Ylog(q).t);
    end
end
if isempty(key)
    for q=1:numel(Ylog)
        if strcmp(char(string(Ylog(q).topology)),top)
            key=sprintf('%s|%.12g',char(Ylog(q).topology),Ylog(q).t);
            return;
        end
    end
end
end
