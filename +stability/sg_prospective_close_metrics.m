function m = sg_prospective_close_metrics(t,x_dev,y,u_dev,event_context,dev,case_data)
%SG_PROSPECTIVE_CLOSE_METRICS  Breaker-left prospective SG injection audit.
%   Evaluates the SG with the accepted breaker-open differential/algebraic
%   states and only its online/mode context changed hypothetically; no state,
%   input, topology or published context is mutated. The rated-current/power
%   gates use the declared machine MVA and system MVA bases; they are not
%   fitted to a transient result.
%
%   OPT-IN AUGMENTED RATING BRANCH (reduced classical SG31 reclose plant)
%   The branch is selected by DEVICE IDENTITY, not by parameter values: the
%   model marker dev.provenance.model=='sg_classical_reclose_project_derived', the
%   exact declared input names dev.input_names=={'P_ref','Emag_ref'}, or the
%   exact schema id 'ne39_sg31_classical_reclose_v1' in
%   dev.provenance.params.
%
%   - Marker absent -> LEGACY path, unchanged: rating from
%     case_data.machines.base.S_MVA, no new fields, no new gate.
%   - Marker present -> the rating MUST come from the declared record at the
%     exact path dev.provenance.params with schema id
%     'ne39_sg31_classical_reclose_v1'. A marked device whose record/schema is
%     missing, whose system_base_MVA does not match the case system base, or
%     whose rating is not finite positive, FAILS CLOSED as NOT_DECLARED (NaN
%     rating, passes=false). It never falls back to the machine MVA base.
%   - Metadata gaps are reported through m.rating_status, never a hard throw.
%
%   In the opt-in branch the ACTUAL mechanical shaft power is
%   dev.reconstruct(...).Pm_pu (measured state), not u_dev(1), which is the
%   electrical reference command P_ref. m.Tm_pu keeps its existing value for
%   ABI compatibility and its semantics are declared by m.Tm_pu_semantics.
%   The circle comparison uses the same operator/epsilon as the legacy path.

arguments
    t (1,1) double
    x_dev (:,1) double
    y (:,1) double
    u_dev (:,1) double
    event_context struct
    dev struct
    case_data struct
end
if ~isfield(event_context,'hybrid_state') || ...
        ~isfield(dev,'device_id') || ~isfield(dev,'bus_position')
    error('stability:sg_prospective_close_metrics:badContract', ...
        'Hybrid state, device identity and bus position are required.');
end
ec_close=event_context;
key=matlab.lang.makeValidName(char(dev.device_id),'ReplacementStyle','underscore');
if ~isfield(ec_close.hybrid_state,'device_online') || ...
        ~isfield(ec_close.hybrid_state.device_online,key) || ...
        ~isfield(ec_close.hybrid_state,'device_modes') || ...
        ~isfield(ec_close.hybrid_state.device_modes,key)
    error('stability:sg_prospective_close_metrics:missingDevice', ...
        'SG is absent from the hybrid-state online/mode maps.');
end
ec_close.hybrid_state.device_online.(key)=true;
ec_close.hybrid_state.device_modes.(key)='synchronous';
I=dev.current_injection(t,x_dev,y,u_dev,ec_close);
V=complex(y(2*dev.bus_position-1),y(2*dev.bus_position));
S=V*conj(I);
Pe=dev.electrical_power(t,x_dev,y,u_dev,ec_close);
dx=dev.f(t,x_dev,y,u_dev,ec_close);
rec=dev.reconstruct(t,x_dev,y,u_dev,event_context);

