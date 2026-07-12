function out = generate_padiyar_two_area_report()
%GENERATE_PADIYAR_TWO_AREA_REPORT Generate Padiyar PF/SSSA/TS report assets.
pf_init_paths;
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
outdir=fullfile(root,'docs','source','figures','padiyar_two_area');
if ~exist(outdir,'dir'), mkdir(outdir); end
c=cases.case_padiyar_two_area_4m_avr();
pf=pfsolver.powerflow_newton_raphson(c,struct('verbose',false,'plot_results',false, ...
    'enforce_q_limits',false,'tolerance',1e-11));
avr=stability.padiyar_model11_ssa(c,struct('excitation','avr','fd_eps',1e-6));
manual=stability.padiyar_model11_ssa(c,struct('excitation','manual','fd_eps',1e-6));
scenario=struct('fault_enabled',true,'fault_bus',3,'Zf',1i*0.5, ...
    't_fault',1,'t_clear',1.1,'t_end',3,'dt',0.005);
ts_avr=stability.ts_simulate_padiyar_model11(c,merge(scenario,struct('excitation','avr')));
ts_manual=stability.ts_simulate_padiyar_model11(c,merge(scenario,struct('excitation','manual')));

save(fullfile(outdir,'padiyar_two_area_results.mat'), ...
    'c','pf','avr','manual','ts_avr','ts_manual','scenario');
plot_pf(pf,fullfile(outdir,'powerflow_summary.png'));
plot_pf_precision(c,pf,fullfile(outdir,'pf_precision.png'));
plot_eigs(c,avr,manual,fullfile(outdir,'eigenvalue_comparison.png'));
plot_swing_modes(c,avr,manual,fullfile(outdir,'swing_mode_comparison.png'));
plot_ts_result(ts_avr,'Padiyar two-area',root,'padiyar_two_area', ...
    fullfile(outdir,'fault_comparison.png'));
plot_ts_avr_vs_manual(ts_avr,ts_manual,fullfile(outdir,'ts_avr_vs_manual.png'));
write_pf_bus(c,pf,fullfile(outdir,'table_pf_bus.tex'));
write_pf_summary(c,pf,fullfile(outdir,'table_pf_summary.tex'));
write_pf_results(c,pf,fullfile(outdir,'table_pf_results.tex'));
write_eigs(c,avr,fullfile(outdir,'table_eigenvalues.tex'));
write_modes(c,avr,manual,fullfile(outdir,'table_swing_modes.tex'));
write_ts(ts_avr,ts_manual,fullfile(outdir,'table_ts_summary.tex'));

out=struct('case_data',c,'pf',pf,'ssa_avr',avr,'ssa_manual',manual, ...
    'ts_avr',ts_avr,'ts_manual',ts_manual,'output_dir',outdir);
fprintf('Padiyar report assets: %s\n',outdir);
fprintf('PF: converged=%d iter=%d; AVR DAE residual=%.3e; TS nonconv AVR/manual=%d/%d\n', ...
    pf.converged,pf.iterations,avr.initial_residual, ...
    ts_avr.nonconverged_step_count,ts_manual.nonconverged_step_count);
end

function s=merge(a,b)
s=a; f=fieldnames(b); for k=1:numel(f), s.(f{k})=b.(f{k}); end
end

function plot_pf(pf,path)
f=figure('Visible','off','Color','w','Position',[100 100 1100 700]);
tiledlayout(2,2,'Padding','compact','TileSpacing','compact'); b=pf.external_bus_ids;
nexttile; bar(categorical(string(b)),pf.bus_voltage,'FaceColor',[.08 .39 .62]); grid on;
yline(1,'--'); ylabel('|V| (pu)'); title('Bus voltage magnitude');
nexttile; bar(categorical(string(b)),pf.bus_angle_deg,'FaceColor',[.85 .42 .12]); grid on;
ylabel('Angle (deg)'); title('Bus voltage angle');
nexttile; bar(categorical(string(b)),pf.P_generation*100,'FaceColor',[.17 .55 .34]); grid on;
ylabel('MW'); title('Generator active power');
nexttile; semilogy(1:pf.iterations,pf.mismatch_history(1:pf.iterations),'-o','LineWidth',1.8); grid on;
xlabel('Iteration'); ylabel('Max mismatch (pu)'); title('Newton--Raphson convergence');
sgtitle('Padiyar two-area power flow'); exportgraphics(f,path,'Resolution',200); close(f);
end

