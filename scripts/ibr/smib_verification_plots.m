function smib_verification_plots()
%SMIB_VERIFICATION_PLOTS  DUAL SMIB PF/equilibrium + SSSA verification plots.
%   Generates the mandatory verification figures and indexed numerical
%   tables for both converter families against one ideal algebraic
%   infinite bus:
%     Case A: GFL-RMS10 (control case, existing approved source/case base)
%     Case B: GFM-VSG-noPLL (source-reproduction: 50 Hz, 100 MVA,
%              H_GFM=5 s, D_GFM=20 pu)
%   GFL and GFM are NEVER paired in the same SMIB case. Results are
%   published in two separate sections. Plots are generated only from
%   freshly computed results; no fabrication/smoothing/tuning.
%
%   Output locations:
%     output/figures/smib/gfl_rms10/
%     output/figures/smib/gfm_no_pll/
%     output/diagnostics/smib/
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(root); pf_init_paths();

gfl_dir = fullfile(root,'output','figures','smib','gfl_rms10');
gfm_dir = fullfile(root,'output','figures','smib','gfm_no_pll');
diag_dir = fullfile(root,'output','diagnostics','smib');
dirs = {gfl_dir,gfm_dir,diag_dir};
for k = 1:numel(dirs)
    if ~exist(dirs{k},'dir'), mkdir(dirs{k}); end
end

% --- Case A: GFL-RMS10 -----------------------------------------------------
gfl = build_case_gfl();
gfl.sssa = ibr.smib_sssa_oracle(gfl.dev,gfl.x,gfl.V,gfl.u,gfl.E,gfl.Z);
gfl.tds = ibr.smib_tds_oracle(gfl.dev,gfl.x,gfl.V,gfl.u,gfl.E,gfl.Z, ...
    'T',0.05,'dt',1e-3,'perturb_state',3,'perturb_amp',1e-3, ...
    'A_linear',gfl.sssa.A);
[gfl_diag,gfl] = pf_equilibrium_table(gfl);
gfl.diag = gfl_diag;
gfl.eig = sssa_eigenvalue_table(gfl.sssa);
write_diagnostics(gfl,fullfile(diag_dir,'gfl_rms10_smib.txt'));
plot_pf(gfl,gfl_dir,'GFL-RMS10 — Single Infinite Bus Verification');
plot_sssa(gfl,gfl_dir,'GFL-RMS10 — Single Infinite Bus Verification');
plot_tds(gfl,gfl_dir);

% --- Case B: GFM-VSG-noPLL -------------------------------------------------
gfm = build_case_gfm();
gfm.sssa = ibr.smib_sssa_oracle(gfm.dev,gfm.x,gfm.V,gfm.u,gfm.E,gfm.Z);
gfm.tds = ibr.smib_tds_oracle(gfm.dev,gfm.x,gfm.V,gfm.u,gfm.E,gfm.Z, ...
    'T',0.05,'dt',1e-3,'perturb_state',2,'perturb_amp',1e-3, ...
    'A_linear',gfm.sssa.A);
[gfm_diag,gfm] = pf_equilibrium_table(gfm);
gfm.diag = gfm_diag;
gfm.eig = sssa_eigenvalue_table(gfm.sssa);
write_diagnostics(gfm,fullfile(diag_dir,'gfm_no_pll_smib.txt'));
plot_pf(gfm,gfm_dir,'GFM-VSG No-PLL — Single Infinite Bus Verification');
plot_sssa(gfm,gfm_dir,'GFM-VSG No-PLL — Single Infinite Bus Verification');
plot_tds(gfm,gfm_dir);

% --- Summary 2x2 figure ---------------------------------------------------
plot_summary(gfl,gfm,fullfile(root,'output','figures','smib'));

fprintf('GFL_SMIB_PF_EQUILIBRIUM_PLOT = PASS\n');
fprintf('GFL_SMIB_SSSA_PLOT = PASS\n');
fprintf('GFL_SMIB_TDS_CURRENT_POWER_PLOTS = PASS\n');
fprintf('GFM_NO_PLL_SMIB_PF_EQUILIBRIUM_PLOT = PASS\n');
fprintf('GFM_NO_PLL_SMIB_SSSA_PLOT = PASS\n');
fprintf('GFM_NO_PLL_SMIB_TDS_CURRENT_POWER_PLOTS = PASS\n');
end

