function dev = wecc_regca_reeca_model(device_id, bus_id, bus_position, ...
    bus_ids, V0, params, P_ref_pu, Q_ref_pu)
%WECC_REGCA_REECA_MODEL  WECC REGC_A + REEC_A positive-sequence GFL model.
%
% This is the canonical production GFL implementation.  It implements the
% constant-P/constant-Q REEC_A control option (PFflag=0, QFlag=0), the
% REEC_A voltage-dip reactive-current path and P/Q-priority current limit,
% followed by the REGC_A converter-current lags, LVPL, low-voltage active
% current management, and high-voltage reactive-current management.
%
% Internal power/current quantities use the inverter MVA base.  The public
% composite-device ABI uses the system base.  With
%   kappa = Sbase/Mbase,
% conversion is P_inv=kappa*P_sys and I_inv=kappa*I_sys.
%
% State order (SOURCE_TRANSFORMED from the documented dynamic blocks):
%   1 Vt_f       REEC_A filtered terminal-voltage magnitude
%   2 P_f        REEC_A filtered electrical active power
%   3 Iq_cmd_f   REEC_A reactive-current command lag
%   4 Pord       REEC_A active-power-order lag/rate limiter
%   5 Vlvpl_f    REGC_A terminal-voltage filter for LVPL
%   6 Ip_reg     REGC_A active-current regulator state
%   7 Iq_reg     REGC_A reactive-current regulator state
%
% Sign convention: Ip/Iq are positive active/reactive injections.  The
% network-frame complex current is (Ip-j*Iq)*exp(j*angle(V))/kappa, so
% S=V*conj(I) gives positive P and Q into the network.
%
% Primary sources:
% - WECC, Specification of the Second Generation Generic Models for Wind
%   Turbine Generators, 2014, Secs. 3.2-3.3 and Appendices A-B.
% - WECC Wind Plant Dynamic Modeling Guidelines, 2014, REGC_A/REEC_A.
% - WECC, Converting REEC_B to REEC_A for Solar PV Generators, Table 2.

arguments
    device_id (1,1) string
    bus_id (1,1) double
    bus_position (1,1) double
    bus_ids (1,:) double
    V0 (1,1) {mustBeFinite}
    params struct
    P_ref_pu (1,1) double
    Q_ref_pu (1,1) double
end

validate_bus_mapping(bus_id, bus_position, bus_ids);
if ~isfinite(V0) || abs(V0) <= 0
    error('ibr:wecc_regca_reeca_model:badV0', ...
        'V0 must be a finite nonzero bus-voltage phasor.');
end
if ~isfinite(P_ref_pu) || ~isfinite(Q_ref_pu) || ...
        ~isreal(P_ref_pu) || ~isreal(Q_ref_pu)
    error('ibr:wecc_regca_reeca_model:badRef', ...
        'P_ref_pu and Q_ref_pu must be finite real system-base values.');
end

% Frozen source/example parameter profile.  REGC_A values are WECC typical
% values; REEC_A values are the official conversion example except Vdip,
% which is the WECC normal production setting at the top of its typical
% range.  These values are CASE_DEFINED/SOURCE_MAPPED, not fitted results.
p = struct( ...
    'Sbase',100.0,'Mbase',100.0, ...
    'Tfltr',0.02,'Lvpl1',1.22,'Zerox',0.40,'Brkpt',0.90, ...
    'Lvplsw',1,'rrpwr',10.0,'Tg',0.02,'Volim',1.20, ...
    'Iolim',-1.30,'Khv',0.70,'lvpnt0',0.40,'lvpnt1',0.80, ...
    'Iqrmax',999.0,'Iqrmin',-999.0, ...
    'Vdip',0.90,'Vup',1.10,'Trv',0.01,'dbd1',-0.10,'dbd2',0.10, ...
    'Kqv',2.0,'Iqh1',1.0,'Iql1',-1.0,'Vref0',abs(V0), ...
    'Tp',0.01,'Tiq',0.01,'dPmax',1.0,'dPmin',-1.0, ...
    'Pmax',1.0,'Pmin',0.0,'Imax',1.0,'Tpord',0.01, ...
    'PFflag',0,'VFlag',1,'QFlag',0,'Pflag',0,'PQFlag',1);

overridden = struct();
names = fieldnames(p);
for k = 1:numel(names)
    nm = names{k};
    overridden.(nm) = false;
    if isfield(params,nm) && ~isempty(params.(nm))
        p.(nm) = params.(nm);
        overridden.(nm) = true;
    end
