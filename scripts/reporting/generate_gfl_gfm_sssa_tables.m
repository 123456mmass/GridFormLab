function generate_gfl_gfm_sssa_tables
%GENERATE_GFL_GFM_SSSA_TABLES  Modal tables for the automatic SG-off selector.
% Participation factors are reporting diagnostics only. No modal quantity
% produced here feeds the selector, equilibrium, SSSA gate, or TDS runtime.

pf_init_paths();
source_file='output/diagnostics/automatic_selector_table.mat';
s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
% Rebuild through the same authenticated automatic producer used by the
% production launcher.  Do not depend on an opaque or stale MAT artifact.
table_opt=struct('sg_on',struct('n_gfm_required',0));
tbl=stability.ibr_selector_table(s.case_data,s.resources,s,table_opt);
audit_dir=fileparts(source_file);
if ~exist(audit_dir,'dir'), mkdir(audit_dir); end
save(source_file,'tbl','-v7.3');
[devices,~]=stability.build_mixed_resource_devices( ...
    s.case_data,s.resources,s.scenario_opt);
outdir=fullfile('docs','source','figures','switch_ieee14');
if ~exist(outdir,'dir'), mkdir(outdir); end

write_candidate_summary(tbl.sg_off.configurations, ...
    fullfile(outdir,'sssa_candidate_summary.tex'));
write_sg_on_candidate_summary(tbl.sg_on.configurations, ...
    fullfile(outdir,'sssa_sg_on_candidate_summary.tex'));
cfgs=tbl.sg_off.configurations;
feasible=find([cfgs.feasible]);
for ii=1:numel(feasible)
    c=cfgs(feasible(ii));
    sssa=rebuild_sssa(c,devices,s.case_data);
    rows=modal_rows(sssa,devices);
    filename=fullfile(outdir,sprintf('sssa_modes_n%d.tex',c.n_gfm_required));
    write_mode_table(rows,c,sssa,filename);
    write_state_inventory(sssa,devices,c,fullfile(outdir, ...
        sprintf('sssa_states_n%d.tex',c.n_gfm_required)));
end

% SG-online handback is staged one IBR at a time. Publish the complete
% 16-subset decision inventory, plus full modal/state tables for every
% authenticated stable configuration. The accepted runtime event log later
% identifies which of these configurations formed the actual path. These
% files are reporting evidence only.
on_cfgs=tbl.sg_on.configurations;
ready_on=find([on_cfgs.ready_to_commit]);
for ii=1:numel(ready_on)
    c=on_cfgs(ready_on(ii)); sssa=rebuild_sssa(c,devices,s.case_data);
    suffix=tuple_suffix(c.selected_gfm_indices);
    write_mode_table(modal_rows(sssa,devices),c,sssa, ...
        fullfile(outdir,['sssa_sg_on_modes_' suffix '.tex']));
    write_state_inventory(sssa,devices,c, ...
        fullfile(outdir,['sssa_sg_on_states_' suffix '.tex']));
end
fprintf('GFL_GFM_SSSA_TABLES_DONE: %s\n',outdir);
end

function write_sg_on_candidate_summary(cfgs,filename)
fid=fopen(filename,'w'); guard=onCleanup(@()fclose(fid));
fprintf(fid,'%% Complete authenticated SG-online 16-subset table.\n');
fprintf(fid,'\\begingroup\\footnotesize\\setlength{\\tabcolsep}{2pt}\n');
fprintf(fid,'\\begin{longtable}{@{}r p{0.12\\textwidth} r r r r c p{0.21\\textwidth}@{}}\n');
fprintf(fid,['\\toprule\nNo. & GFM resources & $n_{GFM}$ & Ref. & ' ...
    '$\\Omega_{worst}$ (s$^{-1}$) & Margin & Ready & Classification \\\\ \\midrule\n']);
