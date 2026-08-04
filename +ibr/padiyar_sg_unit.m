function sg = padiyar_sg_unit(dae, k, R, bus_position)
%PADIYAR_SG_UNIT  Single Padiyar model-1.1 synchronous generator unit (AVR or
%   manual/constant-field excitation), extracted from a full
%   stability.padiyar_model11_dae for machine index K, in the same
%   f(x,y)/current_injection(x,y) ABI as ibr.SwitchableIbr6 so it can be
%   coupled into a mixed SG+IBR composite network solver.
%
%   sg = ibr.padiyar_sg_unit(DAE, K [,R]) returns a struct with:
%     nx (=5 for AVR, =4 for manual), bus_position, x0, f(x,y),
%     current_injection(x,y), reconstruct(x,y), reinit(V). The excitation
%     (and hence the state count) is taken from DAE.excitation / DAE.ns.
%
%   The governing equations are Padiyar model 1.1 (two-axis transient) with a
%   single-time-constant AVR, transcribed VERBATIM from
%   stability.padiyar_model11_dae (same source, Padiyar 2nd ed. Sec. 9.6.1).
%   Machine parameters, the equilibrium state x0, Pm and Vref are read from the
%   audited DAE (built with all machines so its own equilibrium check passes);
%   only the single-machine evaluation is re-expressed here. Currents/powers are
%   on the system (100-MVA) base, matching the DAE network residual.

m = dae.machine; u = dae.units; init = dae.init; ns = dae.ns;
if nargin < 3 || isempty(R), R = 0.05; end   % primary-governor droop (pu/pu)
if k < 1 || k > m.ng
    error('ibr:padiyar_sg_unit:index','machine index out of range.');
end
par = struct( ...
    'Ra',m.Ra(k),'Xd',m.Xd(k),'Xdp',m.Xdp(k),'Xq',m.Xq(k),'Xqp',m.Xqp(k), ...
    'Tpd0',m.Tpd0(k),'Tpq0',m.Tpq0(k),'KA',m.KA(k),'TA',m.TA(k),'wB',m.wB, ...
    'H',u.H(k),'D',u.D(k),'Pm',init.Pm(k),'Vref',init.Vref(k),'R',R, ...
    'Efd0',init.Efd0(k),'ns',ns, ...
    'Q0',dae.pf.Q_generation(u.bus_idx(k)),'fbase',dae.base.frequency_Hz);
bp = init.bus_idx(k);
if nargin >= 4 && ~isempty(bus_position), bp = bus_position; end   % place on a custom network
ii = (k-1)*ns;
x0 = dae.x0(ii+(1:ns));

sg = struct();
sg.name = sprintf('SG_%s', char(dae.state_names{ii+1}(7:end)));  % after 'delta_'
sg.device_type = sprintf('padiyar_sg_model11_%s', dae.excitation);
sg.excitation = dae.excitation;
sg.nx = ns;
sg.bus_position = bp;
sg.x0 = x0(:);
sg.par = par;
sg.f = @(x,y) sg_f(x,y,bp,par);
sg.current_injection = @(x,y) sg_current(x,y,bp,par);
sg.reconstruct = @(x,y) sg_reconstruct(x,y,bp,par);
sg.reinit = @(V) sg_reinit(V, par);   % synchronized reclose to scheduled (Pm,Q0)
end

% =========================================================================
function [Id,Iq,Vd,Vq,V] = stator(x,y,bp,par)
delta=x(1); Eqp=x(3); Edp=x(4);
V=complex(y(2*bp-1),y(2*bp));
[Vd,Vq]=to_dq(V,delta);
rd=Vd-Edp; rq=Vq-Eqp; den=par.Ra^2+par.Xdp*par.Xqp;
Id=(-par.Ra*rd-par.Xqp*rq)/den;
Iq=( par.Xdp*rd-par.Ra*rq)/den;
end

function dx = sg_f(x,y,bp,par)
[Id,Iq,Vd,Vq,V]=stator(x,y,bp,par);
omega=x(2); Eqp=x(3); Edp=x(4);
if par.ns>=5, Efd=x(5); else, Efd=par.Efd0; end   % AVR state vs manual (constant field, NO AVR)
Te=Vd*Id+Vq*Iq+par.Ra*(Id^2+Iq^2);
dx=zeros(par.ns,1);
dx(1)=par.wB*(omega-1);
Pm_eff = par.Pm - (omega-1)/par.R;      % primary-governor droop; R=Inf => no action, omega=1 => Pm_eff=Pm
dx(2)=(Pm_eff-Te-par.D*(omega-1))/(2*par.H);
dx(3)=(Efd-Eqp-(par.Xd-par.Xdp)*Id)/par.Tpd0;
dx(4)=(-Edp+(par.Xq-par.Xqp)*Iq)/par.Tpq0;
if par.ns>=5, dx(5)=(par.KA*(par.Vref-abs(V))-Efd)/par.TA; end   % AVR only
if any(~isfinite(dx)), error('ibr:padiyar_sg_unit:nonfiniteRhs','SG RHS non-finite.'); end
end