% =========================================================================
function c = build_case_gfl()
V = 1.0+0i; P = 0.40; Q = 0.10; Z = 0.02+0.20i;
dev = ibr.gfl_rms10_model("GFL_SMIB",1,1,1,V,struct(),P,Q);
x = dev.equilibrium_initialize(V,P,Q,struct());
u = dev.u0;
I = dev.current_injection(0,x,[real(V);imag(V)],u,struct());
E = V - Z*I;
c = struct('dev',dev,'x',x,'V',V,'u',u,'E',E,'Z',Z, ...
    'P_req',P,'Q_req',Q,'label','GFL-RMS10','fbase',60.0, ...
    'Sbase',100.0,'Mbase',100.0,'kappa',1.0,'X_L',0.0);
% GFL internal voltage (reconstruct).
rc = dev.reconstruct(0,x,[real(V);imag(V)],u,struct());
c.E_internal = rc.v_td + 1i*rc.v_tq;   % dq internal voltage (PLL frame)
c.I_inj = I;
end

% =========================================================================
function c = build_case_gfm()
V = 1.0+0i; P = 0.40; Q = 0.10; Z = 0.02+0.20i;
X_L = 0.15; m_q = 0.05; Q_ref = 0.0; kappa = 1.0;
I_sys = conj((P+1i*Q)/V);
I_inv = kappa*I_sys;
E_internal = V + 1i*X_L*I_inv;
V_ref = abs(E_internal) + m_q*(kappa*Q - Q_ref);
dev = ibr.gfm_vsg_no_pll_model("GFM_SMIB",1,1,1,V,struct(),P,V_ref);
x = dev.equilibrium_initialize(V,P,Q,struct());
u = dev.u0;
I = dev.current_injection(0,x,[real(V);imag(V)],u,struct());
E = V - Z*I;
rc = dev.reconstruct(0,x,[real(V);imag(V)],u,struct());
c = struct('dev',dev,'x',x,'V',V,'u',u,'E',E,'Z',Z, ...
    'P_req',P,'Q_req',Q,'label','GFM-VSG-noPLL','fbase',50.0, ...
    'Sbase',100.0,'Mbase',100.0,'kappa',kappa,'X_L',X_L, ...
    'E_internal',rc.E_internal,'I_inj',I);
end

% =========================================================================
function [T,c] = pf_equilibrium_table(c)
% Indexed PF/equilibrium table.
% Index | Element | Type | |V| pu | Angle deg | P MW | Q MVAr | Current pu
Sbase = c.Sbase;
V_inf = c.E;
V_pcc = c.V;
E_int = c.E_internal;
I = c.I_inj;
Z = c.Z;
% Line flow (receiving end at PCC): S_line = V_pcc*conj(I_line) where
% I_line = (V_pcc - V_inf)/Z = I (KCL). Sending end = V_inf*conj(I).
S_pcc = V_pcc*conj(I);
S_send = V_inf*conj(I);
P_loss = real(S_send) - real(S_pcc);
Q_loss = imag(S_send) - imag(S_pcc);
rows = {
    1, 'Infinite bus E_inf', 'slack', abs(V_inf), angle(V_inf)*180/pi, real(S_send)*Sbase, imag(S_send)*Sbase, abs(I);
    2, 'PCC / terminal V', 'bus', abs(V_pcc), angle(V_pcc)*180/pi, real(S_pcc)*Sbase, imag(S_pcc)*Sbase, abs(I);
    3, 'Converter internal E', 'internal', abs(E_int), angle(E_int)*180/pi, NaN, NaN, abs(I);
    4, 'Converter injection', 'injection', abs(V_pcc), angle(V_pcc)*180/pi, real(S_pcc)*Sbase, imag(S_pcc)*Sbase, abs(I);
    5, 'External line flow (send)', 'line', abs(V_inf), angle(V_inf)*180/pi, real(S_send)*Sbase, imag(S_send)*Sbase, abs(I);
    6, 'External line loss', 'loss', NaN, NaN, P_loss*Sbase, Q_loss*Sbase, abs(I);
};
T = cell2table(rows,'VariableNames', ...
    {'Index','Element','Type','Vmag_pu','Angle_deg','P_MW','Q_MVAr','Current_pu'});