fprintf(fid,['\\endfirsthead\n\\toprule\nNo. & GFM resources & $n_{GFM}$ & Ref. & ' ...
    '$\\Omega_{worst}$ (s$^{-1}$) & Margin & Ready & Classification \\\\ \\midrule\n\\endhead\n']);
for k=1:numel(cfgs)
    c=cfgs(k);
    fprintf(fid,'%d & %s & %d & %s & %s & %s & %s & %s \\\\ \n', ...
        k,latex_text(mat2str(c.selected_gfm_indices)),c.n_gfm_required, ...
        latex_text(mat2str(c.reference_resource_index)),latex_number(c.omega), ...
        latex_number(c.margin),yesno(c.ready_to_commit), ...
        latex_text(sg_on_reason(c)));
end
fprintf(fid,'\\bottomrule\n\\end{longtable}\\endgroup\n'); clear guard
end

function s=sg_on_reason(c)
if c.ready_to_commit
    if isempty(c.fd_omegas)
        s='stable; robustness evidence unavailable';
    else
        s=sprintf('robust stable, FD Omega=%s',mat2str(c.fd_omegas,5));
    end
elseif c.sssa_evaluated && ~isempty(c.physical_eigenvalues)
    s='unstable or insufficient robust margin';
elseif c.equilibrium_evaluated
    s='SSSA unavailable';
else
    s='equilibrium unavailable';
end
end

function s=tuple_suffix(v)
if isempty(v), s='all_gfl'; return; end
s=['gfm_' strjoin(arrayfun(@num2str,v,'UniformOutput',false),'_')];
end

function sssa=rebuild_sssa(c,devices,case_data)
opt=struct('full_kcl',true,'u_eq',c.eq_u_eq, ...
    'event_context',c.eq_context,'active_state_indices',c.eq_active_indices, ...
    'reference_device_index',c.reference_resource_index);
sssa=stability.composite_sssa_model(devices,c.eq_x0,c.eq_y0,case_data,opt);
if ~isequaln(sort_complex(sssa.physical_eigenvalues), ...
        sort_complex(c.physical_eigenvalues))
    err=max(abs(sort_complex(sssa.physical_eigenvalues)- ...
        sort_complex(c.physical_eigenvalues)));
    if ~isfinite(err) || err>1e-8
        error('generate_gfl_gfm_sssa_tables:spectrumMismatch', ...
            'Rebuilt physical spectrum differs from authenticated candidate by %.3g.',err);
    end
end
end

function z=sort_complex(z)
z=z(:); [~,idx]=sortrows([real(z),imag(z)],[1 2]); z=z(idx);
end

