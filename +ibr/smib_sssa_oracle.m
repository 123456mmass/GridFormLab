function out = smib_sssa_oracle(dev,x_eq,V_eq,u_eq,V_inf,Z_line,opt)
%SMIB_SSSA_ORACLE Independent one-IBR/infinite-bus SSSA characterization.
%   OUT = ibr.smib_sssa_oracle(DEV,X_EQ,V_EQ,U_EQ,V_INF,Z_LINE,OPT)
%   treats the infinite bus as an algebraic voltage source (no SG states):
%
%       g(x,V) = I_ibr(x,V) - (V - V_inf)/Z_line = 0.
%
%   The device uses its production f/current_injection closures.  This helper
%   independently forms the centered-FD DAE Jacobian and Schur complement
%
%       A = f_x - f_y*(g_y\g_x),
%
%   then checks it against a second construction that perturbs each state,
%   re-solves g=0, and differentiates the resulting reduced RHS.  It is an
%   ASSUMED_DIAGNOSTIC falsification oracle, not a production SSSA route.

arguments
    dev (1,1) struct
    x_eq (:,1) double
    V_eq (1,1) double {mustBeFinite}
    u_eq (:,1) double
    V_inf (1,1) double {mustBeFinite}
    Z_line (1,1) double {mustBeFinite}
    opt.fd_eps (1,1) double {mustBePositive} = 1e-6
    opt.direct_fd_eps (1,1) double {mustBePositive} = 1e-6
    opt.algebraic_tolerance (1,1) double {mustBePositive} = 1e-12
    opt.algebraic_max_iterations (1,1) double {mustBeInteger,mustBePositive} = 20
end

required = {'nx','nu','bus_position','f','current_injection','state_names'};
for k = 1:numel(required)
    if ~isfield(dev,required{k})
        error('ibr:smib_sssa_oracle:deviceContract', ...
            'Device is missing required field %s.',required{k});
    end
end
if dev.bus_position ~= 1
    error('ibr:smib_sssa_oracle:busPosition', ...
        'The standalone SMIB device must use bus_position=1.');
end
if numel(x_eq) ~= dev.nx || numel(u_eq) ~= dev.nu
    error('ibr:smib_sssa_oracle:dimension', ...
        'x_eq/u_eq dimensions must equal dev.nx/dev.nu.');
end
if any(~isfinite(x_eq)) || any(~isfinite(u_eq)) || abs(V_eq) == 0 || ...
        abs(V_inf) == 0 || abs(Z_line) == 0
    error('ibr:smib_sssa_oracle:nonfiniteInput', ...
        'Operating point, infinite-bus voltage and line impedance must be finite and nonzero.');
end

ec = struct();
y_eq = [real(V_eq);imag(V_eq)];
active = local_active_indices(dev,ec);
nx = dev.nx;
ny = 2;
h = opt.fd_eps;

f_handle = @(x,y) dev.f(0,x,y,u_eq,ec);
g_handle = @(x,y) local_g(dev,x,y,u_eq,ec,V_inf,Z_line);
f0 = f_handle(x_eq,y_eq);
g0 = g_handle(x_eq,y_eq);
if numel(f0) ~= nx || numel(g0) ~= ny || any(~isfinite(f0)) || any(~isfinite(g0))
    error('ibr:smib_sssa_oracle:residualContract', ...
        'Device/network residual dimensions or values are invalid.');
end

[fx,fy,gx,gy] = local_jacobians(f_handle,g_handle,x_eq,y_eq,h);
gy_rcond = rcond(gy);
if ~isfinite(gy_rcond) || gy_rcond <= 1e-10
    error('ibr:smib_sssa_oracle:illConditionedGy', ...
        'Infinite-bus algebraic gy rcond %.3e must exceed 1e-10.',gy_rcond);
end
A_full = fx - fy*(gy\gx);
A = A_full(active,active);

% Independent reduced-RHS derivative: perturb x_active and solve KCL again.
hd = opt.direct_fd_eps;
A_direct = zeros(numel(active));
for j = 1:numel(active)
    xp = x_eq; xm = x_eq;
    xp(active(j)) = xp(active(j)) + hd;
    xm(active(j)) = xm(active(j)) - hd;
    yp = local_solve_y(g_handle,xp,y_eq,opt);
    ym = local_solve_y(g_handle,xm,y_eq,opt);
    fp = f_handle(xp,yp);
    fm = f_handle(xm,ym);
    A_direct(:,j) = (fp(active)-fm(active))/(2*hd);
