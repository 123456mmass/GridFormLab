function out = run_ne39_chronology(opts)
%RUN_NE39_CHRONOLOGY chronology cache แยกจาก scenario suite โดยชัดเจน.
arguments
    opts.compositions (1,:) string = ["5sg_5ibr","1sg_9ibr"]
    opts.policies (1,:) string = ["si","enhanced"]
    opts.dt (1,1) double {mustBePositive} = .01
    opts.outdir (1,1) string = ""
    opts.reuse_completed (1,1) logical = true
    opts.initial_gfm_ids (1,:) string = strings(1,0)
    opts.max_full_evaluations (1,1) double {mustBeInteger,mustBePositive} = 6
    opts.policy_options (1,1) struct = struct()
end
out=run_ne39_scenario_suite(compositions=opts.compositions, ...
    scenarios="chronology",policies=opts.policies,dt=opts.dt, ...
    outdir=opts.outdir,reuse_completed=opts.reuse_completed, ...
    initial_gfm_ids=opts.initial_gfm_ids, ...
    max_full_evaluations=opts.max_full_evaluations,policy_options=opts.policy_options);
end
