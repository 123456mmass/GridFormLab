function r = analysis_registry()
%ANALYSIS_REGISTRY  Pure metadata for the four stable analysis IDs.
%   r = wizard.analysis_registry() returns a struct array describing each
%   analysis exposed by the launcher. This is a PURE, headless, side-effect-free
%   metadata function — no UI, no case loading, no solver invocation.
%
%   The four stable analysis IDs (frozen by characterization):
%     'pf'   - Power Flow            (events NOT_APPLICABLE)
%     'sssa' - Small-Signal Stability (events NOT_APPLICABLE)
%     'ts'   - Transient Stability    (events optional)
%     'ibr'  - IBR Simulation (mixed-resource TS; events optional)
%
%   NOTE: 'ibr' already means mixed-resource transient stability. A separate
%   'ibr_ts' ID is NOT introduced (characterization gate test_stable_analysis_ids).
%
%   Each entry has:
%     id                 - stable analysis ID (char)
%     label              - human-readable display name (char)
%     description        - short description (char)
%     requires_equilibrium - logical (sssa/ts/ibr yes; pf no)
%     events_applicable  - logical (ts/ibr yes; pf/sssa no)
%     supports_resources - cell of resource kinds ({'sg'},{'gfm'},{'gfl'},...)
%     option_field       - which case-catalog option field feeds this analysis
%                           ('pf_options'/'sssa_options'/'ts_options'/'' ibr)
%     accent_color       - [R G B] in [0,1] for UI accent (display only)
%
%   See also: wizard.DISCOVER_CASES, wizard.DEFAULTS_FOR_METHOD.

r = [
  analysis('pf', 'Power Flow', ...
      'Project-owned Newton-Raphson power flow (method via pf_method).', ...
      false, false, {{}}, 'pf_options', [0.20 0.45 0.75]);
  analysis('sssa', 'Small-Signal Stability', ...
      'Linearized eigenvalue analysis at an equilibrium operating point.', ...
      true, false, {{}}, 'sssa_options', [0.35 0.60 0.35]);
  analysis('ts', 'Transient Stability', ...
      'Nonlinear time-domain simulation with optional events.', ...
      true, true, {{}}, 'ts_options', [0.80 0.50 0.20]);
  analysis('ibr', 'IBR Simulation', ...
      'Mixed-resource transient stability (SG/GFM/GFL devices).', ...
      true, true, {{'sg','gfm','gfl'}}, '', [0.65 0.30 0.55]);
];
end

function s = analysis(id, label, description, req_eq, events_app, resources, option_field, accent)
s = struct('id', id, 'label', label, 'description', description, ...
    'requires_equilibrium', logical(req_eq), ...
    'events_applicable', logical(events_app), ...
    'supports_resources', resources, ...
    'option_field', option_field, ...
    'accent_color', accent(:).');
end