end
validate_params(p);

kappa = p.Sbase/p.Mbase;
Vmag0 = abs(V0);
P0_inv = kappa*P_ref_pu;
Q0_inv = kappa*Q_ref_pu;
[Ip0,Iq0] = steady_currents(Vmag0,P0_inv,Q0_inv,p);
x0 = [Vmag0; P0_inv; Iq0; P0_inv; Vmag0; Ip0; Iq0];
u0 = [P_ref_pu; Q_ref_pu];
bp = bus_position;

f = @(t,x,y,u,ec) model_f(x,y,u,bp,kappa,p);
current_injection = @(t,x,y,u,ec) model_current(x,y,bp,kappa,p);
electrical_power = @(t,x,y,u,ec) model_power(x,y,bp,kappa,p);
reconstruct = @(t,x,y,u,ec) model_reconstruct(x,y,u,bp,kappa,p);
equilibrium_initialize = @(V,P,Q,ec) initialize_equilibrium(V,P,Q,kappa,p);

dev = struct();
dev.name = char(device_id);
dev.device_id = char(device_id);
dev.bus_id = bus_id;
dev.bus_position = bus_position;
dev.bus_ids = bus_ids(:).';
dev.device_type = 'ibr_gfl_wecc_regca_reeca';
dev.mode = 'gfl';
dev.nx = numel(x0);
dev.nu = 2;
dev.state_names = {'Vt_f','P_f','Iq_cmd_f','Pord','Vlvpl_f','Ip_reg','Iq_reg'};
dev.input_names = {'P_ref','Q_ref'};
dev.x0 = x0;
dev.u0 = u0;
dev.f = f;
dev.current_injection = current_injection;
dev.electrical_power = electrical_power;
dev.reconstruct = reconstruct;
dev.equilibrium_initialize = equilibrium_initialize;
dev.provenance = struct( ...
    'model','WECC_REGC_A_REEC_A', ...
    'source',['WECC Second Generation Generic WTG Models (2014), ' ...
              'WECC Wind Plant Dynamic Modeling Guidelines (2014), ' ...
              'WECC REEC_B-to-REEC_A conversion Table 2'], ...
    'source_urls',{{ ...
      'https://www.wecc.org/sites/default/files/documents/meeting/2024/WECC-Second-Generation-Wind-Turbine-Model%20Spec-012314.pdf', ...
      'https://www.wecc.org/sites/default/files/documents/meeting/2024/WECC%20Wind%20Plant%20Dynamic%20Modeling%20Guidelines.pdf', ...
      'https://www.wecc.org/sites/default/files/documents/meeting/2024/Converting%20REEC_B%20to%20REEC_A%20for%20Solar%20PV%20Generators.pdf'}}, ...
    'control_option','constant-P/constant-Q REEC_A; P-priority current limit', ...
    'params',p,'param_overridden',overridden, ...
    'pu_base_contract','internal=inverter base; external=system base; kappa=Sbase/Mbase', ...
    'applicability','REGC_A strong-grid current-source model; selector must reject SCR<=3', ...
    'readiness','SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES');
end

function dx = model_f(x,y,u,bp,kappa,p)
check_state_input(x,u);
V = bus_voltage(y,bp);
Vmag = abs(V);
Ssys = V*conj(model_current(x,y,bp,kappa,p));
Pinv_meas = kappa*real(Ssys);

P_ref_inv = kappa*u(1);
Q_ref_inv = kappa*u(2);
dVt = (Vmag-x(1))/p.Trv;
dPf = (Pinv_meas-x(2))/p.Tp;
dPord = rate_limit((clamp(P_ref_inv,p.Pmin,p.Pmax)-x(4))/p.Tpord, ...
    p.dPmin,p.dPmax);

[ip_cmd,iq_cmd] = reec_commands(x(1),x(4),Q_ref_inv,p);
dIqcmd = (iq_cmd-x(3))/p.Tiq;
dVlvpl = (Vmag-x(5))/p.Tfltr;

ip_target = regca_active_target(ip_cmd,Vmag,x(5),p);
dIp = (ip_target-x(6))/p.Tg;
if dIp > p.rrpwr
    dIp = p.rrpwr;
end
dIq = (x(3)-x(7))/p.Tg;
if Q_ref_inv > 0
    dIq = min(dIq,p.Iqrmax);
