function r = discover_cases(analysis_id)
%DISCOVER_CASES  Lazy enumeration of case entries for an analysis.
%   r = wizard.discover_cases(analysis_id) returns a struct array of case
%   entries compatible with the requested analysis. This is PURE and LAZY
%   (correction #8): it calls the catalog functions and attaches loaders as
%   function handles, but it does NOT execute PF/equilibrium, load solved
%   states, or invoke any solver merely to populate the case-selection page.
%
%   Mirrors the case_registry(analysis) logic in solve_case.m:227-242:
%     - pf/sssa/ts: cases.network_case_catalog() (14 generic entries)
%     - sssa additionally: 'sauer_pai' (Sauer-Pai Example 8.3)
%     - ibr: 'ieee14_1sg_4ibr' (Kodsi SG1 + dual-mode IBRs)
%
%   Each entry has:
%     id          - stable case ID (char, lowercased)
%     label       - human-readable display name (char)
%     loader      - zero-arg function handle returning power_case/1.0
%                   (or the IBR scenario for 'ibr')
%     options     - case-defined default options struct for this analysis
%     analysis    - the analysis this entry was discovered for
%     schema      - expected schema version (filled lazily by caller if needed;
%                   left empty here to avoid loading the case)
%
%   Compatibility: an entry is included only if its option field (or IBR
%   specialization) is compatible with the analysis. Fail closed for duplicate
%   IDs, malformed entries, or missing required fields.
%
%   See also: wizard.ANALYSIS_REGISTRY, cases.network_case_catalog.

analysis_id = lower(char(analysis_id));
registry = wizard.analysis_registry();
idx = find(strcmp(analysis_id, {registry.id}), 1);
if isempty(idx)
    error('wizard:discover_cases:unknownAnalysis', ...
        'Unknown analysis ID %s.', analysis_id);
end
entry = registry(idx);
option_field = entry.option_field;

switch analysis_id
    case 'pf'
        catalog = cases.network_case_catalog();
        r = items_from_catalog(catalog, 'pf_options', analysis_id);
    case 'sssa'
        catalog = cases.network_case_catalog();
        r = items_from_catalog(catalog, 'sssa_options', analysis_id);
        r(end+1,1) = item('sauer_pai', 'Sauer-Pai Example 8.3', ...
            @cases.sauer_pai_ex83_case, struct(), analysis_id); %#ok<AGROW>
    case 'ts'
        catalog = cases.network_case_catalog();
        r = items_from_catalog(catalog, 'ts_options', analysis_id);
    case 'ibr'
        r = item('ieee14_1sg_4ibr', ...
            'IEEE14 1-SG + 4-IBR (Kodsi SG1 + dual-mode IBRs)', ...
            @cases.case_ieee14_1sg_4ibr_auto_vsg, wizard.defaults_for_method('ibr'), ...
            analysis_id);
    otherwise
        error('wizard:discover_cases:unknownAnalysis', ...
            'Unknown analysis ID %s.', analysis_id);
end

% Fail closed on duplicate IDs.
ids = {r.id};
[~,~,ic] = unique(ids);
if numel(unique(ic)) ~= numel(ids)
    error('wizard:discover_cases:duplicateId', ...
        'Duplicate case IDs discovered for analysis %s.', analysis_id);
end
end

function r = items_from_catalog(catalog, option_field, analysis_id)
r = repmat(item('','','',struct(),analysis_id), 0, 1);
for k = 1:numel(catalog)
    e = catalog(k);
    if ~isfield(e, option_field)
        continue;  % entry has no options for this analysis -> skip
    end
    r(end+1,1) = item(lower(char(e.id)), char(e.label), e.loader, ...
        e.(option_field), analysis_id); %#ok<AGROW>
end
end

function s = item(id, label, loader, options, analysis_id)
if nargin < 5, analysis_id = ''; end
if nargin < 4, options = struct(); end
s = struct('id', id, 'label', label, 'loader', loader, ...
    'options', options, 'analysis', analysis_id, 'schema', '');
end
