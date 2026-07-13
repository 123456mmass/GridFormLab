function results = powerflow_fdpf_bx(case_data, options)
%POWERFLOW_FDPF_BX  Thin wrapper for FDPF-BX (van Amerongen proposed variant).
%   RESULTS = POWERFLOW_FDPF_BX(CASE_DATA, OPTIONS) calls the shared FDPF solver
%   with variant='BX'. The iteration loop, full-AC-mismatch recomputation,
%   factorization, and Q-limit PV->PQ switching live ONCE in powerflow_fdpf.m;
%   this wrapper only fixes the variant.
%
%   Source (VERIFIED): van Amerongen (1989), IEEE Trans. Power Systems 4(2),
%   pp.760-766. BX = proposed new version (remove R in B'' only).
%
%   P1 scope (CORE_ONLY, NOT_ROUTED): tested by direct calls; solve_case.m
%   is NOT modified.
results = pfsolver.powerflow_fdpf(case_data, options, 'BX');
end