function rows=modal_rows(sssa,devices)
A=sssa.physical_A;
[R,D]=eig(A); lam=diag(D);
% Audited linear solve instead of inv(R). Row i of L is the left
% eigenvector paired with column i of R under L*R=I.
L=R\eye(size(R));
n=numel(lam);
participation=abs(R.*L.');
den=sum(participation,1); den(den<=eps)=1;
participation=participation./den;

keep=true(n,1);
tol=1e-8;
for i=1:n
    if imag(lam(i)) < -tol, keep(i)=false; end
end
idx=find(keep);
[~,ord]=sortrows([real(lam(idx)),abs(imag(lam(idx)))],[1 2]);
idx=idx(ord);
coord=sssa.physical_state_global_indices(:);
rows=repmat(struct('lambda',0,'frequency',0,'damping',0, ...
    'dominant','','dominant_weight',0,'runner_up_weight',0),numel(idx),1);
for q=1:numel(idx)
    i=idx(q); z=lam(i);
    pf=participation(:,i);
    [weights,pord]=sort(pf,'descend');
    % Top three, each with its NORMALISED participation factor in parentheses.
    % The factor is the point of the column: a mode whose three leading entries
    % are 0.131, 0.131, 0.128 is a shared family, not an IBR6 mode, and a column
    % that printed only the first name would say the opposite.
    top=pord(1:min(3,numel(pord)));
    labels=cell(1,numel(top));
    for j=1:numel(top)
        labels{j}=sprintf('%s (%.3f)', ...
            state_label_tex(coord(top(j)),devices),weights(j));
    end
    rows(q).lambda=z;
    rows(q).frequency=abs(imag(z))/(2*pi);
    if abs(z)>eps, rows(q).damping=-real(z)/abs(z); else, rows(q).damping=NaN; end
    rows(q).dominant=strjoin(labels,'; ');
    rows(q).dominant_weight=weights(1);
    if numel(weights)>1, rows(q).runner_up_weight=weights(2);
    else, rows(q).runner_up_weight=0; end
end
end

function label=state_label_tex(global_index,devices)
offset=0; label=sprintf('state~%d',global_index);
for k=1:numel(devices)
    if global_index>offset && global_index<=offset+devices(k).nx
        li=global_index-offset;
        name=devices(k).state_names{li};
        label=sprintf('%s:%s',latex_text(devices(k).device_id),latex_state(name));
        return;
    end
    offset=offset+devices(k).nx;
end
end

function write_candidate_summary(cfgs,filename)
fid=fopen(filename,'w'); guard=onCleanup(@()fclose(fid));
fprintf(fid,'%% Generated from the authenticated automatic selector table.\n');
fprintf(fid,'\\begingroup\\footnotesize\\setlength{\\tabcolsep}{1.5pt}\n');
fprintf(fid,'\\begin{longtable}{@{}r p{0.08\\textwidth} r c c p{0.105\\textwidth} p{0.105\\textwidth} p{0.18\\textwidth}@{}}\n');
fprintf(fid,'\\toprule\n$n_{GFM}$ & Selected & Ref. & Eq. & SSSA & $\\Omega$ (s$^{-1}$) & Margin & Result \\\\ \\midrule\n');
fprintf(fid,'\\endfirsthead\n\\toprule\n$n_{GFM}$ & Selected & Ref. & Eq. & SSSA & $\\Omega$ (s$^{-1}$) & Margin & Result \\\\ \\midrule\n\\endhead\n');
for k=1:numel(cfgs)
    c=cfgs(k);
    fprintf(fid,'%d & %s & %s & %s & %s & %s & %s & %s \\\\ \n', ...
        c.n_gfm_required,latex_text(mat2str(c.selected_gfm_indices)), ...
        latex_text(mat2str(c.reference_resource_index)),yesno(c.equilibrium_evaluated), ...
        yesno(c.sssa_evaluated),latex_number(c.omega),latex_number(c.margin), ...
        latex_text(short_reason(c)));
end
fprintf(fid,'\\bottomrule\n\\end{longtable}\\endgroup\n'); clear guard
end

function s=short_reason(c)
if c.feasible, s='PASS'; return; end
if ~c.equilibrium_evaluated, s='not evaluated'; return; end
if c.equilibrium_evaluated && ~c.sssa_evaluated
    if contains(string(c.failure_id),'deviceLimit')
        s='equilibrium: device limit';
    else
        s='equilibrium: no convergence';
    end
    return;
end
s='SSSA: insufficient margin';
end

function write_mode_table(rows,c,sssa,filename)
% One row per mode with the four modal quantities SEPARATED into their own
% columns: real part, imaginary part, modal frequency and damping ratio. An
% earlier revision printed the eigenvalue as a single composite cell, which put
% the real and imaginary parts in one column and dropped zeta entirely -- the
% reader could no longer read off the decay rate and the damping of a mode
% independently. Every value comes from modal_rows; nothing is recomputed here.
fid=fopen(filename,'w'); guard=onCleanup(@()fclose(fid));
fprintf(fid,'%% Physical decision spectrum; conjugate pairs printed once.\n');
fprintf(fid,'%% nGFM=%d selected=%s reference=%d full=%d physical=%d method=%s\n', ...
    c.n_gfm_required,mat2str(c.selected_gfm_indices),c.reference_resource_index, ...
    numel(c.eigenvalues),numel(c.physical_eigenvalues),sssa.physical_reduction_method);
HDR=['No. & $\\Re\\lambda$ (s$^{-1}$) & $\\Im\\lambda$ (s$^{-1}$) & ' ...
     '$f$ (Hz) & $\\zeta$ & ' ...
     'Dominant participation: device:state (normalised) \\\\ \\midrule\n'];
fprintf(fid,'\\begingroup\\footnotesize\\setlength{\\tabcolsep}{3pt}\n');
fprintf(fid,'\\begin{longtable}{@{}r r r r r p{0.34\\textwidth}@{}}\n');
fprintf(fid,['\\toprule\n' HDR]);
fprintf(fid,['\\endfirsthead\n\\toprule\n' HDR '\\endhead\n']);
% A row whose two leading participations differ by less than the resolution of
% the printed factors does not identify one dominant state, and saying so is the
% honest reading of that row. The threshold and the count are computed here so
% neither can go stale in report prose if this table is regenerated.
TIE_TOL=0.02;
n_tie=0;
for k=1:numel(rows)
    z=rows(k).lambda;
    tie=(rows(k).dominant_weight-rows(k).runner_up_weight)<TIE_TOL;
    % Single-quoted: MATLAB does not process escapes here and %s passes the
    % string through, so exactly ONE backslash must appear in the source.
    if tie, n_tie=n_tie+1; mark='$^{\dagger}$'; else, mark=''; end
    fprintf(fid,'%d%s & %s & %s & %s & %s & %s \\\\ \n',k,mark, ...
        latex_number(real(z)),latex_signed_imag(z), ...
        latex_number(rows(k).frequency),latex_damping(rows(k).damping), ...
        rows(k).dominant);
end
fprintf(fid,'\\bottomrule\n\\end{longtable}\n');
if n_tie>0
    fprintf(fid,['\\noindent$^{\\dagger}$\\,%d of the %d rows carry this mark. ' ...
        'Their two leading participations differ by less than %.2f, the ' ...
        'resolution of the printed factors, so the first entry is not a sole ' ...
        'attribution there and the three entries should be read together.\\par\n'], ...
        n_tie,numel(rows),TIE_TOL);
end
fprintf(fid,'\\endgroup\n'); clear guard
end

function s=latex_signed_imag(z)
% Conjugate pairs are printed once, so the tabulated imaginary part is the
% positive member of the pair. A purely real mode prints 0, not a dash: zero
% imaginary part is a measured value, not a missing one.
if ~isfinite(z), s='--'; return; end
v=abs(imag(z));
if v<=1e-10, s='$0$'; return; end
s=sprintf('$\\pm%s$',strip_math(latex_number(v)));
end

function s=latex_damping(zeta)
% A real negative mode has zeta = 1 exactly; print it as such rather than as
% 1.000000, and keep six figures elsewhere so a lightly damped mode is legible.
if ~isscalar(zeta) || ~isfinite(zeta), s='--'; return; end
if abs(zeta-1)<=1e-12, s='$1$'; return; end
if abs(zeta)<=1e-12, s='$0$'; return; end
s=sprintf('$%.6f$',zeta);
end

function write_state_inventory(sssa,devices,c,filename)
coord=sssa.physical_state_global_indices(:);
fid=fopen(filename,'w'); guard=onCleanup(@()fclose(fid));
fprintf(fid,'%% Physical coordinates after the one-angle quotient.\n');
fprintf(fid,'\\begin{longtable}{@{}r l l l@{}}\n');
fprintf(fid,'\\toprule\nCoordinate & Device & State & Owner \\\\ \\midrule\n');
fprintf(fid,'\\endfirsthead\n\\toprule\nCoordinate & Device & State & Owner \\\\ \\midrule\n\\endhead\n');
for q=1:numel(coord)
    [dev_id,state,owner]=state_parts(coord(q),devices,c);
    fprintf(fid,'%d & %s & %s & %s \\\\ \n',q,latex_text(dev_id), ...
        latex_state(state),latex_text(owner));
end
fprintf(fid,'\\bottomrule\n\\end{longtable}\n'); clear guard
end

function [dev_id,state,owner]=state_parts(global_index,devices,c)
offset=0; dev_id='unknown'; state=sprintf('state %d',global_index); owner='unknown';
for k=1:numel(devices)
    if global_index>offset && global_index<=offset+devices(k).nx
        li=global_index-offset; dev_id=devices(k).device_id;
        state=devices(k).state_names{li};
        if k==1, owner='SG';
        elseif li<=3, owner='common plant';
        elseif ismember(k,c.selected_gfm_indices), owner='GFM';
        else, owner='GFL';
        end
        return;
    end
    offset=offset+devices(k).nx;
end
end

function s=yesno(v)
if isequal(v,true), s='yes'; else, s='no'; end
end

function s=latex_complex(z)
if ~isfinite(z), s='--'; return; end
re=latex_number(real(z)); im=latex_number(abs(imag(z)));
if abs(imag(z))<=1e-10
    s=re;
else
    if imag(z)>=0, sign='+'; else, sign='-'; end
    s=sprintf('$%s%s\\mathrm{j}%s$',strip_math(re),sign,strip_math(im));
end
end

function s=latex_number(v)
if ~isscalar(v) || ~isfinite(v), s='--'; return; end
if v==0, s='$0$'; return; end
e=floor(log10(abs(v)));
if e>=-2 && e<=3
    s=sprintf('$%.6f$',v);
else
    a=v/10^e; s=sprintf('$%.4f\\times10^{%d}$',a,e);
end
end

function s=strip_math(s)
if startsWith(s,'$') && endsWith(s,'$'), s=s(2:end-1); end
end

function s=latex_text(s)
s=char(string(s));
s=strrep(s,'\','\textbackslash{}');
s=strrep(s,'_','\_');
s=strrep(s,'%','\%');
s=strrep(s,'&','\&');
s=strrep(s,'#','\#');
s=strrep(s,'[','{[}');
s=strrep(s,']','{]}');
end

function s=latex_state(name)
% Report-facing mathematical notation for the production state contract.
switch char(name)
case 'i_d',             s='$i_d$';
case 'i_q',             s='$i_q$';
case 'V_dc',            s='$V_{dc}$';
case 'I_dc',            s='$I_{dc}$';
case 'gfl_delta_PLL',   s='$\delta_{PLL}^{GFL}$';
case 'gfl_xi_PLL',      s='$\xi_{PLL}^{GFL}$';
case 'gfl_xi_P',        s='$\xi_{P}^{GFL}$';
case 'gfl_xi_Q',        s='$\xi_{Q}^{GFL}$';
case 'gfl_xi_Id',       s='$\xi_{Id}^{GFL}$';
case 'gfl_xi_Iq',       s='$\xi_{Iq}^{GFL}$';
case 'gfm_delta_VSG',   s='$\delta_{VSG}^{GFM}$';
case 'gfm_omega_VSG',   s='$\omega_{VSG}^{GFM}$';
case 'gfm_E',           s='$E^{GFM}$';
case 'gfm_xi_Vd',       s='$\xi_{Vd}^{GFM}$';
case 'gfm_xi_Vq',       s='$\xi_{Vq}^{GFM}$';
case 'gfm_xi_Id',       s='$\xi_{Id}^{GFM}$';
case 'gfm_xi_Iq',       s='$\xi_{Iq}^{GFM}$';
case 'gfm_omega_f',     s='$\omega_{f}^{GFM}$';
otherwise,              s=latex_text(name);
end
end