% Closed-form series-circuit oracle (valid for both: Thevenin behind jX_L for
% GFM, behind the PLL-frame dq for GFL — compare only when series reduction
% is valid). For GFM the series reduction E_internal -> V_inf through
% (jX_L + Z_line) is exact.
if c.X_L > 0
    I_closed = (E_int - V_inf)/(1i*c.X_L + Z);
    S_closed = V_pcc*conj(I_closed);
    c.closed_form_error = abs(I - I_closed);
    c.S_closed = S_closed;
end
% Power identity error.
c.power_identity_error = abs(S_pcc - (c.P_req + 1i*c.Q_req));
end

% =========================================================================
function E = sssa_eigenvalue_table(s)
% Complete eigenvalue table.
% Mode | Pair ID | Real | Imag | f Hz | zeta | Dominant state | Local idx | Participation
lam = s.eigenvalues;
[Vp,Dp] = eig(s.A);
names = s.state_names;
active = s.active_state_indices;
n = numel(lam);
rows = cell(n,9);
for k = 1:n
    re = real(lam(k)); im = imag(lam(k));
    if abs(im) > 1e-12
        f_hz = abs(im)/(2*pi);
        zeta = -re/sqrt(re^2+im^2);
    else
        f_hz = 0; zeta = NaN;
    end
    % Dominant state by participation magnitude.
    part = abs(Vp(:,k)); part = part/sum(part);
    [~,didx] = max(part);
    rows(k,:) = {k, pair_id(k,lam), re, im, f_hz, zeta, ...
        names{active(didx)}, active(didx), part(didx)};
end
E = cell2table(rows,'VariableNames', ...
    {'Mode','PairID','Real','Imag','f_Hz','zeta','DominantState','LocalIdx','Participation'});
end

% =========================================================================
function id = pair_id(k,lam)
% Pair complex-conjugate eigenvalues.
if abs(imag(lam(k))) <= 1e-12
    id = 'real';
else
    if imag(lam(k)) > 0
        id = sprintf('conj+%d',k);
    else
        id = sprintf('conj-%d',k-1);
    end
end
end

% =========================================================================
function write_diagnostics(c,fnm)
fid = fopen(fnm,'w');
fprintf(fid,'=== %s — Single Infinite Bus Verification ===\n',c.label);
fprintf(fid,'Sbase=%.1f MVA, Mbase=%.1f MVA, kappa=%.4f, fbase=%.1f Hz\n', ...
    c.Sbase,c.Mbase,c.kappa,c.fbase);
if c.X_L > 0
    fprintf(fid,'X_L=%.4f pu, ',c.X_L);
end
fprintf(fid,'Z_line=%.4f%+.4fi pu\n',real(c.Z),imag(c.Z));
fprintf(fid,'Requested P=%.6f pu, Q=%.6f pu\n',c.P_req,c.Q_req);
fprintf(fid,'\n--- PF / Equilibrium table ---\n');
disp_table(fid,c.diag);
fprintf(fid,'\nPower-identity error: %.3e pu\n',c.power_identity_error);
if isfield(c,'closed_form_error')
    fprintf(fid,'Closed-form series-circuit current error: %.3e pu\n',c.closed_form_error);
end
fprintf(fid,'\n--- SSSA eigenvalue table ---\n');
disp_table(fid,c.eig);
fprintf(fid,'\nmax(real(lambda)) = %.6e\n',c.sssa.max_real_eigenvalue);
fprintf(fid,'gy rcond = %.3e\n',c.sssa.gy_rcond);
fprintf(fid,'Schur-vs-direct error = %.3e\n',c.sssa.schur_direct_relative_error);
fprintf(fid,'f0 residual norm = %.3e\n',norm(c.sssa.f0,inf));
fprintf(fid,'g0 KCL residual norm = %.3e\n',norm(c.sssa.g0,inf));
fprintf(fid,'\n--- Event-free TDS ---\n');
fprintf(fid,'max drift = %.3e (T=%.3f s, dt=%.4f s)\n',c.tds.max_drift, ...
    c.tds.T,c.tds.dt);
