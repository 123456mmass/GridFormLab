function generate_ibr_gfl_gfm_report_figures()
%GENERATE_IBR_GFL_GFM_REPORT_FIGURES  Build tables/figures for the GFL/GFM
%   IBR SSSA + id/iq/P/Q Thai report (report_ibr_gfl_gfm_th.tex).
%   Fresh in-house run; no saved artifacts read. Two reduced 6-state SMIB
%   devices (EECON49-P4): GFL 6-state and GFM 6-state (2 states per block).
pf_init_paths;
outdir = fullfile('docs','source','figures','ibr_gfl_gfm_th');
if ~exist(outdir,'dir'), mkdir(outdir); end

% Match the LaTeX report font (TH Sarabun) in all generated figures so figure
% text and the document body share one typeface.
prevAx = get(groot,'defaultAxesFontName');
prevTx = get(groot,'defaultTextFontName');
prevLg = get(groot,'defaultLegendFontName');
prevSz = get(groot,'defaultAxesFontSize');
set(groot,'defaultAxesFontName','TH SarabunPSK');
set(groot,'defaultTextFontName','TH SarabunPSK');
set(groot,'defaultLegendFontName','TH SarabunPSK');
set(groot,'defaultAxesFontSize',12);
cleanup = onCleanup(@() restore_fonts(prevAx,prevTx,prevLg,prevSz));

M = build_all();   % struct array of the three models with eig + eq + tds

write_eig_tables(M,outdir);
write_A_tables(M,outdir);
write_idqpq_table(M,outdir);
plot_eigenplane(M,outdir);
plot_eig_loadsweep(outdir);
plot_modal_frequency(M,outdir);
plot_ode45_loads(outdir);
plot_pert_loads(outdir);
plot_freq_loads(outdir);
plot_combined_step(outdir);
fprintf('REPORT_FIGURES_DONE dir=%s\n',outdir);
end

function restore_fonts(ax,tx,lg,sz)
set(groot,'defaultAxesFontName',ax);
set(groot,'defaultTextFontName',tx);
set(groot,'defaultLegendFontName',lg);
set(groot,'defaultAxesFontSize',sz);
end

% =========================================================================
function M = build_all()
V = 1.0+0i; P = 0.40; Q = 0.10; Z = 0.02+0.20i;

% --- GFL 6-state (reduced, EECON49): IBR + GFL(PLL) + PQ ---
d1 = ibr.gfl_reduced6_model('GFL_REDUCED6',1,1,1,V,struct(),P,Q);
M(1) = pack_model('GFL 6-state', d1, V,P,Q,Z, 3);   % perturb delta_PLL (PLL mode)

% --- GFM 6-state (reduced VSG, EECON49): IBR + VSG + GFM ---
d2 = ibr.gfm_reduced6_model('GFM_REDUCED6',1,1,1,V,struct(),P,Q);
M(2) = pack_model('GFM 6-state', d2, V,P,Q,Z, 3);   % perturb omega (swing mode)
end

% =========================================================================
function s = pack_model(label, dev, V,P,Q,Z, pstate)
x = dev.equilibrium_initialize(V,P,Q,struct());
u = dev.u0; ec = struct(); y = [real(V);imag(V)];
I0 = dev.current_injection(0,x,y,u,ec);
Vinf = V - Z*I0;
oc = ibr.smib_sssa_oracle(dev,x,V,u,Vinf,Z);
% equilibrium id/iq/P/Q (via signal history at the equilibrium point)
sig0 = ibr.smib_tds_signal_history(dev,x,y,u,ec);
% TDS ring-down for id/iq/P/Q time series (T=2 s to expose the GFM swing)
tds = ibr.smib_tds_oracle(dev,x,V,u,Vinf,Z,'T',2.0,'dt',1e-3, ...
    'perturb_state',pstate,'perturb_amp',1e-2,'A_linear',oc.A);
sigp = tds.signals_perturbed;
s = struct();
s.label = label;
s.device_type = dev.device_type;
s.nx = dev.nx;
s.state_names = dev.state_names;
s.eig = oc.eigenvalues(:);
s.A = oc.A;
s.active = oc.active_state_indices(:).';
s.max_real = oc.max_real_eigenvalue;
s.id0 = sig0.i_d_pu_inverter(1);
s.iq0 = sig0.i_q_pu_inverter(1);
s.P0  = sig0.P_pu_system(1);
s.Q0  = sig0.Q_pu_system(1);
s.current_source = sig0.current_source;
s.t = tds.tgrid(:);
s.id = sigp.i_d_pu_inverter(:);
s.iq = sigp.i_q_pu_inverter(:);
s.P  = sigp.P_MW(:);
s.Q  = sigp.Q_MVAr(:);
end

