function p = ne39_sg_reclose_plant_params(case_data, opt)
%NE39_SG_RECLOSE_PLANT_PARAMS Frozen PROJECT_DERIVED reduced SG31 plant data.
%   P = stability.ne39_sg_reclose_plant_params(CASE_DATA) returns the
%   opt-in parameters consumed by stability.sg_classical_reclose_device.
%   Only the TAMU NE39 1-SG composition with SG31 is accepted.
%
%   Source-machine H, D, X'd and the healthy operating point are read from
%   CASE_DATA. This function DOES NOT reinterpret MBASE as a stator rating.
%   Every added loss, governor/excitation lag, capture gain/target, prime-mover
%   upper bound without an existing project contract, and stator capability
%   proxy is explicitly PROJECT_DERIVED. The reduced field tracker is not the
%   source GENROU/EXST1 model; the no-load loss is not TAMU machine data.
%
%   The reduced rotor follows an energy-consistent positive-speed power balance:
%       2 H_system omega domega/dt = Pm - Pe - L0*omega^2
%                                      - D_system*omega*(omega-1).
%   L0 > 0 is required: with the source's D=0, Pm=0 and loss=0 cannot arrest
%   an offline rotor. The default L0 is 1% of healthy SG31 electrical MW, a
%   declared PROJECT_DERIVED study assumption, not a measurement.
%
%   Optional OPT fields (all opt-in design inputs, never sourced ratings):
%     Pmax_MW                 positive prime-mover study ceiling; default to
%                             finite case project contract, else 1.25*P0 rounded
%                             upward to 10 MW (PROJECT_DERIVED)
%     no_load_loss_fraction   L0/P0, default 0.01, range (0,0.05]
%     Tsv_s                   valve lag, default 0.20, range [0.05,0.20] s
%     Tch_s                   steam-chest lag, default 0.40, range [0.20,0.40] s
%     T_emag_s                reduced field-magnitude lag, default 0.50,
%                             range [0.10,1.00] s
%     omega_n_rad_s           offline capture target, default 0.20, range
%                             [0.10,0.30] rad/s; lag-inclusive roots still need
%                             explicit verification
%     zeta                    capture design target, default 1.0, range [0.8,1.2]
%     emag_min_fraction       lower Emag bound relative to healthy Emag0,
%                             default 0.80, range [0.5,1.0]
%     emag_max_fraction       upper Emag bound relative to healthy Emag0,
%                             default 1.20, range [1.0,1.5]
%     Q_envelope_MVAr         explicit reactive design envelope; default is
%                             max(|Qmin|,|Qmax|) from SG31 source RAW limits
%     stator_rating_margin    multiplier on hypot(Pmax,Q-envelope), default
%                             1.10, range [1.0,1.25]; resultant stator apparent
%                             rating/current circle is PROJECT_DERIVED, not a
%                             source nameplate or certified capability curve
%     omega_min_pu            minimum admissible absolute speed, default 0.20;
%                             states/trials at or below it fail closed
%     pll_Kp_rad_s            local-terminal phase estimator proportional
%                             gain, default 4 rad/s (PROJECT_DERIVED)
%     pll_Ki_rad_s2           local-terminal phase estimator integral gain,
%                             default 4 rad/s^2 (PROJECT_DERIVED)
%     pll_frequency_limit_pu  estimator deviation bound, default 0.05 pu;
%                             this is a model domain, not a synchronism gate
%     pll_phase_limit_rad     wrapped phase-detector limit, default pi/2
%
%   The type-II local terminal estimator is a PROJECT_DERIVED reduced PLL,
%   not a TAMU controller mapping. Its two states are part of the plant DAE.
%   Offline speed/phase control uses its estimated local bus frequency. A
%   nominal-frequency-only phase law was falsified at +/-0.1 Hz, so it is not
%   used by this opt-in plant. This estimator is not an authenticated relay.

%
%   P_REF is the electrical active-power reference (system pu). At synchronous
%   equilibrium actual Pm = P_REF + L0; the loss is not hidden in or added to a
%   source D value. No negative valve or shaft power is authorized.
arguments
    case_data (1,1) struct
    opt (1,1) struct = struct()