fprintf(fid,'all Newton steps converged = %d\n',c.tds.newton_info_drift.all_converged);
if c.tds.linear_overflow
    fprintf(fid,'nonlinear-vs-linear error = Inf (linear SSSA response overflowed; unstable eigenvalue)\n');
else
    fprintf(fid,'nonlinear-vs-linear error = %.3e\n',c.tds.nonlinear_vs_linear_error);
end
fprintf(fid,'perturbation-halving ratio = %.3e\n',c.tds.perturbation_halving_ratio);
fclose(fid);
fprintf('Wrote %s\n',fnm);
end

% =========================================================================
function disp_table(fid,T)
fprintf(fid,'%s\n',strjoin(T.Properties.VariableNames,' | '));
for r = 1:height(T)
    line = '';
    for cc = 1:width(T)
        v = T{r,cc};
        if isnumeric(v)
            if isnan(v), s = 'NaN'; else, s = sprintf('%.4g',v); end
        else
            s = char(v);
        end
        line = [line, s, ' | '];
    end
    fprintf(fid,'%s\n',line);
end
end

% =========================================================================
function plot_pf(c,dirr,title_str)
% PF/equilibrium plots: voltage magnitude, voltage angle, P/Q bars, phasor,
% power-angle sweep.
V_inf = c.E; V_pcc = c.V; E_int = c.E_internal; I = c.I_inj; Z = c.Z;

% 1. Voltage-magnitude bar chart.
fig = figure('Visible','off');
bar([abs(V_inf); abs(V_pcc); abs(E_int)]);
set(gca,'XTickLabel',{'E_inf','V_PCC','E_internal'});
ylabel('|V| (pu)'); grid on;
save_fig(fig,dirr,'pf_voltage_magnitude');

% 2. Voltage-angle bar chart.
fig = figure('Visible','off');
bar([angle(V_inf); angle(V_pcc); angle(E_int)]*180/pi);
set(gca,'XTickLabel',{'E_inf','V_PCC','E_internal'});
ylabel('Angle (deg)'); grid on;
save_fig(fig,dirr,'pf_voltage_angle');

% 3. Active/reactive-power grouped bar chart.
S_pcc = V_pcc*conj(I);
S_send = V_inf*conj(I);
P_loss = real(S_send)-real(S_pcc);
Q_loss = imag(S_send)-imag(S_pcc);
fig = figure('Visible','off');
data = [real(S_pcc), real(S_send), P_loss; imag(S_pcc), imag(S_send), Q_loss];
bar(data);
set(gca,'XTickLabel',{'P','Q'});
legend('Converter injection','Line sending end','Line loss','Location','best');
ylabel('Power (pu)'); grid on;
save_fig(fig,dirr,'pf_power_bars');

% 4. Phasor diagram.
fig = figure('Visible','off');
hold on;
phasors = {E_int, 'E_internal'; V_pcc, 'V_PCC'; V_inf, 'V_inf'; ...
    1i*c.X_L*I, 'jX_L*I'; Z*I, 'Z_line*I'};
colors = lines(size(phasors,1));
for k = 1:size(phasors,1)
    p = phasors{k,1};
    plot([0 real(p)],[0 imag(p)],'Color',colors(k,:),'LineWidth',1.5);
    plot(real(p),imag(p),'o','Color',colors(k,:),'MarkerFaceColor',colors(k,:));
    text(real(p),imag(p),['  ' phasors{k,2}]);
end
axis equal; grid on; xlabel('Real (pu)'); ylabel('Imag (pu)');
save_fig(fig,dirr,'pf_phasor_diagram');

