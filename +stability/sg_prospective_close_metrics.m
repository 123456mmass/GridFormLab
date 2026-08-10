function m = sg_prospective_close_metrics(t,x_dev,y,u_dev,event_context,dev,case_data)
%SG_PROSPECTIVE_CLOSE_METRICS  Breaker-left prospective SG injection audit.
%   The SG is evaluated with the accepted breaker-open differential and
%   algebraic states, but with only its online/mode context changed
%   hypothetically.  No state, input, topology, or published context is
%   mutated.  The rated-current/power gates use the declared machine MVA and
%   system MVA bases; they are not fitted to a transient result.

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
m.passes=m.finite && m.current_pass && m.apparent_power_pass;
end
