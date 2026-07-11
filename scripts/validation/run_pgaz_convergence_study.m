function study = run_pgaz_convergence_study(case_name, scenario)
%RUN_PGAZ_CONVERGENCE_STUDY  Numerical convergence characterization of PGAz.
%   Runs PGAz with a range of corrector_iter values and timesteps (WITHOUT
%   changing physical inputs: same case, fault, Zf, model). Compares
%   successive trajectories on a common grid to determine whether PGAz's
%   fixed-iteration corrector reaches a plateau, and reports the timestep
%   convergence order. This JUSTIFIES (or refutes) using a plateau corrector
%   count for the primary PGAz validation instead of the default 3.
%
%   PGAz is a reference tool only (never a production dep). Physical inputs
%   are never tuned; only the documented runtime option corrector_iter and
%   the comparison timestep vary.
if nargin<2, scenario=struct(); end
sc = struct('fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1, ...
    'dt',0.01,'t_end',15.0);
fn = fieldnames(scenario); for k=1:numel(fn), sc.(fn{k})=scenario.(fn{k}); end
root = pf_init_paths;
addpath('/home/birds/Documents/PGAz_V1.1.1');

c = cases.(case_name)();
if ~isfield(c,'machines') || isempty(c.machines)
    gbus0 = unique(c.mpc.gen(c.mpc.gen(:,8)~=0,1));
    units = struct('gen_id',num2cell(gbus0),'bus',num2cell(gbus0), ...
        'H',num2cell(5*ones(numel(gbus0),1)),'D',num2cell(zeros(numel(gbus0),1)), ...
        'Xdp',num2cell(0.3*ones(numel(gbus0),1)), ...
        'is_sync_condenser',num2cell(false(numel(gbus0),1)));
    c.machines = struct('units',units);
end
sys = case_to_pgaz_sys(c);
H = sys.Gen(:,11).';   % inertia per gen bus (system base)
gbus = sort(sys.Gen(:,1));

% --- Corrector-iteration study (fixed dt = scenario dt) ---
ci_list = [1 2 3 5 8 12];
ci_runs = struct();
for i = 1:numel(ci_list)
    ci = ci_list(i);
    optp = struct(); optp.t_end=sc.t_end; optp.dt=sc.dt; optp.method='trapezoidal';
    optp.corrector_iter=ci; optp.make_plots=false;
    optp.fault=struct('enable',true,'bus',sc.fault_bus,'t_fault',sc.t_fault, ...
        't_clear',sc.t_clear,'Rf',real(sc.Zf),'Xf',imag(sc.Zf));
    TS = pgaz_ts(sys,1e-10,50,optp);
    [~,pg] = sort(TS.gen_bus);
    ci_runs.(sprintf('ci%d',ci)) = struct('ci',ci,'t',TS.t, ...
        'delta_deg',TS.delta_deg(:,pg),'omega',TS.omega(:,pg), ...
        'Pe_MW',TS.Pe_pu(:,pg)*TS.baseMVA,'Vm_fault',TS.Vm(:,sc.fault_bus), ...
        'gbus',TS.gen_bus(pg));
end

% Common grid = finest available (the dt grid). All ci runs use the same dt.
tg = ci_runs.ci1.t;
% Successive differences (ci_k vs ci_{k+1}) on the common grid.
ci_pairs = [1 2; 2 3; 3 5; 5 8; 8 12];
ci_diff = struct('pairs',ci_pairs,'dCOI',zeros(numel(ci_pairs),1), ...
    'domega',zeros(numel(ci_pairs),1),'dPe',zeros(numel(ci_pairs),1), ...
    'dVm',zeros(numel(ci_pairs),1));
for p = 1:size(ci_pairs,1)
    a = ci_runs.(sprintf('ci%d',ci_pairs(p,1)));
    b = ci_runs.(sprintf('ci%d',ci_pairs(p,2)));
    ra = coi_relative(a.delta_deg, a.omega, H, a.gbus);
    rb = coi_relative(b.delta_deg, b.omega, H, b.gbus);
    ci_diff.dCOI(p)  = max(abs(ra.delta_rel - rb.delta_rel),[],'all');
    ci_diff.domega(p)= max(abs(ra.omega_rel - rb.omega_rel),[],'all');
    ci_diff.dPe(p)   = max(abs(a.Pe_MW - b.Pe_MW),[],'all');
    ci_diff.dVm(p)   = max(abs(a.Vm_fault - b.Vm_fault),[],'all');
end

% Plateau criterion (declared BEFORE reading results): the trajectory has
% plateaued at ci=k if the successive difference ci_k vs ci_{k+1} is below
% PLATEAU_TOL on ALL four metrics. PLATEAU_TOL is chosen from the numerical
% scale of the swings (COI swings are ~10 deg; 0.05 deg is ~0.5%, a
% defensible plateau threshold declared a priori).
PLATEAU_TOL = struct('dCOI',0.05,'domega',1e-4,'dPe',0.1,'dVm',1e-3);
plateau_ci = NaN;
for p = 1:size(ci_pairs,1)
    if ci_diff.dCOI(p) <= PLATEAU_TOL.dCOI && ci_diff.domega(p) <= PLATEAU_TOL.domega && ...
       ci_diff.dPe(p) <= PLATEAU_TOL.dPe && ci_diff.dVm(p) <= PLATEAU_TOL.dVm
        plateau_ci = ci_pairs(p,1);   % plateau reached at this ci
        break;
    end
