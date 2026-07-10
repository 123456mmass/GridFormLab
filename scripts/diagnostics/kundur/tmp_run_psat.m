% Minimal PSAT runner - bypasses GUI
addpath('tools/PSAT/psat-mat/psat');
addpath('tools/PSAT/psat-mat/psat/tests');
global Path File Fig Settings DAE LA clpsat
% Setup paths
Path.data = pwd; Path.temp = pwd;
Path.psat = fullfile(pwd, 'tools', 'PSAT', 'psat-mat', 'psat');
Path.pert = ''; Path.rep = ''; Path.fig = '';
File.data = 'd_009_mdl.m'; File.pert = ''; File.rep = '';
Fig.dir = 0; Fig.main = 0;
Settings.freq = 60; Settings.baseMVA = 100; Settings.baseKV = 230;
Settings.rad = 2*pi*60; Settings.mva = 100; Settings.kv = 230;
clpsat.init = false; clpsat.mesg = false;
% Load data
d_009_mdl;
% Build system directly (bypass fm_set GUI)
fm_build;
% Run power flow
fm_pf;
% Build state-space
fm_abcd;
% Eigenvalues
lam = eig(LA.A);
[~,idx] = sort(real(lam),'descend'); lam = lam(idx);
fprintf('PSAT_EIG_START\n');
for k=1:min(30,numel(lam))
  if abs(imag(lam(k)))<1e-8
    fprintf('EIG %+10.4f\n', real(lam(k)));
  else
    fprintf('EIG %+10.4f %+10.4fj\n', real(lam(k)), imag(lam(k)));
  end
end
fprintf('PSAT_EIG_END\n');