% =========================================================================
function plot_ode45_loads(outdir)
% Fault time-domain response of i_d,i_q,P,Q at load levels 20/40/60/80/100%.
% At each load the equilibrium is re-solved and a shunt fault (Z_f) is applied
% over [fault_on,fault_clear] using the project implicit-trapezoidal TDS
% (ibr.smib_tds_oracle). The response is FLAT until the fault (initialised at
% the PF equilibrium: static = dynamic, no spurious oscillation), then rings
% down after clearing -- consistent with the launcher. As load rises the
% operating levels shift and the GFM swing ring-down changes.
V=1.0+0i; Q=0.10; Z=0.02+0.20i;
loads=[20 40 60]; Pset=loads/100; cols=lines(numel(loads));
fon=0.2; fclr=0.3; Zf=0.5i; T=2.0; dt=1e-3;
specs = {'GFL 6-state', 1, 'ode45_loads_gfl.png'; ...
         'GFM 6-state', 2, 'ode45_loads_gfm.png'};
lab = {'i_d (pu)','i_q (pu)','P (pu)','Q (pu)'}; fld = {'id','iq','P','Q'};
for mdl = 1:size(specs,1)
    D = struct();
    for li = 1:numel(Pset)
        P = Pset(li);
        if specs{mdl,2}==1
            d = ibr.gfl_reduced6_model('GFL6',1,1,1,V,struct(),P,Q);
        else
            d = ibr.gfm_reduced6_model('GFM6',1,1,1,V,struct(),P,Q);
        end
        x0 = d.equilibrium_initialize(V,P,Q,struct()); u0 = d.u0;
        y = [real(V);imag(V)];
        Vinf = V - Z*d.current_injection(0,x0,y,u0,struct());
        oc = ibr.smib_sssa_oracle(d,x0,V,u0,Vinf,Z);
        td = ibr.smib_tds_oracle(d,x0,V,u0,Vinf,Z,'T',T,'dt',dt,'A_linear',oc.A, ...
            'fault_on',fon,'fault_clear',fclr,'fault_Zf',Zf);
        sg = td.signals_fault;
        D(li).t = td.tgrid;
        D(li).id = sg.i_d_pu_inverter; D(li).iq = sg.i_q_pu_inverter;
        D(li).P = sg.P_MW/100; D(li).Q = sg.Q_MVAr/100;   % MW/MVAr -> pu (100 MVA base)
    end
    f = figure('Visible','off','Position',[100 100 1150 720]);
    tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
    for a = 1:4
        nexttile; hold on; grid on;
        for li = 1:numel(Pset)
            plot(D(li).t,D(li).(fld{a}),'Color',cols(li,:),'LineWidth',1.3, ...
                'DisplayName',sprintf('%d%% (P=%.1f)',loads(li),Pset(li)));
        end
        xline(fon,'r--','HandleVisibility','off'); xline(fclr,'k--','HandleVisibility','off');
        xlabel('t (s)'); ylabel(lab{a}); if a==1, legend('Location','best'); end
        title(sprintf('%s: %s',specs{mdl,1},lab{a}));
    end
    exportgraphics(f,fullfile(outdir,specs{mdl,3}),'Resolution',150);
    close(f);
end
end

