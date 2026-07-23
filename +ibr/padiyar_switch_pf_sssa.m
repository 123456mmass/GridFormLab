function res = padiyar_switch_pf_sssa(sys)
%PADIYAR_SWITCH_PF_SSSA  Power-flow summary + small-signal (SSSA) modes of the
%   composite Padiyar 1-SG + 3-GFL switch system at the SG-online equilibrium.
%
%   res = ibr.padiyar_switch_pf_sssa(SYS) returns a struct with:
%     .pf   table [bus Pgen Qgen |V| angle_deg] from the audited power flow
%     .A    reduced state matrix (algebraic network eliminated)
%     .eig  eigenvalues of A (small-signal modes)
%     .modes table of oscillatory modes [sigma  freq_Hz  zeta]
%     .min_zeta / .min_zeta_freq  least-damped oscillatory mode
%     .n_unstable  number of eigenvalues with Re > 1e-6
%
%   Classification: ASSUMED_DIAGNOSTIC. The linearisation is a finite-difference
%   Jacobian of the SAME differential/algebraic right-hand side f(x,y)/g(x,y)
%   that ibr.padiyar_switch_tds integrates (single source of truth); the reduced
%   state matrix is A = f_x - f_y*(g_y\g_x). It characterises the SG-online
%   (also the post-reclose) operating point; it does not model the discrete
%   dwell/AGSI switching logic. Not a production stability claim.

nsg = sys.sg.nx; nib = numel(sys.devs); nxi = 6;
nx  = nsg + nib*nxi; ny = numel(sys.y0);

% --- power-flow summary ----------------------------------------------------
pf = sys.pf; bid = sys.bus_ids(:).'; y0 = sys.y0;
rows = [];
for b = bid
    p = find(bid==b,1);
    Vp = complex(y0(2*p-1), y0(2*p));
    rows = [rows; b, pf.P_generation(p), pf.Q_generation(p), abs(Vp), angle(Vp)*180/pi]; %#ok<AGROW>
end
res.pf = rows;   % [bus Pgen Qgen |V| ang_deg]

% --- composite equilibrium state ------------------------------------------
z0 = [sys.x_sg0(:); vertcat(sys.x_ibr0{:}); y0(:)];

% --- central-difference Jacobian of [f_diff ; g_alg] w.r.t. [x ; y] -------
nR = numel(local_rhs(z0, sys, nsg, nib, nxi, ny));
J  = zeros(nR, numel(z0)); h = 1e-6;
for i = 1:numel(z0)
    zp = z0; zp(i) = zp(i) + h;
    zm = z0; zm(i) = zm(i) - h;
    J(:,i) = (local_rhs(zp, sys, nsg, nib, nxi, ny) - local_rhs(zm, sys, nsg, nib, nxi, ny))/(2*h);
end
ix = 1:nx; iy = nx + (1:ny);
fx = J(ix,ix); fy = J(ix,iy); gx = J(iy,ix); gy = J(iy,iy);
A  = fx - fy*(gy\gx);                 % network-reduced state matrix
ev = eig(A);
res.A = A; res.eig = ev;

% --- mode table (oscillatory pairs) ---------------------------------------
tol = 1e-6;
res.n_unstable = sum(real(ev) > tol);
osc = ev(imag(ev) > tol);             % one of each complex-conjugate pair
sig = real(osc); frq = imag(osc)/(2*pi);
zet = -sig ./ abs(osc);
[frq, o] = sort(frq); sig = sig(o); zet = zet(o);
res.modes = [sig, frq, zet];          % [sigma freq_Hz zeta]
if isempty(zet)
    res.min_zeta = NaN; res.min_zeta_freq = NaN;
else
    [res.min_zeta, im] = min(zet); res.min_zeta_freq = frq(im);
end
res.classification = 'ASSUMED_DIAGNOSTIC_PADIYAR_SWITCH_SSSA';
end

% =========================================================================
function R = local_rhs(z, sys, nsg, nib, nxi, ny)
% Composite [differential f ; algebraic KCL g] at the SG-online configuration.
xs = z(1:nsg);
off = nsg; xib = cell(1,nib);
for j = 1:nib, xib{j} = z(off+(1:nxi)); off = off + nxi; end
yv = z(off+(1:ny));
V  = complex(yv(1:2:end), yv(2:2:end));
gc = -sys.Y*V;
gc(sys.sg_bus_position) = gc(sys.sg_bus_position) + sys.sg.current_injection(xs, yv);
fdiff = sys.sg.f(xs, yv);
for j = 1:nib
    bp = sys.ibr_bus_positions(j);
    gc(bp) = gc(bp) + sys.devs{j}.current_injection(xib{j}, yv);
    fdiff = [fdiff; sys.devs{j}.f(xib{j}, yv)]; %#ok<AGROW>
end
g = zeros(ny,1); g(1:2:end) = real(gc); g(2:2:end) = imag(gc);
R = [fdiff; g];
end