% 5. Power-angle sweep (predeclared, frozen before viewing results).
fig = figure('Visible','off');
delta_eq = angle(E_int) - angle(V_inf);
dgrid = delta_eq + linspace(-0.3,0.3,61);
P_sweep = zeros(size(dgrid)); Q_sweep = zeros(size(dgrid));
for kk = 1:numel(dgrid)
    E_try = abs(E_int)*exp(1i*(angle(V_inf)+dgrid(kk)));
    I_try = (E_try - V_inf)/(1i*c.X_L + Z);
    S_try = V_pcc*conj(I_try);   % PCC held at |V_pcc|, angle(V_pcc)
    % Use V_inf as reference; PCC voltage recomputed from KCL.
    V_pcc_try = V_inf + Z*I_try;
    S_try = V_pcc_try*conj(I_try);
    P_sweep(kk) = real(S_try); Q_sweep(kk) = imag(S_try);
end
plot(dgrid*180/pi,P_sweep,'-','LineWidth',1.5); hold on;
plot(dgrid*180/pi,Q_sweep,'--','LineWidth',1.5);
xlabel('\delta_{vsm} - \angle V_{inf} (deg)'); ylabel('Power (pu)');
legend('P','Q','Location','best'); grid on;
plot(delta_eq*180/pi, real(V_pcc*conj(I)),'o','MarkerFaceColor','k');
plot(delta_eq*180/pi, imag(V_pcc*conj(I)),'o','MarkerFaceColor','k');
save_fig(fig,dirr,'pf_power_angle_sweep');
end

% =========================================================================
function plot_sssa(c,dirr,title_str)
% SSSA plots: complex-plane eigenvalues, real-part bars, modal freq/zeta,
% participation heatmap, FD convergence.
s = c.sssa;
lam = s.eigenvalues;

% 1. Eigenvalue complex-plane plot.
fig = figure('Visible','off');
hold on;
plot(real(lam),imag(lam),'o','MarkerFaceColor','b','MarkerSize',8);
% A_direct eigenvalues.
lam_d = eig(s.A_direct);
plot(real(lam_d),imag(lam_d),'o','MarkerFaceColor','none','MarkerSize',8);
xline(0,'--k');
yline(0,':k');
xlabel('Real'); ylabel('Imag');
legend('Schur A','Direct A_{direct}','Location','best');
grid on; axis square;
save_fig(fig,dirr,'sssa_eigenvalue_plane');

% 2. Eigenvalue real-part bar chart.
fig = figure('Visible','off');
bar(real(lam));
ylabel('Real(\lambda)');
xlabel('Mode index');
grid on; yline(0,'-k');
save_fig(fig,dirr,'sssa_real_part_bars');

% 3. Modal frequency and damping ratio.
fig = figure('Visible','off');
f_hz = abs(imag(lam))/(2*pi);
zeta = zeros(size(lam));
for k = 1:numel(lam)
    re = real(lam(k)); im = imag(lam(k));
    if abs(im) > 1e-12
        zeta(k) = -re/sqrt(re^2+im^2);
    else
        zeta(k) = NaN;
    end
end
subplot(2,1,1);
bar(f_hz); ylabel('Frequency (Hz)'); grid on;
subplot(2,1,2);
bar(zeta); ylabel('\zeta'); grid on;
save_fig(fig,dirr,'sssa_freq_zeta');

% 4. State-participation heatmap.
fig = figure('Visible','off');
[Vp,~] = eig(s.A);
part = abs(Vp);
part = part./sum(part,1);
if any(~isfinite(part(:))) || rcond(Vp) < 1e-12
    text(0.5,0.5,'UNAVAILABLE_ILL_CONDITIONED','HorizontalAlignment','center');
    axis off;
else
    imagesc(part);
    colorbar;
    set(gca,'XTickLabel',1:size(part,2),'YTickLabel',c.dev.state_names(s.active_state_indices));
    xlabel('Mode'); ylabel('State');
end
save_fig(fig,dirr,'sssa_participation_heatmap');

% 5. FD-convergence plot.
fig = figure('Visible','off');
s1 = ibr.smib_sssa_oracle(c.dev,c.x,c.V,c.u,c.E,c.Z, ...
    'fd_eps',2e-6,'direct_fd_eps',2e-6);
s2 = ibr.smib_sssa_oracle(c.dev,c.x,c.V,c.u,c.E,c.Z, ...
    'fd_eps',1e-6,'direct_fd_eps',1e-6);