% =========================================================================
function plot_combined_step(outdir)
% Single combined figure: frequency (dual y-axis) + i_d,i_q,P,Q, GFL vs GFM,
% after a grid step (phase +45 deg, V -10%) over a 15 s simulation. GFM = blue
% solid, GFL = orange dashed throughout.
V=1.0+0i; P=0.40; Q=0.10; Z=0.02+0.20i;
son=1.0; dV=-0.10; dph=45; T=15; dt=1e-3;
cGFM=[0 0.447 0.741]; cGFL=[0.85 0.325 0.098];
dM=ibr.gfm_reduced6_model('GFM',1,1,1,V,struct(),P,Q); xM=dM.equilibrium_initialize(V,P,Q,struct()); uM=dM.u0;
VM=V-Z*dM.current_injection(0,xM,[real(V);imag(V)],uM,struct()); sMo=ibr.smib_sssa_oracle(dM,xM,V,uM,VM,Z);
tM=ibr.smib_tds_oracle(dM,xM,V,uM,VM,Z,'T',T,'dt',dt,'A_linear',sMo.A,'step_on',son,'step_dV',dV,'step_dphase_deg',dph);
dL=ibr.gfl_reduced6_model('GFL',1,1,1,V,struct(),P,Q); xL=dL.equilibrium_initialize(V,P,Q,struct()); uL=dL.u0;
VL=V-Z*dL.current_injection(0,xL,[real(V);imag(V)],uL,struct()); sLo=ibr.smib_sssa_oracle(dL,xL,V,uL,VL,Z);
tL=ibr.smib_tds_oracle(dL,xL,V,uL,VL,Z,'T',T,'dt',dt,'A_linear',sLo.A,'step_on',son,'step_dV',dV,'step_dphase_deg',dph);
sM=tM.signals_step; sL=tL.signals_step; t=tM.tgrid;
f=figure('Visible','off','Position',[100 100 1200 950]);
tl=tiledlayout(3,2,'Padding','compact','TileSpacing','compact');
nexttile([1 2]); ax=gca;
yyaxis left;  plot(t,sM.f_hz,'-','Color',cGFM,'LineWidth',1.5); ylabel('GFM  f (Hz)'); ylim([54 68]); ax.YAxis(1).Color=cGFM;
yyaxis right; plot(t,sL.f_hz,'--','Color',cGFL,'LineWidth',1.5); ylabel('GFL  f (Hz)'); ylim([59.8 60.25]); ax.YAxis(2).Color=cGFL;
xline(son,'k:','step','HandleVisibility','off'); grid on; xlabel('t (s)');
legend({'GFM (VSG rotor)','GFL (PLL)'},'Location','northeast');
title('Frequency (dual axis): GFM swings (inertia), GFL PLL just re-locks');
sig={'i_d_pu_inverter','i_q_pu_inverter','P_MW','Q_MVAr'};
sc=[1 1 1/100 1/100]; lab={'i_d (pu)','i_q (pu)','P (pu)','Q (pu)'};
for a=1:4
    nexttile; hold on; grid on;
    plot(t,sM.(sig{a})*sc(a),'-','Color',cGFM,'LineWidth',1.3,'DisplayName','GFM');
    plot(t,sL.(sig{a})*sc(a),'--','Color',cGFL,'LineWidth',1.3,'DisplayName','GFL');
    xline(son,'k:','HandleVisibility','off');
    xlabel('t (s)'); ylabel(lab{a}); if a==1, legend('Location','best'); end
    title(lab{a});
end
title(tl,'GFL vs GFM: grid step (\Delta\theta=+45\circ, \DeltaV=-10%) at 1 s, 15 s simulation');
exportgraphics(f,fullfile(outdir,'combined_step.png'),'Resolution',150); close(f);
end

% =========================================================================
function plot_freq_compare(outdir)
% Combined GFL-vs-GFM frequency after a grid step (dual y-axis so both are
% visible at their own scale): GFM (VSG rotor) swings large and fast (inertia
% response); GFL (PLL) deviates little and slowly (it just re-locks/tracks).
V=1.0+0i; P=0.40; Q=0.10; Z=0.02+0.20i;
son=1.0; dV=-0.10; dph=45; T=10; dt=1e-3;
% GFM
dM=ibr.gfm_reduced6_model('GFM6',1,1,1,V,struct(),P,Q); xM=dM.equilibrium_initialize(V,P,Q,struct()); uM=dM.u0;
VinfM=V-Z*dM.current_injection(0,xM,[real(V);imag(V)],uM,struct()); sM=ibr.smib_sssa_oracle(dM,xM,V,uM,VinfM,Z);
tM=ibr.smib_tds_oracle(dM,xM,V,uM,VinfM,Z,'T',T,'dt',dt,'A_linear',sM.A,'step_on',son,'step_dV',dV,'step_dphase_deg',dph);
% GFL
dL=ibr.gfl_reduced6_model('GFL6',1,1,1,V,struct(),P,Q); xL=dL.equilibrium_initialize(V,P,Q,struct()); uL=dL.u0;
VinfL=V-Z*dL.current_injection(0,xL,[real(V);imag(V)],uL,struct()); sL=ibr.smib_sssa_oracle(dL,xL,V,uL,VinfL,Z);
tL=ibr.smib_tds_oracle(dL,xL,V,uL,VinfL,Z,'T',T,'dt',dt,'A_linear',sL.A,'step_on',son,'step_dV',dV,'step_dphase_deg',dph);
f=figure('Visible','off','Position',[100 100 1100 480]);
yyaxis left; plot(tM.tgrid,tM.signals_step.f_hz,'-','LineWidth',1.6); ylabel('GFM  f (Hz)'); ylim([54 68]);
yyaxis right; plot(tL.tgrid,tL.signals_step.f_hz,'--','LineWidth',1.6); ylabel('GFL (PLL)  f (Hz)'); ylim([59.8 60.25]);
xline(son,'k:','step','HandleVisibility','off','LabelVerticalAlignment','bottom');
xlabel('Time (s)'); grid on; legend({'GFM (VSG rotor)','GFL (PLL)'},'Location','northeast');
title(sprintf('Frequency after grid step (\\DeltaV=%+.0f%%, \\Delta\\theta=%+.0f deg): GFM swings, GFL PLL tracks',100*dV,dph));
exportgraphics(f,fullfile(outdir,'freq_compare.png'),'Resolution',150); close(f);
end

