function J = pf_build_jacobian(V, delta, P_calc, Q_calc, model)
%PF_BUILD_JACOBIAN Build the Newton-Raphson Jacobian for the model indices.

Gbus = model.Gbus;
Bbus = model.Bbus;
J = zeros(model.n_total, model.n_total);

for i = 1:model.n_delta
    bus_i = model.delta_idx(i);
    for j = 1:model.n_delta
        bus_j = model.delta_idx(j);
        delta_ij = delta(bus_i) - delta(bus_j);
        if i == j
            J(i, j) = -Q_calc(bus_i) - Bbus(bus_i, bus_i) * V(bus_i)^2;
        else
            J(i, j) = V(bus_i) * V(bus_j) * (Gbus(bus_i, bus_j) * sin(delta_ij) - Bbus(bus_i, bus_j) * cos(delta_ij));
        end
    end
end

for i = 1:model.n_delta
    bus_i = model.delta_idx(i);
    for j = 1:model.n_V
        bus_j = model.V_idx(j);
        delta_ij = delta(bus_i) - delta(bus_j);
        if bus_i == bus_j
            J(i, model.n_delta + j) = P_calc(bus_i) / V(bus_i) + Gbus(bus_i, bus_i) * V(bus_i);
        else
            J(i, model.n_delta + j) = V(bus_i) * (Gbus(bus_i, bus_j) * cos(delta_ij) + Bbus(bus_i, bus_j) * sin(delta_ij));
        end
    end
end

for i = 1:model.n_V
    bus_i = model.V_idx(i);
    for j = 1:model.n_delta
        bus_j = model.delta_idx(j);
        delta_ij = delta(bus_i) - delta(bus_j);
        if bus_i == bus_j
            J(model.n_delta + i, j) = P_calc(bus_i) - Gbus(bus_i, bus_i) * V(bus_i)^2;
        else
            J(model.n_delta + i, j) = -V(bus_i) * V(bus_j) * (Gbus(bus_i, bus_j) * cos(delta_ij) + Bbus(bus_i, bus_j) * sin(delta_ij));
        end
    end
end

for i = 1:model.n_V
    bus_i = model.V_idx(i);
    for j = 1:model.n_V
        bus_j = model.V_idx(j);
        delta_ij = delta(bus_i) - delta(bus_j);
        if i == j
            J(model.n_delta + i, model.n_delta + j) = Q_calc(bus_i) / V(bus_i) - Bbus(bus_i, bus_i) * V(bus_i);
        else
            J(model.n_delta + i, model.n_delta + j) = V(bus_i) * (Gbus(bus_i, bus_j) * sin(delta_ij) - Bbus(bus_i, bus_j) * cos(delta_ij));
        end
    end
end
end
