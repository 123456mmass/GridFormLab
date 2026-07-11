function result = multicase_sssa(case_data, options)
%MULTICASE_SSSA Dispatch a case to its parameter-driven SSSA model plugin.

if nargin < 1 || isempty(case_data)
    error('multicase_sssa:caseRequired', 'case_data is required.');
end
if nargin < 2 || isempty(options), options=struct(); end

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
    model=struct('x0',lin.x0,'y0',0, ...
        'f',@(x,y) zeros(ns*ng,1),'g',@(x,y) 0, ...
        'Jxx',lin.A,'Jxy',zeros(ns*ng,1), ...
        'Jyx',zeros(1,ns*ng),'Jyy',1,'free_y',1, ...
        'reduction','coi','ng',ng,'states_per_machine',ns, ...
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
