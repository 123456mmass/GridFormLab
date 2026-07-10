function out = compare_kundur6_sssa_3way()
%COMPARE_KUNDUR6_SSSA_3WAY SSSA eigenvalues: ours vs Kundur book vs PSAT.

pf_init_paths;
outdir = fullfile(pwd,'docs','source','figures','kundur_ex126');

% --- Book (Table E12.3, 3 rotor modes) ---
ref_re = [-0.111; -0.492; -0.506];
ref_im = [ 3.430;  6.820;  7.020];
book = complex(ref_re, ref_im);

% --- Ours (book-reproduction 6th-order, validated <0.5% vs Table E12.3) ---
ssa = stability.kundur_ex126_book_e123_ssa();
ev = ssa.eigenvalues(:);
osc_o = ev(imag(ev)>0.5 & real(ev)<0);
[~,idx]=sort(real(osc_o)); ours = osc_o(idx);

% --- PSAT ---
S = load(fullfile(outdir,'psat_kundur6_sssa.mat'));
pev = S.ps_ev(:);
osc_p = pev(imag(pev)>0.5 & real(pev)<0);
[~,pidx]=sort(real(osc_p)); psat = osc_p(pidx);

% --- Plot: complex plane, 3 rotor-mode pairs ---
f = figure('Visible','off','Color','w','Position',[80 80 860 640]);
hold on; grid on; box on;
hBook = plot(real(book), imag(book),'o','MarkerSize',11,'LineWidth',1.5,'Color',[0 0.4 0.8]);
plot(real(book),-imag(book),'o','MarkerSize',11,'LineWidth',1.5,'Color',[0 0.4 0.8], 'HandleVisibility','off');
hOur = plot(real(ours), imag(ours),'x','MarkerSize',13,'LineWidth',1.8,'Color',[0.1 0.1 0.1]);
plot(real(ours),-imag(ours),'x','MarkerSize',13,'LineWidth',1.8,'Color',[0.1 0.1 0.1], 'HandleVisibility','off');
hPsat = plot(real(psat), imag(psat),'s','MarkerSize',10,'LineWidth',1.4,'Color',[0.85 0.2 0.2]);
plot(real(psat),-imag(psat),'s','MarkerSize',10,'LineWidth',1.4,'Color',[0.85 0.2 0.2], 'HandleVisibility','off');
xline(0,'--','Color',[0.5 0.5 0.5], 'HandleVisibility','off');
xlabel('Real part \sigma (1/s)'); ylabel('Imaginary part \omega (rad/s)');
title('SSSA rotor modes: in-house vs Kundur book vs PSAT');
legend([hBook hOur hPsat], {'Kundur Table E12.3','In-house latest engine','PSAT model 6'}, ...
    'Location','southoutside','Orientation','horizontal','NumColumns',3);
ylim([-8 8]); xlim([-1.5 0.8]);
exportgraphics(f, fullfile(outdir,'kundur6_sssa_compare_3way.png'),'Resolution',200); close(f);

out = struct('book',book,'ours',ours,'psat',psat);
fprintf('Saved: %s\n', fullfile(outdir,'kundur6_sssa_compare_3way.png'));
end
