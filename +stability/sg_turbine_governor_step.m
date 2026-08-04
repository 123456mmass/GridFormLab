function [Psv1,Pm1,command]=sg_turbine_governor_step(Psv,Pm,delta_omega,h,p)
%SG_TURBINE_GOVERNOR_STEP Exact frozen-input Type-A governor/turbine step.
%   Implements the Sauer-Pai non-reheat equations
%       Tsv*dPsv/dt = -Psv + Pc - delta_omega/R
%       Tch*dPm/dt  = -Pm + Psv
%   over one interval while the measured speed is held at its accepted
%   left-sample value.  Pc=Pref and the valve command is limited to
%   [Pmin,Pmax].  Psv and Pm are additional prime-mover states; they do not
%   change the operational six-state EMF6 machine state order.
arguments
    Psv (1,1) double {mustBeFinite}
    Pm (1,1) double {mustBeFinite}
    delta_omega (1,1) double {mustBeFinite}
    h (1,1) double {mustBeNonnegative,mustBeFinite}
    p struct
end
required={'Tsv','Tch','R','Pref','Pmin','Pmax'};
for k=1:numel(required)
    if ~isfield(p,required{k}) || ~isscalar(p.(required{k})) || ...
            ~isfinite(p.(required{k}))
        error('stability:sg_turbine_governor_step:parameter', ...
            'Parameter %s must be a finite scalar.',required{k});
    end
end
if p.Tsv<=0 || p.Tch<=0 || p.R<=0 || p.Pmax<p.Pmin
    error('stability:sg_turbine_governor_step:parameterRange', ...
        'Require Tsv,Tch,R>0 and Pmax>=Pmin.');
end
command=min(p.Pmax,max(p.Pmin,p.Pref-delta_omega/p.R));
esv=exp(-h/p.Tsv); ech=exp(-h/p.Tch);
Psv1=command+(Psv-command)*esv;
if p.Tsv==p.Tch
    Pm1=command+(Pm-command)*ech+(Psv-command)*(h/p.Tch)*ech;
else
    Pm1=command+(Pm-command)*ech+ ...
        (Psv-command)*p.Tsv/(p.Tsv-p.Tch)*(esv-ech);
end
end