elseif Q_ref_inv < 0
    dIq = max(dIq,p.Iqrmin);
end
dx = [dVt;dPf;dIqcmd;dPord;dVlvpl;dIp;dIq];
if any(~isfinite(dx))
    error('ibr:wecc_regca_reeca_model:nonfiniteRhs', ...
        'REGC_A/REEC_A RHS produced a non-finite value.');
end
end

function I = model_current(x,y,bp,kappa,p)
if numel(x) ~= 7 || any(~isfinite(x))
    error('ibr:wecc_regca_reeca_model:badState', ...
        'Expected seven finite REGC_A/REEC_A states.');
end
V = bus_voltage(y,bp);
Vmag = abs(V);
if Vmag <= 0
    error('ibr:wecc_regca_reeca_model:zeroVoltageAngle', ...
        'REGC_A current-source interface requires a nonzero terminal-voltage angle.');
end
gain = piecewise_gain(Vmag,p.lvpnt0,p.lvpnt1);
Ip = x(6)*gain;
Iq = x(7);
if Vmag > p.Volim
    Iq = max(p.Iolim, Iq-p.Khv*(Vmag-p.Volim));
end
I = (Ip-1i*Iq)*exp(1i*angle(V))/kappa;
end

function Pe = model_power(x,y,bp,kappa,p)
V = bus_voltage(y,bp);
Pe = real(V*conj(model_current(x,y,bp,kappa,p)));
end

function out = model_reconstruct(x,y,u,bp,kappa,p)
check_state_input(x,u);
V = bus_voltage(y,bp);
I = model_current(x,y,bp,kappa,p);
S = V*conj(I);
[ip_cmd,iq_cmd] = reec_commands(x(1),x(4),kappa*u(2),p);
out = struct('Vt_f',x(1),'P_f',x(2),'Iq_cmd_f',x(3), ...
    'Pord',x(4),'Vlvpl_f',x(5),'Ip_reg',x(6),'Iq_reg',x(7), ...
    'Ipcmd',ip_cmd,'Iqcmd',iq_cmd,'I_gfl',I,'Vbus',abs(V), ...
    'Pe',real(S),'Qe',imag(S),'kappa',kappa,'Mbase',p.Mbase, ...
    'Sbase',p.Sbase,'Iabs_inv',kappa*abs(I),'Imax',p.Imax, ...
    'voltage_dip',x(1)<p.Vdip || x(1)>p.Vup, ...
    'low_voltage_gain',piecewise_gain(abs(V),p.lvpnt0,p.lvpnt1));
end

function xeq = initialize_equilibrium(V,Psys,Qsys,kappa,p)
if ~isscalar(V) || ~isfinite(V) || abs(V) <= 0 || ...
        ~isscalar(Psys) || ~isscalar(Qsys) || ...
        ~isfinite(Psys) || ~isfinite(Qsys)
    error('ibr:wecc_regca_reeca_model:equilibriumInput', ...
        'Equilibrium V/P/Q must be finite scalar values with |V|>0.');
end
Pinv = kappa*Psys;
Qinv = kappa*Qsys;
[Ip,Iq] = steady_currents(abs(V),Pinv,Qinv,p);
xeq = [abs(V);Pinv;Iq;Pinv;abs(V);Ip;Iq];
end

function [Ip,Iq] = steady_currents(Vmag,Pinv,Qinv,p)
if Pinv < p.Pmin-64*eps || Pinv > p.Pmax+64*eps
    error('ibr:wecc_regca_reeca_model:equilibriumPowerLimit', ...
        'Inverter-base P=%.15g is outside [%.15g,%.15g].',Pinv,p.Pmin,p.Pmax);
end
Ip = Pinv/Vmag;
Iq = Qinv/Vmag;
if hypot(Ip,Iq) > p.Imax+64*eps(max(1,p.Imax))
    error('ibr:wecc_regca_reeca_model:equilibriumCurrentLimit', ...
        'Requested steady current %.15g exceeds Imax=%.15g.',hypot(Ip,Iq),p.Imax);
end
end

function [Ip,Iq] = reec_commands(Vf,Pord,Qref,p)
vdiv = max(Vf,0.01); % NUMERICAL_METHOD: documented zero-voltage division guard
Ip0 = Pord/vdiv;
Iqinj = 0;
if Vf < p.Vdip || Vf > p.Vup
    verr = p.Vref0-Vf;
    verr = deadband(verr,p.dbd1,p.dbd2);
    Iqinj = clamp(p.Kqv*verr,p.Iql1,p.Iqh1);
