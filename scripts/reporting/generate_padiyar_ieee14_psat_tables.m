function out = generate_padiyar_ieee14_psat_tables(output_dir)
%GENERATE_PADIYAR_IEEE14_PSAT_TABLES Fresh IEEE14 Our-vs-PSAT report tables.
%   This report-only orchestrator deliberately has no saved-result fallback:
%   every PF, SSSA, and TS value is computed in this invocation. PSAT is an
%   independent validation reference and is never placed on a production path.

pf_init_paths;
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
if nargin < 1 || isempty(output_dir)
    output_dir = fullfile(root,'docs','source','figures','padiyar_two_area');
end
if exist(output_dir,'dir') ~= 7, mkdir(output_dir); end

scenario = struct('fault_bus',4,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*1e-4,'dt',0.01,'t_end',15.0);
c = attach_classical_machines(cases.case_matpower6_case14());

% In-house results are always recomputed here.
pf_ours = pfsolver.powerflow_newton_raphson(c,struct( ...
    'verbose',false,'plot_results',false,'enforce_q_limits',false, ...
    'tolerance',1e-10));
if ~pf_ours.converged
    error('generate_padiyar_ieee14_psat_tables:ourPF', ...
        'In-house IEEE14 power flow did not converge.');
end
sssa_ours = stability.classical_sssa(c,struct('fd_eps',1e-6,'verbose',false));

% Use the same non-interactive launcher path as run_ts.m. Only the declared
% report scenario and headless settings override the MATPOWER14 catalog
% defaults; solve_case still dispatches to the canonical TS engine.
ts_override = struct('t_end',scenario.t_end,'dt',scenario.dt, ...
    'fault_bus',scenario.fault_bus,'t_fault',scenario.t_fault, ...
    't_clear',scenario.t_clear,'Zf',scenario.Zf, ...
    'pm_mode','balanced','verbose',false,'plot_results',false);
ts_ours = solve_case('analysis','ts','case','matpower14', ...
    'options',ts_override);
if ts_ours.nonconverged_step_count ~= 0 || ...
        abs(ts_ours.t(end)-scenario.t_end) > 1e-9
    error('generate_padiyar_ieee14_psat_tables:ourTS', ...
        'In-house IEEE14 TS did not complete with zero non-converged steps.');
end

% PSAT is also run fresh. Restore the project-only MATLAB path afterward.
path_snapshot = path();
path_cleanup = onCleanup(@() path(path_snapshot)); %#ok<NASGU>
psat = run_psat_case14(scenario);
if ~psat.pf_conv || abs(psat.td_tend-scenario.t_end) > 1e-6
    error('generate_padiyar_ieee14_psat_tables:psatRun', ...
        'Fresh PSAT PF/TS did not complete the requested scenario.');
end
if ~isfield(psat,'sssa_eigenvalues') || isempty(psat.sssa_eigenvalues)
    error('generate_padiyar_ieee14_psat_tables:psatSSSA', ...
        'Fresh PSAT SSSA returned no eigenvalues.');
end

% Deterministic bus mapping for PF.
[bus_ours, io] = sort(pf_ours.external_bus_ids(:));
[bus_psat, ip] = sort(psat.bus_ids(:));
if ~isequal(bus_ours,bus_psat)
    error('generate_padiyar_ieee14_psat_tables:pfBusMapping', ...
        'Our/PSAT PF bus-ID mappings differ.');
end
vm_ours = pf_ours.bus_voltage(io);
va_ours = pf_ours.bus_angle_deg(io);
vm_psat = psat.pf_vmag(ip);
va_psat = psat.pf_angle_deg(ip);

% Compare only physical positive-imaginary relative modes. The common-angle
% zero pair is excluded a priori by the 1e-3 rad/s threshold.
lam_ours = positive_relative_modes(sssa_ours.reduced_eigenvalues);
lam_psat = positive_relative_modes(psat.sssa_eigenvalues);
if numel(lam_ours) ~= numel(lam_psat)
    error('generate_padiyar_ieee14_psat_tables:sssaModeCount', ...
        'Our/PSAT positive-mode counts differ (%d versus %d).', ...
        numel(lam_ours),numel(lam_psat));
end

% Deterministic generator mapping and no-extrapolation common-grid TS data.
[gen_ours, go] = sort(ts_ours.gen_buses(:));
[gen_psat, gp] = sort(psat.delta_bus(:));
if ~isequal(gen_ours,gen_psat)
    error('generate_padiyar_ieee14_psat_tables:genMapping', ...
        'Our/PSAT generator bus-ID mappings differ.');
end
tg = ts_ours.t(:);
delta_ours = rad2deg(ts_ours.delta(:,go));
omega_ours = ts_ours.omega(:,go);
pe_ours = ts_ours.Pe_MW(:,go);
delta_psat = rad2deg(interp_no_extrapolate(psat.t,psat.delta(:,gp),tg));
omega_psat = interp_no_extrapolate(psat.t,psat.omega(:,gp),tg);
pe_psat = 100*interp_no_extrapolate(psat.t,psat.Pe_pu(:,gp),tg);

v4_ours_idx = find(ts_ours.pf.external_bus_ids==scenario.fault_bus,1);
v4_psat_idx = find(psat.vbus_ids==scenario.fault_bus,1);
if isempty(v4_ours_idx) || isempty(v4_psat_idx)
    error('generate_padiyar_ieee14_psat_tables:faultBusMapping', ...
        'Fault bus 4 is missing from an Our/PSAT voltage mapping.');
end
v4_ours = ts_ours.Vbus(:,v4_ours_idx);
v4_psat = interp_no_extrapolate(psat.t,psat.Vbus(:,v4_psat_idx),tg);

metrics = struct();
metrics.pf_max_dV_pu = max(abs(vm_psat-vm_ours));
metrics.pf_max_dangle_deg = max(abs(va_psat-va_ours));
metrics.sssa_max_dlambda = max(abs(lam_psat-lam_ours));
metrics.ts_max_ddelta_deg = max(abs(delta_psat-delta_ours),[],'all');
metrics.ts_max_domega_pu = max(abs(omega_psat-omega_ours),[],'all');
metrics.ts_max_dpe_MW = max(abs(pe_psat-pe_ours),[],'all');
metrics.ts_max_dv4_pu = max(abs(v4_psat-v4_ours),[],'all');

