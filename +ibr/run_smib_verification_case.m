function result = run_smib_verification_case(case_data,opt)
%RUN_SMIB_VERIFICATION_CASE  Execute one selected converter/SMIB diagnostic.
%   The production device f/current_injection closures are used unchanged.
%   PF here means the source-frozen phasor equilibrium identity, not a
%   multi-bus Newton PF. SSSA and TDS are independent ASSUMED_DIAGNOSTIC
%   falsification oracles and never feed a production state or parameter.

if ~isstruct(case_data) || ~isfield(case_data,'smib_verification')
    error('ibr:run_smib_verification_case:badCase', ...
        'case_data must contain smib_verification metadata.');
end
if nargin < 2, opt = struct(); end
kind = lower(char(case_data.smib_verification.kind));
product = lower(char(option_value(opt,'ibr_analysis','full')));
if ~ismember(product,{'pf','sssa','ts','full'})
    error('ibr:run_smib_verification_case:badProduct', ...
        'SMIB product must be pf, sssa, ts, or full.');
end

c = build_fixture(case_data);
y = [real(c.V);imag(c.V)];
f0 = c.dev.f(0,c.x,y,c.u,struct());
I = c.dev.current_injection(0,c.x,y,c.u,struct());
g0c = I-(c.V-c.V_inf)/c.Z;
g0 = [real(g0c);imag(g0c)];
S_terminal = c.V*conj(I);
S_infinite = c.V_inf*conj(I);
S_loss = S_terminal-S_infinite;

pf = struct( ...
    'classification','ASSUMED_DIAGNOSTIC_SMIB_PF_EQUILIBRIUM', ...
    'converged',all(isfinite([f0(:);g0(:)])) && ...
        norm(f0,inf)<1e-9 && norm(g0,inf)<1e-9, ...
    'device_id',char(c.dev.device_id),'device_type',char(c.dev.device_type), ...
    'V_terminal',c.V,'V_infinite_bus',c.V_inf,'Z_line',c.Z, ...
    'I_terminal',I,'S_terminal',S_terminal, ...
    'S_infinite_bus_received',S_infinite,'S_line_loss',S_loss, ...
    'P_requested_pu',c.P,'Q_requested_pu',c.Q, ...
    'power_identity_error',abs(S_terminal-(c.P+1i*c.Q)), ...
    'f_residual_inf',norm(f0,inf),'g_residual_inf',norm(g0,inf), ...
    'base_values',case_data.base_values);

equilibrium = struct('converged',pf.converged,'x0',c.x,'y0',y, ...
    'u_eq',c.u,'f0',f0,'g0',g0,'device',c.dev, ...
    'V_terminal',c.V,'V_inf',c.V_inf,'Z_line',c.Z, ...
    'classification','SOURCE_FROZEN_SMIB_EQUILIBRIUM');

sssa = [];
if ismember(product,{'sssa','ts','full'})
    sssa = ibr.smib_sssa_oracle(c.dev,c.x,c.V,c.u,c.V_inf,c.Z);
    sssa.stability_status = classify_stability(sssa.eigenvalues,1e-7);
end

tds = [];
if ismember(product,{'sssa','ts','full'})
    T = option_value(opt,'t_end',0.05);
    dt = option_value(opt,'dt',1e-3);
    % The TDS horizon follows the user's t_end setting (no hard cap). The
    % former clamp (T=min(T,0.05)) was a workaround for the GFL-RMS10 PLL
    % phase-detector sign defect (+3.4e5 unstable mode) fixed 2026-07-22
    % (defect SWEEP-2026-07-21-01); the SMIB spectrum is now asymptotically
    % stable (max_real ~ -11.2) so long horizons no longer overflow. The
    % smib_tds_oracle still fails safe via its linear_overflow guard.
    perturb_state = 3;
    if strcmp(kind,'gfm_no_pll'), perturb_state = 2; end
    if strcmp(kind,'gfm_vsm_sakimoto'), perturb_state = 5; end  % omega_R swing
    tds = ibr.smib_tds_oracle(c.dev,c.x,c.V,c.u,c.V_inf,c.Z, ...
        'T',T,'dt',dt,'perturb_state',perturb_state, ...
        'perturb_amp',1e-3,'A_linear',sssa.A, ...
        'fault_on',option_value(opt,'smib_fault_on',0), ...
        'fault_clear',option_value(opt,'smib_fault_clear',0), ...
        'fault_Zf',option_value(opt,'smib_fault_Zf',0.10i), ...
        'step_on',option_value(opt,'smib_step_on',0), ...
        'step_dV',option_value(opt,'smib_step_dV',-0.10), ...
        'step_dphase_deg',option_value(opt,'smib_step_dphase_deg',20));