end

lambda = eig(A);
matrix_scale = max(1,norm(A,inf));
agreement = norm(A-A_direct,inf)/max(1,norm(A,inf)+norm(A_direct,inf));

out = struct();
out.classification = 'ASSUMED_DIAGNOSTIC_SMIB_ORACLE';
out.device_id = dev.device_id;
out.device_type = dev.device_type;
out.state_names = dev.state_names;
out.active_state_indices = active;
out.x_eq = x_eq;
out.y_eq = y_eq;
out.u_eq = u_eq;
out.V_inf = V_inf;
out.Z_line = Z_line;
out.f0 = f0;
out.g0 = g0;
out.fx = fx;
out.fy = fy;
out.gx = gx;
out.gy = gy;
out.gy_rcond = gy_rcond;
out.A_full = A_full;
out.A = A;
out.A_direct = A_direct;
out.schur_direct_relative_error = agreement;
out.eigenvalues = lambda;
out.max_real_eigenvalue = max(real(lambda));
out.eigenvalue_count = numel(lambda);
out.fd_eps = h;
out.direct_fd_eps = hd;
out.matrix_scale = matrix_scale;
end

function active = local_active_indices(dev,ec)
active = dev.active_state_indices;
if isa(active,'function_handle'), active = active(ec); end
active = active(:).';
if isempty(active) || any(~isfinite(active)) || any(active ~= fix(active)) || ...
        any(active < 1) || any(active > dev.nx) || numel(unique(active)) ~= numel(active)
    error('ibr:smib_sssa_oracle:activeStateIndices', ...
        'Device active-state indices must be unique integers in 1:dev.nx.');
end
end

function g = local_g(dev,x,y,u,ec,V_inf,Z_line)
I_ibr = dev.current_injection(0,x,y,u,ec);
V = complex(y(1),y(2));
I_line = (V-V_inf)/Z_line;
mis = I_ibr-I_line;
g = [real(mis);imag(mis)];
end

function [fx,fy,gx,gy] = local_jacobians(fh,gh,x,y,h)
nx = numel(x); ny = numel(y);
fx = zeros(nx); gx = zeros(ny,nx);
fy = zeros(nx,ny); gy = zeros(ny);
for j = 1:nx
    xp=x; xm=x; xp(j)=xp(j)+h; xm(j)=xm(j)-h;
    fx(:,j)=(fh(xp,y)-fh(xm,y))/(2*h);
    gx(:,j)=(gh(xp,y)-gh(xm,y))/(2*h);
end
for j = 1:ny
    yp=y; ym=y; yp(j)=yp(j)+h; ym(j)=ym(j)-h;
    fy(:,j)=(fh(x,yp)-fh(x,ym))/(2*h);
    gy(:,j)=(gh(x,yp)-gh(x,ym))/(2*h);
end
end

function y = local_solve_y(gh,x,y0,opt)
y = y0;
for it = 1:opt.algebraic_max_iterations
    r = gh(x,y);
    if norm(r,inf) <= opt.algebraic_tolerance, return; end
    h = opt.fd_eps;
    J = zeros(2);
    for j = 1:2
        yp=y; ym=y; yp(j)=yp(j)+h; ym(j)=ym(j)-h;
        J(:,j)=(gh(x,yp)-gh(x,ym))/(2*h);
    end
    if rcond(J) <= 1e-12
        error('ibr:smib_sssa_oracle:algebraicJacobian', ...
            'Perturbed algebraic solve has ill-conditioned Jacobian.');
    end
    y = y-J\r;
    if any(~isfinite(y))
        error('ibr:smib_sssa_oracle:algebraicNonfinite', ...
            'Perturbed algebraic solve generated a non-finite voltage.');
    end
end
error('ibr:smib_sssa_oracle:algebraicNoConverge', ...
    'Perturbed algebraic solve did not converge in %d iterations.', ...
    opt.algebraic_max_iterations);
end
