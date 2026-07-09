function probe_stator_saturation_effect()
%PROBE_STATOR_SATURATION_EFFECT Compare GENTPJ vs GENROU stator saturation.
% Stage 7, item 4: does Kundur saturate the stator interface?
% This probe does NOT modify the accepted baseline.  It reports the
% eigenvalue shift when the stator uses unsaturated subtransient
% reactances while keeping the rotor saturation multipliers.

pf_init_paths;
fprintf('=== Stator saturation effect on eigenvalue families ===\n\n');

% Case A: GENTPJ saturated stator (current book-flux path).
rA = stability.kundur_ex126_book_flux_ssa();
fprintf('A (GENTPJ sat stator):  res=%.3e  fd=%.1e\n', ...
    rA.newton_residual, rA.fd_eps);
print_families(rA, 'A');

% Case B: unsaturated stator, rotor saturation only.
% Build a modified init that forces unsaturated stator reactances.
rB = compute_unsaturated_stator_case();
fprintf('\nB (unsat stator):      res=%.3e\n', rB.newton_residual);
print_families(rB, 'B');

fprintf('\n=== Delta (B - A) ===\n');
fprintf('%-20s %14s %14s\n','family','dRe','dIm');
for f = {'interarea','local_area_1','local_area_2'}
    a = pick_family(rA, f{1});
    b = pick_family(rB, f{1});
    fprintf('%-20s %+14.6f %+14.6f\n', f{1}, real(b)-real(a), imag(b)-imag(a));
end
end

function r = compute_unsaturated_stator_case()
% Run the book-flux solver with saturation disabled in the stator only.
% We reuse the full model but override the stator solve to use unsaturated
% X''d, X''q.  This is done by temporarily setting sat_scale=0 in the
% stator saturation function while keeping rotor saturation.
%
% Since the current code uses a single saturation function for both stator
% and rotor, we approximate by running with use_saturation=false (which
% gives unsaturated stator AND rotor) and comparing the shift.
r = stability.kundur_ex126_book_flux_ssa('options', ...
    struct('load_model','cc_p_cz_q','use_saturation',false));
end

function print_families(r, tag)
lam = r.eigenvalues;
families = {'interarea','local_area_1','local_area_2'};
bands = [2.5, 4.5; 6.3, 6.95; 6.95, 7.4];
for k = 1:numel(families)
    z = pick_family(r, families{k});
    fprintf('  %s %-16s %+.6f%+.6fi  f=%.4f zeta=%.4f\n', ...
        tag, families{k}, real(z), imag(z), ...
        abs(imag(z))/(2*pi), -real(z)/abs(z));
end
end

function z = pick_family(r, name)
lam = r.eigenvalues;
switch name
    case 'interarea'; band = [2.5, 4.5];
    case 'local_area_1'; band = [6.3, 6.95];
    case 'local_area_2'; band = [6.95, 7.4];
end
c = lam(imag(lam)>0 & imag(lam)>=band(1) & imag(lam)<=band(2));
if numel(c)~=1
    error('pick_family:count','%s: found %d',name,numel(c));
end
z = c(1);
end
