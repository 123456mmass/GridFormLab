function [Vpcc, info] = solve_pcc_infbus_equilibrium(V_inf, Z_line, S_list, opts)
%SOLVE_PCC_INFBUS_EQUILIBRIUM  PCC voltage for N injectors behind one line to
%   an infinite bus.
%
%   [VPCC, INFO] = ibr.solve_pcc_infbus_equilibrium(V_INF, Z_LINE, S_LIST)
%   solves the single-node power balance at a common point of connection (PCC)
%   where the aggregate injected complex power S_tot = sum(S_LIST) flows through
%   Z_LINE into the infinite bus V_INF:
%
%       conj(Vpcc) * (Vpcc - V_inf) / Z_line = conj(S_tot).
%
%   Derivation: the line current from the PCC to the infinite bus is
%   I_line = (Vpcc - V_inf)/Z_line, and power balance at the PCC requires the
%   injectors to supply exactly that line flow, S_tot = Vpcc*conj(I_line), i.e.
%   conj(S_tot) = conj(Vpcc)*I_line. This is one complex equation; it is solved
%   by a damped Newton iteration on the two real unknowns [Re(Vpcc);Im(Vpcc)]
%   with a finite-difference Jacobian (the residual is non-analytic in Vpcc
%   because of the conjugate).
%
%   S_LIST entries and S_tot are in system pu (generator convention: injection
%   into the network is positive). Z_LINE and V_INF are system-pu phasors.
%
%   Classification: NUMERICAL_METHOD (in-house Newton on an exact algebraic
%   power-balance identity). No external solver is used.

arguments
    V_inf (1,1) double {mustBeFinite}
    Z_line (1,1) double {mustBeFinite}
    S_list (1,:) double
    opts.tol (1,1) double {mustBePositive} = 1e-12
    opts.max_iter (1,1) double {mustBeInteger,mustBePositive} = 100
    opts.fd_eps (1,1) double {mustBePositive} = 1e-7
end

if abs(Z_line) == 0
    error('ibr:solve_pcc_infbus_equilibrium:badLine','Z_line must be nonzero.');
end
if abs(V_inf) == 0
    error('ibr:solve_pcc_infbus_equilibrium:badVinf','V_inf must be nonzero.');
end
if isempty(S_list) || any(~isfinite(S_list))
    error('ibr:solve_pcc_infbus_equilibrium:badS','S_list must be finite and nonempty.');
end

Stot = sum(S_list);

    function r = residual(v)
        Vc = complex(v(1), v(2));
        Fc = conj(Vc)*(Vc - V_inf)/Z_line - conj(Stot);
        r = [real(Fc); imag(Fc)];
    end

v = [real(V_inf); imag(V_inf)];   % warm start at the infinite bus
converged = false;
last_norm = NaN;
for it = 1:opts.max_iter
    r = residual(v);
    last_norm = norm(r, inf);
    if last_norm <= opts.tol
        converged = true;
        break;
    end
    h = opts.fd_eps;
    J = zeros(2);
    for j = 1:2
        vp = v; vm = v;
        vp(j) = vp(j) + h;
        vm(j) = vm(j) - h;
        J(:,j) = (residual(vp) - residual(vm))/(2*h);
    end
    if rcond(J) <= 1e-14
        error('ibr:solve_pcc_infbus_equilibrium:singular', ...
            'PCC power-balance Jacobian is singular (rcond<=1e-14).');
    end
    dv = -J\r;
    % Damped step to keep |V| positive and finite.
    alpha = 1.0;
    for ls = 1:20
        v_try = v + alpha*dv;
        if all(isfinite(v_try)) && (v_try(1)^2 + v_try(2)^2) > 0
            v = v_try;
            break;
        end
        alpha = alpha/2;
    end
    if ~all(isfinite(v))
        error('ibr:solve_pcc_infbus_equilibrium:nonfinite', ...
            'PCC Newton produced a non-finite voltage.');
    end
end

if ~converged
    error('ibr:solve_pcc_infbus_equilibrium:noConverge', ...
        'PCC power-balance did not converge in %d iterations (||r||inf=%.3e).', ...
        opts.max_iter, last_norm);
end

Vpcc = complex(v(1), v(2));
info = struct('converged', converged, 'iterations', it, ...
    'residual_inf', last_norm, 'S_total', Stot, ...
    'I_line', (Vpcc - V_inf)/Z_line);
end
