function [y, info, Jyy] = ts_algebraic_solve_u(x, y, Y, dae_g_u, jac_y_u_fn, tol, Jyy, u)
%TS_ALGEBRAIC_SOLVE_U  Provider-aware damped-Newton algebraic solver (R1).
%   [Y, INFO] = ts_algebraic_solve_u(X, Y0, Y_ADM, DAE_G_U, JAC_Y_U_FN, TOL, JYY, U)
%   solves g(x,y,Y,u)=0 by damped Newton, where DAE_G_U = @(x,y,Y,u) g and
%   JAC_Y_U_FN = @(x,y,Y,u) dg/dy. This is a THIN WRAPPER that binds u into
%   closures and delegates to stability.ts_algebraic_solve, so the damped-
%   Newton / backtracking line-search logic is NOT duplicated (one owner).
%
%   R1: this function is reached ONLY on the provider-aware path (when
%   strategy.provider is present). The legacy ts_algebraic_solve path is
%   unchanged and is used when no provider is present.

g_u  = @(x_,y_,Y_) dae_g_u(x_, y_, Y_, u);
jac_u = @(x_,y_,Y_,~) jac_y_u_fn(x_, y_, Y_, u);
if nargin < 7 || isempty(Jyy)
    Jyy = jac_y_u_fn(x, y, Y, u);
end
[y, info, Jyy] = stability.ts_algebraic_solve(x, y, Y, g_u, jac_u, tol, Jyy);
end
