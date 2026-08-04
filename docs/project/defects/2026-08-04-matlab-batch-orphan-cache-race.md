# SWITCH-2026-08-04-04 — MATLAB batch orphan and cache-write race

- **Status:** RESOLVED_FOR_THIS_RUN
- **Area:** unattended diagnostic execution
- **Environment:** Windows, MATLAB R2026a, branch `main`, 2026-08-04 switching tree

## Symptom and reproduction

Terminating the yielded shell cell that launched
`matlab -batch "run('scripts/diagnostics/probe_regfm_post_trip_20260804.m')"`
stopped the shell monitor but did not terminate its MATLAB child process. A later
replacement run therefore left two 160-s simulations active. Both used the same
output path, `output/diagnostics/regfm_post_trip_probe.mat`, creating a possible
last-writer-wins provenance race.

## Root cause and evidence

`Win32_Process` showed two distinct MATLAB parent/child pairs. The obsolete pair
had creation time 13:23 and the accepted replacement pair had creation time 13:29.
The shell-cell termination did not propagate to the first MATLAB child. This is
an execution-orchestration trap; it does not change a project equation or solver.

## Resolution and verification

The exact obsolete PIDs were resolved and terminated. A second `Win32_Process`
query verified that only the 13:29 replacement pair remained. Final cache
provenance must use the terminal output and elapsed time from that surviving run.
Future reruns must inspect MATLAB child processes after terminating a yielded
shell cell and before reusing a shared output filename.

## Limitations

This record does not change MATLAB, the report generator, or numerical results.
It prevents an obsolete process from overwriting a cache produced by a newer
source tree.