ours_response = response_summary(tg,delta_ours,omega_ours,pe_ours,v4_ours);
psat_response = response_summary(tg,delta_psat,omega_psat,pe_psat,v4_psat);

write_case_summary(c,fullfile(output_dir,'table_ieee14_case_summary.tex'));
write_bus_types(c,fullfile(output_dir,'table_ieee14_bus_types.tex'));
write_bus_data(c,fullfile(output_dir,'table_ieee14_bus_data.tex'));
write_bus_parameters(c,fullfile(output_dir,'table_ieee14_bus_parameters.tex'));
write_generator_data(c,fullfile(output_dir,'table_ieee14_generator_data.tex'));
write_branch_data(c,fullfile(output_dir,'table_ieee14_branch_data.tex'));
write_gencost_data(c,fullfile(output_dir,'table_ieee14_gencost_data.tex'));
write_machine_data(c,fullfile(output_dir,'table_ieee14_machine_data.tex'));
write_scenario(scenario,fullfile(output_dir,'table_ieee14_scenario_ours_psat.tex'));
write_pf(bus_ours,vm_ours,va_ours,vm_psat,va_psat, ...
    fullfile(output_dir,'table_ieee14_pf_ours_psat.tex'));
write_sssa(lam_ours,lam_psat, ...
    fullfile(output_dir,'table_ieee14_sssa_ours_psat.tex'));
write_ts(ts_ours,psat,ours_response,psat_response,metrics, ...
    fullfile(output_dir,'table_ieee14_ts_ours_psat.tex'));

figure_paths = struct( ...
    'network',fullfile(output_dir,'ieee14_network.png'), ...
    'pf_solution',fullfile(output_dir,'ieee14_pf_ours_psat.png'), ...
    'pf_error',fullfile(output_dir,'ieee14_pf_error_ours_psat.png'), ...
    'sssa_complex',fullfile(output_dir,'ieee14_sssa_complex_ours_psat.png'), ...
    'sssa_modes',fullfile(output_dir,'ieee14_sssa_modes_ours_psat.png'), ...
    'ts_angle',fullfile(output_dir,'ieee14_ts_angle_ours_psat.png'), ...
    'ts_omega',fullfile(output_dir,'ieee14_ts_omega_ours_psat.png'), ...
    'ts_pe',fullfile(output_dir,'ieee14_ts_pe_ours_psat.png'), ...
    'ts_voltage',fullfile(output_dir,'ieee14_ts_voltage_ours_psat.png'));
plot_network(c,scenario,figure_paths.network);
plot_pf_solution(bus_ours,vm_ours,va_ours,vm_psat,va_psat, ...
    figure_paths.pf_solution);
plot_pf_error(bus_ours,vm_ours,va_ours,vm_psat,va_psat, ...
    figure_paths.pf_error);
plot_sssa_complex(lam_ours,lam_psat,figure_paths.sssa_complex);
plot_sssa_modes(lam_ours,lam_psat,figure_paths.sssa_modes);
plot_ts_generator_pairs(tg,delta_ours,delta_psat,gen_ours,scenario, ...
    'Rotor angle \delta_i (deg)', ...
    'IEEE14 Absolute Rotor Angles: Our vs PSAT',figure_paths.ts_angle);
plot_ts_generator_pairs(tg,omega_ours,omega_psat,gen_ours,scenario, ...
    'Rotor speed \omega_i (pu)', ...
    'IEEE14 Absolute Rotor Speeds: Our vs PSAT',figure_paths.ts_omega);
plot_ts_generator_pairs(tg,pe_ours,pe_psat,gen_ours,scenario, ...
    'Electrical power P_e (MW)', ...
    'IEEE14 Generator Electrical Power: Our vs PSAT',figure_paths.ts_pe);
plot_ts_voltage(tg,v4_ours,v4_psat,min(ts_ours.Vbus,[],2), ...
    min(interp_no_extrapolate(psat.t,psat.Vbus,tg),[],2), ...
    scenario,figure_paths.ts_voltage);

out = struct('fresh',true,'generated_at',datestr(now,31), ...
    'scenario',scenario,'case_data',c, ...
    'ours',struct('pf',pf_ours,'sssa',sssa_ours,'ts',ts_ours), ...
    'psat',psat,'metrics',metrics,'figure_paths',figure_paths, ...
    'output_dir',output_dir);

fprintf(['Fresh IEEE14 Our/PSAT report data: PF dV=%.3e pu, dAng=%.3e deg; ' ...
    'SSSA dLambda=%.3e; TS dDelta=%.4g deg, dOmega=%.3e pu, ' ...
    'dPe=%.4g MW, dV4=%.3e pu\n'], ...
    metrics.pf_max_dV_pu,metrics.pf_max_dangle_deg, ...
    metrics.sssa_max_dlambda,metrics.ts_max_ddelta_deg, ...
    metrics.ts_max_domega_pu,metrics.ts_max_dpe_MW,metrics.ts_max_dv4_pu);
end

function c = attach_classical_machines(c)
if isfield(c,'machines') && ~isempty(c.machines), return; end
gbus = unique(c.mpc.gen(c.mpc.gen(:,8)~=0,1));
units = struct('gen_id',num2cell(gbus),'bus',num2cell(gbus), ...
    'H',num2cell(5*ones(numel(gbus),1)), ...
    'D',num2cell(zeros(numel(gbus),1)), ...
    'Xdp',num2cell(0.3*ones(numel(gbus),1)), ...
    'is_sync_condenser',num2cell(false(numel(gbus),1)));
c.machines = struct('units',units);
c.dynamic_assumptions = struct('source', ...
    'ASSUMED_DIAGNOSTIC: H=5 s, D=0, Xdp=0.3 pu');
end

function lam = positive_relative_modes(values)
lam = values(:);
lam = lam(isfinite(real(lam)) & isfinite(imag(lam)) & imag(lam)>1e-3);
[~,order] = sort(imag(lam),'descend');
lam = lam(order);
end

