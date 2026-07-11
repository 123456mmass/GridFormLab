function result = kundur_fault_simulation_6th_order(varargin)
%KUNDUR_FAULT_SIMULATION_6TH_ORDER  Full 6th-order nonlinear transient
%simulation using the Kundur/GENTPJ DAE with implicit trapezoidal integration.
%
%   RESULT = kundur_fault_simulation_6th_order() runs the default scenario.

% --- Parse options -----------------------------------------------------------
bus_fault = 8;   tclear = 0.1;   tmax = 5;   dt = 1e-3;
tfault_start = 0.5;   temporary = true;
method = 'trapezoidal';  % PGAz-style predictor-corrector trapezoidal/Heun
corrector_iter = 1;
if nargin > 0 && isstruct(varargin{1})
    o = varargin{1};
    if isfield(o,'bus');          bus_fault    = o.bus;          end
    if isfield(o,'tclear');       tclear       = o.tclear;       end
    if isfield(o,'tmax');         tmax         = o.tmax;         end
    if isfield(o,'dt');           dt           = o.dt;           end
    if isfield(o,'tfault_start'); tfault_start = o.tfault_start; end
    if isfield(o,'temporary');    temporary    = o.temporary;    end
    if isfield(o,'method');       method       = o.method;       end
    if isfield(o,'corrector_iter'); corrector_iter = o.corrector_iter; end
end

% --- Get 6th-order SSSA operating point --------------------------------------
ssa = stability.kundur_ex126_kundur_ssa('options', struct('load_model','cc_p_cz_q'));
if isempty(ssa.dae_f), error('SSSA did not expose DAE handles.'); end
init = ssa.init;
case_data = cases.case_kundur_two_area_classical();
M = case_data.machines;
nb = size(ssa.Ynet, 1);
bus_ids = (1:nb)';          % buses are ordered 1..nb in the SSSA Ynet
ng = init.ng;
base = case_data.base_values;

% Build init with correct opts for DAE calls
tmp_init = init;
tmp_init.opts.load_model = 'cc_p_cz_q';
dae_f = ssa.dae_f;
dae_g = ssa.dae_g;
zb_scale = init.zb_scale;

% --- Ybus networks: fault = bus 8 solid fault; post-fault = network restored
Ypre   = ssa.Ynet;
% During fault: bus 8 solid fault (voltage forced to zero)
Yfault = Ypre;
b_fault = find(bus_ids == bus_fault, 1);
Yfault(b_fault, :) = 0;
Yfault(:, b_fault) = 0;
Yfault(b_fault, b_fault) = 1;
% Post-fault: network restored (temporary fault, standard for small-signal verification)
Ypost = Ypre;
% --- Initial condition -------------------------------------------------------
x = init.x0(:);
y = init.y0(:);
Ynet = Ypre;

% --- Time integration: PGAz-style trapezoidal predictor-corrector/Heun -------
t_vec = 0:dt:tmax;
Nt = numel(t_vec);

delta_hist = zeros(Nt, ng);
omega_hist = zeros(Nt, ng);
Pe_hist    = zeros(Nt, ng);
Vbus_hist  = zeros(Nt, nb);

newton_tol = 1e-8;
newton_maxit = 15; %#ok<NASGU> retained for compatibility with older implicit option
nx = numel(x);
ny = numel(y);

% Compute initial Jacobian
[Jxx, Jxy, Jyx, Jyy] = compute_jac_fd(x, y, tmp_init, M, Ynet, base, zb_scale, dae_f, dae_g);
Jyy_inv_Jyx = Jyy \ Jyx;
J_trap = eye(nx) - 0.5*dt*(Jxx + Jxy * (-Jyy_inv_Jyx));

for it = 1:Nt
    t = t_vec(it);
    if t < tfault_start
        Ynet = Ypre;
    elseif t < tfault_start + tclear
        Ynet = Yfault;
    else
        Ynet = Ypost;
    end

    % Recompute Jacobian at network switches and periodically
    if it==1 || it==round(tfault_start/dt)+1 || it==round((tfault_start+tclear)/dt)+1 || mod(it,5)==0
        [Jxx, Jxy, Jyx, Jyy] = compute_jac_fd(x, y, tmp_init, M, Ynet, base, zb_scale, dae_f, dae_g);
        Jyy_inv_Jyx = Jyy \ Jyx;
        J_trap = eye(nx) - 0.5*dt*(Jxx + Jxy * (-Jyy_inv_Jyx));
    end

    % Record
    for k = 1:ng
        ix = (k-1)*6+1;
        delta_hist(it,k) = x(ix);
        omega_hist(it,k) = x(ix+1);
    end
    Pe = compute_pe_6th(x, y, init, M, base, zb_scale, ng);
    Pe_hist(it,:) = Pe';
    Vbus = abs(complex(y(1:2:end), y(2:2:end)));
    Vbus_hist(it,:) = Vbus';

    if it < Nt
        % Ensure y consistent with x using Newton on g(x,y)=0
        y = solve_g(x, y, tmp_init, M, Ynet, base, zb_scale, dae_g, Jyy);

        fn = dae_f(x, y, tmp_init, M, Ynet, base, []);

        switch lower(method)
            case {'trapezoidal','heun','predictor-corrector','predictor_corrector'}
                % PGAz-style predictor-corrector trapezoidal (Heun):
                %   x_pred = x_k + dt*f_k
                %   x_{k+1} = x_k + dt/2*(f_k + f(t_{k+1},x_pred))
                x_next = x + dt*fn;
                y_next = y;
                for cit = 1:max(1, corrector_iter)
                    y_next = solve_g(x_next, y_next, tmp_init, M, Ynet, base, zb_scale, dae_g, Jyy);
                    fn_next = dae_f(x_next, y_next, tmp_init, M, Ynet, base, []);
                    x_next = x + 0.5*dt*(fn + fn_next);
                end
                x = x_next;
                y = solve_g(x, y_next, tmp_init, M, Ynet, base, zb_scale, dae_g, Jyy);
            case {'implicit','implicit_trapezoidal'}
                % Legacy fully implicit trapezoidal Newton option.
                x_next = x + dt*fn;
                for nit = 1:15
                    y_next = solve_g(x_next, y, tmp_init, M, Ynet, base, zb_scale, dae_g, Jyy);
                    fn_next = dae_f(x_next, y_next, tmp_init, M, Ynet, base, []);
                    R = x_next - x - 0.5*dt*(fn + fn_next);
                    if norm(R, inf) < newton_tol || nit == 15
                        break;
                    end
                    dx = J_trap \ (-R);
                    x_next = x_next + dx;
                end
                x = x_next;
                y = solve_g(x, y_next, tmp_init, M, Ynet, base, zb_scale, dae_g, Jyy);
            otherwise
                error('kundur_fault_simulation_6th_order:unknownMethod', 'Unknown integration method "%s".', method);
        end
    end
