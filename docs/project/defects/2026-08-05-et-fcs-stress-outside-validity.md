# ET-FCSPS reference-PCC stress outside candidate validity

Status: `RESOLVED_DIAGNOSTIC_BOUNDARY`

## Observation

The predeclared reference-PCC stress schedule (bus-2 fault 19.75--20.00 s,
SG trip at 20.0125 s) completed the legacy selector arm to 160 s, but the
authenticated ET-FCSPS candidate producer rejected every candidate before
prediction: `screen=0/32`, with voltage-violation and incomplete-evidence
failures. No ET or BO long-run result was claimed.

## Reproduction

```matlab
pf_init_paths;
addpath(fullfile(pwd,'scripts','reporting'));
run_ieee14_controller_comparison(reuse_completed=true, ...
    case_id='reference_fault_stress');
```

The cached legacy arm is finite and converged to 160 s (`min |V|=0.13926685`
pu including the fault); the failure occurs only while constructing the
post-trip candidate table from the accepted event-left state.

## Evidence-backed boundary

The fault is cleared only one fixed step before SG loss. The accepted state is
therefore still a severe transient, and the fixed hard candidate domain
requires post-trip voltage in `[0.80,1.20]` pu. The failure is not a selector
ranking error, BO error, or solver crash. It is a deliberate fail-closed
outcome: no candidate has authenticated evidence satisfying the declared
production screen.

## Follow-up

The stress matrix retains this case as an outside-validity diagnostic and adds
a second frozen case with the same bus/fault and SG-trip identities but a
0.5125-s recovery interval (fault clear 19.50 s, SG trip 20.0125 s). This tests
the controller inside its declared candidate domain without changing equations,
thresholds, weights, or solver settings. A controller benefit is reported only
if all three arms reach 160 s and raw metrics differ; otherwise the result is
null or fail-closed.
