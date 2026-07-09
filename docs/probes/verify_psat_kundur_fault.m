function verify_psat_kundur_fault()
%VERIFY_PSAT_KUNDUR_FAULT Run PSAT's built-in Kundur two-area fault case.
% This is a verification-only script. It does not replace the in-house solver.

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
psat_dir = fullfile(root, 'tools', 'PSAT', 'psat-mat', 'psat');
if ~exist(fullfile(psat_dir, 'psat.m'), 'file')
    error('PSAT not found at %s', psat_dir);
end
addpath(psat_dir);
cd(psat_dir);

% Initialize PSAT in command-line mode.
initpsat;
global Path Settings clpsat Varout DAE Syn
Settings.freq = 60;
Settings.fixt = 1;     % fixed-step trapezoidal integration
Settings.tstep = 1e-3; % match project dt
Settings.tf = 5;
clpsat.readfile = 1;
clpsat.pq2z = 1;       % convert PQ to impedance for transient simulation

% Use PSAT's original Kundur case but override fault timing to match ours
runpsat('d_kundur1_mdl', [Path.psat, 'tests'], 'data');
runpsat('pf');
% Override fault timing: match our scenario (t=0.5s, clear=0.6s)
global Fault
Fault.con(1,5) = 0.5;
Fault.con(1,6) = 0.6;
runpsat('td');

fprintf('PSAT run complete. Varout samples=%d, variables=%d\n', size(Varout.vars,1), size(Varout.vars,2));
fprintf('Final time = %.4f s\n', Varout.t(end));
fprintf('Mean terminal/algebraic values check = %.6g\n', mean(DAE.y));

% PSAT stores dynamic states first in Varout.vars. Syn.delta and Syn.omega
% are the row indices in DAE.x/Varout.vars for synchronous-machine angles
% and speeds. PSAT omega is absolute pu speed, so speed deviation is omega-1.
t = Varout.t;
delta = Varout.vars(:, Syn.delta);
omega_dev = Varout.vars(:, Syn.omega) - 1;
delta_deg_rel = rad2deg(delta - delta(:,1));

save(fullfile(root, 'docs', 'source', 'figures', 'kundur_ex126', 'psat_kundur_fault_verify.mat'), ...
    'Varout', 'DAE', 'Settings', 'Syn', 't', 'delta', 'omega_dev', 'delta_deg_rel');

fprintf('Saved PSAT verification data. Integration=%s, tstep=%.4g, tf=%.4g\n', ...
    'implicit trapezoidal', Settings.tstep, Settings.tf);
end
