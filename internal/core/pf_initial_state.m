function x = pf_initial_state(model)
%PF_INITIAL_STATE Build the Newton unknown vector from case initial values.

x = zeros(model.n_total, 1);
for i = 1:model.n_delta
    x(i) = deg2rad(model.angle_spec_deg(model.delta_idx(i)));
end
for i = 1:model.n_V
    x(model.n_delta + i) = model.V_spec(model.V_idx(i));
end
end
