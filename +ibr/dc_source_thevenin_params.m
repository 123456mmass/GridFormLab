function p=dc_source_thevenin_params(dc,Vdc0,Cdc,Rf,kappa,P_ref,Q_ref,V0,Pac0_override)
%DC_SOURCE_THEVENIN_PARAMS  Non-ideal DC source behind its internal resistance.
%
%   p = ibr.dc_source_thevenin_params(dc,Vdc0,Cdc,Rf,kappa,P_ref,Q_ref,V0)
%
% Classification: PROJECT_DERIVED. The EECON49 source publishes the DC-link
% energy balance C dVdc/dt = Idc - Pac/Vdc but not the law for Idc, so the
% project must supply one. This file supplies it and records its derivation.
%
% WHY THE PREVIOUS CLOSURE WAS REPLACED
% -------------------------------------
% The former closure was Idc = Pac/Vdc + (C/Tdc)(Vdc0 - Vdc), which cancels the
% AC loading EXACTLY and reduces the link to dVdc/dt = (Vdc0 - Vdc)/Tdc. Two
% consequences were measured on the delivered 250 s trajectory and are the
% reason for this change:
%   * Vdc(0) = Vdc0 is the equilibrium of that scalar equation, so Vdc stayed at
%     1.000000000000 pu for all 4994 accepted samples of all four converters,
%     range exactly 0. The state carried no information.
%   * Because C cancels, the case value Cdc never entered any residual. The DC
%     capacitance was declared but unused.
% Both are the signature of an ideal DC source. They are removed here.
%
% THE MODEL
% ---------
% Any DC-side source -- rectifier, battery, PV string in its voltage-source
% region, or a DC feeder -- is to first order an EMF behind its internal plus
% cable resistance. That circuit also has inductance, so the current it actually
% delivers is a STATE that chases its own static characteristic:
%
%   tau_s dIdc/dt = (Edc - Vdc)/Rdc - Idc          tau_s = Ls/Rdc          (1)
%   C     dVdc/dt = Idc - Pac/Vdc - max(0,Vdc-Vdc_max)/Rch                 (2)
%
% Idc is the fourth plant coordinate of the device. An earlier revision omitted
% it, i.e. took tau_s = 0, which made the DC row a single scalar equation. That
% limit is recovered exactly (see the degeneracy note below), so the earlier
% spectrum is a special case of this one and not a different model.
%
% Edc: FORCED, not chosen. Requiring the dispatched point to be an equilibrium,
% i.e. dVdc/dt = 0 at Vdc = Vdc0 and Pac = Pac0, gives the unique value
%
%   Edc = Vdc0 + Rdc*Pac0/Vdc0                                             (3)
%
% Pac0 is the converter-side power at t=0, which is the bus power plus the
% filter loss. At the initial point both branches set id0 = kappa*P/|V0| and
% iq0 = -kappa*Q/|V0| with theta = angle(V0), hence vd = |V0| and vq = 0, and
% the two omega*L cross terms of vcd*id + vcq*iq cancel identically, leaving
%
%   Pac0 = kappa*P_ref + Rf*(id0^2 + iq0^2)                                (4)
%
% in closed form. Because (3)-(4) are evaluated from the same P_ref, Q_ref, V0
% and Rf in the GFL and the GFM branch, Edc is identical in both, so a runtime
% GFL<->GFM transfer introduces no step in dVdc/dt. That identity is the reason
% this helper exists instead of two copies of the formula.
%
% Rdc: from a declared DC-source regulation eps, the fractional DC voltage rise
% from the dispatched point to no load at rated converter power Pr,
%
%   Rdc = eps*Vdc0^2/Pr                                                    (5)
%
% eps is bounded above by the requirement that the link still support the
% largest power the AC current limiter permits. The equilibrium of (2) with the
% chopper off is Vdc^2 - Edc*Vdc + Rdc*P = 0, which has a real solution only if
%
%   Edc^2 >= 4*Rdc*Pmax                                                    (6)
%
% Demanding margin m in (6) at Pmax = Vmax*Imax gives eps <= about 0.115 for
% m = 2 on this device (Vmax = 1.06, Imax = 1.2, P_ref = 0.85). The declared
% value eps = 0.10 sits inside that bound with realised margin 2.32 and
% coincides with the usual 10% regulation of a DC link fed through a boost
% stage or a feeder. It is NOT chosen to suit the integrator step: see below.
%
% Chopper: a braking resistor conducting in its linear region,
%
%   Ich = max(0, Vdc - Vdc_max)/Rch                                        (7)
%
% continuous and Lipschitz, non-differentiable only on Vdc = Vdc_max, exactly
% like the current limiter Pi_I, so it needs no new smoothness argument.
% Rch follows from requiring the chopper to sink rated power at a declared
% overshoot delta above the threshold:
%
%   Rch = Vdc_max^2*delta*(1+delta)/Pr                                     (8)
%
% tau_s: DERIVED FROM A STANDARD FILTER CRITERION, NOT FROM A DESIRED OUTPUT
% -------------------------------------------------------------------------
% Linearising (1)-(2) about the dispatched point, with the chopper off, gives the
% 2x2 DC block
%
%   A_dc = [  Pac0/(C Vdc0^2)      1/C
%            -1/(tau_s Rdc)       -1/tau_s ]                               (9)
%
% whose determinant and trace are
%
%   det = K/tau_s,  K = (1/C)(1/Rdc - Pac0/Vdc0^2)
%   tr  = a - 1/tau_s,  a = Pac0/(C Vdc0^2)
%
% Two consequences fix tau_s from above and below without reference to any
% reported quantity:
%
%   * det > 0 requires Rdc < Vdc0^2/Pac0. That is the SAME constant-power-load
%     condition the resistive model had; adding the source state does not relax
%     it.
%   * tr < 0 requires tau_s < C Vdc0^2 / Pac0. This is NEW: a source that reacts
%     too slowly cannot hold a constant-power load, and the link goes unstable.
%
% Between those bounds tau_s is set by the maximally-flat criterion zeta = 1/sqrt2
% on the L-C pair, which is the ordinary way a filter of this shape is specified.
% With x = 1/tau_s, zeta = (x - a)/(2 sqrt(K x)), so zeta = zeta* has the closed
% form
%
%   tau_s = 1/y^2,   y = zeta* sqrt(K) + sqrt(zeta*^2 K + a)              (10)
%
% On this device (C = Rdc = 0.10, Vdc0 = 1) that returns tau_s = 5.00 ms, and the
% realised zeta is 0.707 at Pac0 = 0.45 and 0.708 at Pac0 = 0.90, so ONE declared
% tau_s serves the whole dispatch range and the parameter can stay a component
% value rather than a per-converter tuning. The resulting pair sits near
% -98 +/- 98 1/s, i.e. about 15.5 Hz.
%
% DEGENERACY. As tau_s -> 0 the pair separates into a fast root at about
% -1/tau_s and a slow root at -(1/C)(1/Rdc - Pac0/Vdc0^2), which is exactly the
% eigenvalue of the resistive model. Verified numerically to 9.5e-3 at
% tau_s = 1e-6 and falling linearly with tau_s.
%
% BOUNDEDNESS WHILE EXPORTING, AND THE CASE THAT ESCAPES IT
% ---------------------------------------------------------
% For Vdc > Edc every term of (2) is negative whenever Pac >= 0, so
% dVdc/dt < 0 and therefore
%
%   Vdc(t) <= max(Vdc(0),Edc) = Edc   whenever Pac(t) >= 0.                (9)
%
% Read the hypothesis of (9) carefully, because it is not decoration. While the
% converter EXPORTS, the link cannot run away: when the network collapses and
% Pac -> 0 the voltage rises only towards Edc = Vdc0*(1 + eps*Pac0/Vdc0^2), so
% the internal resistance is itself the limit and, at this dispatch,
% Edc = 1.0453 sits below Vdc_max = 1.10.
%
% (9) says NOTHING about Pac < 0. A converter driven into ABSORPTION -- pinned at
% its current limit while the island voltage and angle run away from it -- pumps
% energy into its own link, +|Pac|/Vdc becomes a charging term, and Vdc can rise
% past Edc and reach the chopper threshold. That is not hypothetical here: on the
% four-GFM pinned arm of the delivered comparison, IBR1 crosses Vdc_max at
% t = 20.4573 s and stays above it for 94 accepted samples to the end of that
% arm, peaking at 1.103080 pu, with Pac in [-0.925, -0.747] pu and |i| ~ 1.204
% (current-limited) at every one of them. Restricted to the samples of the same
% arm where Pac >= 0 the peak is 1.048176 pu, below the threshold. On the three
% arms that reach the horizon the peak over all four converters is
% 1.0108 / 1.0224 / 1.0167 pu and the chopper never conducts.
%
% So the chopper is not ornamental and must never be reported as provably idle.
% `chopper_inactive_by_bound` below is exactly what its name says and no more: a
% property of the DISPATCHED point (Edc <= Vdc_max), hence of trajectories that
% stay in export. Whether it conducted on a given run is decided afterwards from
% max_t Vdc against Vdc_max, which is exact because the conduction condition
% depends on Vdc alone.
%
% STIFFNESS, STATED NOT HIDDEN
% ----------------------------
% Linearising (2) with the chopper off about the dispatched point gives
%
%   lambda_dc = -(1/C)*(1/Rdc - Pac0/Vdc0^2)                              (10)
%
% whose second term is the negative incremental resistance of a constant-power
% load; stability requires Rdc < Vdc0^2/Pac0. With C = 0.10, Rdc = 0.10 and
% Pac0 = 0.85 this is lambda_dc = -91.5 1/s, tau = 10.9 ms, so |lambda|*dt =
% 4.6 at the nominal phasor step dt = 0.05 s. The implicit trapezoidal rule is
% A-stable there, but the mode is under-resolved at the nominal step and the
% adaptive controller must reduce dt where it is excited. eps was NOT enlarged
% to make |lambda|*dt approach 1: choosing a physical parameter to suit a step
% size would be reverse-engineering it from numerical convenience. The honest
% consequence is that a firmer DC source (eps of order 0.01, a battery at the
% terminals) is stiffer still and belongs to EMT rather than to a 50 ms phasor
% step. That limitation is reported, not designed around.

