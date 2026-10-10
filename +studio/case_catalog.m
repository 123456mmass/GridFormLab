function entries = case_catalog()
%CASE_CATALOG  Studio offer list: exactly the GUI-visible production cases.
%   entries = studio.case_catalog() reads the authoritative case list from
%   cases.network_case_catalog() and FILTERS on its gui_visible display
%   field.  The catalog is never re-implemented here -- this is the display
%   layer only, a sibling of the full case resolver rather than a fork of
%   the data.  Hidden entries stay fully runnable elsewhere.
%
%   The owner's working set (2026-09-26): the starter cases are no longer
%   used; only IEEE 14 and the 39-bus are offered.  That filter already
%   lives in network_case_catalog's gui_visible list, so this function is a
%   filter, not a second registry.
%
%   Each returned entry keeps its loader (lazy, zero-argument) and gains
%   run_opts.pf / run_opts.sssa / run_opts.ts -- the frozen launcher option
%   values merged with the entry's own case-level pf_options/sssa_options/
%   ts_options.  run_analysis itself applies NO defaults.
%
%   See also: cases.NETWORK_CASE_CATALOG, studio.RUN_ANALYSIS.

c = cases.network_case_catalog();
keep = [c.gui_visible];
entries = c(keep);
for k = 1:numel(entries)
    entries(k).run_opts = compose_run_opts(entries(k));
end
end

function opt = compose_run_opts(entry)
% Frozen launcher values (the approved production defaults used by the
% shared request dispatcher's defaults table: PF max_iter=50,
% tolerance=1e-10, enforce_q_limits with q_limit_tolerance=1e-6 and
% max_q_limit_switches=20; SSSA fd_eps=1e-6, stability_tolerance=1e-7,
% equilibrium_tolerance=1e-10, newton_max_iterations=300,
% load_model='cz_p_cz_q').  Merged ONTO the entry's case-level options.
pf = merge(struct( ...
    'max_iter', 50, 'tolerance', 1e-10, ...
    'enforce_q_limits', true, 'q_limit_tolerance', 1e-6, ...
    'max_q_limit_switches', 20), entry.pf_options);
sssa = merge(struct( ...
    'fd_eps', 1e-6, 'stability_tolerance', 1e-7, ...
    'equilibrium_tolerance', 1e-10, 'newton_max_iterations', 300, ...
    'load_model', 'cz_p_cz_q'), entry.sssa_options);
ts = entry.ts_options;
opt = struct('pf', pf, 'sssa', sssa, 'ts', ts);
end

function opt = merge(base, over)
opt = base;
if ~isstruct(over), return; end
names = fieldnames(over);
for k = 1:numel(names)
    opt.(names{k}) = over.(names{k});
end
end