end
Iq0 = Qref/vdiv+Iqinj;
Ip_cap = p.Imax;
Iq_cap = p.Imax;
if p.PQFlag == 1
    Ip = clamp(Ip0,0,Ip_cap);
    Iq_lim = min(Iq_cap,sqrt(max(p.Imax^2-Ip^2,0)));
    Iq = clamp(Iq0,-Iq_lim,Iq_lim);
else
    Iq = clamp(Iq0,-Iq_cap,Iq_cap);
    Ip_lim = min(Ip_cap,sqrt(max(p.Imax^2-Iq^2,0)));
    Ip = clamp(Ip0,0,Ip_lim);
end
end

function target = regca_active_target(Ipcmd,V,Vf,p)
if p.Lvplsw == 1
    lvpl = piecewise_lvpl(Vf,p.Zerox,p.Brkpt,p.Lvpl1);
    target = min(Ipcmd,lvpl);
else
    target = Ipcmd;
end
% The final low-voltage active-current multiplier is applied at the network
% interface.  The state remains the pre-multiplier converter-current output.
if V <= p.lvpnt0
    target = max(target,0);
end
end

function value = piecewise_lvpl(V,zero_x,breakpoint,lvpl1)
if V <= zero_x
    value = 0;
elseif V >= breakpoint
    value = lvpl1;
else
    value = lvpl1*(V-zero_x)/(breakpoint-zero_x);
end
end

function value = piecewise_gain(V,v0,v1)
if V <= v0
    value = 0;
elseif V >= v1
    value = 1;
else
    value = (V-v0)/(v1-v0);
end
end

function value = deadband(value,lo,hi)
if value > hi
    value = value-hi;
elseif value < lo
    value = value-lo;
else
    value = 0;
end
end

function V = bus_voltage(y,bp)
if numel(y) < 2*bp || any(~isfinite(y(2*bp-1:2*bp)))
    error('ibr:wecc_regca_reeca_model:badNetworkState', ...
        'Network state does not contain a finite voltage for bus position %d.',bp);
end
V = complex(y(2*bp-1),y(2*bp));
end

function check_state_input(x,u)
if numel(x) ~= 7 || any(~isfinite(x))
    error('ibr:wecc_regca_reeca_model:badState', ...
        'Expected seven finite REGC_A/REEC_A states.');
end
if numel(u) ~= 2 || any(~isfinite(u))
    error('ibr:wecc_regca_reeca_model:badInput', ...
        'Expected finite u=[P_ref;Q_ref].');
end
end

function validate_bus_mapping(bus_id,bp,bus_ids)
if ~isfinite(bp) || bp ~= floor(bp) || bp < 1 || bp > numel(bus_ids) || ...
        bus_ids(bp) ~= bus_id
    error('ibr:wecc_regca_reeca_model:busMappingMismatch', ...
        'bus_position and bus_id do not identify the same network bus.');
end
end

function validate_params(p)
positive = {'Sbase','Mbase','Tfltr','Tg','Trv','Tp','Tiq','Tpord','Imax'};
names = fieldnames(p);
for k = 1:numel(names)
    value = p.(names{k});
    if ~isscalar(value) || ~isfinite(value)
        error('ibr:wecc_regca_reeca_model:badParam', ...
            'Parameter %s must be a finite scalar.',names{k});
    end
end
for k = 1:numel(positive)
    if p.(positive{k}) <= 0
        error('ibr:wecc_regca_reeca_model:badParam', ...
            'Parameter %s must be positive.',positive{k});
    end
end
if ~(p.Lvplsw==0 || p.Lvplsw==1) || ~(p.PQFlag==0 || p.PQFlag==1) || ...
        p.Zerox >= p.Brkpt || p.lvpnt0 >= p.lvpnt1 || p.Vdip >= p.Vup || ...
        p.Pmin > p.Pmax || p.Iql1 > p.Iqh1 || p.dPmin > p.dPmax
    error('ibr:wecc_regca_reeca_model:badParam', ...
        'WECC flag, breakpoint, or limiter ordering is invalid.');
end
end

function y = clamp(x,lo,hi)
y = min(max(x,lo),hi);
end

function y = rate_limit(x,lo,hi)
y = clamp(x,lo,hi);
end
