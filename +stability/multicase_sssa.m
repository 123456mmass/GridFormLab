function result = multicase_sssa(case_data, options)
%MULTICASE_SSSA Dispatch a case to its parameter-driven SSSA model plugin.
%   B2: explicit dispatch via opt.model_bundle / opt.model_fn / opt.sssa_model
%   (all three MUTUALLY EXCLUSIVE; any pair fails closed). If exactly one is
%   supplied, the SSSA model is taken from bundle.sssa.model / factory
%   result / prebuilt sssa_model, validated via validate_sssa_model, and
%   executed via stability.multimachine_ssa. If NONE is supplied, fall
%   through to the built-in string chain (existing behavior, bit-identical).

if nargin < 1 || isempty(case_data)
    error('multicase_sssa:caseRequired', 'case_data is required.');
end
if nargin < 2 || isempty(options), options=struct(); end

% --- B2 explicit SSSA dispatch (mutually exclusive) ----------------------
has_bundle = isfield(options,'model_bundle') && ~isempty(options.model_bundle);
has_mfn    = isfield(options,'model_fn') && ~isempty(options.model_fn);
has_sssa_model = isfield(options,'sssa_model') && ~isempty(options.sssa_model);
explicit_count = has_bundle + has_mfn + has_sssa_model;
if explicit_count > 1
    error('multicase_sssa:exclusiveDispatch', ...
        ['opt.model_bundle, opt.model_fn, and opt.sssa_model are mutually ' ...
         'exclusive; supply at most one.']);
end
if has_bundle
    model = options.model_bundle.sssa.model;
    model = stability.validate_sssa_model(model);
    result = stability.multimachine_ssa(model);
    result.metadata = set_dispatch(result.metadata, 'explicit_model_bundle');
    return;
end
if has_mfn
    bundle = options.model_fn(case_data, options);
    model = bundle.sssa.model;
    model = stability.validate_sssa_model(model);
    result = stability.multimachine_ssa(model);
    result.metadata = set_dispatch(result.metadata, 'explicit_model_fn');
    return;
end
if has_sssa_model
    model = stability.validate_sssa_model(options.sssa_model);
    result = stability.multimachine_ssa(model);
    result.metadata = set_dispatch(result.metadata, 'explicit_sssa_model');
    return;
end

% --- Built-in string chain (existing behavior, bit-identical) -------------
requested_model='';
if isfield(options,'model'), requested_model=lower(char(options.model)); end

if any(strcmp(requested_model,{'padiyar_1_1_avr','padiyar_1_1_manual'}))
    if strcmp(requested_model,'padiyar_1_1_manual')
        options.excitation='manual';
    else
        options.excitation='avr';
    end
    result=stability.padiyar_model11_ssa(case_data,options);
    result.metadata.plugin='padiyar_model_1_1';
elseif ~strcmp(requested_model,'classical') && ...
        isfield(case_data,'bus_data') && isfield(case_data,'machines') && ...
        isfield(case_data.machines,'reactances') && ...
        isfield(case_data.machines.reactances,'Xdpp')
    % The operational EMF6 model (states [delta,omega,E'q,E'd,E''q,E''d]) is
    % the single sixth-order equation set for SSSA and TS, built from
    % stability.emf6_dae / stability.synchronous_emf6_ssa (in-house Newton,
    % no fsolve). The historical primitive-flux (psi-state) and calibrated
    % GENTPJ realizations have been moved to legacy/.
    result=stability.synchronous_emf6_ssa(case_data,options);
    result.metadata.plugin='operational_emf_sixth_order';
elseif all(isfield(case_data,{'Ybus','V','theta','gen_buses','Xd','Xdp'}))
    lin=stability.sauer_pai_linearization(case_data);
    ng=lin.ng; ns=lin.ns;
    gbus=case_data.gen_buses(:);
    states={'\delta';'\omega';'Eq''';'Ed''';'Efd';'V_R';'R_f'};
    snm=cell(ns*ng,1);
    for k=1:ng, i0=(k-1)*ns;
        for s=1:ns, snm{i0+s}=sprintf('%s_G%d@Bus%d',states{s},k,gbus(k)); end;
    end
    model=struct('x0',lin.x0,'y0',0, ...
        'f',@(x,y) zeros(ns*ng,1),'g',@(x,y) 0, ...
        'Jxx',lin.A,'Jxy',zeros(ns*ng,1), ...
        'Jyx',zeros(1,ns*ng),'Jyy',1,'free_y',1, ...
        'reduction','coi','ng',ng,'states_per_machine',ns, ...
        'state_names',{snm}, ...
        'angle_state_index',1,'speed_state_index',2,'inertia',lin.H, ...
        'metadata',struct('engine','stability.multimachine_ssa', ...
            'plugin','sauer_pai_two_axis_ieee_type1', ...
            'benchmark',char(case_data.name)));
    result=stability.multimachine_ssa(model);
    result.linearization=lin;
elseif isfield(case_data,'schema_version') && ...
        strcmp(case_data.schema_version,'power_case/1.0')
    result=stability.classical_sssa(case_data,options);
    result.metadata.plugin='classical_network_linearization';
else
    error('multicase_sssa:unsupportedCase', ...
        'No SSSA model plugin recognizes this case schema.');
end
end

function md = set_dispatch(md, dispatch)
%SET_DISPATCH  Set the dispatch provenance on metadata (B2).
if ~isstruct(md), md = struct(); end
md.dispatch = dispatch;
end
