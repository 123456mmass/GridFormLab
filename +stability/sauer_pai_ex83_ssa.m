function result = sauer_pai_ex83_ssa()
%SAUER_PAI_EX83_SSA Sauer-Pai Example 8.3 / Table 8.2 reproduction.
% 3-machine 9-bus WSCC system with IEEE-Type I exciters.
%
% This wrapper contains no benchmark-specific eigenvalue fitting.  It asks
% the in-house analytical model plugin to assemble the reduced state matrix,
% then passes that matrix through the common multimachine_ssa engine for COI
% reduction and eigenvalue/damping calculations.
%
% State per machine: [delta, omega, Eq', Ed', Efd, VR, Rf]

lin = stability.sauer_pai_ex83_linearization_inhouse();
Asys = lin.A;
ng = lin.ng;
ns = lin.ns;
H = lin.H;

model = struct();
model.x0 = lin.x0;
model.y0 = 0;
model.f = @(x,y) zeros(ns*ng, 1);
model.g = @(x,y) 0;
model.Jxx = Asys;
model.Jxy = zeros(ns*ng, 1);
model.Jyx = zeros(1, ns*ng);
model.Jyy = 1;
model.free_y = 1;
model.reduction = 'coi';
model.ng = ng;
model.states_per_machine = ns;
model.angle_state_index = 1;
model.speed_state_index = 2;
model.inertia = H;
model.metadata = struct('benchmark','Sauer-Pai Example 8.3', ...
    'engine','stability.multimachine_ssa', 'jacobian','analytical');

result = stability.multimachine_ssa(model);
result.A = Asys;
result.linearization = lin;
result.reference = cases.sauer_pai_reference_catalog().example_8_3_table_8_1;
end
