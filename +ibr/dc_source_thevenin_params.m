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
% cable resistance:
%
%   Idc = (Edc - Vdc)/Rdc                                                  (1)
%
% so the link equation becomes, with the overvoltage chopper of (5),
%
%   C dVdc/dt = (Edc - Vdc)/Rdc - Pac/Vdc - max(0,Vdc-Vdc_max)/Rch         (2)
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
% BOUNDEDNESS (proved, not assumed)
% ---------------------------------
% For Vdc > Edc every term of (2) is negative whenever Pac >= 0, so
% dVdc/dt < 0 and therefore
%
%   Vdc(t) <= max(Vdc(0),Edc) = Edc   for all t.                           (9)
%
% The link cannot run away during a fault: when the network collapses and
% Pac -> 0 the voltage rises only towards Edc = Vdc0*(1 + eps*Pac0/Vdc0^2).
% The chopper is therefore provably inactive whenever Edc <= Vdc_max, which for
% eps = 0.10 and Pac0 <= 0.9 holds with 0.09 <= 0.10. It is retained because a
% real converter has one and a different dispatch would engage it; the runtime
% counts its activations so the report can state the fact rather than assume it.
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

% (10): the second term is the negative incremental resistance of a
% constant-power load. Reported so the stiffness is visible in provenance
% rather than discovered from a step-size failure.
lambda_dc=-(1/Cdc)*(1/Rdc-Pac0/Vdc0^2);

p=struct('closure','THEVENIN_SOURCE_WITH_LINEAR_CHOPPER', ...
    'classification','PROJECT_DERIVED', ...
    'eps_dc',eps_dc,'Pr',Pr,'Rdc',Rdc,'Edc',Edc,'Vdc0',Vdc0,'Cdc',Cdc, ...
    'Vdc_max',Vdc_max,'Rch',Rch,'delta_ch',delta_ch, ...
    'Pac0',Pac0,'id0',id0,'iq0',iq0,'lambda_dc',lambda_dc, ...
    'cpl_stability_margin',(Vdc0^2/Pac0)/Rdc, ...
    'discriminant_margin',Edc^2/(4*Rdc*getv(dc,'Pmax',1.06*1.2)), ...
    'chopper_inactive_by_bound',Edc<=Vdc_max);
end

function v=getv(s,n,d)
if isstruct(s) && isfield(s,n) && ~isempty(s.(n)), v=s.(n); else, v=d; end
end