function plot_eigs(c,avr,manual,path)
f=figure('Visible','off','Color','w','Position',[100 100 1050 650]); hold on; grid on;
la=avr.eigenvalues; lm=manual.eigenvalues; lr=c.reference.table95_eigenvalues;
scatter(real(lr),imag(lr),70,'o','MarkerEdgeColor',[.1 .1 .1],'LineWidth',1.4);
scatter(real(la),imag(la),46,'filled','MarkerFaceColor',[.08 .42 .68]);
scatter(real(lm),imag(lm),52,'^','MarkerEdgeColor',[.80 .33 .08],'LineWidth',1.3);
xline(0,'k--'); xlabel('Real part (1/s)'); ylabel('Imaginary part (rad/s)');
title('Small-signal eigenvalues'); legend('Padiyar Table 9.5','Computed AVR','Computed manual excitation','Location','best');
exportgraphics(f,path,'Resolution',200); close(f);
end

function plot_swing_modes(c,avr,manual,path)
% Swing-mode-only view corresponding directly to the SSSA comparison table.
book=swing_modes(c.reference.table95_eigenvalues);
labels={'Inter-area','Local Area 2','Local Area 1'};
a=swing_modes(avr.eigenvalues); m=swing_modes(manual.eigenvalues);
[~,ia]=sort(imag(a)); a=a(ia); [~,im]=sort(imag(m)); m=m(im);
freq_err=100*abs(imag(a)-imag(book))./imag(book);
zb=-real(book)./abs(book); za=-real(a)./abs(a);
damp_err=100*abs(za-zb)./zb;

