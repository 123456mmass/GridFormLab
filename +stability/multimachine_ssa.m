function result = multimachine_ssa(model)
%MULTIMACHINE_SSA General DAE small-signal stability engine.
% This is the common solver/linearisation core used by benchmark wrappers.
% It is intentionally case-agnostic: Kundur, Sauer-Pai, or any other
% multimachine benchmark supplies only f(x,y), g(x,y), x0, y0, and options.
%
% Required model fields:
%   x0, y0          equilibrium state/algebraic vectors
%   f, g            function handles f(x,y), g(x,y)
%
% Optional model fields:
%   Jxx,Jxy,Jyx,Jyy precomputed DAE Jacobian blocks. If absent, central
%                   finite differences are used.
%   fd_eps          finite-difference step, default 1e-6
%   free_y          algebraic variables to retain in Schur complement
%   reduction       'none' (default) or 'coi'
%   ng              machine count for COI reduction
%   states_per_machine
%   angle_state_index, speed_state_index
%   inertia         H or M weights for COI
%   state_names

arguments
    model struct
end

mustHave(model, 'x0'); mustHave(model, 'y0'); mustHave(model, 'f'); mustHave(model, 'g');
x0 = model.x0(:); y0 = model.y0(:);
nx = numel(x0); ny = numel(y0);
if isfield(model, 'fd_eps'); h = model.fd_eps; else; h = 1e-6; end

if all(isfield(model, {'Jxx','Jxy','Jyx','Jyy'}))
    Jxx = model.Jxx; Jxy = model.Jxy; Jyx = model.Jyx; Jyy = model.Jyy;
else
    [Jxx, Jxy, Jyx, Jyy] = finite_difference_jacobian(model.f, model.g, x0, y0, h);
end

if isfield(model, 'free_y') && ~isempty(model.free_y)
    free_y = model.free_y(:).';
else
    free_y = 1:ny;
end

Afull = Jxx - Jxy(:,free_y) * (Jyy(free_y,free_y) \ Jyx(free_y,:));
lambda_full = eig(Afull);
[Vfull, ~] = eig(Afull);

Ared = Afull; lambda_reduced = lambda_full; Vreduced = Vfull; T = eye(nx); keep = 1:nx;
if isfield(model, 'reduction') && strcmpi(model.reduction, 'coi')
    required = {'ng','states_per_machine','angle_state_index','speed_state_index','inertia'};
    for k = 1:numel(required); mustHave(model, required{k}); end
    [Ared, keep, T] = reduce_coi(Afull, model.ng, model.states_per_machine, ...
        model.angle_state_index, model.speed_state_index, model.inertia);
    lambda_reduced = eig(Ared);
    [Vreduced, ~] = eig(Ared);
end

result = struct();
result.Afull = Afull;
result.Ared = Ared;
result.Jxx = Jxx; result.Jxy = Jxy; result.Jyx = Jyx; result.Jyy = Jyy;
result.free_y = free_y;
result.eigenvalues = lambda_full;
result.reduced_eigenvalues = lambda_reduced;
result.mode_shapes = Vfull;
result.reduced_mode_shapes = Vreduced;
result.frequency_Hz = abs(imag(lambda_full))/(2*pi);
result.damping_ratio = -real(lambda_full)./(abs(lambda_full)+eps);
result.stable = all(real(lambda_full) < -1e-9);
result.reduced_frequency_Hz = abs(imag(lambda_reduced))/(2*pi);
result.reduced_damping_ratio = -real(lambda_reduced)./(abs(lambda_reduced)+eps);
result.reduced_stable = all(real(lambda_reduced) < -1e-9);
result.T_reduction = T;
result.keep = keep;
if isfield(model, 'state_names'); result.state_names = model.state_names; end
if isfield(model, 'metadata'); result.metadata = model.metadata; end
end

function [Jxx,Jxy,Jyx,Jyy] = finite_difference_jacobian(fhandle, ghandle, x0, y0, h)
nx = numel(x0); ny = numel(y0);
f0 = fhandle(x0,y0); g0 = ghandle(x0,y0); %#ok<NASGU>
nf = numel(f0); ng = numel(g0);
Jxx = zeros(nf,nx); Jxy = zeros(nf,ny); Jyx = zeros(ng,nx); Jyy = zeros(ng,ny);
for i = 1:nx
    xp = x0; xm = x0; xp(i) = xp(i)+h; xm(i) = xm(i)-h;
    Jxx(:,i) = (fhandle(xp,y0) - fhandle(xm,y0))/(2*h);
    Jyx(:,i) = (ghandle(xp,y0) - ghandle(xm,y0))/(2*h);
end
for j = 1:ny
    yp = y0; ym = y0; yp(j) = yp(j)+h; ym(j) = ym(j)-h;
    Jxy(:,j) = (fhandle(x0,yp) - fhandle(x0,ym))/(2*h);
    Jyy(:,j) = (ghandle(x0,yp) - ghandle(x0,ym))/(2*h);
end
end

function [Arel, keep, T] = reduce_coi(Afull, ng, ns, angle_idx, speed_idx, inertia)
% Generic COI projection.  It assumes each machine has the same number of
% states and the angle/speed locations are identical in each machine block.
Hn = inertia(:)/sum(inertia(:));
nx = size(Afull,1);
remove = false(nx,1);
remove(angle_idx) = true;
remove(speed_idx) = true;
nred = nx - 2;
T = zeros(nx,nred);
keep_mask = false(nx,1);
c = 1;
% Machine 1: angle/speed absorbed into COI, keep all other states.
for s = 1:ns
    if s == angle_idx || s == speed_idx; continue; end
    T(s,c) = 1; keep_mask(s) = true; c = c+1;
end
% Machines 2..ng: relative angle/speed and all other states.
for k = 2:ng
    base = (k-1)*ns;
    T(base+angle_idx,c) = 1;
    for kk = 1:ng
        T((kk-1)*ns+angle_idx,c) = T((kk-1)*ns+angle_idx,c) - Hn(kk);
    end
    keep_mask(base+angle_idx) = true; c = c+1;
    T(base+speed_idx,c) = 1;
    for kk = 1:ng
        T((kk-1)*ns+speed_idx,c) = T((kk-1)*ns+speed_idx,c) - Hn(kk);
    end
    keep_mask(base+speed_idx) = true; c = c+1;
    for s = 1:ns
        if s == angle_idx || s == speed_idx; continue; end
        T(base+s,c) = 1; keep_mask(base+s) = true; c = c+1;
    end
end
keep = find(keep_mask);
Arel = pinv(T) * Afull * T;
end

function mustHave(s, name)
if ~isfield(s, name)
    error('multimachine_ssa:missingField', 'Model is missing required field "%s".', name);
end
end
