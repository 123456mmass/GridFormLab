function out = generate_ieee14_switch_evidence(opts)
%GENERATE_IEEE14_SWITCH_EVIDENCE  Build every figure and table of the study.
%
%   generate_ieee14_switch_evidence()
%   generate_ieee14_switch_evidence(pages="decision")
%
% One entry point, so the whole evidence set is reproducible by a single command
% and the page list cannot drift between the report and the generator.
%
% Pages:
%   decision     three decision pages for the adaptive arm: the full 250 s
%                horizon, plus zooms on the two windows where the supervisor
%                actually commanded mode changes
%   modepq       severity, mode, reference owner and per-converter P and Q
%   electrical   the eight-panel electrical response, per arm
%   comparison   the cross-arm comparison figures, tables and macros
%
% Every page is drawn from a stored accepted trajectory produced by
% run_ieee14_gfm_lock_comparison. Nothing is simulated here.
%
% The page list is VALIDATED. A mistyped token used to select nothing and exit
% silently, which looks exactly like a successful run that produced no files.

arguments
    opts.pages (1,:) string = ["decision","modepq","electrical","comparison"]
    opts.cache_dir (1,1) string = fullfile('output','diagnostics', ...
        'ieee14_gfm_lock_compare')
    opts.figure_dir (1,1) string = fullfile('docs','source','figures', ...
        'switch_ieee14_decision')
    opts.dpi (1,1) double = 300
end

KNOWN = ["decision","modepq","electrical","comparison"];
bad = setdiff(opts.pages,KNOWN);
if ~isempty(bad)
    error('generate_ieee14_switch_evidence:unknownPage', ...
        'Unknown page token(s): %s. Known tokens: %s.', ...
        strjoin(bad,', '),strjoin(KNOWN,', '));
end

pf_init_paths();
C = char(opts.cache_dir);
F = char(opts.figure_dir);
if ~isfolder(F), mkdir(F); end

out = struct('figure_dir',F,'cache_dir',C,'pages',struct());

if any(opts.pages == "decision")
    src = fullfile(C,'adaptive_250s.mat');
    out.pages.decision_full = generate_ieee14_decision_figure( ...
        result_file=src,dpi=opts.dpi, ...
        output=fullfile(F,'decision_indices.png'));
    out.pages.decision_island = generate_ieee14_decision_figure( ...
        result_file=src,dpi=opts.dpi,window=[17 58], ...
        label_families=["disturbance","supervisor"], ...
        title_suffix=' (island formation)', ...
        output=fullfile(F,'decision_indices_zoom_island.png'));
    out.pages.decision_reclose = generate_ieee14_decision_figure( ...
        result_file=src,dpi=opts.dpi,window=[143 178], ...
        label_families=["disturbance","supervisor"], ...
        title_suffix=' (reclose and handback)', ...
        output=fullfile(F,'decision_indices_zoom_reclose.png'));
end

if any(opts.pages == "modepq")
    out.pages.modepq = generate_ieee14_mode_pq_figure( ...
        result_file=fullfile(C,'adaptive_250s.mat'),dpi=opts.dpi, ...
        output=fullfile(F,'mode_switch_PQ.png'));
end

if any(opts.pages == "electrical")
    arms = {'adaptive','Adaptive GFL/GFM switching'; ...
            'pinned_gfm1','One grid-forming unit pinned (IBR2)'};
    for k = 1:size(arms,1)
        src = fullfile(C,[arms{k,1} '_250s.mat']);
        if ~isfile(src), continue; end
        out.pages.(['electrical_' arms{k,1}]) = ...
            generate_ieee14_electrical_figure(result_file=src,dpi=opts.dpi, ...
                arm_label=arms{k,2}, ...
                output=fullfile(F,['electrical_' arms{k,1} '.png']));
    end
end

if any(opts.pages == "comparison")
    out.pages.comparison = generate_ieee14_gfm_lock_comparison( ...
        cache_dir=C,figure_dir=F,dpi=opts.dpi);
end
end