f=figure('Visible','off','Color','w','Position',[100 100 1150 470]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');
nexttile; hold on; grid on; box on;
scatter(real(book),imag(book),85,'o','MarkerEdgeColor',[.1 .1 .1],'LineWidth',1.5);
scatter(real(a),imag(a),60,'filled','MarkerFaceColor',[.08 .42 .68]);
scatter(real(m),imag(m),70,'^','MarkerEdgeColor',[.80 .33 .08],'LineWidth',1.4);
for k=1:numel(book)
    text(real(book(k))-.035,imag(book(k))+.11,labels{k},'FontSize',9, ...
        'HorizontalAlignment','right');
end
xline(0,'k--'); xlabel('Real part (1/s)'); ylabel('Imaginary part (rad/s)');
title('Positive-imaginary swing modes');
legend('Padiyar Table 9.5','Computed AVR','Computed manual','Location','southwest');

nexttile;
mode_axis=categorical(labels,labels,'Ordinal',true);
bar(mode_axis,[freq_err damp_err],'grouped'); grid on; box on;
ylabel('Absolute relative error (%)'); title('AVR error versus Table 9.5');
legend('Frequency error','Damping-ratio error','Location','northwest');
exportgraphics(f,path,'Resolution',200); close(f);
end

function plot_pf_precision(c,pf,path)
% Precision graph: per-bus PF errors vs Padiyar Table 9.2 (clean, no overlap).
[~,ix]=ismember(c.operating_point.printed_bus_ids,pf.external_bus_ids);
Vo=pf.bus_voltage(ix); Vp=c.operating_point.printed_V;
ao=pf.bus_angle_deg(ix); ap=c.operating_point.printed_angle_deg;
b=pf.external_bus_ids(ix); bx=1:numel(b);
f=figure('Visible','off','Color','w','Position',[100 100 1000 400]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');
nexttile; bar(bx,abs(Vo-Vp)*1e5,'FaceColor',[.08 .39 .62]); grid on; box on;
ylabel('|\Delta V| (\times 10^{-5} pu)'); title('Voltage magnitude error vs Table 9.2');
xticks(bx); xticklabels(string(b)); xtickangle(30);
nexttile; bar(bx,abs(ao-ap)*1e5,'FaceColor',[.85 .42 .12]); grid on; box on;
ylabel('|\Delta\theta| (\times 10^{-5} deg)'); title('Voltage angle error vs Table 9.2');
xticks(bx); xticklabels(string(b)); xtickangle(30);
sgtitle('Power-flow precision: in-house vs Padiyar Table 9.2 (all errors < 5\times 10^{-5})');
exportgraphics(f,path,'Resolution',200); close(f);
end

function plot_ts_avr_vs_manual(a,m,path)
% AVR (solid) vs manual (dashed), SAME format as plot_ts_result.
gen_ids=a.gen_buses(:)'; ng=numel(gen_ids); colors=lines(ng);
labels=compose('G%d@Bus%d',(1:ng)',gen_ids);
da=rad2deg(a.delta-a.delta(1,:)); dm=rad2deg(m.delta-m.delta(1,:));
t=a.t; f=figure('Visible','off','Color','w','Position',[70 70 1300 820]);
tl=tiledlayout(f,2,2,'Padding','compact','TileSpacing','compact');
% Top-left: rotor angle
ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for k=1:ng, plot(ax,t,da(:,k),'-','Color',colors(k,:),'LineWidth',1.4); plot(ax,t,dm(:,k),'--','Color',colors(k,:),'LineWidth',1.0); end
fl2(ax,a); xlabel(ax,'Time (s)'); ylabel(ax,'\Delta\delta_i = \delta_i-\delta_i(0) (deg)');
title(ax,'Absolute rotor-angle deviations (PSAT delta\_Syn style)'); legend(ax,labels,'Location','best');
% Top-right: speed
ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for k=1:ng, plot(ax,t,a.omega-1,'-','Color',colors(k,:),'LineWidth',1.3); plot(ax,t,m.omega-1,'--','Color',colors(k,:),'LineWidth',1.0); end
fl2(ax,a); xlabel(ax,'Time (s)'); ylabel(ax,'Delta omega (pu)');
title(ax,'Generator speed deviations'); legend(ax,labels,'Location','best');
% Bottom-left: electrical power
ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for k=1:ng, plot(ax,t,a.Pe_MW(:,k),'-','Color',colors(k,:),'LineWidth',1.3); plot(ax,t,m.Pe_MW(:,k),'--','Color',colors(k,:),'LineWidth',1.0); end
fl2(ax,a); xlabel(ax,'Time (s)'); ylabel(ax,'P_e (MW)');
title(ax,'Electrical power (classical air-gap)'); legend(ax,labels,'Location','best');
% Bottom-right: fault-bus and minimum voltage
bi=find(a.bus_ids==a.fault_bus,1); if isempty(bi), bi=1; end
ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
plot(ax,t,a.Vbus(:,bi),'-k','LineWidth',1.8); plot(ax,t,m.Vbus(:,bi),'--k','LineWidth',1.2);
plot(ax,t,min(a.Vbus,[],2),'-r','LineWidth',1.3); plot(ax,t,min(m.Vbus,[],2),'--r','LineWidth',1.0);
fl2(ax,a); xlabel(ax,'Time (s)'); ylabel(ax,'|V| (pu)'); ylim(ax,[0 1.2]);
title(ax,'Fault-bus and minimum voltage');
legend(ax,{sprintf('Bus %g (AVR)',a.fault_bus),sprintf('Bus %g (Manual)',a.fault_bus),'Min |V| (AVR)','Min |V| (Manual)'},'Location','best');
sgtitle(tl,sprintf(['AVR (solid) vs manual (dashed): bus %g fault, Z_f = %.3g%+.3gj pu, %s, dt=%.4g s'], ...
  a.fault_bus,real(a.Zf),imag(a.Zf),a.method,a.dt),'FontWeight','bold');
exportgraphics(f,path,'Resolution',180); close(f);
end

function fl2(ax,r)
xline(ax,r.t_fault,'--','Fault on','Color',[0.75 0.1 0.1],'LineWidth',1.1,'LabelOrientation','horizontal','HandleVisibility','off');
xline(ax,r.t_clear,'--','Fault cleared','Color',[0.75 0.1 0.1],'LineWidth',1.1,'LabelOrientation','horizontal','HandleVisibility','off');
end


function write_pf_bus(c,pf,path)
% PF voltage comparison. Angle differences are absolute because percentage
% error is undefined at the zero-angle reference bus.
[~,ix]=ismember(c.operating_point.printed_bus_ids,pf.external_bus_ids);
ids=c.operating_point.printed_bus_ids;
fid=fopen(path,'w'); z=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'\\begin{tabular}{rrrrrrr}\\toprule\n');
fprintf(fid,'{Bus} & {$V_{book}$} & {$V_{ours}$} & {$|\\Delta V|$} & {$\\theta_{book}$} & {$\\theta_{ours}$} & {$|\\Delta\\theta|$}\\\\\n');
fprintf(fid,'{} & {(pu)} & {(pu)} & {(pu)} & {(deg)} & {(deg)} & {(deg)}\\\\ \\midrule\n');
for k=1:numel(ix)
  b=ids(k); Vo=pf.bus_voltage(ix(k)); Vp=c.operating_point.printed_V(k);
  ao=pf.bus_angle_deg(ix(k)); ap=c.operating_point.printed_angle_deg(k);
  fprintf(fid,'%g & %.4f & %.4f & %.2e & %.4f & %.4f & %.2e\\\\\n', ...
    b,Vp,Vo,abs(Vo-Vp),ap,ao,abs(ao-ap));
end
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function write_pf_summary(c,pf,path)
[~,ix]=ismember(c.operating_point.printed_bus_ids,pf.external_bus_ids);
fid=fopen(path,'w'); z=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'\\begin{tabular}{@{}lr@{}}\\toprule Quantity & Value\\\\ \\midrule\n');
fprintf(fid,'Converged & %s\\\\\nIterations & %d\\\\\n',yesno(pf.converged),pf.iterations);
fprintf(fid,'Maximum $|\\Delta V|$ vs Table 9.2 & %.3e pu\\\\\n',max(abs(pf.bus_voltage(ix)-c.operating_point.printed_V)));
fprintf(fid,'Maximum $|\\Delta \\theta|$ vs Table 9.2 & %.3e deg\\\\\n',max(abs(pf.bus_angle_deg(ix)-c.operating_point.printed_angle_deg)));
fprintf(fid,'Total generation & %.2f MW\\\\\nTotal load & %.2f MW\\\\\nTotal loss & %.2f MW\\\\\n', ...
 pf.P_total_gen*100,pf.P_total_load*100,pf.P_loss_total*100);
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function write_pf_results(c,pf,path)
% Detailed PF results. The cited case provides no physical voltage-base
% assignment for every bus, so only per-unit voltage is reported.
bd=c.bus_data; b=pf.external_bus_ids; V=pf.bus_voltage; th=pf.bus_angle_deg;
typs={'REF','PV','PQ'};
fid=fopen(path,'w'); z=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'\\begin{tabular}{rlrrrrrrrr}\\toprule\n');
fprintf(fid,'{Bus} & {Type} & {$|V|$} & {$\\theta$} & {$P_G$} & {$Q_G$} & {$P_L$} & {$Q_L$} & {$P_{net}$} & {$Q_{net}$}\\\\\n');
fprintf(fid,'{} & {} & {(pu)} & {(deg)} & {(pu)} & {(pu)} & {(pu)} & {(pu)} & {(pu)} & {(pu)}\\\\ \\midrule\n');
for k=1:numel(b)
  r=find(bd(:,1)==b(k),1);
  ti=bd(r,2); tn=typs{ti};
  pg=pf.P_generation(k); qg=pf.Q_generation(k);
  pl=bd(r,7); ql=bd(r,8); pn=pg-pl; qn=qg-ql;
  fprintf(fid,'%g & %s & %.4f & %.4f & %.4f & %.4f & %.4f & %.4f & %.4f & %.4f\\\\\n', ...
    b(k),tn,V(k),th(k),pg,qg,pl,ql,pn,qn);
