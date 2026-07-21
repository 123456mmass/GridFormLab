function files = plot_smib_verification_case(result,opt)
%PLOT_SMIB_VERIFICATION_CASE  MATLAB plots for one selected SMIB case.
arguments
    result (1,1) struct
    opt.visible (1,1) logical = true
end
root = pf_init_paths();
outdir = fullfile(root,'output','figures','smib',result.smib_kind);
if ~exist(outdir,'dir'), mkdir(outdir); end
vis='off'; if opt.visible, vis='on'; end
files={};
p=result.pf;

f=figure('Visible',vis,'Name',sprintf('%s SMIB PF equilibrium',p.device_id));
tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
nexttile;
bar([abs(p.V_terminal),abs(p.V_infinite_bus)]);
set(gca,'XTickLabel',{'Terminal','Infinite bus'}); ylabel('|V| (pu)'); grid on;
title('Voltage magnitude');
nexttile;
bar([angle(p.V_terminal),angle(p.V_infinite_bus)]*180/pi);
set(gca,'XTickLabel',{'Terminal','Infinite bus'}); ylabel('Angle (deg)'); grid on;
title('Voltage angle');
nexttile;
bar([real(p.S_terminal),imag(p.S_terminal); ...
    real(p.S_infinite_bus_received),imag(p.S_infinite_bus_received); ...
    real(p.S_line_loss),imag(p.S_line_loss)]);
set(gca,'XTickLabel',{'Converter','Infinite bus','Line loss'});
ylabel('Power (pu)'); legend('P','Q','Location','best'); grid on;
title('Power balance');
nexttile; hold on;
phasor(p.V_terminal,'V terminal',[0 0.447 0.741]);
phasor(p.V_infinite_bus,'V infinite',[0.85 0.325 0.098]);
axis equal; grid on; xlabel('Real (pu)'); ylabel('Imag (pu)');
title('Voltage phasors'); legend('Location','best');
files{end+1}=save_plot(f,outdir,'pf_equilibrium'); %#ok<AGROW>
if strcmpi(vis,'off'), close(f); end

if ~isempty(result.sssa)
    s=result.sssa; lam=s.eigenvalues;
    f=figure('Visible',vis,'Name',sprintf('%s SMIB SSSA',p.device_id));
    tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
    nexttile; plot(real(lam),imag(lam),'o','MarkerFaceColor',[0 0.447 0.741]);
    xline(0,'--k'); yline(0,':k'); grid on;
    xlabel('Real (1/s)'); ylabel('Imag (1/s)'); title('Eigenvalue plane');
    nexttile; bar(real(lam)); yline(0,'--k'); grid on;
    xlabel('Mode'); ylabel('Real(\lambda) (1/s)'); title('Modal real parts');
    nexttile; bar(abs(imag(lam))/(2*pi)); grid on;
    xlabel('Mode'); ylabel('Frequency (Hz)'); title('Modal frequencies');
    nexttile;
    [V,~]=eig(s.A); amp=abs(V); amp=amp./max(sum(amp,1),eps);
    imagesc(amp); colorbar; xlabel('Mode'); ylabel('Active state');
    set(gca,'YTick',1:numel(s.active_state_indices), ...
        'YTickLabel',s.state_names(s.active_state_indices));
    title('Normalized right-mode amplitude');
    files{end+1}=save_plot(f,outdir,'sssa'); %#ok<AGROW>
    if strcmpi(vis,'off'), close(f); end
end

if ~isempty(result.ts)
    q=result.ts;
    f=figure('Visible',vis,'Name',sprintf('%s SMIB event-free TDS',p.device_id));
    tiledlayout(2,1,'Padding','compact','TileSpacing','compact');
    nexttile;
    plot(q.tgrid,q.x_drift.','LineWidth',1.1); grid on;
    xlabel('Time (s)'); ylabel('State'); title('Event-free equilibrium trajectory');
    legend(q.state_names,'Interpreter','none','Location','best');
    nexttile;
    plot(q.tgrid,q.dx_perturbed.','LineWidth',1.1); hold on;
    if q.linear_available && ~q.linear_overflow
        plot(q.tgrid,q.dx_linear.','--','LineWidth',0.9);
    end
    grid on; xlabel('Time (s)'); ylabel('\Delta state');
    title('Small-perturbation nonlinear / linear response');
    files{end+1}=save_plot(f,outdir,'event_free_tds'); %#ok<AGROW>
    if strcmpi(vis,'off'), close(f); end

    sig=q.signals_perturbed;
    files=tiled_time_plot(files,q.tgrid,sig,vis,outdir,p.device_id);
end
end

function phasor(z,label,color)
plot([0 real(z)],[0 imag(z)],'-o','LineWidth',1.5, ...
    'Color',color,'DisplayName',label);
end

function file=save_plot(fig,outdir,name)
file=fullfile(outdir,[name '.png']);
exportgraphics(fig,file,'Resolution',180);
end

function files=tiled_time_plot(files,t,sig,vis,outdir,device_id)
f=figure('Visible',vis,'Name',sprintf('%s SMIB TDS current and power signals',device_id));
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
subtitle('S = V conj(I), generator injection','Interpreter','none');

nexttile;
plot(t,sig.Q_MVAr,'-o','LineWidth',1.15,'MarkerSize',3); grid on;
xlabel('Time (s)'); ylabel('Q injection (MVAr)');
title('Reactive power','Interpreter','none');
subtitle('S = V conj(I), generator injection','Interpreter','none');

files{end+1}=save_plot(f,outdir,'tds_dq_power_signals'); %#ok<AGROW>
if strcmpi(vis,'off'), close(f); end
end

function files=scalar_time_plot(files,t,y,vis,outdir,name,ylabel_text,title_text,source)
f=figure('Visible',vis,'Name',title_text);
plot(t,y,'-o','LineWidth',1.15,'MarkerSize',3); grid on;
xlabel('Time (s)'); ylabel(ylabel_text);
title(title_text,'Interpreter','none');
subtitle(source,'Interpreter','none');
files{end+1}=save_plot(f,outdir,name); %#ok<AGROW>
if strcmpi(vis,'off'), close(f); end
end
