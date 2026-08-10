function [Psv1,Pm1,command,audit] = sg_offline_synchronizer_step( ...
    Psv,Pm,omega_sg,omega_grid,phase_error,h,opt)
%SG_OFFLINE_SYNCHRONIZER_STEP  Project-derived SG speed/phase synchronizer.
%   The breaker-open SG has Te=0, so its mechanical states obey
%
%       2 H domega_sg/dt = Pm - D omega_sg
%       ddelta_sg/dt     = omega_0 omega_sg .
%
%   With e_theta=wrap(theta_grid-theta_sg) and
%   e_omega=omega_grid-omega_sg, the command is
%
%       Pc = sat(D omega_grid + K_omega e_omega + K_theta e_theta,
%                Pmin,Pmax).
%
%   Ignoring the explicitly retained actuator lags for gain construction,
%   K_omega=4 H zeta omega_n-D and
%   K_theta=2 H omega_n^2/omega_0 place the relative angle/speed pair at the
%   requested second-order poles.  The valve/steam-chest states then advance
%   exactly for a piecewise-constant command.  This helper never changes the
%   synchronism guard or its thresholds.
%
%   Classification: PROJECT_DERIVED control law; NUMERICAL_METHOD exact
%   zero-order-hold actuator update.

arguments
    Psv (1,1) double {mustBeFinite}
    Pm (1,1) double {mustBeFinite}
    omega_sg (1,1) double {mustBeFinite}
    omega_grid (1,1) double {mustBeFinite}
    phase_error (1,1) double {mustBeFinite}
    h (1,1) double {mustBePositive,mustBeFinite}
    opt struct
end

required={'H','D','omega_0','omega_n','zeta','Tsv','Tch','Pmin','Pmax'};
for k=1:numel(required)
    if ~isfield(opt,required{k}) || ~isscalar(opt.(required{k})) || ...
            ~isfinite(opt.(required{k}))
        error('stability:sg_offline_synchronizer_step:badOption', ...
            'Option %s must be one finite scalar.',required{k});
    end
end
if opt.H<=0 || opt.D<=0 || opt.omega_0<=0 || opt.omega_n<=0 || ...
        opt.zeta<=0 || opt.Tsv<=0 || opt.Tch<=0 || opt.Pmax<opt.Pmin
    error('stability:sg_offline_synchronizer_step:badOption', ...
        'Controller and actuator parameters must define a positive physical model.');
end
if abs(opt.Tsv-opt.Tch)<=10*eps(max(opt.Tsv,opt.Tch))
    error('stability:sg_offline_synchronizer_step:equalTimeConstants', ...
        'The exact distinct-lag update requires Tsv and Tch to differ.');
end

Komega=4*opt.H*opt.zeta*opt.omega_n-opt.D;
Ktheta=2*opt.H*opt.omega_n^2/opt.omega_0;
if Komega<0 || Ktheta<=0
    error('stability:sg_offline_synchronizer_step:badGains', ...
        'Derived synchronizer gains must satisfy K_omega>=0 and K_theta>0.');
end

raw=opt.D*omega_grid + Komega*(omega_grid-omega_sg) + ...
    Ktheta*phase_error;
command=min(opt.Pmax,max(opt.Pmin,raw));
esv=exp(-h/opt.Tsv);
ech=exp(-h/opt.Tch);
Psv1=command+(Psv-command)*esv;
Pm1=command+(Pm-command)*ech + ...
    (Psv-command)*opt.Tsv/(opt.Tsv-opt.Tch)*(esv-ech);

audit=struct('command_raw',raw,'command',command,'K_omega',Komega, ...
    'K_theta',Ktheta,'e_omega',omega_grid-omega_sg, ...
    'e_theta',phase_error,'classification','PROJECT_DERIVED');
end
