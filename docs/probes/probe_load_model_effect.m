function probe_load_model_effect()
%PROBE_LOAD_MODEL_EFFECT Compare CC-P/CZ-Q vs CZ-P/CZ-Q load models.
% Stage 7, item 6: does the load model explain the damping discrepancy?
% The book says CC-P, but CZ-P gives field modes closer to Table E12.3.
% This probe reports the full family comparison for both load models.

pf_init_paths;
ref = stability.kundur_e123_reference();
targets = struct( ...
    'ia',-0.111+1i*3.43, 'l1',-0.492+1i*6.82, 'l2',-0.506+1i*7.02, ...
    'f1',-0.265, 'f2',-0.276, 'q1',-3.428, 'q2',-4.139, ...
    'q3',-5.287, 'q4',-5.303);

for lm = {'cc_p_cz_q','cz_p_cz_q'}
    opt = struct('load_model',lm{1},'use_saturation',true);
    r = stability.kundur_ex126_book_flux_ssa('options',opt);
    lam = r.eigenvalues;
    fprintf('\n=== %s (res=%.3e) ===\n', lm{1}, r.newton_residual);
    print_family(lam, 'interarea', 2.5, 4.5, targets.ia);
    print_family(lam, 'local_1', 6.3, 6.95, targets.l1);
    print_family(lam, 'local_2', 6.95, 7.4, targets.l2);
    print_real(lam, 'field', -0.30, -0.15, [targets.f1, targets.f2]);
    print_real(lam, 'q_damp', -10, -1, [targets.q1, targets.q2, targets.q3, targets.q4]);
end
end

function print_family(lam, name, wlo, whi, target)
c = lam(imag(lam)>0 & imag(lam)>=wlo & imag(lam)<=whi);
if numel(c)~=1; fprintf('  %-12s: found %d roots\n',name,numel(c)); return; end
z = c(1);
fprintf('  %-12s: got=%+.5f%+.5fi  book=%+.5f%+.5fi  re_err=%5.2f%%  im_err=%5.2f%%\n', ...
    name, real(z), imag(z), real(target), imag(target), ...
    100*abs(real(z)-real(target))/abs(real(target)), ...
    100*abs(imag(z)-imag(target))/abs(imag(target)));
end

function print_real(lam, name, lo, hi, targets)
c = real(lam(abs(imag(lam))<1e-7 & real(lam)>lo & real(lam)<hi));
c = sort(c,'descend');
fprintf('  %-12s: got=[',name);
for k=1:numel(c); fprintf('%+.4f ',c(k)); end
fprintf(']  book=[');
for k=1:numel(targets); fprintf('%+.4f ',targets(k)); end
fprintf(']\n');
end