end

allowed = {'Pmax_MW','no_load_loss_fraction','Tsv_s','Tch_s','T_emag_s', ...
    'omega_n_rad_s','zeta','emag_min_fraction','emag_max_fraction', ...
    'Q_envelope_MVAr','stator_rating_margin','omega_min_pu', ...
    'pll_Kp_rad_s','pll_Ki_rad_s2','pll_frequency_limit_pu','pll_phase_limit_rad', ...
    'pll_Kp','pll_Ki'};
unknown = setdiff(fieldnames(opt),allowed);
if ~isempty(unknown)
    error('stability:ne39_sg_reclose_plant_params:unknownOption', ...
        'Unknown opt.%s.',unknown{1});
end

if ~isfield(case_data,'source_variant') || ~isstruct(case_data.source_variant) || ...
        ~isfield(case_data.source_variant,'id') || ...
        ~strcmp(case_data.source_variant.id,'TAMU_LEDESMA_2016') || ...
        ~isfield(case_data,'sg_buses') || ~isequal(double(case_data.sg_buses(:).'),31) || ...
        ~isfield(case_data,'ibr_buses') || numel(case_data.ibr_buses)~=9 || ...
        ~isfield(case_data,'machines') || ~isstruct(case_data.machines) || ...
        ~isfield(case_data.machines,'units') || numel(case_data.machines.units)~=1 || ...
        case_data.machines.units(1).bus~=31
    error('stability:ne39_sg_reclose_plant_params:unsupportedComposition', ...
        'This opt-in reduced reclose plant supports only the NE39 SG31 + 9-IBR composition.');
end
if ~isfield(case_data,'base_values') || ...
        ~all(isfield(case_data.base_values,{'S_base_MVA','frequency_Hz'}))
    error('stability:ne39_sg_reclose_plant_params:missingBase', ...
        'case_data.base_values must declare S_base_MVA and frequency_Hz.');
end
Sbase = double(case_data.base_values.S_base_MVA);
fbase = double(case_data.base_values.frequency_Hz);
if ~(isscalar(Sbase) && isfinite(Sbase) && Sbase>0 && ...
        isscalar(fbase) && isfinite(fbase) && fbase>0)
    error('stability:ne39_sg_reclose_plant_params:badBase', ...
        'System power and frequency bases must be positive finite scalars.');
end
if ~isfield(case_data.machines,'base') || ...
        ~isfield(case_data.machines.base,'S_MVA') || ...
        abs(double(case_data.machines.base.S_MVA)-Sbase)>1e-10*max(1,Sbase)
    error('stability:ne39_sg_reclose_plant_params:machineBase', ...
        'SG H/D/Xdp input must already be declared on the system power base.');
end
u = case_data.machines.units(1);
for name = {'H','D','Xdp'}
    if ~isfield(u,name{1}) || ~isscalar(u.(name{1})) || ~isfinite(u.(name{1}))
        error('stability:ne39_sg_reclose_plant_params:machineData', ...
            'System-base machine.%s must be one finite scalar.',name{1});
    end
end
if ~(u.H>0 && u.D>=0 && u.Xdp>0)
    error('stability:ne39_sg_reclose_plant_params:machineRange', ...
        'Require source H>0, D>=0 and Xdp>0; values are never altered here.');
end

pf = pfsolver.powerflow_newton_raphson(case_data,struct('verbose',false, ...
    'plot_results',false,'max_iter',100,'tolerance',1e-10, ...
    'enforce_q_limits',false));
if ~isfield(pf,'converged') || ~pf.converged
    error('stability:ne39_sg_reclose_plant_params:powerFlow', ...
        'The in-house PF must converge before the SG31 plant can be initialized.');
end
row = find(pf.external_bus_ids==31,1);
if isempty(row) || numel(pf.P_generation)<row || numel(pf.Q_generation)<row
    error('stability:ne39_sg_reclose_plant_params:operatingPoint', ...
        'The converged PF must contain SG31 voltage and P/Q generation.');
end
V0 = pf.bus_voltage(row)*exp(1i*deg2rad(pf.bus_angle_deg(row)));
P0_pu = double(pf.P_generation(row));
Q0_pu = double(pf.Q_generation(row));
if ~(isfinite(real(V0)) && isfinite(imag(V0)) && abs(V0)>0 && ...
        isfinite(P0_pu) && isfinite(Q0_pu) && P0_pu>0)
    error('stability:ne39_sg_reclose_plant_params:operatingPoint', ...
        'SG31 healthy PF V must be nonzero and P/Q generation finite with P>0.');
end
I0 = conj((P0_pu+1i*Q0_pu)/V0);
E0 = V0+1i*double(u.Xdp)*I0;
Emag0 = abs(E0);
if ~(isfinite(Emag0) && Emag0>0)
    error('stability:ne39_sg_reclose_plant_params:internalEmf', ...
        'The PF port implies an invalid classical internal EMF magnitude.');
end
P0_MW = P0_pu*Sbase;

loss_fraction = option(opt,'no_load_loss_fraction',0.01);
range_scalar(loss_fraction,'no_load_loss_fraction',0,0.05,false,true);
L0 = loss_fraction*P0_pu;

[Pmax_MW,pmax_source] = resolve_pmax(case_data,opt,P0_MW);
if ~(isfinite(Pmax_MW) && Pmax_MW>Sbase*(P0_pu+L0))
    error('stability:ne39_sg_reclose_plant_params:primeMoverCeiling', ...
        'Pmax_MW must exceed the healthy shaft input including declared no-load loss.');
end
Pmax_pu = Pmax_MW/Sbase;

[Qenv_MVAr,qenv_source] = resolve_q_envelope(case_data,opt);
margin = option(opt,'stator_rating_margin',1.10);
range_scalar(margin,'stator_rating_margin',1.0,1.25,true,true);
S_rated_MVA = margin*hypot(Pmax_MW,Qenv_MVAr);
if ~(isfinite(S_rated_MVA) && S_rated_MVA>0)
    error('stability:ne39_sg_reclose_plant_params:statorRating', ...
        'The explicit PROJECT_DERIVED stator apparent-power envelope is invalid.');
end

Tsv = option(opt,'Tsv_s',0.20); range_scalar(Tsv,'Tsv_s',0.05,0.20,true,true);
Tch = option(opt,'Tch_s',0.40); range_scalar(Tch,'Tch_s',0.20,0.40,true,true);
Temag = option(opt,'T_emag_s',0.50); range_scalar(Temag,'T_emag_s',0.10,1.00,true,true);
wn = option(opt,'omega_n_rad_s',0.20); range_scalar(wn,'omega_n_rad_s',0.10,0.30,true,true);
zeta = option(opt,'zeta',1.0); range_scalar(zeta,'zeta',0.80,1.20,true,true);
EminFrac = option(opt,'emag_min_fraction',0.80);
EmaxFrac = option(opt,'emag_max_fraction',1.20);
range_scalar(EminFrac,'emag_min_fraction',0.50,1.00,true,true);
range_scalar(EmaxFrac,'emag_max_fraction',1.00,1.50,true,true);
if EmaxFrac<=EminFrac
    error('stability:ne39_sg_reclose_plant_params:emagRange', ...
        'Emag maximum fraction must exceed its minimum fraction.');
end
omega_min = option(opt,'omega_min_pu',0.20);
range_scalar(omega_min,'omega_min_pu',0.05,0.80,true,true);
pll_Kp = option_alias(opt,'pll_Kp_rad_s','pll_Kp',4.0);
pll_Ki = option_alias(opt,'pll_Ki_rad_s2','pll_Ki',4.0);
pll_frequency_limit = option(opt,'pll_frequency_limit_pu',0.05);
pll_phase_limit = option(opt,'pll_phase_limit_rad',pi/2);
range_scalar(pll_Kp,'pll_Kp_rad_s',0.5,20,true,true);
range_scalar(pll_Ki,'pll_Ki_rad_s2',0.1,40,true,true);
range_scalar(pll_frequency_limit,'pll_frequency_limit_pu',0.005,0.10,true,true);
range_scalar(pll_phase_limit,'pll_phase_limit_rad',pi/12,pi,true,true);

% Linearize the exact power balance about omega=1. Loss contributes 2*L0
% and source damping contributes D to the speed coefficient; neither is hidden.
w0 = 2*pi*fbase;
Komega = 4*u.H*zeta*wn-u.D-2*L0;
Ktheta = 2*u.H*wn^2/w0;
if ~(isfinite(Komega) && Komega>=0 && isfinite(Ktheta) && Ktheta>0)
    error('stability:ne39_sg_reclose_plant_params:gainRange', ...
        'PROJECT_DERIVED capture gains must satisfy Komega>=0, Ktheta>0.');
end
if ~(P0_pu+L0<Pmax_pu)
    error('stability:ne39_sg_reclose_plant_params:primeMoverHeadroom', ...
        'The healthy equilibrium shaft input exceeds the declared prime-mover ceiling.');
end

p = struct();
p.schema_id = 'ne39_sg31_classical_reclose_v1';
p.resource_id = 'SG31';
p.bus_id = 31;
p.classification = 'PROJECT_DERIVED';
p.source = 'TAMU NE39 SG31 source GENROU values reduced to classical power-balance plant';
p.system_base_MVA = Sbase;
p.frequency_Hz = fbase;
p.H_system_s = double(u.H);
p.D_system_pu = double(u.D);       % unchanged source value (TAMU SG31 D=0)
p.Xdp_system_pu = double(u.Xdp);  % unchanged source value
p.machine_MBASE_MVA = NaN;
if isfield(u,'Mbase') && isfinite(u.Mbase), p.machine_MBASE_MVA=double(u.Mbase); end
p.machine_MBASE_role = 'SOURCE_MODEL_NORMALIZATION_ONLY_NOT_STATOR_RATING';
p.P_ref0_pu = P0_pu;
p.Q0_pu = Q0_pu;
p.P0_MW = P0_MW;
p.Emag0_pu = Emag0;
p.delta0_rad = angle(E0);
p.no_load_loss_fraction = loss_fraction;
p.no_load_loss_pu = L0;
p.no_load_loss_MW = L0*Sbase;
p.Pmax_MW = Pmax_MW;
p.Pmax_pu = Pmax_pu;
p.Pmax_provenance = pmax_source;
p.Q_envelope_MVAr = Qenv_MVAr;
p.Q_envelope_provenance = qenv_source;
p.stator_rating_margin = margin;
p.S_rated_MVA = S_rated_MVA;
p.stator_rating_provenance = ['PROJECT_DERIVED spherical apparent-power envelope: ' ...
    'margin*hypot(Pmax_MW,Q-envelope); not source nameplate or certified curve'];
p.I_rated_system_pu = S_rated_MVA/Sbase;
p.Emag_min_pu = EminFrac*Emag0;
p.Emag_max_pu = EmaxFrac*Emag0;
p.emag_min_fraction = EminFrac;
p.emag_max_fraction = EmaxFrac;
p.Tsv_s = Tsv;
p.Tch_s = Tch;
p.T_emag_s = Temag;
p.omega_n_rad_s = wn;
p.zeta_target = zeta;
p.Komega = Komega;
p.Ktheta = Ktheta;
p.omega_min_pu = omega_min;
p.pll_Kp_rad_s = pll_Kp;
p.pll_Ki_rad_s2 = pll_Ki;
p.pll_frequency_limit_pu = pll_frequency_limit;
p.pll_phase_limit_rad = pll_phase_limit;
p.governor_classification = 'PROJECT_DERIVED bounded nonnegative Type-A actuator structure';
p.field_model_classification = 'PROJECT_DERIVED reduced Emag tracker; not GENROU/EXST1/AVR';
p.sync_model_classification = 'PROJECT_DERIVED type-II local terminal PLL plus nominal-frame phase/speed feedback; not external-grid synch-check';
p.provenance = struct('classification','PROJECT_DERIVED', ...
    'source',p.source, ...
    'details',['H/D/Xdp are passed through unchanged; P_ref0 follows healthy PF; ' ...
    'no-load loss, governor/field lags, capture gains, prime-mover ceiling and ' ...
    'stator apparent-power envelope are project design assumptions.']);
end

function [Pmax,source] = resolve_pmax(c,opt,P0_MW)
if isfield(opt,'Pmax_MW')
    Pmax=double(opt.Pmax_MW);
    source='PROJECT_DERIVED explicit opt.Pmax_MW prime-mover study ceiling';
    if ~isscalar(Pmax) || ~isfinite(Pmax) || Pmax<=0
        error('stability:ne39_sg_reclose_plant_params:badPmax', ...
            'opt.Pmax_MW must be positive finite.');
    end
    return;
end
Pmax=NaN; source='';
if isfield(c,'dispatch_contract') && isfield(c.dispatch_contract,'pmax_MW') && ...
        isstruct(c.dispatch_contract.pmax_MW) && ...
        isfield(c.dispatch_contract.pmax_MW,'SG31')
    value=double(c.dispatch_contract.pmax_MW.SG31);
    if isscalar(value) && isfinite(value) && value>0
        Pmax=value;
        source='PROJECT_DERIVED existing SG31 dispatch-contract prime-mover design ceiling';
    end
end
if ~isfinite(Pmax)
    Pmax=10*ceil(1.25*P0_MW/10);
    source=['PROJECT_DERIVED 10*ceil(1.25*healthy SG31 MW/10) ' ...
        'prime-mover study ceiling; not source Pmax/nameplate'];
end
end

function [Qenv,source] = resolve_q_envelope(c,opt)
if isfield(opt,'Q_envelope_MVAr')
    Qenv=double(opt.Q_envelope_MVAr);
    source='PROJECT_DERIVED explicit opt.Q_envelope_MVAr';
else
    if ~isfield(c,'mpc') || ~isfield(c.mpc,'gen') || size(c.mpc.gen,2)<5
        error('stability:ne39_sg_reclose_plant_params:missingQEnvelope', ...
            'No SG31 Q limit is declared; pass an explicit PROJECT_DERIVED Q_envelope_MVAr.');
    end
    row=find(c.mpc.gen(:,1)==31,1);
    if isempty(row) || ~all(isfinite(c.mpc.gen(row,4:5)))
        error('stability:ne39_sg_reclose_plant_params:missingQEnvelope', ...
            'Finite SG31 source Qmax/Qmin or an explicit design envelope is required.');
    end
    Qenv=max(abs(double(c.mpc.gen(row,4:5))));
    source='SOURCE_DEFINED SG31 RAW Qmax/Qmin envelope; used in PROJECT_DERIVED stator proxy';
end
if ~isscalar(Qenv) || ~isfinite(Qenv) || Qenv<=0
    error('stability:ne39_sg_reclose_plant_params:badQEnvelope', ...
        'Q_envelope_MVAr must be one positive finite scalar.');
end
end

function value = option(opt,name,default)
if isfield(opt,name) && ~isempty(opt.(name))
    value=double(opt.(name));
else
    value=default;
end
end

function value = option_alias(opt,name,alias,default)
if isfield(opt,name) && isfield(opt,alias) && ...
        ~isempty(opt.(name)) && ~isempty(opt.(alias)) && ...
        ~isequal(double(opt.(name)),double(opt.(alias)))
    error('stability:ne39_sg_reclose_plant_params:pllGainConflict', ...
        'Specify only one consistent PLL gain spelling (%s or %s).',name,alias);
end
if isfield(opt,name) && ~isempty(opt.(name))
    value=double(opt.(name));
elseif isfield(opt,alias) && ~isempty(opt.(alias))
    value=double(opt.(alias));
else
    value=default;
end
end

function range_scalar(value,name,lo,hi,include_lo,include_hi)
if ~isscalar(value) || ~isfinite(value) || ...
        (include_lo && value<lo) || (~include_lo && value<=lo) || ...
        (include_hi && value>hi) || (~include_hi && value>=hi)
    error('stability:ne39_sg_reclose_plant_params:optionRange', ...
        'opt.%s must lie within the declared PROJECT_DERIVED range.',name);
end
end
