function S = compare_kundur_psat_params()
%COMPARE_KUNDUR_PSAT_PARAMS Verify PSAT d_kundur1_mdl params/PF vs ours.

pf_init_paths;
our = cases.case_kundur_two_area_classical();
R = our.machines.reactances; T = our.machines.time_constants;
ourH = [our.machines.units.H].';            % G1..G4 by bus order 1,2,3,4
ourbus = [our.machines.units.bus].';

% --- Run PSAT d_kundur1_mdl PF ---
psat_root = 'C:/Users/User/Downloads/psat-2.1.11-mat/psat';
old=pwd; cleanup=onCleanup(@()cd(old)); addpath(genpath(psat_root)); cd(psat_root);
global Settings Path clpsat DAE Bus Syn;
command_line_psat=1; psat; clpsat.mesg=0; clpsat.readfile=1; clpsat.pq2z=1;
runpsat('d_kundur1_mdl',[Path.psat,'tests'],'data');
runpsat('pf');
psSyn = Syn.con;
[psSyn(:,1),order] = sort(psSyn(:,1));  % order by bus
psSyn = psSyn(order,:);
cd(old);

% PSAT Syn.con cols: bus Sn Vn fn model xl ra xd xdp xdpp Tdo' Tdo'' xq xqp xqpp Tqo' Tqo'' M D ...
fprintf('\n================ MACHINE PARAMETER COMPARISON (by bus) ================\n');
fprintf('%-4s | %-22s | %-22s\n','bus','OURS','PSAT');
fprintf('     | Xd Xdp Xdpp Xq Xqp Xqpp | Xd Xdp Xdpp Xq Xqp Xqpp\n');
for k=1:4
  b=ourbus(k);
  o=[R.Xd R.Xdp R.Xdpp R.Xq R.Xqp R.Xqpp];
  p=psSyn(k,[8 9 10 13 14 15]);
  fprintf('%-4d | %.3f %.3f %.3f %.3f %.3f %.3f | %.3f %.3f %.3f %.3f %.3f %.3f\n',b,o,p);
end
fprintf('\nTime constants: ours Tdo=%.2f Tdopp=%.3f Tqo=%.2f Tqopp=%.3f | PSAT Tdo=%.2f Tdopp=%.3f Tqo=%.2f Tqopp=%.3f\n', ...
  T.Tpd0,T.Tppd0,T.Tpq0,T.Tppq0, psSyn(1,11),psSyn(1,12),psSyn(1,16),psSyn(1,17));
fprintf('Ra: ours=%.4f PSAT=%.4f | Xl: ours=%.4f PSAT=%.4f\n',R.Ra,psSyn(1,7),R.Xl,psSyn(1,6));
fprintf('Sn/Vn: ours=%.0f/%.0f PSAT=%.0f/%.0f | model: ours=6 PSAT=%g\n',our.machines.base.S_MVA,our.machines.base.V_kV,psSyn(1,2),psSyn(1,3),psSyn(1,5));
fprintf('\n%-4s | H_ours | H_psat (M/2) | D_ours | D_psat\n','bus');
for k=1:4
  fprintf('%-4d | %.4f | %.4f (%.3f/2) | %.3f | %.3f\n',ourbus(k),ourH(k),psSyn(k,18)/2,psSyn(k,18),0,psSyn(k,19));
end

% --- PF comparison ---
ssa=stability.kundur_ex126_kundur_ssa('options',struct('load_model','cc_p_cz_q'));
fprintf('\n================ PF / OPERATING POINT ================\n');
fprintf('delta0 (q-axis) deg: ours=[%s]  (PSAT delta_Syn t=0 from TD)\n',num2str(rad2deg(ssa.init.x0(1:6:end)),'%.3f '));
nb=Bus.n;
fprintf('\n%-4s | Vm_ours | Vm_psat | ang_ours | ang_psat\n','bus');
omax=0; amax=0;
for k=1:nb
  b=Bus.con(k,1);
  % ours bus voltage: from SSSA init y0 (theta, V interleaved)
  voi=abs(complex(ssa.init.y0(2*k-1),ssa.init.y0(2*k)));
  aoi=angle(complex(ssa.init.y0(2*k-1),ssa.init.y0(2*k)))*180/pi;
  vps=DAE.y(nb+k); aps=DAE.y(k)*180/pi;
  omax=max(omax,abs(voi-vps)); amax=max(amax,abs(aoi-aps));
  fprintf('%-4d | %.4f | %.4f | %.4f | %.4f\n',b,voi,vps,aoi,aps);
end
fprintf('\nMax |dV|=%.4g pu  Max |dAngle|=%.4g deg\n',omax,amax);
S=struct('max_dV',omax,'max_dAngle',amax);
end
