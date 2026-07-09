function rows = probe_kundur_book_fd_plateau()
%PROBE_KUNDUR_BOOK_FD_PLATEAU Central-difference convergence diagnostic.
% This probe does not alter parameters or use Table E12.3 roots to build a
% model.  It reports the movement of physical eigenvalue families as fd_eps
% changes for the PF-preserving book-flux model.

pf_init_paths();
steps = [1e-4,3e-5,1e-5,3e-6,1e-6,3e-7];
rows = repmat(struct('h',0,'residual',0,'interarea',NaN,'local1',NaN, ...
    'local2',NaN,'max_nearest_drift',NaN,'rankA',NaN,'rankA2',NaN, ...
    'common_angle_residual',NaN),numel(steps),1);
prev = [];
for n=1:numel(steps)
    opt = struct('load_model','cc_p_cz_q','use_saturation',true,'fd_eps',steps(n));
    r = stability.kundur_ex126_book_flux_ssa('options',opt);
    lam = r.eigenvalues;
    rows(n).h = steps(n);
    rows(n).residual = r.newton_residual;
    rows(n).interarea = positive_family(lam,2.5,4.5);
    rows(n).local1 = positive_family(lam,6.3,6.95);
    rows(n).local2 = positive_family(lam,6.95,7.4);
    rows(n).rankA = rank(r.Afull,1e-6);
    rows(n).rankA2 = rank(r.Afull*r.Afull,1e-6);
    v = zeros(size(r.Afull,1),1); v(1:6:end)=1;
    rows(n).common_angle_residual = norm(r.Afull*v);
    if ~isempty(prev)
        drift = zeros(numel(lam),1);
        for k=1:numel(lam); drift(k)=min(abs(lam(k)-prev)); end
        rows(n).max_nearest_drift = max(drift);
    end
    prev = lam;
end

fprintf(' h          ||F,G||       interarea              local-1                local-2       max drift     rank(A,A2)  ||Av_angle||\n');
for n=1:numel(rows)
    q=rows(n);
    fprintf('%8.1e  %10.3e  %+.7f%+.7fi  %+.7f%+.7fi  %+.7f%+.7fi  %10.3e  (%d,%d)   %10.3e\n', ...
        q.h,q.residual,real(q.interarea),imag(q.interarea), ...
        real(q.local1),imag(q.local1),real(q.local2),imag(q.local2), ...
        q.max_nearest_drift,q.rankA,q.rankA2,q.common_angle_residual);
end
end

function z = positive_family(lam,wlo,whi)
candidates = lam(imag(lam)>0 & imag(lam)>=wlo & imag(lam)<=whi);
if numel(candidates)~=1
    error('probe_kundur_book_fd_plateau:family', ...
        'Expected exactly one positive-imaginary family root in [%.3f, %.3f].',wlo,whi);
end
z = candidates(1);
end