end

result = struct('converged',pf.converged, ...
    'ibr_analysis',product,'smib_kind',kind,'pf',pf, ...
    'equilibrium',equilibrium,'sssa',sssa,'ts',tds, ...
    'selector_log',struct('ready',true,'candidate_count',1, ...
        'source','SMIB_CASE_FIXED_SINGLE_DEVICE'), ...
    'metadata',struct('classification','ASSUMED_DIAGNOSTIC_SMIB_VERIFICATION', ...
        'device_state_count',c.dev.nx,'events','NOT_APPLICABLE'));
if ismember(product,{'ts','full'}) && ~isempty(tds)
    result.converged = result.converged && tds.newton_info_drift.all_converged;
end
result.execution_summary = struct( ...
    'pf_stage_invocations',1,'equilibrium_invocations',1, ...
    'equilibrium_newton_iterations',0, ...
    'sssa_invocations',double(~isempty(sssa)), ...
    'ts_invocations',double(~isempty(tds)), ...
    'ts_step_attempts',tds_steps(tds), ...
    'ts_accepted_steps',tds_steps(tds), ...
    'ts_newton_iterations',NaN,'event_transactions',0);

if option_value(opt,'plot_results',true)
    result.figure_files = ibr.plot_smib_verification_case(result, ...
        'visible',logical(option_value(opt,'plot_visible',true)));
end
print_summary(result);
end

function c = build_fixture(case_data)
m = case_data.smib_verification;
V=m.V_terminal; P=m.P_terminal_pu; Q=m.Q_terminal_pu; Z=m.Z_line_pu;
switch lower(char(m.kind))
    case 'gfl_rms10'
        dev=ibr.gfl_rms10_model("GFL_SMIB",1,1,1,V,struct(),P,Q);
    case 'gfm_no_pll'
        X_L=0.15; m_q=0.05; Q_ref=0; kappa=1;
        I_sys=conj((P+1i*Q)/V);
        E_internal=V+1i*X_L*(kappa*I_sys);
        V_ref=abs(E_internal)+m_q*(kappa*Q-Q_ref);
        dev=ibr.gfm_vsg_no_pll_model("GFM_SMIB",1,1,1,V,struct(),P,V_ref);
    case 'gfm_vsm_sakimoto'
        % 9-state Sakimoto VSG (no PLL/AVR/PSS); constructor solves the
        % consistent Q-V droop reference internally (u=[P_ref;Q_ref]).
        dev=ibr.gfm_vsm_sakimoto_model("GFM_VSM_SAKIMOTO",1,1,1,V,struct(),P,Q);
    case 'gfl_reduced6'
        % 6-state reduced GFL (EECON49-P4): IBR+GFL(PLL)+PQ, 2 states each.
        dev=ibr.gfl_reduced6_model("GFL_REDUCED6",1,1,1,V,struct(),P,Q);
    case 'gfm_reduced6'
        % 6-state reduced GFM VSG (EECON49-P4): IBR+VSG+GFM, 2 states each, no
        % PLL; constructor back-solves the consistent Q-V droop reference.
        dev=ibr.gfm_reduced6_model("GFM_REDUCED6",1,1,1,V,struct(),P,Q);
    otherwise
        error('ibr:run_smib_verification_case:unknownKind', ...
            'Unknown SMIB kind %s.',m.kind);
