function [model, vcon_spec] = synthetic_slack_case(variant)
%SYNTHETIC_SLACK_CASE  Test-only 2-bus slack-constrained SSSA fixture (R4).
%   Returns an SSSA model struct + vcon spec for R4 voltage-constraint tests.
%   TEST-ONLY (tests/+fixtures, called as fixtures.synthetic_slack_case). No +ibr.
%
%   Variants:
%     'one_constraint'  - one slack bus, V fixed (2 vcon: Re+Im).
%     'two_constraints' - two constrained buses.
%     'state_dependent' - vcon_eq depends on x (must fail-closed).
%     'rank_deficient'  - vcon_eq Jacobian is rank-deficient (must fail-closed).
%     'mismatched'      - numel(vcon_vars) != numel(vcon_rows) (must fail-closed).
%
%   Source: project SSSA contract §2; Sauer-Pai §6.7 (slack V specified, KCL
%   replaced). Synthetic, no +ibr.

if nargin < 1, variant = 'one_constraint'; end
% Minimal 2-bus, 1-generator linear model.
% x = [delta; omega] (2 states). y = [Re(V1); Im(V1); Re(V2); Im(V2)] (4 alg).
% f(x,y) = swing; g(x,y) = KCL.
x0 = [0; 1.0]; y0 = [1.0; 0; 1.0; 0];
A = [0, 1; -1, 0];   % linear swing Jacobian (synthetic)
f = @(x,y) A*x;
g = @(x,y) [y(1)-1.0; y(2)-0; y(3)-1.0; y(4)-0];   % trivial KCL (synthetic)
model = struct('x0',x0,'y0',y0,'f',f,'g',g,'state_names',{{'delta','omega'}});
switch lower(variant)
case 'one_constraint'
    % Fix bus 2 voltage (Re+Im): vcon_vars=[3,4], vcon_rows=[3,4].
    vcon_spec = struct( ...
        'vcon_vars',[3,4], 'vcon_rows',[3,4], ...
        'vcon_eq',@(x,y) [y(3)-1.0; y(4)-0]);
case 'two_constraints'
    % Fix bus 1 and bus 2: vcon_vars=[1,2,3,4], vcon_rows=[1,2,3,4].
    vcon_spec = struct( ...
        'vcon_vars',[1,2,3,4], 'vcon_rows',[1,2,3,4], ...
        'vcon_eq',@(x,y) [y(1)-1.0; y(2)-0; y(3)-1.0; y(4)-0]);
case 'state_dependent'
    % vcon_eq depends on x (Jcon_x != 0) => must fail-closed.
    vcon_spec = struct( ...
        'vcon_vars',[3,4], 'vcon_rows',[3,4], ...
        'vcon_eq',@(x,y) [y(3)-1.0+x(1); y(4)-0+x(2)]);
case 'rank_deficient'
    % vcon_eq has rank-deficient Jacobian (both constraints identical).
    vcon_spec = struct( ...
        'vcon_vars',[3,4], 'vcon_rows',[3,4], ...
        'vcon_eq',@(x,y) [y(3)-1.0; y(3)-1.0]);
case 'mismatched'
    % numel(vcon_vars) != numel(vcon_rows).
    vcon_spec = struct( ...
        'vcon_vars',[3,4], 'vcon_rows',[3], ...
        'vcon_eq',@(x,y) [y(3)-1.0]);
otherwise
    error('synthetic_slack_case:badVariant', 'Unknown variant "%s".', variant);
end
end
