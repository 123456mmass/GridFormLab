# Analysis Wizard footer, selection, and Events navigation

Status: RESOLVED

## Symptom

The desktop Analysis Wizard rendered Page 1 and highlighted an analysis row,
but displayed no navigation buttons, so the user could not continue. The case
page could also display its first row as selected without committing `case_id`,
and TS/IBR navigation skipped the Events page.

## Reproduction and affected tree

- Branch: `main`
- First affected delivery: `fe1c505`
- Environment: MATLAB desktop on Windows
- Reproduction: call `solve_case`, select an analysis, and observe the missing
  footer. The former batch smoke test only resolved page-builder function
  handles and therefore did not execute footer construction.

## Root cause

1. `render_page` passed `string(logical)` to the classic `uicontrol` `Enable`
   property. This produces `"0"` or `"1"`, while the property requires
   `'off'`, `'on'`, or `'inactive'`; construction stopped before the buttons
   were completed.
2. `p2_case` assigned an initial listbox `Value` but did not invoke the same
   callback used by a user selection, leaving application state empty.
3. Page 4 was statically marked disabled before the method-aware
   `events_applicable` check, so it was skipped for every analysis.

The earlier hypothesis that child deletion alone caused the initial-page
failure was incomplete. That correction addressed second-page re-rendering,
not the invalid `Enable` value during initial footer construction.

## Correction

- Map logical button state explicitly to `'on'`/`'off'`.
- Commit the displayed initial case through `p2_case_selected`.
- Keep Page 4 navigable in the page table and skip it dynamically only for
  PF/SSSA.
- Reserve footer space and use compact Page 1/Page 2 layouts similar to the
  former launcher dialog.
- Extend the smoke test to render a real hidden classic figure and exercise
  callbacks/navigation rather than checking function resolution alone.
- Restore compact legacy-style dialogs as the default `solve_case()`
  interactive surface after user desktop review rejected the six-page layout.
  The shared pure dispatcher remains unchanged.

## Verification and limitations

Verification on MATLAB R2025a / Windows:

- Actual hidden-figure UI render and callback smoke: 21 passed / 0 failed.
- Wizard pure/dispatch/Section-H and existing launcher targeted suite:
  66 passed / 0 failed / 0 incomplete.

The hidden-figure gate proves footer construction, analysis selection, initial
case commit, IBR Events navigation, and PF Events skipping on the real classic
graphics objects. Final appearance remains subject to normal user desktop
visual acceptance.

The blank fallback Results page was also traced to a package-qualified call to
`p6_section_text` even though it is local to `p6_render_section.m`; the call is
now local. The compact legacy flow does not depend on that page.

No PF, equilibrium, SSSA, TS, IBR equation, parameter, tolerance, or numerical
solver was changed. Full repository regression was intentionally not rerun by
user request; interactive visual acceptance remains a user desktop check.