end
x=dev.equilibrium_initialize(V,P,Q,struct());
u=dev.u0;
I=dev.current_injection(0,x,[real(V);imag(V)],u,struct());
V_inf=V-Z*I;
c=struct('dev',dev,'x',x,'u',u,'V',V,'V_inf',V_inf, ...
    'Z',Z,'P',P,'Q',Q);
end

function status = classify_stability(lambda,tol)
if any(real(lambda)>tol), status='UNSTABLE';
elseif any(abs(real(lambda))<=tol), status='MARGINAL';
else, status='ASYMPTOTICALLY STABLE'; end
end

function n = tds_steps(tds)
if isempty(tds), n=0; else, n=max(0,numel(tds.tgrid)-1); end
end

function value = option_value(s,name,fallback)
if isstruct(s) && isfield(s,name) && ~isempty(s.(name)), value=s.(name);
else, value=fallback; end
end

function print_summary(r)
p=r.pf; Sbase=p.base_values.S_base_MVA;
fprintf('\n---------------- SMIB PF / EQUILIBRIUM ----------------\n');
fprintf('Device             : %s (%s)\n',p.device_id,p.device_type);
fprintf('Dynamic order      : %d states\n',r.metadata.device_state_count);
fprintf('Terminal voltage   : %.6f pu at %+.6f deg\n', ...
    abs(p.V_terminal),angle(p.V_terminal)*180/pi);
fprintf('Infinite-bus voltage: %.6f pu at %+.6f deg\n', ...
    abs(p.V_infinite_bus),angle(p.V_infinite_bus)*180/pi);
fprintf('Converter injection: P=%+.6f pu (%+.3f MW), Q=%+.6f pu (%+.3f MVAr)\n', ...
    real(p.S_terminal),real(p.S_terminal)*Sbase, ...
    imag(p.S_terminal),imag(p.S_terminal)*Sbase);
fprintf('Line loss          : P=%+.6e pu, Q=%+.6e pu\n', ...
    real(p.S_line_loss),imag(p.S_line_loss));
fprintf('Residuals          : ||f||inf=%.3e, ||g||inf=%.3e, power identity=%.3e\n', ...
    p.f_residual_inf,p.g_residual_inf,p.power_identity_error);
if ~isempty(r.sssa)
    s=r.sssa;
    fprintf('\n---------------- SMIB SSSA ----------------\n');
    fprintf('States / roots      : %d / %d\n',size(s.A,1),numel(s.eigenvalues));
    fprintf('gy rcond            : %.3e\n',s.gy_rcond);
    fprintf('Schur/direct error  : %.3e\n',s.schur_direct_relative_error);
    fprintf('Stability status    : %s\n',s.stability_status);
    fprintf('  No  State                       Real (1/s)   Imag (1/s)       f (Hz)\n');
    [V,D]=eig(s.A); %#ok<ASGLU>
    for k=1:numel(s.eigenvalues)
        [~,j]=max(abs(V(:,k)));
        name=s.state_names{s.active_state_indices(j)};
        lam=s.eigenvalues(k);
        fprintf('  %02d  %-26s %+11.3e %+11.3e %11.3e\n', ...
            k,name,real(lam),imag(lam),abs(imag(lam))/(2*pi));
    end
end
if ~isempty(r.ts)
    fprintf('\n---------------- SMIB EVENT-FREE TDS ----------------\n');
    fprintf('Samples / dt / T    : %d / %.4g s / %.4g s\n', ...
        numel(r.ts.tgrid),r.ts.dt,r.ts.T);
    fprintf('Equilibrium drift   : %.3e\n',r.ts.max_drift);
    fprintf('All Newton steps    : %d\n',r.ts.newton_info_drift.all_converged);
    fprintf('Linear overflow     : %d\n',r.ts.linear_overflow);
end
end