Sbase=case_data.base_values.S_base_MVA;
Mbase=case_data.machines.base.S_MVA;
rating_sys=Mbase/Sbase;
Imax=rating_sys/max(abs(V),sqrt(eps));
Tm=u_dev(1);
m=struct('I',I,'I_abs_pu',abs(I),'P_pu',real(S),'Q_pu',imag(S), ...
    'S_abs_pu',abs(S),'Pe_pu',Pe,'Tm_pu',Tm, ...
    'torque_mismatch_pu',Tm-Pe,'state_derivative_inf',norm(dx,inf), ...
    'V_bus',V,'V_open_circuit',rec.V_open_circuit, ...
    'rating_MVA',Mbase,'rating_system_pu',rating_sys, ...
    'current_limit_system_pu',Imax, ...
    'current_pass',abs(I)<=Imax+100*eps(max(1,Imax)), ...
    'apparent_power_pass',abs(S)<=rating_sys+100*eps(max(1,rating_sys)), ...
    'finite',all(isfinite([real(I) imag(I) real(S) imag(S) Pe Tm dx(:).'])));

if is_augmented_plant(dev)
    [S_rated,status]=explicit_rating(dev,case_data);
    [Pm_actual,dPm]=mechanical_power(rec,Pe);
    if isfinite(S_rated), rating_aug=S_rated/Sbase; else, rating_aug=NaN; end
    if isfinite(rating_aug), Imax_aug=rating_aug/max(abs(V),sqrt(eps)); else, Imax_aug=NaN; end
    m.rating_MVA=S_rated;
    m.rating_system_pu=rating_aug;
    m.current_limit_system_pu=Imax_aug;
    m.current_pass=abs(I)<=Imax_aug+100*eps(max(1,Imax_aug));
    m.apparent_power_pass=abs(S)<=rating_aug+100*eps(max(1,rating_aug));
    m.mechanical_power_pu=Pm_actual;
    m.mechanical_power_minus_electrical_pu=dPm;
    m.Tm_pu_semantics='PER_UNIT_COMMAND_CHANNEL_P_REF_NOT_ACTUAL_SHAFT_POWER';
    m.rating_status=status;
    p=local_struct(dev,'provenance','params');
    m.rating_classification=local_char(p,'classification');
    m.rating_source=local_char(p,'source');
    m.finite=m.finite && isfinite(Pm_actual) && isfinite(dPm);
    m.passes=(isfinite(S_rated) && S_rated>0) && m.finite && ...
        m.current_pass && m.apparent_power_pass;
else
    m.passes=m.finite && m.current_pass && m.apparent_power_pass;
end
end

function tf=is_augmented_plant(dev)
%IS_AUGMENTED_PLANT  Explicit device identity for the opt-in reclose plant.
%   Accepted markers: the model marker, the exact declared input names
%   {'P_ref','Emag_ref'}, or the exact declared schema id in
%   dev.provenance.params. No alias fields and no parameter-value inference.
tf=false;
if isfield(dev,'provenance') && isstruct(dev.provenance) && ...
        isfield(dev.provenance,'model')
    tf=strcmp(local_char(dev.provenance,'model'),'sg_classical_reclose_project_derived');
    if tf, return; end
end
if isfield(dev,'input_names')
    names=dev.input_names;
    if iscell(names) && numel(names)==2 && all(cellfun(@ischar,names)) && ...
            strcmp(names{1},'P_ref') && strcmp(names{2},'Emag_ref')
        tf=true; return;
    end
end
tf=strcmp(local_char(local_struct(dev,'provenance','params'),'schema_id'), ...
    'ne39_sg31_classical_reclose_v1');
end

function [S_rated,status]=explicit_rating(dev,case_data)
%EXPLICIT_RATING  Declared PROJECT_DERIVED stator rating on the system base.
%   Requires the exact record path dev.provenance.params with the fixed schema
%   id, a system_base_MVA matching the case base, finite positive S_rated_MVA,
%   classification PROJECT_DERIVED and a non-empty explicit source. Anything
%   else fails closed as NOT_DECLARED with NaN rating.
S_rated=NaN; status='NOT_DECLARED';
if ~isfield(dev,'provenance') || ~isstruct(dev.provenance) || ...
        ~isfield(dev.provenance,'params') || ~isstruct(dev.provenance.params)
    return;
end
p=dev.provenance.params;
if ~strcmp(local_char(p,'schema_id'),'ne39_sg31_classical_reclose_v1')
    return;
end
if ~isfield(p,'system_base_MVA'), return; end
base=double(p.system_base_MVA);
Sbase=double(case_data.base_values.S_base_MVA);
if ~(isscalar(base) && isfinite(base) && base>0 && ...
        abs(base-Sbase)<=1e-10*max(1,Sbase))
    status='INVALID_METADATA'; return;
end
if ~isfield(p,'S_rated_MVA'), return; end
candidate=double(p.S_rated_MVA);
if ~(isscalar(candidate) && isfinite(candidate) && candidate>0)
    return;
end
if ~strcmp(local_char(p,'classification'),'PROJECT_DERIVED')
    status='INVALID_METADATA'; return;
end
if isempty(local_char(p,'source'))
    status='INVALID_METADATA'; return;
end
S_rated=candidate;
status='DECLARED_PROJECT_DERIVED';
end

function [Pm_actual,dPm]=mechanical_power(rec,Pe)
%MECHANICAL_POWER  Actual shaft mechanical power from the measured state.
Pm_actual=NaN;
if isstruct(rec)
    for name={'Pm_pu','Pm'}
        if isfield(rec,name{1})
            value=double(rec.(name{1}));
            if isscalar(value) && isfinite(value)
                Pm_actual=value;
                break;
            end
        end
    end
end
if isfinite(Pm_actual) && isfinite(Pe), dPm=Pm_actual-Pe; else, dPm=NaN; end
end

function s=local_struct(parent,varargin)
%LOCAL_STRUCT  Nested struct field along a field-name path, or empty struct.
%   LOCAL_STRUCT(PARENT,'provenance','params') walks name by name and returns
%   an empty struct as soon as a name is absent or its value is not a struct.
%   Used so a marked device with missing provenance never hard-throws; the
%   caller reports the gap through m.rating_status instead.
s=parent;
for k=1:numel(varargin)
    name=varargin{k};
    if ~isstruct(s) || ~isfield(s,name) || ~isstruct(s.(name))
        s=struct();
        return;
    end
    s=s.(name);
end
if ~isstruct(s)
    s=struct();
end
end

function text=local_char(s,name)
%LOCAL_CHAR  Char form of one field, or '' when absent or of another type.
text='';
if ~isstruct(s) || ~isfield(s,name)
    return;
end
value=s.(name);
if ischar(value)
    text=value;
elseif isstring(value) && isscalar(value)
    text=char(value);
end
end
