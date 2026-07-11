function J = ts_jac_y_fd(x, y, Y, dae_g)
%TS_JAC_Y_FD Central finite-difference Jacobian of g w.r.t. y.
%   J = ts_jac_y_fd(X, Y, Y_ADM, DAEG) returns dg/dy evaluated at (x,y,Y)
%   using central differences. The output type (real or complex) is inferred
%   from dae_g so it works for both the Padiyar (real) and EMF6 (complex)
%   algebraic residuals without a separate copy.

g0 = dae_g(x, y, Y);
n = numel(y);
J = zeros(n, n, 'like', g0);
for j = 1:n
    h = 1e-7*(1 + abs(y(j)));
    yp = y; ym = y;
    yp(j) = yp(j) + h;
    ym(j) = ym(j) - h;
    J(:,j) = (dae_g(x, yp, Y) - dae_g(x, ym, Y)) / (2*h);
end
end
