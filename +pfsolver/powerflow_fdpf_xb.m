function results = powerflow_fdpf_xb(case_data, options)
%POWERFLOW_FDPF_XB  Thin wrapper for FDPF-XB (Stott-Alsac original variant).
%   RESULTS = POWERFLOW_FDPF_XB(CASE_DATA, OPTIONS) calls the shared FDPF solver
%   with variant='XB'. The iteration loop, full-AC-mismatch recomputation,
%   factorization, and Q-limit PV->PQ switching live ONCE in powerflow_fdpf.m;
%   this wrapper only fixes the variant.
%
%   Source (VERIFIED): Stott & Alsac (1974), IEEE Trans. PAS-93, pp.859-869,
%   DOI 10.1109/TPAS.1974.293985. XB = standard FDL (remove R in B' only).
%
%   P1 scope (CORE_ONLY, NOT_ROUTED): tested by direct calls; solve_case.m
%   is NOT modified.
results = pfsolver.powerflow_fdpf(case_data, options, 'XB');
end
