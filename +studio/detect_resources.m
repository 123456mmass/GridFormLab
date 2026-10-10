function report = detect_resources(case_data)
%DETECT_RESOURCES  Auto-detect IBR/SG units on a case, with honest evidence.
%   report = studio.detect_resources(case_data) returns a struct with the
%   fields
%       has_ibr, n_ibr, n_sg, n_unknown, complete, authority,
%       is_device_evidence, headline, detail
%   resolving evidence in this order:
%
%   1. case_data.resources  -- the shape only stability.build_hybrid_scenario
%      produces.  Authoritative and the ONLY device-level evidence
%      (authority='resource_table', is_device_evidence=true).  n_ibr counts
%      entries whose resource_type normalises to 'ibr', matching the
%      normalisation gate at +stability/resource_table.m (resource_type in
%      {"sg","ibr"}).  An entry WITHOUT resource_type increments n_unknown
%      and sets complete=false; it is NEVER silently counted as an IBR (the
%      default-to-'ibr' behaviour of the selector stack would over-count).
%
%   2. Else case_data.bus_role (every power_case/1.0 case has it) --
%      n_ibr = count of "GFL"/"GFM" roles, n_sg = count of "SLACK"/"PV"
%      roles (bus roles use SLACK, not REF).  authority='bus_role_label',
%      is_device_evidence=false: standardize_case states bus_role never
%      feeds the PF equations -- it is a presentation label -- so the
%      headline says "declares", not "contains".
%
%   3. Else generator buses alone -- n_ibr=0, n_sg = sum(bus_data(:,2)<=2).
%      authority='generator_bus_type', is_device_evidence=false.
%
%   GFM capability is NOT "is IBR": it additionally requires can_switch_mode
%   AND gfm in supported_modes (the resource_table contract).  The count is
%   reported on its own line of DETAIL, and only when authority is
%   'resource_table'; otherwise the line states that GFM capability is not
%   declared.  No caller may read n_ibr as a GFM count.
%
%   See also: studio.FORMAT_OVERVIEW, studio.LAUNCH.

if ~isstruct(case_data)
    error('studio:detect_resources:badCase', 'case_data must be a struct.');
end

report = struct('has_ibr', false, 'n_ibr', 0, 'n_sg', 0, 'n_unknown', 0, ...
    'complete', true, 'authority', 'generator_bus_type', ...
    'is_device_evidence', false, 'headline', '', 'detail', '');

% ---- 1. device-level resource table ----------------------------------
if isfield(case_data, 'resources') && isstruct(case_data.resources) && ...
        ~isempty(case_data.resources)
    res = case_data.resources(:);
    n_ibr = 0; n_sg = 0; n_unknown = 0; n_gfm_capable = 0;
    for k = 1:numel(res)
        r = res(k);
        if ~isfield(r, 'resource_type') || isempty(r.resource_type)
            n_unknown = n_unknown + 1;
            continue
        end
        rt = lower(char(r.resource_type));
        switch rt
            case 'ibr'
                n_ibr = n_ibr + 1;
                if isfield(r, 'can_switch_mode') && isfield(r, 'supported_modes') ...
                        && isscalar(r.can_switch_mode) && ~isempty(r.can_switch_mode) ...
                        && logical(r.can_switch_mode)
                    sm = lower(string(r.supported_modes));
                    if any(sm == "gfm")
                        n_gfm_capable = n_gfm_capable + 1;
                    end
                end
            case 'sg'
                n_sg = n_sg + 1;
            otherwise
                % Unknown type: count as unknown, never guess.
                n_unknown = n_unknown + 1;
        end
    end
    report.authority = 'resource_table';
    report.is_device_evidence = true;
    report.n_ibr = n_ibr;
    report.n_sg = n_sg;
    report.n_unknown = n_unknown;
    report.complete = (n_unknown == 0);
    report.headline = sprintf( ...
        'This case contains %d IBR unit(s) and %d synchronous generator(s).', ...
        n_ibr, n_sg);
    detail = sprintf( ...
        'Evidence: resource_table (device-level; the only evidence that proves a device exists).');
    detail = sprintf('%s\nGFM-capable IBR units: %d (requires can_switch_mode and gfm in supported_modes).', ...
        detail, n_gfm_capable);
    if n_unknown > 0
        detail = sprintf('%s\n%d resource entr(y/ies) lack a recognized resource_type; counts are incomplete.', ...
            detail, n_unknown);
    end
    report.detail = detail;

% ---- 2. bus_role presentation labels ---------------------------------
elseif isfield(case_data, 'bus_role') && ~isempty(case_data.bus_role)
    role = upper(string(case_data.bus_role(:)));
    n_ibr = sum(role == "GFL" | role == "GFM");
    n_sg = sum(role == "SLACK" | role == "PV");
    n_gfl = sum(role == "GFL");
    n_gfm_label = sum(role == "GFM");
    report.authority = 'bus_role_label';
    report.is_device_evidence = false;
    report.n_ibr = n_ibr;
    report.n_sg = n_sg;
    report.n_unknown = 0;
    report.complete = true;
    report.headline = sprintf( ...
        'This case declares %d IBR unit(s) and %d synchronous generator(s).', ...
        n_ibr, n_sg);
    report.detail = sprintf( ...
        ['Evidence: bus_role labels (GFL=%d, GFM=%d). Labels are presentational ', ...
         'and do not prove a device exists at runtime.\n', ...
         'GFM capability: not declared.'], n_gfl, n_gfm_label);

% ---- 3. generator bus types only -------------------------------------
else
    if isfield(case_data, 'bus_data') && isnumeric(case_data.bus_data) && ...
            size(case_data.bus_data, 2) >= 2
        n_sg = sum(case_data.bus_data(:, 2) <= 2);
    end
    report.authority = 'generator_bus_type';
    report.is_device_evidence = false;
    report.n_ibr = 0;
    report.n_sg = n_sg;
    report.n_unknown = 0;
    report.complete = true;
    report.headline = sprintf( ...
        'This case declares %d IBR unit(s) and %d synchronous generator(s).', ...
        0, n_sg);
    report.detail = sprintf( ...
        ['Evidence: generator bus types only (no resource table, no bus_role labels).\n', ...
         'GFM capability: not declared.']);
end

report.has_ibr = report.n_ibr > 0;
end