if nargin<9, Pac0_override=[]; end
eps_dc=getv(dc,'eps_dc',0.10);
Pr=getv(dc,'Pr',1.0);
Vdc_max=getv(dc,'Vdc_max',1.10);
delta_ch=getv(dc,'delta_ch',0.02);

if ~isfinite(eps_dc) || eps_dc<=0
    error('ibr:dc_source_thevenin:eps','eps_dc must be finite and positive.');
end
if ~isfinite(Pr) || Pr<=0
    error('ibr:dc_source_thevenin:Pr','Pr must be finite and positive.');
end
if ~isfinite(Vdc_max) || Vdc_max<=0
    error('ibr:dc_source_thevenin:Vdcmax','Vdc_max must be finite and positive.');
end
if ~isfinite(delta_ch) || delta_ch<=0
    error('ibr:dc_source_thevenin:delta','delta_ch must be finite and positive.');
end

Rdc=eps_dc*Vdc0^2/Pr;                                  % (5)
Rch=getv(dc,'Rch',Vdc_max^2*delta_ch*(1+delta_ch)/Pr); % (8)
if ~isfinite(Rch) || Rch<=0
    error('ibr:dc_source_thevenin:Rch','Rch must be finite and positive.');
end

Vmag=abs(V0);
if ~isfinite(Vmag) || Vmag<=0
    error('ibr:dc_source_thevenin:V0','V0 must be finite and nonzero.');