end

% --- Timestep study (use plateau ci if found, else ci=12) ---
ci_for_dt = plateau_ci; if isnan(ci_for_dt), ci_for_dt = 12; end
dt_list = [0.02 0.01 0.005];
dt_runs = struct();
for i = 1:numel(dt_list)
    dt = dt_list(i);
    optp = struct(); optp.t_end=sc.t_end; optp.dt=dt; optp.method='trapezoidal';
    optp.corrector_iter=ci_for_dt; optp.make_plots=false;
    optp.fault=struct('enable',true,'bus',sc.fault_bus,'t_fault',sc.t_fault, ...
        't_clear',sc.t_clear,'Rf',real(sc.Zf),'Xf',imag(sc.Zf));
    TS = pgaz_ts(sys,1e-10,50,optp);
    [~,pg] = sort(TS.gen_bus);
    dt_runs.(sprintf('dt%d',round(dt*1000))) = struct('dt',dt,'t',TS.t, ...
        'delta_deg',TS.delta_deg(:,pg),'omega',TS.omega(:,pg), ...
        'Pe_MW',TS.Pe_pu(:,pg)*TS.baseMVA,'Vm_fault',TS.Vm(:,sc.fault_bus), ...
        'gbus',TS.gen_bus(pg));
end
% Compare on the COARSE common grid (dt=0.02).
tc = dt_runs.dt20.t;
dt_pairs = [20 10; 10 5];   % dt=0.02 vs 0.01, 0.01 vs 0.005
dt_diff = struct('pairs',dt_pairs,'dCOI',zeros(numel(dt_pairs),1), ...
    'domega',zeros(numel(dt_pairs),1),'dPe',zeros(numel(dt_pairs),1),'dVm',zeros(numel(dt_pairs),1));
for p = 1:size(dt_pairs,1)
    a = dt_runs.(sprintf('dt%d',dt_pairs(p,1)));
    b = dt_runs.(sprintf('dt%d',dt_pairs(p,2)));
    % interpolate b onto a's (coarser) grid; both cover [0,t_end]
    da = interp1(a.t, a.delta_deg, a.t, 'linear');
    db = interp1(b.t, b.delta_deg, a.t, 'linear');
    oa = interp1(a.t, a.omega, a.t, 'linear');
    ob = interp1(b.t, b.omega, a.t, 'linear');
    pa = interp1(a.t, a.Pe_MW, a.t, 'linear');
    pb = interp1(b.t, b.Pe_MW, a.t, 'linear');
    va = interp1(a.t, a.Vm_fault, a.t, 'linear');
    vb = interp1(b.t, b.Vm_fault, a.t, 'linear');
    ra = coi_relative(da, oa, H, a.gbus); rb = coi_relative(db, ob, H, a.gbus);
    dt_diff.dCOI(p)   = max(abs(ra.delta_rel - rb.delta_rel),[],'all');
    dt_diff.domega(p) = max(abs(ra.omega_rel - rb.omega_rel),[],'all');
    dt_diff.dPe(p)    = max(abs(pa - pb),[],'all');
    dt_diff.dVm(p)    = max(abs(va - vb),[],'all');
end

study = struct('case',case_name,'ci_list',ci_list,'ci_diff',ci_diff, ...
    'plateau_tol',PLATEAU_TOL,'plateau_ci',plateau_ci, ...
    'ci_for_dt_study',ci_for_dt,'dt_list',dt_list,'dt_diff',dt_diff, ...
    'gbus',gbus,'H',H);

fprintf('\n=== PGAz convergence study: %s ===\n', case_name);
fprintf('Corrector-iteration study (dt=%.3f):\n', sc.dt);
fprintf('  pair    dCOI(deg)  domega     dPe(MW)   dVm\n', sc.dt);
for p=1:size(ci_pairs,1)
    fprintf('  ci%d-ci%d  %.4e  %.4e  %.4e  %.4e\n', ci_pairs(p,1),ci_pairs(p,2), ...
        ci_diff.dCOI(p),ci_diff.domega(p),ci_diff.dPe(p),ci_diff.dVm(p));
end
fprintf('  plateau_ci = %s (PLATEAU_TOL dCOI<%.3f domega<%.1e dPe<%.3f dVm<%.1e)\n', ...
    ternary(isnan(plateau_ci),'NONE (no plateau)',num2str(plateau_ci)), ...
    PLATEAU_TOL.dCOI, PLATEAU_TOL.domega, PLATEAU_TOL.dPe, PLATEAU_TOL.dVm);
fprintf('Timestep study (ci=%d):\n', ci_for_dt);
for p=1:size(dt_pairs,1)
    fprintf('  dt%.3f-dt%.3f  dCOI=%.4e  domega=%.4e  dPe=%.4e  dVm=%.4e\n', ...
        dt_list(p), dt_list(p+1), dt_diff.dCOI(p),dt_diff.domega(p),dt_diff.dPe(p),dt_diff.dVm(p));
end
end

function s = ternary(c,a,b), if c, s=a; else, s=b; end, end