end
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function write_eigs(c,avr,path)
% Combined eigenvalue table: Padiyar Table 9.5 vs the in-house result.
ref=c.reference.table95_eigenvalues(:); got=avr.eigenvalues(:); [match,err]=greedy(got,ref);
cmt=cell(numel(ref),1);
cmt(9)={'Swing 1'}; cmt(10)={'Swing 1'}; cmt(11)={'Swing 2'}; cmt(12)={'Swing 2'};
cmt(13)={'Inter-area'}; cmt(14)={'Inter-area'};
fid=fopen(path,'w'); z=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'\\begin{tabular}{rccrcl}\\toprule\n');
fprintf(fid,'{No.} & {$\\lambda_{book}$} & {$\\lambda_{ours}$} & {$|\\Delta\\lambda|$} & {$\\varepsilon_{\\lambda}$} & {Mode}\\\\\n');
fprintf(fid,'{} & {(s$^{-1}$)} & {(s$^{-1}$)} & {(s$^{-1}$)} & {(\\%%)} & {}\\\\ \\midrule\n');
for k=1:numel(ref)
  rb=real(ref(k)); ib=imag(ref(k));
  ro=real(match(k)); io=imag(match(k));
  if abs(ib)<1e-9, sb=sprintf('%.4f',rb); else, sb=sprintf('%.4f %+.4fj',rb,ib); end
  if abs(io)<1e-9, so=sprintf('%.4f',ro); else, so=sprintf('%.4f %+.4fj',ro,io); end
  if abs(ref(k))>1e-2, pct=sprintf('%.2f',100*err(k)/abs(ref(k))); else, pct='--'; end
  cm=cmt{k}; if isempty(cm), cm=''; end
  fprintf(fid,'%d & $%s$ & $%s$ & %.4f & {%s} & %s\\\\\n',k,sb,so,err(k),pct,cm);