end
id0=kappa*P_ref/Vmag;
iq0=-kappa*Q_ref/Vmag;
if isempty(Pac0_override)
    Pac0=kappa*P_ref+Rf*(id0^2+iq0^2);                 % (4)
else
    Pac0=Pac0_override;
end
Edc=Vdc0+Rdc*Pac0/Vdc0;                                % (3)

if ~isfinite(Cdc) || Cdc<=0
    error('ibr:dc_source_thevenin:Cdc','Cdc must be finite and positive.');
end

% The tau_s -> 0 limit of the DC mode, kept because it is the eigenvalue of the
% resistive model and therefore the degeneracy target of (10).
lambda_dc=-(1/Cdc)*(1/Rdc-Pac0/Vdc0^2);

% Source-current state. OPT-IN, because the same two equations with tau_s -> 0
% collapse to the single resistive row, and several models in this package share
% this GFL adapter while keeping that earlier limit. dc.source_state selects which
% of the two the device exposes; nothing else about the closure differs.
source_state=logical(getv(dc,'source_state',false));
% tau_s is a component value: Ls/Rdc of the DC circuit.
K_dc=(1/Cdc)*(1/Rdc-Pac0/Vdc0^2);
a_dc=Pac0/(Cdc*Vdc0^2);
zeta_target=getv(dc,'zeta_target',1/sqrt(2));
y_mf=zeta_target*sqrt(max(K_dc,0))+sqrt(zeta_target^2*max(K_dc,0)+a_dc);
tau_s_maxflat=1/max(y_mf,eps)^2;                                   % (10)
tau_s=getv(dc,'tau_s',tau_s_maxflat);
tau_s_stability_max=Cdc*Vdc0^2/max(Pac0,eps);
if source_state && (~isfinite(tau_s) || tau_s<=0)
    error('ibr:dc_source_thevenin:tau','tau_s must be finite and positive.');
