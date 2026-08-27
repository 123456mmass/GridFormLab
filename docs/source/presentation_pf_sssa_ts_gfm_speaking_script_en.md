# English Speaking Script — Automatic Following/Forming Framework

Target speaking time: 15-20 minutes. The script discusses results and mathematics only.

## Slide 1 — Title

Good morning. We are Phichitchai Jueajan and Pakkapol Phdungdan from the Department of Electrical Engineering, KMITL, under the supervision of Dr. Tossaporn Surinkaew. Our project develops and evaluates an automatic framework that changes inverter-based resources between grid-following and grid-forming reference behaviour. The analysis connects power flow, small-signal stability, and transient stability on one modified IEEE 14-bus study system.

## Slide 2 — Problem and contribution

A grid-following converter needs an existing voltage-angle reference. A grid-forming converter can create that reference, but keeping every converter in grid-forming mode is not automatically better. The operating question is therefore: after the synchronous reference is lost, how many converters should form the grid, which converters should be selected, and through what transition route? Our contributions are a unified mathematical analysis, a current-continuous dual-mode transfer, exhaustive screening of all fifteen non-empty converter sets, and a five-policy dynamic comparison.

## Slide 3 — Mathematical analysis chain

The analysis begins with the AC power-flow residual and the correct REF, PV, and PQ specifications. The solved equilibrium then defines the differential-algebraic model. Small-signal stability follows from the Schur complement, while transient stability uses an implicit trapezoidal residual for the differential and algebraic variables together. A mode change is treated separately from time integration: the destination controller coordinates are assigned at the current operating point, and the terminal-current discontinuity must remain below (10^{-10}) per unit.

## Slide 4 — Defensible parameter choices

The switching signal combines normalised voltage and frequency deviations. The voltage base is 0.10 per unit and the frequency base is 0.50 hertz, so the two terms are dimensionless before equal weighting. Promotion uses the upper threshold for 0.10 seconds, while release uses the lower threshold for 1.00 second. This creates hysteresis and makes support faster than release. The DC-source response was also frozen before measurement: the maximally-flat target predicts approximately 15.5 hertz and damping 0.7071. The assembled system later returns 15.18 to 15.66 hertz and damping 0.7072 to 0.7079.

## Slide 5 — Independent PF and SSSA validation

Before studying converter switching, the base analysis is compared with PSAT on classical-machine cases using identical mapped inputs. The network admittance and power-flow solutions agree at machine precision on IEEE 14 and RTS-24. In the small-signal comparison, all four oscillatory frequencies match to the printed precision. These are validation results, not inputs to the proposed switching decision.

## Slide 6 — Independent transient validation

The transient comparison evaluates rotor angle, speed, electrical power, and fault-bus voltage over the same event and time grid. Every maximum difference remains within its tolerance declared before comparison. For example, the maximum centre-of-inertia angle difference is about 0.0096 degrees against a 0.05-degree limit. This establishes the classical transient baseline before introducing dual-mode converters.

## Slide 7 — Dual-mode switching contract

Each converter stores a seventeen-coordinate superset. Grid-following activates ten coordinates, grid-forming activates eleven, and a tripped device activates none. The two controller branches are exclusive. The severity signal determines when support is requested, but a transition is committed only after the destination operating point satisfies current continuity and the network equilibrium. Four additional indices are diagnostic only and do not enter the switching gate.

## Slide 8 — Study network

The modified IEEE 14-bus system has one synchronous generator at bus 1 and four dual-mode converters at buses 2, 3, 6, and 8. In healthy operation the synchronous generator owns the angle reference. After it trips, at least one authenticated grid-forming converter must own the island reference. All generators, converters, loads, and branches remain coupled through the same network current-balance equation.

## Slide 9 — Two operating-point spectra

With the synchronous machine online and all converters following, the electromechanical mode has damping 0.156, more than three times the declared 0.05 requirement. After the machine trips and one converter forms, every physical eigenvalue remains in the left half plane. The slowest mode is associated with the voltage loop, while the DC pairs appear near 15 hertz. This is a local result at one equilibrium, so it is necessary evidence but not a trajectory certificate.

## Slide 10 — DC-link prediction and measurement

The DC source was changed from an ideal source to a non-ideal second-order source. Before evaluating the assembled spectrum, the selected damping target predicts a pole pair near 15.5 hertz with damping 0.7071. The four measured pairs fall between 15.18 and 15.66 hertz with damping from 0.7072 to 0.7079. However, the AC command is not limited by available DC voltage in this model. Therefore this result does not establish DC-limited ride-through.

## Slide 11 — How many and which converters

There are fifteen non-empty subsets of four converters. Each subset is solved at its own equilibrium and screened using the declared small-signal conditions. Seven sets are admissible. The result is non-monotonic: every one-converter set passes, no three-converter set passes, and the best damping margin occurs with two converters at buses 3 and 6. The all-four set passes the linear screen but fails when held from the trip, proving that local admissibility is not sufficient for dynamic reachability.

## Slide 12 — Disturbance chronology

The trajectory contains six operating periods. The synchronous generator trips at 20 seconds, the load increases by 20 percent at 50 seconds, a bus-9 fault is applied from 85.000 to 85.150 seconds, line 6–13 opens at 110 seconds, and the generator is commanded to reclose at 145 seconds. The achieved reclose and release times are measured outcomes, not scheduled inputs.

## Slide 13 — Supervisor decision

The top panel shows the severity signal and both thresholds. The middle panel shows the actual grid-following and grid-forming modes, and the bottom panel shows the angle-reference owner. The mode changes occur after the required dwell rather than exactly at the disturbance instant. Support rises in stages to four grid-forming converters, then is released after the machine successfully returns. The final condition has no converter in grid-forming mode because the synchronous machine owns the reference again.

## Slide 14 — Electrical response

When the machine trips, its active and reactive powers fall to zero and the converters take up the islanded demand. The frequency exhibits both under- and overshoot during the sequence, while the minimum voltage collapses only during the fault. After the machine recloses, power sharing transfers back and the terminal frequency reaches 60.000001 hertz. These extrema are model results under a severe chronology, not equipment ratings.

## Slide 15 — Why switching is necessary

The comparison falsifies two static alternatives. If no converter may form the grid, the post-trip equilibrium is refused immediately because no voltage-angle reference exists. If all four converters are pinned in grid-forming mode, power, frequency, and voltage hunt until the trajectory terminates near 25.49 seconds. The automatic policy stages the same resources, crosses all six scheduled disturbances, and settles without the persistent hunting seen in the pinned case.

## Slide 16 — Conclusions and limits

The main result is not that more grid-forming converters are always better. The admissible set is non-monotonic, the transition route matters, and at least one voltage-forming resource is necessary after reference loss. The complete 250-second chronology recloses the machine and returns every converter to grid-following mode. We do not claim grid-code compliance, multi-machine generality, superiority over other selectors, or DC-limited ride-through. These are explicit boundaries of the present study.