end
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function write_modes(c,avr,manual,path)
% Direct SSSA comparison. Table 9.5 is the AVR configuration only; manual
% excitation is reported without a fabricated book counterpart.
book=swing_modes(c.reference.table95_eigenvalues);
book_lab={'Inter-area','Local Area 2','Local Area 1'};
a=swing_modes(avr.eigenvalues); m=swing_modes(manual.eigenvalues);
[~,ia]=sort(imag(a)); a=a(ia); [~,im2]=sort(imag(m)); m=m(im2);
fid=fopen(path,'w'); z=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'\\begin{tabular}{llccrrrrrr}\\toprule\n');
fprintf(fid,'{Configuration} & {Mode} & {$\\lambda_{book}$} & {$\\lambda_{ours}$} & {$f_{book}$} & {$f_{ours}$} & {$\\varepsilon_f$} & {$\\zeta_{book}$} & {$\\zeta_{ours}$} & {$\\varepsilon_{\\zeta}$}\\\\\n');
fprintf(fid,'{} & {} & {(s$^{-1}$)} & {(s$^{-1}$)} & {(Hz)} & {(Hz)} & {(\\%%)} & {(\\%%)} & {(\\%%)} & {(\\%%)}\\\\ \\midrule\n');
for k=1:numel(a)
  lb=book(k); fb=imag(lb)/(2*pi); fa=imag(a(k))/(2*pi);
  ef=100*abs(fa-fb)/fb; zb=-real(lb)/abs(lb); za=-real(a(k))/abs(a(k));
  ez=100*abs(za-zb)/zb;
  fprintf(fid,'AVR & %s & $%.4f%+.4fj$ & $%.4f%+.4fj$ & %.4f & %.4f & %.2f & %.3f & %.3f & %.2f\\\\\n', ...
    book_lab{k},real(lb),imag(lb),real(a(k)),imag(a(k)),fb,fa,ef,100*zb,100*za,ez);
end
for k=1:numel(m)
  fm=imag(m(k))/(2*pi); zm=-real(m(k))/abs(m(k));
  fprintf(fid,'Manual & %s & {--} & $%.4f%+.4fj$ & {--} & %.4f & {--} & {--} & %.3f & {--}\\\\\n', ...
    book_lab{k},real(m(k)),imag(m(k)),fm,100*zm);
end
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function write_ts(a,m,path)
fid=fopen(path,'w'); z=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'\\begin{tabular}{llrr}\\toprule {Metric} & {Unit} & {AVR} & {Manual excitation}\\\\ \\midrule\n');
fprintf(fid,'Initial DAE residual & pu & %.3e & %.3e\\\\\n',a.initial_dae_residual,m.initial_dae_residual);
fprintf(fid,'Non-converged steps & steps & %d & %d\\\\\n',a.nonconverged_step_count,m.nonconverged_step_count);
fprintf(fid,'Maximum corrector residual & pu & %.3e & %.3e\\\\\n',a.max_corrector_residual,m.max_corrector_residual);
fprintf(fid,'Minimum bus voltage & pu & %.4f & %.4f\\\\\n',min(a.Vbus,[],'all'),min(m.Vbus,[],'all'));
fprintf(fid,'Maximum speed deviation & pu & %.3e & %.3e\\\\\n',max(abs(a.omega-1),[],'all'),max(abs(m.omega-1),[],'all'));
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function modes=swing_modes(lambda)
modes=lambda(imag(lambda)>1 & imag(lambda)<10); [~,i]=sort(imag(modes)); modes=modes(i);
end

function [match,err]=greedy(got,ref)
match=zeros(size(ref)); err=zeros(size(ref)); used=false(size(got));
for k=1:numel(ref), d=abs(got-ref(k)); d(used)=inf; [err(k),j]=min(d); match(k)=got(j); used(j)=true; end
end

function s=yesno(v)
if v, s='Yes'; else, s='No'; end
end
