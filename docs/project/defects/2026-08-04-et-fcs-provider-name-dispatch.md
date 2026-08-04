# ET-FCS-2026-08-04-01 — ET-FCSPS provider-name dispatch

Status: `RESOLVED`
Area: additive ET-FCSPS project-provider interface
Affected tree: uncommitted implementation on `main` after `6eeb05c`
Environment: MATLAB batch on Windows, 4 August 2026

## Observation

The diagnostic function-handle providers passed, but the production-classified
trial-table test returned `INFEASIBLE` with
`stability:et_fcs_supervisor:internalFailure`. The captured cause was:

```text
Undefined function 'func2str' for input arguments of type 'char'.
```

Reproduction:

```matlab
restoredefaultpath;
cd('D:/Project/Power-flow');
addpath(pwd); pf_init_paths; rehash;
s = testsuite('tests/test_et_fcs_supervisor.m', ...
    'ProcedureName','test_authenticated_trial_table_runs_with_project_owned_providers');
r = run(s);
```

## Root cause and falsified hypotheses

`et_fcs_screen` and `et_fcs_predict` called `func2str(provider)` before testing
whether `provider` was already a character/string function name. `func2str`
accepts a function handle, not a character vector. The trial table and candidate
identity were not at fault: the callback was never reached, and the same
evidence passed through local function handles.

## Correction

Both provider validators now branch on type first:

- character/string provider: use `char(provider)` directly;
- function-handle provider: use `func2str(provider)`.

The existing rule remains unchanged: production providers must resolve under
`stability.*`; non-project callbacks require the explicit diagnostic-test flag.

## Verification

- authenticated project-owned trial-table test: 1/1 PASS;
- complete ET-FCSPS + BO suite: 19/19 PASS;
- Code Analyzer: zero issues in all `+stability/et_fcs_*.m` files and the test.

## Limitations

This fix validates dispatch and evidence authentication. It does not create the
nonlinear accepted-state trial producer or claim closed-loop IEEE14 performance.
