function bench_ne39_fd_y_grouping_ab()
%BENCH_NE39_FD_Y_GROUPING_AB  Option-pinned warm A/B for FD y-column grouping.
%   Same horizon, dt, tolerance and event set for both arms; the ONLY pinned
%   difference is opt.fd_y_grouping ('off' = historical per-column, 'auto' =
%   disjoint-closed-neighbourhood grouping). Correctness arm runs with the
%   in-kernel fd_structure_check oracle ON; timing arms run with it OFF so the
%   measurement is not doubled by the verification rebuild.
pf_init_paths();
s = cases.scenario_ne39_5sg_5ibr();
sc = stability.build_hybrid_scenario(s.case_data, s.resources, s.scenario_opt);

common = struct('t_end',0.5,'dt',0.004,'verbose',false,'fd_grouping','auto');
off  = common; off.fd_y_grouping  = 'off';
auto = common; auto.fd_y_grouping = 'auto';

% --- Correctness: grouped must be bit-identical to per-column ----------------
chk  = auto; chk.fd_structure_check = true;
ra   = stability.run_hybrid_case(sc, chk);   % raises if any grouped col differs
ro   = stability.run_hybrid_case(sc, off);
nsteps = size(ra.x_traj,2) - 1;
fprintf('CORRECT auto_conv=%d off_conv=%d steps=%d\n', ra.converged, ro.converged, nsteps);
fprintf('CORRECT x_maxdiff=%.3e y_maxdiff=%.3e\n', ...
    max(abs(ra.x_traj(:)-ro.x_traj(:))), max(abs(ra.y_traj(:)-ro.y_traj(:))));

% --- Timing: warm, then 3 reps each, median ---------------------------------
median_s = @(v) median(v);
rep = 5;
stability.run_hybrid_case(sc, off);    % warm
stability.run_hybrid_case(sc, auto);
t_off = zeros(1,rep); t_auto = zeros(1,rep);
for i = 1:rep
    a = tic; stability.run_hybrid_case(sc, off);  t_off(i)  = toc(a);
    a = tic; stability.run_hybrid_case(sc, auto); t_auto(i) = toc(a);
end
off_med = median_s(t_off); auto_med = median_s(t_auto);
fprintf('TIME off_med=%.3f auto_med=%.3f speedup=%.3fx simsec=%.4f\n', ...
    off_med, auto_med, off_med/auto_med, 0.5);
fprintf('TIME off_each=%s auto_each=%s\n', mat2str(round(t_off,3)), mat2str(round(t_auto,3)));
end