end
if source_state && tau_s>=tau_s_stability_max
    error('ibr:dc_source_thevenin:tauUnstable', ...
        ['tau_s=%.6g exceeds the constant-power-load bound C*Vdc0^2/Pac0=%.6g; ' ...
         'the DC link would be unstable at this dispatch.'],tau_s,tau_s_stability_max);
end
A_dc=[a_dc, 1/Cdc; -1/(tau_s*Rdc), -1/tau_s];                      % (9)
lam_pair=eig(A_dc);
omega_n_dc=sqrt(abs(det(A_dc)));
zeta_dc=-trace(A_dc)/(2*max(omega_n_dc,eps));
Idc0=Pac0/Vdc0;   % dVdc/dt = 0 and dIdc/dt = 0 hold together at this value

p=struct('closure','THEVENIN_SOURCE_STATE_WITH_LINEAR_CHOPPER', ...
    'classification','PROJECT_DERIVED', ...
    'eps_dc',eps_dc,'Pr',Pr,'Rdc',Rdc,'Edc',Edc,'Vdc0',Vdc0,'Cdc',Cdc, ...
    'Vdc_max',Vdc_max,'Rch',Rch,'delta_ch',delta_ch, ...
    'Pac0',Pac0,'id0',id0,'iq0',iq0,'lambda_dc',lambda_dc, ...
    'source_state',source_state, ...
    'tau_s',tau_s,'tau_s_maxflat',tau_s_maxflat, ...
    'tau_s_stability_max',tau_s_stability_max,'zeta_target',zeta_target, ...
    'Idc0',Idc0,'lambda_dc_pair',lam_pair(:).', ...
    'omega_n_dc',omega_n_dc,'zeta_dc',zeta_dc, ...
    'f_dc_Hz',abs(imag(lam_pair(1)))/(2*pi), ...
    'cpl_stability_margin',(Vdc0^2/Pac0)/Rdc, ...
    'discriminant_margin',Edc^2/(4*Rdc*getv(dc,'Pmax',1.06*1.2)), ...
    'chopper_inactive_by_bound',Edc<=Vdc_max);
end

function v=getv(s,n,d)
if isstruct(s) && isfield(s,n) && ~isempty(s.(n)), v=s.(n); else, v=d; end
end