end

% --- Package result -----------------------------------------------------------
result = struct();
result.t = t_vec;
result.delta = delta_hist;
result.omega = omega_hist;
result.Pgen = Pe_hist * 100;
result.Pe_pu = Pe_hist;
result.Vbus = Vbus_hist;
result.bus_ids = bus_ids;
result.fault_bus = bus_fault;
result.tclear = tclear;
result.tfault_start = tfault_start;
result.temporary = temporary;
result.integration_method = sprintf('%s predictor-corrector/Heun (corrector_iter=%d)', method, corrector_iter);
result.model = '6th-order Kundur/GENTPJ full nonlinear';
result.H_machine = [M.units(1).H; M.units(2).H; M.units(3).H; M.units(4).H];
result.H_sys = init.H_sys;
result.D_sys = zeros(ng,1);
result.Pm = init.Tm;
end

% =========================================================================
function [Jxx, Jxy, Jyx, Jyy] = compute_jac_fd(x, y, init, M, Ynet, base, zb_scale, dae_f, dae_g)
nx = numel(x); ny = numel(y);
eps_j = 1e-6;

f0 = dae_f(x, y, init, M, Ynet, base, []);
g0 = dae_g(x, y, init, M, Ynet, base, [], zb_scale);

Jxx = zeros(nx, nx);
for j = 1:nx
    xp = x; xp(j) = xp(j) + eps_j;
    Jxx(:,j) = (dae_f(xp, y, init, M, Ynet, base, []) - f0)/eps_j;
end

Jxy = zeros(nx, ny);
for j = 1:ny
    yp = y; yp(j) = yp(j) + eps_j;
    Jxy(:,j) = (dae_f(x, yp, init, M, Ynet, base, []) - f0)/eps_j;
end

Jyx = zeros(ny, nx);
for j = 1:nx
    xp = x; xp(j) = xp(j) + eps_j;
    Jyx(:,j) = (dae_g(xp, y, init, M, Ynet, base, [], zb_scale) - g0)/eps_j;
end

Jyy = zeros(ny, ny);
for j = 1:ny
    yp = y; yp(j) = yp(j) + eps_j;
    Jyy(:,j) = (dae_g(x, yp, init, M, Ynet, base, [], zb_scale) - g0)/eps_j;
end
end

% =========================================================================
function y_out = solve_g(x, y0, init, M, Ynet, base, zb_scale, dae_g, Jyy)
y = y0(:);
maxit = 20; tol = 1e-8;
for nit = 1:maxit
    g_cur = dae_g(x, y, init, M, Ynet, base, [], zb_scale);
    if norm(g_cur, inf) < tol
        break;
    end
    dy = Jyy \ (-g_cur);
    y = y + dy;
end
y_out = y;
end

% =========================================================================
function Pe = compute_pe_6th(x, y, init, M, base, zb_scale, ng)
R = M.reactances;
Ra_n = R.Ra * zb_scale;
Xdpp_n = R.Xdpp * zb_scale;
Xqpp_n = R.Xqpp * zb_scale;
Pe = zeros(ng,1);
for k = 1:ng
    ix = (k-1)*6+1;
    delta = x(ix);
    Eqpp = x(ix+4);  Edpp = x(ix+5);
    bidx = init.bus_idx(k);
    Vt = complex(y(2*bidx-1), y(2*bidx));
    Vd = sin(delta)*real(Vt) - cos(delta)*imag(Vt);
    Vq = cos(delta)*real(Vt) + sin(delta)*imag(Vt);
    det_val = Xdpp_n*Xqpp_n + Ra_n*Ra_n;
    Id = (-Ra_n*(Vd-Edpp) - Xqpp_n*(Vq-Eqpp)) / det_val;
    Iq = ( Xdpp_n*(Vd-Edpp) - Ra_n*(Vq-Eqpp)) / det_val;
    Pe(k) = Vd*Id + Vq*Iq + Ra_n*(Id^2 + Iq^2);
end
end
