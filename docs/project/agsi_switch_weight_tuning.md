# AGSI++ switching weight / threshold tuning (provenance)

**Tool:** `scripts/reporting/optimize_agsi_weights.m` (project-owned base MATLAB;
**no external optimization solver**, not on any production runtime path).
**Method (NUMERICAL_METHOD):** uniform-simplex random search over the six AGSI++
weights `[w_V w_f w_R w_P w_SCR w_lock]` (>=0, sum = 1) and the thresholds
`Gamma_on / Gamma_off`, followed by a coordinate local refine. Guided by the
EECON49-P4 Bayesian-Optimization concept; implemented as an offline design-time
search whose output is *frozen* as documented study parameters (it is not read
back into production at run time).

**Objective (minimise), IEEE 14-bus 1-SG + 4-IBR, SG-trip@1 s + reclose@4 s, T=6 s:**

    J = 12 * mean_t|1 - Vmin(t)|  +  0.6 * (total mode switches)  +  0.05 * max AGSI
        (+ 1e5 penalty on divergence / non-convergence)

## Result (seed 1, 32 random + 4 refine passes)

| parameter | hand-set baseline | search optimum |
|-----------|------------------:|---------------:|
| w_V       | 0.25 | 0.134 |
| w_f       | 0.25 | 0.178 |
| w_R       | 0.25* | 0.123 |
| w_P       | 0.15 | 0.186 |
| w_SCR     | 0.15 | 0.379 |
| w_lock    | 0.10 | 0.000 |
| Gamma_on  | 0.65 | 0.511 |
| Gamma_off | 0.35 | 0.358 |
| **J**     | **11.959** | **11.906** |

(\*baseline AGSI++ weights are `[0.25 0.25 0.15 0.10 0.15 0.10]`.)

## Conclusion (frozen decision)

The search improves the objective by only **0.4 %**, i.e. the hand-set AGSI++
weights and thresholds are **already near-optimal** for the stable IEEE 14-bus
operating point. The optimum leans toward the grid-strength term `w_SCR`
(consistent with weak-grid GFL instability being the dominant stress) and
drops `w_lock`, but the gain is negligible and the hand-set weights are more
physically interpretable and balanced.

**Decision:** keep the hand-set defaults
`[w_V,w_f,w_R,w_P,w_SCR,w_lock] = [0.25,0.25,0.15,0.10,0.15,0.10]`,
`Gamma_on = 0.65`, `Gamma_off = 0.35` (SwitchableIbr6 defaults) as the frozen
study values; the search is retained as a reproducible tuning tool that
*validates* the choice.

**Reproduce:**
```matlab
pf_init_paths;
best = optimize_agsi_weights(n_random=32, n_refine=4, T=6);
```

Classification: ASSUMED_DIAGNOSTIC design-time tuning; the objective, search,
and decision were frozen before use in the report.