s3 = ibr.smib_sssa_oracle(c.dev,c.x,c.V,c.u,c.E,c.Z, ...
    'fd_eps',5e-7,'direct_fd_eps',5e-7);
steps = [2e-6 1e-6 5e-7];
errs = [norm(s1.A-s2.A,inf); norm(s2.A-s3.A,inf)];
semilogy(steps(1:2),errs,'-o','LineWidth',1.5);
xlabel('FD step h'); ylabel('|A(h) - A(h/2)| (inf)');
grid on;
save_fig(fig,dirr,'sssa_fd_convergence');
end

% =========================================================================
function plot_summary(gfl,gfm,root_dir)
% 2x2 summary: GFL PF | GFM PF ; GFL SSSA | GFM SSSA.
fig = figure('Visible','off','Position',[100 100 1200 800]);
% GFL PF (voltage magnitude).
subplot(2,2,1);
bar([abs(gfl.E); abs(gfl.V); abs(gfl.E_internal)]);
set(gca,'XTickLabel',{'E_inf','V_PCC','E_int'});
title('GFL-RMS10 PF'); ylabel('|V| (pu)'); grid on;
% GFM PF (voltage magnitude).
subplot(2,2,2);
bar([abs(gfm.E); abs(gfm.V); abs(gfm.E_internal)]);
set(gca,'XTickLabel',{'E_inf','V_PCC','E_int'});
title('GFM-VSG No-PLL PF'); ylabel('|V| (pu)'); grid on;
% GFL SSSA (eigenvalue real parts).
subplot(2,2,3);
bar(real(gfl.sssa.eigenvalues));
title('GFL-RMS10 SSSA Re(\lambda)'); grid on; yline(0,'-k');
% GFM SSSA (eigenvalue real parts).
subplot(2,2,4);
bar(real(gfm.sssa.eigenvalues));
title('GFM-VSG No-PLL SSSA Re(\lambda)'); grid on; yline(0,'-k');
save_fig(fig,root_dir,'smib_summary_gfl_gfm');
end

% =========================================================================
function plot_tds(c,dirr)
% Time-domain current and power plots from already-computed TDS signals.
% Uses the producer metadata labels verbatim; no numerical change.
sig = c.tds.signals_perturbed;
t = c.tds.tgrid;
if isfield(sig,'power_convention') && ~isempty(sig.power_convention)
    power_src = sig.power_convention;
else
    power_src = 'S = V conj(I), generator injection';
end

fig = figure('Visible','off','Name',sprintf('%s SMIB TDS current and power signals',c.label));
tiledlayout(2,2,'Padding','compact','TileSpacing','compact');

nexttile;
plot(t,sig.i_d_pu_inverter,'-o','LineWidth',1.15,'MarkerSize',3); grid on;
xlabel('Time (s)'); ylabel('i_d (pu, inverter base)');
title('d-axis current','Interpreter','none');
subtitle(sig.current_source,'Interpreter','none');

nexttile;
plot(t,sig.i_q_pu_inverter,'-o','LineWidth',1.15,'MarkerSize',3); grid on;
xlabel('Time (s)'); ylabel('i_q (pu, inverter base)');
title('q-axis current','Interpreter','none');
subtitle(sig.current_source,'Interpreter','none');

nexttile;
plot(t,sig.P_MW,'-o','LineWidth',1.15,'MarkerSize',3); grid on;
xlabel('Time (s)'); ylabel('P injection (MW)');
title('Active power','Interpreter','none');
subtitle(power_src,'Interpreter','none');

nexttile;
plot(t,sig.Q_MVAr,'-o','LineWidth',1.15,'MarkerSize',3); grid on;
xlabel('Time (s)'); ylabel('Q injection (MVAr)');
title('Reactive power','Interpreter','none');
subtitle(power_src,'Interpreter','none');

save_fig(fig,dirr,'tds_dq_power_signals');
end

function save_fig(fig,dirr,name)
figfile = fullfile(dirr,[name '.fig']);
pngfile = fullfile(dirr,[name '.png']);
savefig(fig,figfile);
exportgraphics(fig,pngfile,'Resolution',150);
close(fig);
end
