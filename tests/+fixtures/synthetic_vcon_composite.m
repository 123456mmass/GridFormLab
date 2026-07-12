function [dae, vcon_opt] = synthetic_vcon_composite(variant)
%SYNTHETIC_VCON_COMPOSITE  Test-only composite + vcon fixture (B4).
%   Returns a composite DAE (over IEEE14 MATPOWER) + an opt.vcon struct for
%   B4 voltage-constraint tests. TEST-ONLY (tests/+fixtures, called as
%   fixtures.synthetic_vcon_composite). No +ibr.
%
%   Variants:
%     'one_constraint'  - one slack bus voltage fixed (vars=[1,2],rows=[1,2])
%     'disjoint'        - vars=[1,2], rows=[3,4] (equal cardinality, diff idx)
%     'two_constraints' - two buses constrained
%     'cardinality_bad' - vars=[1,2], rows=[3] (unequal cardinality, fail)
%     'duplicate_row'   - rows=[1,1] (duplicate, fail)
%     'bad_index'       - vars out of range (fail)
%     'bad_eq_dim'      - eq output dim != numel(rows) (fail)
%
%   Source: project B4 design. MATPOWER provides network/PF data only;
%   device parameters are SYNTHETIC test fixtures (ASSUMED_DIAGNOSTIC,
%   excluded from production acceptance). Sauer-Pai §6.7 (slack V specified,
%   KCL replaced).

if nargin < 1, variant = 'one_constraint'; end
c = cases.case_matpower6_case14();
mpc = c.mpc;
% First generator bus for the synthetic device.
gbus = mpc.gen(1,1);
dev = struct('name','trivial','device_id','g1','bus_id',gbus, ...
    'nx',1,'nu',1, ...
    'f',@(t,x,y,u,ec) -x, ...
    'current_injection',@(t,x,y,u,ec) complex(0,0), ...
    'electrical_power',@(t,x,y,u,ec) 0, ...
    'x0',0,'u0',0, ...
    'state_names',{{'delta'}}, ...
    'reconstruct',@(t,x,y,u,ec) struct('delta',x,'omega',0,'Pe',0,'Vbus',abs(y(1))));
% vcon reference: bus 1 voltage magnitude=1.0, angle=0 (Re=y(1)=1, Im=y(2)=0).
switch lower(variant)
case 'one_constraint'
    % vars=[1,2], rows=[1,2]: constrain Re/Im of bus 1, replace KCL rows 1,2.
    vcon_opt = struct('vars',[1,2],'rows',[1,2], ...
        'eq',@(y,ref) [y(1)-ref(1); y(2)-ref(2)], 'ref',[1.0; 0]);
case 'disjoint'
    % vars=[1,2], rows=[3,4]: equal cardinality, DIFFERENT index values.
    % Constrain vars 1,2 but replace KCL rows 3,4 (still square reduced).
    vcon_opt = struct('vars',[1,2],'rows',[3,4], ...
        'eq',@(y,ref) [y(1)-ref(1); y(2)-ref(2)], 'ref',[1.0; 0]);
case 'two_constraints'
    % Two buses constrained: vars=[1,2,3,4], rows=[1,2,3,4].
    vcon_opt = struct('vars',[1,2,3,4],'rows',[1,2,3,4], ...
        'eq',@(y,ref) [y(1)-ref(1); y(2)-ref(2); y(3)-ref(3); y(4)-ref(4)], ...
        'ref',[1.0;0;1.0;0]);
case 'cardinality_bad'
    vcon_opt = struct('vars',[1,2],'rows',[3], ...
        'eq',@(y,ref) y(1)-ref(1), 'ref',1.0);
case 'duplicate_row'
    vcon_opt = struct('vars',[1,2],'rows',[1,1], ...
        'eq',@(y,ref) [y(1)-ref(1); y(2)-ref(2)], 'ref',[1.0;0]);
case 'bad_index'
    vcon_opt = struct('vars',[1,99999],'rows',[1,2], ...
        'eq',@(y,ref) [y(1)-ref(1); y(2)-ref(2)], 'ref',[1.0;0]);
case 'bad_eq_dim'
    vcon_opt = struct('vars',[1,2],'rows',[1,2], ...
        'eq',@(y,ref) y(1)-ref(1), 'ref',1.0);   % returns scalar, not 2-vector
otherwise
    error('synthetic_vcon_composite:badVariant', 'Unknown variant "%s".', variant);
end
opt = struct();
opt.vcon = vcon_opt;
dae = stability.composite_dae(c, dev, opt);
end