function I = sg_current(x,y,bp,par)
[Id,Iq]=stator(x,y,bp,par); delta=x(1);
I=from_dq_current(Id,Iq,delta);
end

function out = sg_reconstruct(x,y,bp,par)
[Id,Iq,Vd,Vq,V]=stator(x,y,bp,par);
delta=x(1); omega=x(2);
if par.ns>=5, Efd=x(5); else, Efd=par.Efd0; end
I=from_dq_current(Id,Iq,delta);
S=V*conj(I);
out=struct('delta',delta,'omega',omega,'Eqp',x(3),'Edp',x(4),'Efd',Efd, ...
    'f_hz',par.fbase*omega,'Id',Id,'Iq',Iq,'Vbus',abs(V),'Vbus_phasor',V, ...
    'I_sys',I,'Pe',real(S),'Qe',imag(S));
end

% =========================================================================
function x = sg_reinit(V, par)
% Synchronized reclose at omega=1.  With AVR, Efd is a state and the machine can
% be initialized at scheduled (Pm,Q0).  With manual excitation Efd is fixed;
% imposing Pm, Q0 and Efd0 simultaneously at an arbitrary restored voltage is
% over-specified and produces a non-equilibrium electromagnetic state.  The
% manual route therefore preserves the physical inputs (Pm,Efd0), solves the
% scalar torque equilibrium, and lets Q be the resulting output.
if par.ns < 5
    x = manual_reclose_equilibrium(V, par);
    return;
end
S = par.Pm + 1i*par.Q0;
I = conj(S/V);
delta = angle(V + (par.Ra + 1i*par.Xq)*I);          % seed
for it = 1:60
    [Id,Iq] = to_dq(I,delta); [Vd,~] = to_dq(V,delta);
    r = Vd + par.Ra*Id - par.Xq*Iq;
    if abs(r) < 1e-12, break; end
    h = 1e-7;
    [Idp,Iqp] = to_dq(I,delta+h); [Vdp,~] = to_dq(V,delta+h);
    rp = Vdp + par.Ra*Idp - par.Xq*Iqp;
    delta = delta - r/((rp-r)/h);
end
[Id,Iq] = to_dq(I,delta); [Vd,Vq] = to_dq(V,delta); %#ok<ASGLU>
Edp = (par.Xq-par.Xqp)*Iq;
Eqp = Vq + par.Ra*Iq + par.Xdp*Id;
Efd = Eqp + (par.Xd-par.Xdp)*Id;
x = [delta;1;Eqp;Edp;Efd];
end

function x = manual_reclose_equilibrium(V, par)
% Project-owned scalar Newton solve of the cited model-1.1 steady equations.
% For a trial rotor angle, the stator and fixed-field equations reduce to
%   [Vd; Vq-Efd0] = [-Ra Xq; -Xd -Ra]*[Id;Iq].
% The remaining residual is air-gap torque Te-Pm=0.
delta = angle(V) + 0.5;
for it = 1:60
    [r, Id, Iq] = torque_residual(delta, V, par);
    if abs(r) < 1e-12, break; end
    h = 1e-7;
    rp = torque_residual(delta+h, V, par);
    dr = (rp-r)/h;
    if ~isfinite(dr) || abs(dr) < 1e-10
        error('ibr:padiyar_sg_unit:reinitJacobian', ...
            'Manual-excitation reclose torque Jacobian is singular.');
    end
    step = max(-0.25,min(0.25,-r/dr));
    delta = delta + step;
end
[r, Id, Iq] = torque_residual(delta, V, par);
if abs(r) > 1e-9
    error('ibr:padiyar_sg_unit:reinitNoEquilibrium', ...
        'No manual-excitation reclose equilibrium found (|Te-Pm|=%.3g).',abs(r));
end
Eqp = par.Efd0 - (par.Xd-par.Xdp)*Id;
Edp = (par.Xq-par.Xqp)*Iq;
x = [atan2(sin(delta),cos(delta));1;Eqp;Edp];
end

function [r,Id,Iq] = torque_residual(delta,V,par)
[Vd,Vq] = to_dq(V,delta);
A = [-par.Ra, par.Xq; -par.Xd, -par.Ra];
ii = A \ [Vd; Vq-par.Efd0];
Id=ii(1); Iq=ii(2);
Te=Vd*Id+Vq*Iq+par.Ra*(Id^2+Iq^2);
r=Te-par.Pm;
end

% =========================================================================
function [d,q]=to_dq(z,delta)
d=sin(delta)*real(z)-cos(delta)*imag(z);
q=cos(delta)*real(z)+sin(delta)*imag(z);
end

function I=from_dq_current(Id,Iq,delta)
I=(sin(delta)*Id+cos(delta)*Iq)+1i*(-cos(delta)*Id+sin(delta)*Iq);
end
