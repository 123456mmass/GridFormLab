function Ig = sg_stator_current(x_dev, y, bus_position, machine, units, k)
%SG_STATOR_CURRENT  Network-frame stator current from EMF6 states (audited helper).
%   Ig = sg_stator_current(X_DEV, Y, BUS_POSITION, MACHINE, UNITS, K) computes the
%   synchronous-machine network-frame complex stator current (positive INTO network,
%   generator convention) from the EMF6 state slice and the bus voltage in y.
%
%   This is the SAME EMF6 stator equation used by synchronous_emf6_ssa/
%   machine_algebraic (Id=(-Ra*rhs_d - Xqpp*rhs_q)/det,
%   Iq=(Xdpp*rhs_d - Ra*rhs_q)/det, rhs_d=Vd-Edpp, rhs_q=Vq-Eqpp), then rotated to
%   the network frame via kundur_book_network_current. It is NOT reverse-derived
%   from Pe/V (correction 2: SG composite current must come from the EMF6 stator
%   Id/Iq equations and network-frame transformation).
%
%   Single-machine form (machine k of ng). For the composite SG device, ng=1, k=1.
%
%   Inputs:
%     X_DEV   - 6-state EMF6 slice [delta; omega; Eqp; Edp; Eqpp; Edpp]
%     Y       - full composite interleaved [Re(V1);Im(V1);...]
%     BUS_POSITION - internal bus index of this machine
%     MACHINE - struct from synchronous_emf6_ssa machine_parameters (Xd,Xdp,Xdpp,
%               Xq,Xqp,Xqpp,Ra,Tpd0,Tppd0,Tpq0,Tppq0,c_d,d_d,c_q,d_q,w0,ng) —
%               per-machine scalars (already base-converted)
%     UNITS   - struct with H_system, D_system, bus_idx, id
%     K       - machine index (1 for single-machine SG1)
%
%   Output:
%     IG - complex current INTO network (pu, system base)
%
%   Source: EMF6 stator equations (Kundur/GENTPJ 6th-order), reused verbatim from
%   synchronous_emf6_ssa.machine_algebraic + stability.kundur_book_network_current.
%   PROJECT_DERIVED adapter (single-machine slice of the existing audited multi-machine
%   path); no new equation.
%
%   Sign convention: S = V*conj(I) (generator convention); I positive INTO network.
%   This matches composite_dae KCL g = Y*V - Ibus and the IBR devices.

delta = x_dev(1);
Eqpp  = x_dev(5);
Edpp  = x_dev(6);
b = bus_position;
V = complex(y(2*b-1), y(2*b));
[Vd, Vq] = stability.kundur_book_dq(V, delta);
rhs_d = Vd - Edpp;
rhs_q = Vq - Eqpp;
det = machine.Xdpp(k)*machine.Xqpp(k) + machine.Ra(k)^2;
Id = (-machine.Ra(k)*rhs_d - machine.Xqpp(k)*rhs_q) / det;
Iq = ( machine.Xdpp(k)*rhs_d - machine.Ra(k)*rhs_q) / det;
Ig = stability.kundur_book_network_current(Id, Iq, delta);
end