function s = response_summary(t,delta,omega,pe,vfault)
s = struct();
s.t_end = t(end);
s.n_points = numel(t);
s.max_abs_angle_deg = max(abs(delta),[],'all');
s.max_abs_speed_pu = max(abs(omega),[],'all');
s.max_abs_pe_MW = max(abs(pe),[],'all');
s.min_fault_voltage_pu = min(vfault);
end

function plot_network(c,scenario,path_out)
% Detailed single-line schematic generated from the same case used by both
% solvers. Fixed coordinates affect presentation only; every connection,
% generator marker, load marker and transformer marker is data-driven.
standard_xy = [ ...
    0.8 3.0; 2.1 0.8; 5.8 0.8; 5.8 3.1; 2.6 2.5; ...
    3.3 3.7; 5.7 3.9; 6.8 4.0; 5.6 4.7; 4.7 4.9; ...
    4.3 5.6; 2.5 6.2; 3.4 6.9; 5.2 6.2];
bus_ids = c.mpc.bus(:,1);
[mapped,bus_index] = ismember(bus_ids,(1:14)');
if ~all(mapped)
    error('generate_padiyar_ieee14_psat_tables:networkLayout', ...
        'The report schematic requires the standard IEEE14 bus IDs 1--14.');
end
xy = standard_xy(bus_index,:);
f = report_figure('IEEE14 single-line diagram',1250,820);
ax = axes(f); hold(ax,'on'); box(ax,'off'); axis(ax,'equal'); axis(ax,'off');
branch = c.mpc.branch;
for k=1:size(branch,1)
    if size(branch,2)>=11 && branch(k,11)==0, continue; end
    i = find(bus_ids==branch(k,1),1);
    j = find(bus_ids==branch(k,2),1);
    is_transformer = size(branch,2)>=9 && branch(k,9)~=0;
    route=single_line_route(branch(k,1),branch(k,2),xy(i,:),xy(j,:));
    draw_single_line_branch(ax,route,is_transformer);
end

generator_offset=zeros(14,2);
generator_offset(1,:)=[-.85 0];
generator_offset(2,:)=[0 -.80];
generator_offset(3,:)=[0 -.80];
generator_offset(6,:)=[-.80 0];
generator_offset(8,:)=[.85 0];
gen_bus = [c.machines.units.bus]';
for k=1:numel(gen_bus)
    idx=find(bus_ids==gen_bus(k),1);
    draw_generator_symbol(ax,xy(idx,:),generator_offset(gen_bus(k),:));
end

load_direction=zeros(14,2);
load_direction(2,:)=[-.7 -.7]; load_direction(3,:)=[.7 -.7];
load_direction(4,:)=[0 -1]; load_direction(5,:)=[0 -1];
load_direction(6,:)=[0 -1]; load_direction(9,:)=[0 -1];
load_direction(10,:)=[0 -1]; load_direction(11,:)=[0 1];
load_direction(12,:)=[0 -1]; load_direction(13,:)=[0 1];
load_direction(14,:)=[0 1];
load_idx = find(c.mpc.bus(:,3)~=0 | c.mpc.bus(:,4)~=0);
for k=1:numel(load_idx)
    b=bus_ids(load_idx(k));
    direction=load_direction(b,:);
    if norm(direction)==0, direction=[0 -1]; end
    draw_load_arrow(ax,xy(load_idx(k),:),direction);
end

label_offset=repmat([.12 .25],14,1);
label_offset(1,:)=[.08 -.32]; label_offset(2,:)=[.12 .24];
label_offset(3,:)=[.12 .24]; label_offset(4,:)=[-.82 -.34];
label_offset(6,:)=[.12 -.32]; label_offset(7,:)=[.12 -.38];
label_offset(8,:)=[-.55 .25]; label_offset(9,:)=[.12 .24];
for k=1:numel(bus_ids)
    plot(ax,xy(k,1)+[-.24 .24],xy(k,2)*[1 1],'-k','LineWidth',4.0, ...
        'HandleVisibility','off');
    scatter(ax,xy(k,1),xy(k,2),38,'s','filled', ...
        'MarkerFaceColor',[.93 .12 .09],'MarkerEdgeColor',[.93 .12 .09], ...
        'HandleVisibility','off');
    text(ax,xy(k,1)+label_offset(bus_ids(k),1), ...
        xy(k,2)+label_offset(bus_ids(k),2),sprintf('Bus %g',bus_ids(k)), ...
        'FontSize',11,'Color','k','FontWeight','normal');
end

fault_idx = find(bus_ids==scenario.fault_bus,1);
scatter(ax,xy(fault_idx,1),xy(fault_idx,2),220,'d','LineWidth',2.2, ...
    'MarkerEdgeColor',[.82 .05 .05],'MarkerFaceColor','none', ...
    'HandleVisibility','off');
text(ax,xy(fault_idx,1)+.36,xy(fault_idx,2)-.58,'Fault at bus 4', ...
    'Color',[.72 .08 .08],'FontWeight','bold','FontSize',10);
xlim(ax,[-.62 8.10]); ylim(ax,[-.58 7.78]);
exportgraphics(f,path_out,'Resolution',220); close(f);
end

function route=single_line_route(from_bus,to_bus,p1,p2)
lo=min(from_bus,to_bus); hi=max(from_bus,to_bus);
key=sprintf('%d-%d',lo,hi);
switch key
    case '1-2',   route=[p1;1.25 2.25;1.70 1.25;p2];
    case '1-5',   route=[p1;1.45 3.00;1.45 2.70;p2];
    case '2-3',   route=[p1;p2];
    case '2-4',   route=[p1;3.25 .80;4.60 2.20;p2];
    case '2-5',   route=[p1;2.10 1.70;2.60 1.70;p2];
    case '3-4',   route=[p1;p2];
    case '4-5',   route=[p1;4.70 2.70;3.60 2.40;p2];
    case '4-7',   route=[p1;5.75 3.45;p2];
    case '4-9',   route=[p1;5.95 3.75;5.60 4.25;p2];
    case '5-6',   route=[p1;2.90 3.00;p2];
    case '6-11',  route=[p1;3.75 4.20;3.75 5.10;p2];
    case '6-12',  route=[p1;2.90 4.50;2.50 5.20;p2];
    case '6-13',  route=[p1;3.40 5.10;p2];
    case '7-8',   route=[p1;p2];
    case '7-9',   route=[p1;p2];
    case '9-10',  route=[p1;p2];
    case '9-14',  route=[p1;5.65 5.50;p2];
    case '10-11', route=[p1;4.30 5.15;p2];
    case '12-13', route=[p1;2.50 6.65;3.40 6.65;p2];
    case '13-14', route=[p1;4.20 6.90;4.20 6.30;p2];
    otherwise,    route=[p1;p2];
end
if from_bus>to_bus, route=flipud(route); end
end

function draw_single_line_branch(ax,route,is_transformer)
blue=[.02 .22 .92];
plot(ax,route(:,1),route(:,2),'-','Color',blue,'LineWidth',2.25, ...
    'HandleVisibility','off');
if ~is_transformer, return; end
segment_length=sqrt(sum(diff(route,1,1).^2,2));
[~,idx]=max(segment_length);
p1=route(idx,:); p2=route(idx+1,:); direction=p2-p1;
L=norm(direction); unit=direction/L; normal=[-unit(2) unit(1)];
centre=(p1+p2)/2; half_gap=min(.22,.28*L);
gap=[centre-half_gap*unit;centre+half_gap*unit];
plot(ax,gap(:,1),gap(:,2),'-w','LineWidth',5.5,'HandleVisibility','off');
s=linspace(-half_gap,half_gap,100)';
wave=centre+s.*unit+.075*sin(4*pi*(s+half_gap)/(2*half_gap)).*normal;
plot(ax,wave(:,1),wave(:,2),'-','Color',blue,'LineWidth',2.0, ...
    'HandleVisibility','off');
end

function draw_generator_symbol(ax,bus_xy,offset)
black=[.02 .02 .02]; blue=[.02 .22 .92]; radius=.28;
direction=offset/norm(offset); centre=bus_xy+offset;
lead_end=centre-direction*radius;
plot(ax,[bus_xy(1) lead_end(1)],[bus_xy(2) lead_end(2)],'-', ...
    'Color',blue,'LineWidth',2.25,'HandleVisibility','off');
t=linspace(0,2*pi,160);
fill(ax,centre(1)+radius*cos(t),centre(2)+radius*sin(t),'w', ...
    'EdgeColor',black,'LineWidth',2.0,'HandleVisibility','off');
x=linspace(-.18,.18,100);
y=.075*sin(2*pi*x/.24);
plot(ax,centre(1)+x,centre(2)+y,'-','Color',black,'LineWidth',1.6, ...
    'HandleVisibility','off');
end

function draw_load_arrow(ax,bus_xy,direction)
direction=direction/norm(direction);
start=bus_xy+.10*direction; delta=.48*direction;
quiver(ax,start(1),start(2),delta(1),delta(2),0,'Color','k', ...
    'LineWidth',1.8,'MaxHeadSize',.55,'HandleVisibility','off');
end

function plot_pf_solution(bus,vo,ao,vp,ap,path_out)
f = report_figure('IEEE14 PF solution',1120,620);
tiledlayout(f,2,1,'Padding','compact','TileSpacing','compact');
nexttile; hold on; grid on; box on;
plot(bus,vo,'-o','Color',[.04 .36 .67],'LineWidth',1.7, ...
    'MarkerSize',5,'DisplayName','Our');
plot(bus,vp,'--s','Color',[.85 .33 .10],'LineWidth',1.25, ...
    'MarkerSize',4,'DisplayName','PSAT');
yline(1,'k:','HandleVisibility','off'); ylabel('|V| (pu)');
title('Solved Bus-Voltage Magnitudes'); legend('Location','best');
nexttile; hold on; grid on; box on;
plot(bus,ao,'-o','Color',[.04 .36 .67],'LineWidth',1.7, ...
    'MarkerSize',5,'DisplayName','Our');
plot(bus,ap,'--s','Color',[.85 .33 .10],'LineWidth',1.25, ...
    'MarkerSize',4,'DisplayName','PSAT');
xlabel('Bus'); ylabel('Voltage angle (deg)'); xticks(bus);
title('Solved Bus-Voltage Angles'); legend('Location','best');
sgtitle('Fresh IEEE14 Power Flow: Our vs PSAT','FontWeight','bold');
exportgraphics(f,path_out,'Resolution',200); close(f);
end

function plot_pf_error(bus,vo,ao,vp,ap,path_out)
dv=max(abs(vp-vo),1e-18); da=max(abs(ap-ao),1e-18);
f = report_figure('IEEE14 PF error',1120,440);
tiledlayout(f,1,2,'Padding','compact','TileSpacing','compact');
nexttile; semilogy(bus,dv,'-o','Color',[.04 .36 .67], ...
    'LineWidth',1.6,'MarkerFaceColor',[.04 .36 .67]); grid on; box on;
xlabel('Bus'); ylabel('Absolute voltage difference (pu)'); xticks(bus);
title(sprintf('Magnitude (max %.2e pu)',max(abs(vp-vo))));
nexttile; semilogy(bus,da,'-o','Color',[.85 .33 .10], ...
    'LineWidth',1.6,'MarkerFaceColor',[.85 .33 .10]); grid on; box on;
xlabel('Bus'); ylabel('Absolute angle difference (deg)'); xticks(bus);
title(sprintf('Angle (max %.2e deg)',max(abs(ap-ao))));
sgtitle('Fresh IEEE14 Power-Flow Differences: PSAT - Our', ...
    'FontWeight','bold');
exportgraphics(f,path_out,'Resolution',200); close(f);
end

function plot_sssa_complex(lo,lp,path_out)
% Plot exactly the positive-imaginary rows written to the SSSA table. Do
% not mirror conjugates or magnify the real axis: the raw PSAT -1e-6 shift
% remains in physical units and is quantified explicitly at right.
mode=(1:numel(lo))';
f = report_figure('IEEE14 tabulated SSSA modes',1120,540);
tiledlayout(f,1,2,'Padding','compact','TileSpacing','compact');
ax=nexttile; hold(ax,'on'); grid(ax,'on'); box(ax,'on');
scatter(ax,real(lo),imag(lo),88,'o','LineWidth',1.8, ...
    'MarkerEdgeColor',[.04 .36 .67],'DisplayName','Our');
scatter(ax,real(lp),imag(lp),82,'x','LineWidth',1.8, ...
    'MarkerEdgeColor',[.85 .33 .10],'DisplayName','PSAT');
xline(ax,0,'k:','HandleVisibility','off');
xspan=max(0.02,0.002*max(abs(imag([lo;lp]))));
xlim(ax,[-xspan xspan]);
xlabel(ax,'Real part (s^{-1})');
ylabel(ax,'Imaginary part (rad/s)');
title(ax,'Tabulated Eigenvalues (Physical Scale)','FontWeight','bold');
legend(ax,'Location','best');

ax=nexttile; bar(ax,mode,abs(lp-lo),0.58, ...
    'FaceColor',[.32 .56 .78],'EdgeColor',[.04 .36 .67]);
grid(ax,'on'); box(ax,'on'); xticks(ax,mode);
xlabel(ax,'Mode (table row)'); ylabel(ax,'|\Delta\lambda| (s^{-1})');
title(ax,'Direct Difference from Table','FontWeight','bold');
sgtitle(f,'Fresh IEEE14 SSSA: Our vs PSAT','FontWeight','bold');
exportgraphics(f,path_out,'Resolution',200); close(f);
end

function plot_sssa_modes(lo,lp,path_out)
mode=(1:numel(lo))';
fo=abs(imag(lo))/(2*pi); fp=abs(imag(lp))/(2*pi);
zo=-100*real(lo)./(abs(lo)+eps); zp=-100*real(lp)./(abs(lp)+eps);
f = report_figure('IEEE14 SSSA modal metrics',1120,470);
tiledlayout(f,1,2,'Padding','compact','TileSpacing','compact');
nexttile; bar(mode,[fo fp],'grouped'); grid on; box on;
xlabel('Mode'); ylabel('Frequency (Hz)'); title('Modal Frequency');
legend('Our','PSAT','Location','best'); xticks(mode);
nexttile; bar(mode,[zo zp],'grouped'); grid on; box on;
xlabel('Mode'); ylabel('Damping ratio (%)'); title('Modal Damping Ratio');
legend('Our','PSAT','Location','best'); xticks(mode);
sgtitle('Fresh IEEE14 SSSA Modal Comparison','FontWeight','bold');
exportgraphics(f,path_out,'Resolution',200); close(f);
end

function plot_ts_generator_pairs(t,ours,psat,gen_bus,scenario,y_label,plot_title,path_out)
if size(ours,2)~=numel(gen_bus) || ~isequal(size(ours),size(psat))
    error('generate_padiyar_ieee14_psat_tables:plotMapping', ...
        'Our/PSAT TS plot matrices do not match the generator mapping.');
end
f = report_figure(plot_title,1160,780);
tl=tiledlayout(f,3,1,'Padding','compact','TileSpacing','compact');
ax=nexttile(tl,[2 1]); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
colours=lines(numel(gen_bus)); bus_handles=gobjects(numel(gen_bus),1);
labels=compose('Bus %g',gen_bus);
marker_idx=comparison_marker_indices(t,scenario);
for k=1:numel(gen_bus)
    bus_handles(k)=plot(ax,t,ours(:,k),'-','Color',colours(k,:), ...
        'LineWidth',1.45,'DisplayName',labels{k});
    plot(ax,t(marker_idx),psat(marker_idx,k),'x','Color',colours(k,:), ...
        'LineStyle','none','MarkerSize',4.8,'LineWidth',1.0, ...
        'HandleVisibility','off');
end
our_style=plot(ax,nan,nan,'k-','LineWidth',1.45,'DisplayName','Our');
psat_style=plot(ax,nan,nan,'kx','LineStyle','none','MarkerSize',6, ...
    'LineWidth',1.1,'DisplayName','PSAT samples');
mark_fault(ax,scenario,true);
xlabel(ax,'Time (s)'); ylabel(ax,y_label); xlim(ax,[0 scenario.t_end]);
title(ax,'Absolute trajectories: Our lines with PSAT sample markers', ...
    'FontWeight','bold');
legend(ax,[bus_handles;our_style;psat_style],[labels;"Our";"PSAT samples"], ...
    'Location','best','NumColumns',2);

difference=psat-ours;
ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
for k=1:numel(gen_bus)
    plot(ax,t,difference(:,k),'-','Color',colours(k,:), ...
        'LineWidth',1.15,'HandleVisibility','off');
end
yline(ax,0,'k:','HandleVisibility','off');
mark_fault(ax,scenario,false);
xlabel(ax,'Time (s)'); ylabel(ax,['PSAT - Our: ' y_label]);
xlim(ax,[0 scenario.t_end]);
title(ax,sprintf('Direct difference (maximum absolute difference %.4g)', ...
    max(abs(difference),[],'all')),'FontWeight','bold');
sgtitle(tl,plot_title,'FontWeight','bold');
exportgraphics(f,path_out,'Resolution',190); close(f);
end

function plot_ts_voltage(t,v4o,v4p,vmino,vminp,scenario,path_out)
f = report_figure('IEEE14 voltage response',1160,780);
tl=tiledlayout(f,3,1,'Padding','compact','TileSpacing','compact');
ax=nexttile(tl,[2 1]); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
h1=plot(ax,t,v4o,'-','Color',[.04 .36 .67],'LineWidth',1.7, ...
    'DisplayName','Bus 4');
h2=plot(ax,t,vmino,'-','Color',[.82 .14 .12],'LineWidth',1.45, ...
    'DisplayName','Network minimum');
marker_idx=comparison_marker_indices(t,scenario);
plot(ax,t(marker_idx),v4p(marker_idx),'x','Color',[.04 .36 .67], ...
    'LineStyle','none','MarkerSize',4.8,'LineWidth',1.0, ...
    'HandleVisibility','off');
plot(ax,t(marker_idx),vminp(marker_idx),'x','Color',[.82 .14 .12], ...
    'LineStyle','none','MarkerSize',4.8,'LineWidth',1.0, ...
    'HandleVisibility','off');
our_style=plot(ax,nan,nan,'k-','LineWidth',1.45,'DisplayName','Our');
psat_style=plot(ax,nan,nan,'kx','LineStyle','none','MarkerSize',6, ...
    'LineWidth',1.1,'DisplayName','PSAT samples');
mark_fault(ax,scenario,true);
xlabel(ax,'Time (s)'); ylabel(ax,'Voltage magnitude (pu)');
xlim(ax,[0 scenario.t_end]); ylim(ax,[0 1.2]);
title(ax,'Absolute trajectories: Our lines with PSAT sample markers', ...
    'FontWeight','bold');
legend(ax,[h1 h2 our_style psat_style], ...
    {'Bus 4','Network minimum','Our','PSAT samples'},'Location','best');

dv4=v4p-v4o; dvmin=vminp-vmino;
ax=nexttile(tl); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
plot(ax,t,dv4,'-','Color',[.04 .36 .67],'LineWidth',1.25, ...
    'DisplayName','Bus 4');
plot(ax,t,dvmin,'-','Color',[.82 .14 .12],'LineWidth',1.15, ...
    'DisplayName','Network minimum');
yline(ax,0,'k:','HandleVisibility','off');
mark_fault(ax,scenario,false);
xlabel(ax,'Time (s)'); ylabel(ax,'PSAT - Our voltage (pu)');
xlim(ax,[0 scenario.t_end]);
title(ax,sprintf('Direct difference (maximum absolute difference %.4g pu)', ...
    max(abs([dv4;dvmin]))),'FontWeight','bold');
legend(ax,'Location','best');
sgtitle(tl,'IEEE14 Fault-Bus and Minimum Voltage: Our vs PSAT', ...
    'FontWeight','bold');
exportgraphics(f,path_out,'Resolution',190); close(f);
end

function idx = comparison_marker_indices(t,scenario)
step=max(1,round(numel(t)/45));
idx=(1:step:numel(t))';
[~,fault_idx]=min(abs(t-scenario.t_fault));
[~,clear_idx]=min(abs(t-scenario.t_clear));
idx=unique([idx;fault_idx;clear_idx;numel(t)]);
end

function mark_fault(ax,scenario,show_label)
if nargin<3, show_label=true; end
xline(ax,scenario.t_fault,'--','Color',[.68 .08 .08], ...
    'LineWidth',1.0,'HandleVisibility','off');
xline(ax,scenario.t_clear,'--','Color',[.68 .08 .08], ...
    'LineWidth',1.0,'HandleVisibility','off');
if show_label
    text(ax,.015,.965,sprintf('Fault window: %.1f-%.1f s', ...
        scenario.t_fault,scenario.t_clear),'Units','normalized', ...
        'Color',[.68 .08 .08],'FontWeight','bold', ...
        'VerticalAlignment','top');
end
end

function f = report_figure(name,width,height)
f=figure('Visible','off','Name',name,'Color','w', ...
    'Position',[70 70 width height]);
end

function write_case_summary(c,path_out)
mpc=c.mpc; bus=mpc.bus; gen=mpc.gen; branch=mpc.branch;
online_gen=gen(:,8)~=0;
online_branch=branch(:,11)~=0;
gen_bus=gen(online_gen,1)';
n_transformer=sum(online_branch & branch(:,9)~=0);
n_ref=sum(bus(:,2)==3); n_pv=sum(bus(:,2)==2); n_pq=sum(bus(:,2)==1);
fid=open_text(path_out); z=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%% Fresh case summary derived from the exact IEEE14 case used by both solvers.\n');
fprintf(fid,'\\begin{tabular}{lll}\\toprule\n');
fprintf(fid,'Item & Value & Contract note \\\\ \\midrule\n');
fprintf(fid,'Case & {MATPOWER 6.0 IEEE 14-bus} & Converted from the supplied case14.m \\\\ \n');
fprintf(fid,'Power base & %.0f MVA & MATPOWER mpc.baseMVA \\\\ \n',mpc.baseMVA);
fprintf(fid,'Nominal frequency & %.0f Hz & Project dynamic base \\\\ \n',c.base_values.frequency_Hz);
fprintf(fid,'Bus rows & %d & %d REF, %d PV, %d PQ \\\\ \n',size(bus,1),n_ref,n_pv,n_pq);
fprintf(fid,'Online generators & %d & Buses %s \\\\ \n',sum(online_gen),vector_text(gen_bus));
fprintf(fid,'Online branches & %d & %d transformer-tap branches \\\\ \n',sum(online_branch),n_transformer);
fprintf(fid,'Total specified demand & %.1f MW, %.1f MVAr & Sum of bus Pd and Qd \\\\ \n',sum(bus(:,3)),sum(bus(:,4)));
fprintf(fid,'Nonzero shunt susceptance & %.1f MVAr & Bus 9 source Bs entry \\\\ \n',sum(bus(:,6)));
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function write_bus_types(c,path_out)
bus=c.mpc.bus; codes=[3 2 1]; labels={'REF','PV','PQ'};
fid=open_text(path_out); z=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%% Fresh bus-type assignment from the exact IEEE14 bus matrix.\n');
fprintf(fid,'\\begin{tabular}{l r l r}\\toprule\n');
fprintf(fid,'Bus type & MATPOWER code & Bus IDs & Count \\\\ \\midrule\n');
for k=1:numel(codes)
    ids=bus(bus(:,2)==codes(k),1)';
    fprintf(fid,'%s & %d & {%s} & %d \\\\ \n', ...
        labels{k},codes(k),vector_text(ids),numel(ids));
end
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function write_bus_data(c,path_out)
mpc = c.mpc;
bus = mpc.bus;
gen = mpc.gen(mpc.gen(:,8)~=0,:);
Pg = zeros(size(bus,1),1); Qg = Pg;
for k=1:size(gen,1)
    idx = find(bus(:,1)==gen(k,1),1);
    Pg(idx)=Pg(idx)+gen(k,2); Qg(idx)=Qg(idx)+gen(k,3);
end
types = {'PQ','PV','REF'};
fid = open_text(path_out); z=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%% Fresh source-data table generated in the same invocation as the IEEE14 simulations.\n');
fprintf(fid,'\\begin{tabular}{r l r r r r r r}\\toprule\n');
fprintf(fid,'Bus & Type & {$|V|_{src}$} & {$\\theta_{src}$} & {$P_L$} & {$Q_L$} & {$P_G$} & {$Q_G$} \\\\\n');
fprintf(fid,'{} & {} & {(pu)} & {(deg)} & {(MW)} & {(MVAr)} & {(MW)} & {(MVAr)} \\\\ \\midrule\n');
for k=1:size(bus,1)
    fprintf(fid,'%g & %s & %.4f & %.4f & %.2f & %.2f & %.2f & %.2f \\\\\n', ...
        bus(k,1),types{bus(k,2)},bus(k,8),bus(k,9), ...
        bus(k,3),bus(k,4),Pg(k),Qg(k));
end
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function write_bus_parameters(c,path_out)
bus=c.mpc.bus; types={'PQ','PV','REF'};
fid=open_text(path_out); z=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%% Fresh MATPOWER bus-matrix fields from the case used in this invocation.\n');
fprintf(fid,'\\begin{tabular}{r l r r r r r r r r r r r}\\toprule\n');
fprintf(fid,'Bus & Type & {$P_d$} & {$Q_d$} & {$G_s$} & {$B_s$} & Area & {$V_m$} & {$V_a$} & {baseKV} & Zone & {$V_{max}$} & {$V_{min}$} \\\\ \n');
fprintf(fid,'{} & {} & {(MW)} & {(MVAr)} & {(MW)} & {(MVAr)} & {} & {(pu)} & {(deg)} & {(kV)} & {} & {(pu)} & {(pu)} \\\\ \\midrule\n');
for k=1:size(bus,1)
    fprintf(fid,'%g & %s & %.2f & %.2f & %.2f & %.2f & %g & %.4f & %.4f & %.1f & %g & %.2f & %.2f \\\\ \n', ...
        bus(k,1),types{bus(k,2)},bus(k,3),bus(k,4),bus(k,5),bus(k,6), ...
        bus(k,7),bus(k,8),bus(k,9),bus(k,10),bus(k,11),bus(k,12),bus(k,13));
end
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function write_generator_data(c,path_out)
gen=c.mpc.gen; online=find(gen(:,8)~=0);
fid=open_text(path_out); z=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%% Fresh MATPOWER online-generator fields from the case used in this invocation.\n');
fprintf(fid,'\\begin{tabular}{r r r r r r r r r r r}\\toprule\n');
fprintf(fid,'Gen & Bus & {$P_g$} & {$Q_g$} & {$Q_{max}$} & {$Q_{min}$} & {$V_g$} & {mBase} & Status & {$P_{max}$} & {$P_{min}$} \\\\ \n');
fprintf(fid,'{} & {} & {(MW)} & {(MVAr)} & {(MVAr)} & {(MVAr)} & {(pu)} & {(MVA)} & {} & {(MW)} & {(MW)} \\\\ \\midrule\n');
for j=1:numel(online)
    k=online(j);
    fprintf(fid,'%d & %g & %.2f & %.2f & %.2f & %.2f & %.4f & %.1f & %g & %.2f & %.2f \\\\ \n', ...
        j,gen(k,1),gen(k,2),gen(k,3),gen(k,4),gen(k,5),gen(k,6), ...
        gen(k,7),gen(k,8),gen(k,9),gen(k,10));
end
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function write_branch_data(c,path_out)
br=c.mpc.branch;
fid=open_text(path_out); z=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%% Fresh MATPOWER branch-matrix fields from the case used in this invocation.\n');
fprintf(fid,'\\begin{tabular}{r r r r r r r r r r r r r}\\toprule\n');
fprintf(fid,'From & To & {$r$} & {$x$} & {$b$} & {rateA} & {rateB} & {rateC} & {ratio} & {shift} & Status & {$\\theta_{min}$} & {$\\theta_{max}$} \\\\ \n');
fprintf(fid,'{} & {} & {(pu)} & {(pu)} & {(pu)} & {(MVA)} & {(MVA)} & {(MVA)} & {(pu)} & {(deg)} & {} & {(deg)} & {(deg)} \\\\ \\midrule\n');
for k=1:size(br,1)
    fprintf(fid,'%g & %g & %.5f & %.5f & %.4f & %.0f & %.0f & %.0f & %.3f & %.1f & %g & %.0f & %.0f \\\\ \n', ...
        br(k,1),br(k,2),br(k,3),br(k,4),br(k,5),br(k,6),br(k,7), ...
        br(k,8),br(k,9),br(k,10),br(k,11),br(k,12),br(k,13));
end
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function write_gencost_data(c,path_out)
cost=c.mpc.gencost; gen=c.mpc.gen;
fid=open_text(path_out); z=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%% Fresh MATPOWER polynomial generation-cost rows from the same case.\n');
fprintf(fid,'\\begin{tabular}{r r r r r r r r r}\\toprule\n');
fprintf(fid,'Gen & Bus & Model & Startup & Shutdown & {$N$} & {$c_2$} & {$c_1$} & {$c_0$} \\\\ \\midrule\n');
for k=1:size(cost,1)
    fprintf(fid,'%d & %g & %g & %.1f & %.1f & %g & %.10g & %.10g & %.10g \\\\ \n', ...
        k,gen(k,1),cost(k,1),cost(k,2),cost(k,3),cost(k,4), ...
        cost(k,5),cost(k,6),cost(k,7));
end
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function write_machine_data(c,path_out)
u=c.machines.units;
fid=open_text(path_out); z=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%% Fresh dynamic-machine contract applied identically to Our and PSAT.\n');
fprintf(fid,'\\begin{tabular}{r r r r r l}\\toprule\n');
fprintf(fid,'Machine & Bus & {$H$ (s)} & {$D$ (pu)} & {$X''_d$ (pu)} & Provenance \\\\ \\midrule\n');
for k=1:numel(u)
    fprintf(fid,'%d & %g & %.2f & %.2f & %.3f & {ASSUMED\\_DIAGNOSTIC} \\\\ \n', ...
        k,u(k).bus,u(k).H,u(k).D,u(k).Xdp);
end
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function write_scenario(sc,path_out)
fid = open_text(path_out); z=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%% Fresh identical-input contract for Our and PSAT.\n');
fprintf(fid,'\\begin{tabular}{lcc}\\toprule\n');
fprintf(fid,'Input & Our & PSAT \\\\ \\midrule\n');
fprintf(fid,'Network & MATPOWER 6 IEEE14 & Converted from the same case \\\\\n');
fprintf(fid,'Generator buses & {[1,2,3,6,8]} & {[1,2,3,6,8]} \\\\\n');
fprintf(fid,'Classical dynamics $(H,D,X''_d)$ & $(5,0,0.3)$ & $(5,0,0.3)$ \\\\\n');
fprintf(fid,'Fault bus & %g & %g \\\\\n',sc.fault_bus,sc.fault_bus);
fprintf(fid,'Fault impedance $Z_f$ (pu) & {$j10^{-4}$} & {$j10^{-4}$} \\\\\n');
fprintf(fid,'Fault interval (s) & %.1f--%.1f & %.1f--%.1f \\\\\n', ...
    sc.t_fault,sc.t_clear,sc.t_fault,sc.t_clear);
fprintf(fid,'Simulation horizon (s) & %.0f & %.0f \\\\\n',sc.t_end,sc.t_end);
fprintf(fid,'Nominal step (s) & %.2f & %.2f \\\\\n',sc.dt,sc.dt);
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function write_pf(bus,vo,ao,vp,ap,path_out)
fid = open_text(path_out); z=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%% Fresh Our and PSAT PF results; no saved result was read.\n');
fprintf(fid,'\\begin{tabular}{r rr rr rr}\\toprule\n');
fprintf(fid,'& \\multicolumn{2}{c}{Our} & \\multicolumn{2}{c}{PSAT} & \\multicolumn{2}{c}{Absolute difference} \\\\ \n');
fprintf(fid,'Bus & {$|V|$} & {$\\theta$} & {$|V|$} & {$\\theta$} & {$|\\Delta V|$} & {$|\\Delta\\theta|$} \\\\ \n');
fprintf(fid,'{} & {(pu)} & {(deg)} & {(pu)} & {(deg)} & {(pu)} & {(deg)} \\\\ \\midrule\n');
for k=1:numel(bus)
    fprintf(fid,'%g & %.6f & %.6f & %.6f & %.6f & %.2e & %.2e \\\\\n', ...
        bus(k),vo(k),ao(k),vp(k),ap(k),abs(vo(k)-vp(k)),abs(ao(k)-ap(k)));
end
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function write_sssa(lo,lp,path_out)
fid = open_text(path_out); z=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%% Fresh Our and raw PSAT SSSA modes; common-angle zero modes excluded a priori.\n');
fprintf(fid,'\\begin{tabular}{r cc r rr rr}\\toprule\n');
fprintf(fid,'Mode & {$\\lambda_{Our}$} & {$\\lambda_{PSAT}$} & {$|\\Delta\\lambda|$} & {$f_{Our}$} & {$f_{PSAT}$} & {$\\zeta_{Our}$} & {$\\zeta_{PSAT}$} \\\\ \n');
fprintf(fid,'{} & {(s$^{-1}$)} & {(s$^{-1}$)} & {(s$^{-1}$)} & {(Hz)} & {(Hz)} & {(\\%%)} & {(\\%%)} \\\\ \\midrule\n');
for k=1:numel(lo)
    fprintf(fid,'%d & {$%s$} & {$%s$} & %.3e & %.5f & %.5f & %.5f & %.5f \\\\\n', ...
        k,complex_text(lo(k)),complex_text(lp(k)),abs(lo(k)-lp(k)), ...
        abs(imag(lo(k)))/(2*pi),abs(imag(lp(k)))/(2*pi), ...
        -100*real(lo(k))/(abs(lo(k))+eps),-100*real(lp(k))/(abs(lp(k))+eps));
end
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function write_ts(ours,psat,so,sp,m,path_out)
fid = open_text(path_out); z=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%% Fresh Our and PSAT TS results on the declared scenario.\n');
fprintf(fid,'\\begin{tabular}{llrr}\\toprule\n');
fprintf(fid,'Metric & Unit & Our & PSAT \\\\ \\midrule\n');
fprintf(fid,'Completed to 15 s & -- & Yes & Yes \\\\\n');
fprintf(fid,'Raw time points & points & %d & %d \\\\\n',so.n_points,psat.td_points);
fprintf(fid,'Non-converged steps & steps & %d & {Not exposed} \\\\\n',ours.nonconverged_step_count);
fprintf(fid,'Minimum fault-bus voltage & pu & %.6f & %.6f \\\\\n',so.min_fault_voltage_pu,sp.min_fault_voltage_pu);
fprintf(fid,'Maximum stored rotor-angle magnitude & deg & %.6f & %.6f \\\\\n',so.max_abs_angle_deg,sp.max_abs_angle_deg);
fprintf(fid,'Maximum stored rotor-speed magnitude & pu & %.9f & %.9f \\\\\n',so.max_abs_speed_pu,sp.max_abs_speed_pu);
fprintf(fid,'Maximum absolute electrical power & MW & %.6f & %.6f \\\\ \\midrule\n',so.max_abs_pe_MW,sp.max_abs_pe_MW);
fprintf(fid,'Maximum PSAT--Our rotor-angle difference & deg & {Reference} & %.6e \\\\\n',m.ts_max_ddelta_deg);
fprintf(fid,'Maximum PSAT--Our rotor-speed difference & pu & {Reference} & %.6e \\\\\n',m.ts_max_domega_pu);
fprintf(fid,'Maximum PSAT--Our electrical-power difference & MW & {Reference} & %.6e \\\\\n',m.ts_max_dpe_MW);
fprintf(fid,'Maximum PSAT--Our bus-4 voltage difference & pu & {Reference} & %.6e \\\\\n',m.ts_max_dv4_pu);
fprintf(fid,'\\bottomrule\\end{tabular}\n');
end

function s = complex_text(v)
if abs(imag(v)) < 1e-10
    s = sprintf('%.6f',real(v));
else
    s = sprintf('%.6f%+.6fj',real(v),imag(v));
end
end

function s = vector_text(v)
parts=arrayfun(@(x) sprintf('%g',x),v(:)','UniformOutput',false);
s=['[' strjoin(parts,',') ']'];
end

function fid = open_text(path_out)
fid = fopen(path_out,'w');
if fid < 0
    error('generate_padiyar_ieee14_psat_tables:write', ...
        'Cannot write generated table %s.',path_out);
end
end