% =========================================================================
function plot_freq_loads(outdir)
% Frequency f (Hz) vs time during the fault response: GFL = PLL-estimated
% frequency f = fbase + (kp_PLL*v_q + ki_PLL*xi_PLL)/2pi; GFM = VSG virtual
% rotor frequency f = fbase*omega. Shown at loads 20/40/60% (flat 60 Hz before
% the fault; deviates during/after the fault then recovers).
V=1.0+0i; Q=0.10; Z=0.02+0.20i;
loads=[20 40 60]; Pset=loads/100; cols=lines(numel(loads));
fon=0.2; fclr=0.3; Zf=0.5i; T=2.0; dt=1e-3;
f = figure('Visible','off','Position',[100 100 1100 440]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');
% --- GFL: PLL frequency ---
nexttile; hold on; grid on;
for li = 1:numel(Pset)
    P = Pset(li);
    d = ibr.gfl_reduced6_model('GFL6',1,1,1,V,struct(),P,Q);
    x0 = d.equilibrium_initialize(V,P,Q,struct()); u0 = d.u0; y=[real(V);imag(V)];
    Vinf = V - Z*d.current_injection(0,x0,y,u0,struct());
    oc = ibr.smib_sssa_oracle(d,x0,V,u0,Vinf,Z);
    td = ibr.smib_tds_oracle(d,x0,V,u0,Vinf,Z,'T',T,'dt',dt,'A_linear',oc.A, ...
        'fault_on',fon,'fault_clear',fclr,'fault_Zf',Zf);
    pr = d.provenance.params; xf = td.x_fault; yf = td.y_fault;
    Vc = complex(yf(1,:),yf(2,:)).*exp(-1i*xf(3,:));   % v in PLL frame
    vq = imag(Vc);
    fHz = pr.fbase + (pr.kp_PLL*vq + pr.ki_PLL*xf(4,:))/(2*pi);
    plot(td.tgrid,fHz,'Color',cols(li,:),'LineWidth',1.3,'DisplayName',sprintf('%d%%',loads(li)));
end
xline(fon,'r--','HandleVisibility','off'); xline(fclr,'k--','HandleVisibility','off');
xlabel('t (s)'); ylabel('f (Hz)'); legend('Location','best');
title('GFL: PLL-estimated frequency');
% --- GFM: VSG rotor frequency ---
nexttile; hold on; grid on;
for li = 1:numel(Pset)
    P = Pset(li);
    d = ibr.gfm_reduced6_model('GFM6',1,1,1,V,struct(),P,Q);
    x0 = d.equilibrium_initialize(V,P,Q,struct()); u0 = d.u0; y=[real(V);imag(V)];
    Vinf = V - Z*d.current_injection(0,x0,y,u0,struct());
    oc = ibr.smib_sssa_oracle(d,x0,V,u0,Vinf,Z);
    td = ibr.smib_tds_oracle(d,x0,V,u0,Vinf,Z,'T',T,'dt',dt,'A_linear',oc.A, ...
        'fault_on',fon,'fault_clear',fclr,'fault_Zf',Zf);
    pr = d.provenance.params; xf = td.x_fault;
    fHz = pr.fbase*xf(3,:);      % omega (pu) * fbase
    plot(td.tgrid,fHz,'Color',cols(li,:),'LineWidth',1.3,'DisplayName',sprintf('%d%%',loads(li)));
end
xline(fon,'r--','HandleVisibility','off'); xline(fclr,'k--','HandleVisibility','off');
xlabel('t (s)'); ylabel('f (Hz)'); legend('Location','best');
title('GFM: VSG rotor frequency');
exportgraphics(f,fullfile(outdir,'freq_loads.png'),'Resolution',150);
close(f);
end

% =========================================================================
function plot_pert_loads(outdir)
% Free small-signal response (NO fault): initialise with a small INITIAL
% perturbation of the dominant state at t=0 and integrate d(Dx)/dt = A*Dx with
% ode45. This oscillates from t=0 (there is no flat baseline) because the
% disturbance is injected as an initial condition -- it is a mode-excitation /
% ring-down view, contrasted in the report with the fault response (which is
% flat until the fault). Shown at loads 20/40/60/80/100%.
V=1.0+0i; Q=0.10; Z=0.02+0.20i;
loads=[20 40 60 80 100]; Pset=loads/100; cols=lines(numel(loads));
specs = {'GFL 6-state', 1, 3, 'pert_loads_gfl.png'; ...
         'GFM 6-state', 2, 4, 'pert_loads_gfm.png'};
lab = {'i_d (pu)','i_q (pu)','P (pu)','Q (pu)'}; fld = {'id','iq','P','Q'};
for mdl = 1:size(specs,1)
    pst = specs{mdl,3};
    D = struct();
    for li = 1:numel(Pset)
        P = Pset(li);
        if specs{mdl,2}==1
            d = ibr.gfl_reduced6_model('GFL6',1,1,1,V,struct(),P,Q);
        else
            d = ibr.gfm_reduced6_model('GFM6',1,1,1,V,struct(),P,Q);
        end
        x0 = d.equilibrium_initialize(V,P,Q,struct()); u0 = d.u0;
        y = [real(V);imag(V)]; ec = struct();
        Vinf = V - Z*d.current_injection(0,x0,y,u0,ec);
        oc = ibr.smib_sssa_oracle(d,x0,V,u0,Vinf,Z); A = oc.A;
        Dx0 = zeros(d.nx,1); Dx0(pst) = 0.05;
        [t,Dx] = ode45(@(tt,z) A*z, [0 2], Dx0);
        Pt = zeros(size(t)); Qt = Pt;
        for m = 1:numel(t)
            I = d.current_injection(0,x0+Dx(m,:).',y,u0,ec); Sc = V*conj(I);
            Pt(m) = real(Sc); Qt(m) = imag(Sc);
        end
        D(li).t=t; D(li).id=x0(1)+Dx(:,1); D(li).iq=x0(2)+Dx(:,2); D(li).P=Pt; D(li).Q=Qt;
    end
    f = figure('Visible','off','Position',[100 100 1150 720]);
    tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
    for a = 1:4
        nexttile; hold on; grid on;
        for li = 1:numel(Pset)
            plot(D(li).t,D(li).(fld{a}),'Color',cols(li,:),'LineWidth',1.3, ...
                'DisplayName',sprintf('%d%% (P=%.1f)',loads(li),Pset(li)));
        end
        xlabel('t (s)'); ylabel(lab{a}); if a==1, legend('Location','best'); end
        title(sprintf('%s: %s',specs{mdl,1},lab{a}));
    end
    exportgraphics(f,fullfile(outdir,specs{mdl,4}),'Resolution',150);
    close(f);
end
end

% =========================================================================
function write_A_tables(M,outdir)
% Write the state matrix A (6x6) of each model as a LaTeX table, with the
% state symbols as row/column headers (Delta_dot x = A Delta x, since B=0).
for k = 1:numel(M)
    s = M(k); A = s.A; n = size(A,1);
    hdr = cell(1,n);
    for j = 1:n, hdr{j} = tex_state_math(s.state_names{s.active(j)}); end
    fid = fopen(fullfile(outdir,sprintf('table_A_%d.tex',k)),'w');
    fprintf(fid,'\\begin{tabular}{c%s}\\toprule\n',repmat('r',1,n));
    fprintf(fid,'$A$');
    for j = 1:n, fprintf(fid,' & %s',hdr{j}); end
    fprintf(fid,'\\\\\\midrule\n');
    for i = 1:n
        fprintf(fid,'%s',hdr{i});
        for j = 1:n, fprintf(fid,' & %s',afmt(A(i,j))); end
        fprintf(fid,'\\\\\n');
    end
    fprintf(fid,'\\bottomrule\n\\end{tabular}\n');
    fclose(fid);
end
end

function s = afmt(x)
% Compact numeric cell for the A-matrix table (normal text font).
if ~isfinite(x), s = '--'; return; end
if abs(x) < 1e-9, s = '0'; return; end
s = sprintf('%+.4g', x);
end

% =========================================================================
function write_eig_tables(M,outdir)
for k = 1:numel(M)
    s = M(k);
    A = s.A;
    [Vr,Dg] = eig(A);
    lam = diag(Dg);
    Wl = inv(Vr);            % rows = left eigenvectors
    [~,ord] = sort(real(lam),'descend');
    fid = fopen(fullfile(outdir,sprintf('table_eig_%d.tex',k)),'w');
    fprintf(fid,'\\begin{tabular}{cl p{5.2cm} rrrr}\\toprule\n');
    fprintf(fid,'No & Dominant state & Role (what the state does) & Real (1/s) & Imag (1/s) & $f$ (Hz) & $\\zeta$\\\\\\midrule\n');
    for ii = 1:numel(ord)
        i = ord(ii); li = lam(i);
        fr = abs(imag(li))/(2*pi);
        if abs(li) > 0, ze = -real(li)/abs(li); else, ze = NaN; end
        p = abs(Vr(:,i)).*abs(Wl(i,:).'); [~,jm] = max(p);
        nm = s.state_names{ s.active(jm) };
        fprintf(fid,'%02d & %s & %s & %s & %s & %.4f & %.4f\\\\\n', ...
            ii, tex_state_math(nm), role_of(nm), sci(real(li)), sci(imag(li)), fr, ze);
    end
    fprintf(fid,'\\bottomrule\n\\end{tabular}\n');
    fclose(fid);
end
end

function s = sci(x)
% Format a real number as N x 10^n in the NORMAL TEXT font (not math mode),
% so table numbers match the document body font and size:
%   -3.148 \texttimes 10\textsuperscript{0}
if ~isfinite(x), s = '--'; return; end
if abs(x) < 1e-12, s = '0'; return; end
e = floor(log10(abs(x)));
m = x/10^e;
s = sprintf('%+.3f\\,\\texttimes\\,10\\textsuperscript{%d}', m, e);
end

function t = tex_state_math(nm)
% Render a state name as a proper LaTeX math symbol (subscripts, Greek).
switch nm
    case 'delta_PLL',       t = '$\delta_{PLL}$';
    case 'xi_PLL',          t = '$\xi_{PLL}$';
    case 'P_f',             t = '$P_f$';
    case 'Q_f',             t = '$Q_f$';
    case 'xi_P',            t = '$\xi_{P}$';
    case 'xi_Q',            t = '$\xi_{Q}$';
    case 'xi_id',           t = '$\xi_{id}$';
    case 'xi_iq',           t = '$\xi_{iq}$';
    case 'i_d',             t = '$i_d$';
    case 'i_q',             t = '$i_q$';
    case 'omega_R',         t = '$\omega_R$';
    case 'omega',           t = '$\omega$';
    case 'E',               t = '$E$';
    case 'xi_V',            t = '$\xi_{V}$';
    case 'delta',           t = '$\delta$';
    case 'x_gov',           t = '$x_{gov}$';
    case 'T_m',             t = '$T_m$';
    case 'x_d',             t = '$x_d$';
    case 'delta_vsm',       t = '$\delta_{vsm}$';
    case 'delta_omega_vsm', t = '$\delta\omega_{vsm}$';
    otherwise,              t = ['$' strrep(nm,'_','\_') '$'];
end
end

function r = role_of(nm)
% Short English description of each state's physical role (used in the
% eigenvalue-table "Role" column so a dominant state is self-explanatory).
switch nm
    case 'delta_PLL',       r = 'SRF-PLL angle: synchronises the dq frame to the grid voltage';
    case 'xi_PLL',          r = 'PLL PI integrator (regulates $v_q$)';
    case 'P_f',             r = 'filtered active-power measurement';
    case 'Q_f',             r = 'filtered reactive-power measurement';
    case 'xi_P',            r = 'outer active-power PI integrator (sets $i_d$ ref)';
    case 'xi_Q',            r = 'outer reactive-power PI integrator (sets $i_q$ ref)';
    case 'xi_id',           r = 'inner $d$-axis current PI integrator';
    case 'xi_iq',           r = 'inner $q$-axis current PI integrator';
    case 'i_d',             r = '$d$-axis L-filter (converter) current';
    case 'i_q',             r = '$q$-axis L-filter (converter) current';
    case 'omega_R',         r = 'virtual rotor speed (inertia state of the swing)';
    case 'omega',           r = 'virtual rotor speed (VSG inertia state)';
    case 'E',               r = 'internal voltage magnitude (Q-V droop)';
    case 'xi_V',            r = 'd-axis voltage-PI integrator (forms $|V|$)';
    case 'delta',           r = 'virtual load angle (swing angle vs grid)';
    case 'x_gov',           r = 'governor PI integrator (frequency/power droop)';
    case 'T_m',             r = 'turbine/prime-mover torque (1st-order lag)';
    case 'x_d',             r = 'damper-winding washout state (adds damping torque)';
    case 'delta_vsm',       r = 'virtual rotor angle (swing angle)';
    case 'delta_omega_vsm', r = 'virtual speed deviation (inertia state)';
    otherwise,              r = '--';
end
end

function t = tex_state(nm)
if isempty(nm), t = '--'; return; end
t = strrep(nm,'_','\_');
end

% =========================================================================
function write_idqpq_table(M,outdir)
fid = fopen(fullfile(outdir,'table_idqpq.tex'),'w');
fprintf(fid,'\\begin{tabular}{lcccccc}\\toprule\n');
fprintf(fid,'Model & $n_x$ & $i_d$ (pu) & $i_q$ (pu) & $P$ (pu) & $Q$ (pu) & current frame\\\\\\midrule\n');
for k = 1:numel(M)
    s = M(k);
    frame = 'native';
    if contains(s.current_source,'TRANSFORM'), frame = 'diagnostic'; end
    fprintf(fid,'%s & %d & %+.4f & %+.4f & %+.4f & %+.4f & %s\\\\\n', ...
        strrep(s.label,'_','\_'), s.nx, s.id0, s.iq0, s.P0, s.Q0, frame);
end
fprintf(fid,'\\bottomrule\n\\end{tabular}\n');
fclose(fid);
end

% =========================================================================
function plot_eigenplane(M,outdir)
f = figure('Visible','off','Position',[100 100 1100 460]);
% Distinct markers per model: GFL = black circle, GFM-Sakimoto = red cross,
% GFM-4state = blue plus.
mk  = {'o','x','+'};
col = {[0 0 0],[0.85 0.10 0.10],[0.00 0.30 0.85]};
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');
nexttile; hold on; grid on;
for k=1:numel(M)
    plot(real(M(k).eig),imag(M(k).eig),mk{k},'Color',col{k}, ...
        'MarkerSize',9,'LineWidth',1.6,'DisplayName',M(k).label);
end
xline(0,'k--','HandleVisibility','off');
xlabel('Real (1/s)'); ylabel('Imag (1/s)');
title('Eigenvalue plane (full)'); legend('Location','best');
nexttile; hold on; grid on;
for k=1:numel(M)
    plot(real(M(k).eig),imag(M(k).eig),mk{k},'Color',col{k}, ...
        'MarkerSize',9,'LineWidth',1.6,'DisplayName',M(k).label);
end
xline(0,'k--','HandleVisibility','off'); xlim([-60 5]); ylim([-30 30]);
xlabel('Real (1/s)'); ylabel('Imag (1/s)');
title('Eigenvalue plane (zoom near origin)'); legend('Location','best');
exportgraphics(f,fullfile(outdir,'eigenvalue_plane.png'),'Resolution',150);
close(f);
end

% =========================================================================
function plot_eig_loadsweep(outdir)
% Eigenvalue migration as the load is swept 20/40/60/80/100% (P=0.2..1.0 pu,
% Q held). Two panels: GFL 6-state, GFM 6-state. Zoomed on each model's
% signature oscillatory mode (GFL PLL ~0.34 Hz; GFM swing ~9.5--11 Hz).
V = 1.0+0i; Q = 0.10; Z = 0.02+0.20i;
loads = [20 40 60 80 100]; Pset = loads/100;   % 100% <-> 1.0 pu
lcol = lines(numel(loads));
lmk  = repmat({'x'},1,numel(loads));   % same marker (cross) for all load levels
names = {'GFL 6-state','GFM 6-state'};
f = figure('Visible','off','Position',[100 100 1000 440]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');
for mdl = 1:2
    nexttile; hold on; grid on;
    for li = 1:numel(Pset)
        P = Pset(li);
        lam = eig_at_load(mdl,V,P,Q,Z);
        plot(real(lam),imag(lam),lmk{li},'Color',lcol(li,:), ...
            'MarkerSize',9,'LineWidth',1.6, ...
            'DisplayName',sprintf('%d%% (P=%.1f)',loads(li),P));
    end
    xline(0,'k--','HandleVisibility','off');
    xlabel('Real (1/s)'); ylabel('Imag (1/s)');
    title(names{mdl}); legend('Location','best');
    switch mdl
        case 1, xlim([-1.7 0.1]); ylim([-3 3]);   % GFL: PLL mode near origin
        case 2, xlim([-9 0.5]);   ylim([-75 75]);  % GFM: swing mode
    end
end
exportgraphics(f,fullfile(outdir,'eigenvalue_loadsweep.png'),'Resolution',150);
close(f);
end

function lam = eig_at_load(mdl,V,P,Q,Z)
switch mdl
    case 1
        d = ibr.gfl_reduced6_model('GFL6',1,1,1,V,struct(),P,Q);
    case 2
        d = ibr.gfm_reduced6_model('GFM6',1,1,1,V,struct(),P,Q);
end
x = d.equilibrium_initialize(V,P,Q,struct()); u = d.u0;
I0 = d.current_injection(0,x,[real(V);imag(V)],u,struct());
Vinf = V - Z*I0;
oc = ibr.smib_sssa_oracle(d,x,V,u,Vinf,Z);
lam = oc.eigenvalues(:);
end

% =========================================================================
function plot_modal_frequency(M,outdir)
% Modal frequency content in Hz. Left: oscillation frequency f=|Im|/2pi of the
% oscillatory (complex) modes only. Right: characteristic frequency |lambda|/2pi
% of every mode (log axis) showing the low->high spread typical of IBR
% (electromechanical swing at a few Hz up to fast current-loop modes).
col = {[0 0 0],[0.85 0.10 0.10],[0.00 0.30 0.85]};
mk  = {'o','x','+'};
f = figure('Visible','off','Position',[100 100 1150 440]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');

% Panel A: oscillation frequency of complex modes
nexttile; hold on; grid on;
for k=1:numel(M)
    lam = M(k).eig; osc = abs(imag(lam))>1e-6;
    fo = abs(imag(lam(osc)))/(2*pi);
    if isempty(fo), fo = NaN; end
    plot(k*ones(size(fo)), fo, mk{k},'Color',col{k},'MarkerSize',10, ...
        'LineWidth',1.6,'DisplayName',M(k).label);
end
set(gca,'YScale','log'); xlim([0.5 2.5]);
set(gca,'XTick',1:2,'XTickLabel',{'GFL 6-state','GFM 6-state'});
ylabel('Oscillation frequency f=|Im|/2\pi (Hz)');
title('Oscillatory-mode frequencies'); legend('Location','best');

% Panel B: characteristic frequency of ALL modes
nexttile; hold on; grid on;
for k=1:numel(M)
    lam = M(k).eig; fc = abs(lam)/(2*pi); fc(fc<1e-3)=1e-3;
    plot(k*ones(size(fc)), fc, mk{k},'Color',col{k},'MarkerSize',10, ...
        'LineWidth',1.6,'DisplayName',M(k).label);
end
set(gca,'YScale','log'); xlim([0.5 2.5]);
set(gca,'XTick',1:2,'XTickLabel',{'GFL 6-state','GFM 6-state'});
ylabel('Characteristic frequency |\lambda|/2\pi (Hz)');
title('All-mode characteristic frequencies (log)'); legend('Location','best');
exportgraphics(f,fullfile(outdir,'modal_frequency.png'),'Resolution',150);
close(f);
end

% =========================================================================
function plot_idqpq_timeseries(M,outdir)
f = figure('Visible','off','Position',[100 100 1150 780]);
col = lines(3);
tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
sig = {'id','iq','P','Q'};
ttl = {'d-axis current i_d (pu)','q-axis current i_q (pu)', ...
       'Active power P (MW)','Reactive power Q (MVAr)'};
for a = 1:4
    nexttile; hold on; grid on;
    for k=1:numel(M)
        plot(M(k).t, M(k).(sig{a}),'Color',col(k,:),'LineWidth',1.4, ...
            'DisplayName',M(k).label);
    end
    xlabel('Time (s)'); title(ttl{a});
    if a==1, legend('Location','best'); end
end
exportgraphics(f,fullfile(outdir,'idqpq_comparison.png'),'Resolution',150);
close(f);
end
