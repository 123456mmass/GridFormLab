function result = kundur_ex126_sixth_order_ssa(varargin)
%KUNDUR_EX126_SIXTH_ORDER_SSA 6th-order Kundur Example 12.6 SSSA.
%
%   RESULT = kundur_ex126_sixth_order_ssa() preserves the public API used by
%   the report and presentation material. The implemented machine model is
%   the Sauer-Pai 6th-order formulation in
%   +stability/kundur_ex126_sauer_pai_ssa.m:
%
%       x_i = [delta_i; omega_i; E'_qi; E'_di; psi''_di; psi''_qi]
%
%   No external power-system toolbox is used. The operating point comes from
%   +pfsolver/powerflow_newton_raphson and the DAE is linearised with base
%   MATLAB numerical differentiation/eig.

result = stability.kundur_ex126_sauer_pai_ssa(varargin{:});
result.model_name = '6th-order Sauer-Pai synchronous-machine model';
end
