# `events/` — transient-stability event settings

Every file here is a plain, hand-editable MATLAB function file. **Open one,
change four numbers, run.** There is nothing to compile, no JSON to get wrong,
and no GUI state involved: the file *is* the setting.

```
events/evt_ne39_bus_fault.m      IEEE 39-bus New England, bus fault
events/evt_ieee14_bus_fault.m    IEEE 14-bus, bus fault
events/evt_rts24_bus_fault.m     IEEE RTS-24, bus fault
events/evt_kundur_bus_fault.m    Kundur Example 12.6, bus fault
events/evt_template.m            copy-me starter for a new event
```

## The four values you edit

| Field | Meaning | Notes |
|---|---|---|
| `ev.fault_bus` | External bus ID of the faulted bus | Must exist in the case |
| `ev.ds` | **Fault duration, seconds** | The single authoritative duration |
| `ev.trip` | Machine trip time, s | `[]` = no trip |
| `ev.Zf` | Fault impedance, pu | e.g. `1i*0.1`, or `0.05` for a resistive fault |

`ev.case_id` names the case the numbers belong to (`'ieee14'`, `'ne39'`,
`'rts24'`, `'kundur'`, …). Everything else in the file is advanced and already
has a derived default — leave it alone.

## `ds` is the only duration. `fault_clear` is never stored.

The instant the fault is cleared is **always derived**:

```
fault_clear = t_fault + ds
```

so changing `ds` from `0.10` to `0.15` moves the clearing instant by exactly
that much, everywhere, with no second number to keep in sync. The ordering
`fault_on < fault_clear <= trip < sg_on` is then either preserved or it fails
closed with a named error — never silently reordered.

## Copy-me

```matlab
copyfile('events/evt_template.m', 'events/evt_my_study.m')
% rename the function inside to evt_my_study, then edit the four values
```

Two rules the machinery enforces:

- The file name **must** start with `evt_` and the function name must equal
  the file name. `+events/list.m` refuses to list anything that does not
  resolve inside this folder, so a same-named file elsewhere on the MATLAB
  path can never be run by accident.
- The field list is closed. A typo such as `ev.faultbus = 16` fails closed
  instead of silently leaving `fault_bus` unset.

## Running one

```matlab
ev  = events.load('ne39_bus_fault');   % or events.load('evt_ne39_bus_fault')
events.describe(ev)                    % what this file currently says
opt = events.resolve(ev, case_data);   % fold it into the launcher options
```

`events.resolve` writes the option names the launchers actually read
(`fault_enabled`/`fault_bus`/`t_fault`/`t_clear`/`Zf` for
`stability.ts_simulate`; `ibr_events` for `stability.ibr_event_schedule`) and
does nothing else — it never clips, sorts or relaxes a value.

## Validation: what is caught here, and what is caught at run time

`events.validate` checks the cheap things before a run: the schema, a
malformed `case_id`, an unknown or missing `fault_bus`, a non-positive `ds`, a
zero `Zf`, a malformed event instant, and `trip` before the fault clears.

It deliberately does **not** duplicate the runtime gates. The legal set of
profile names, which events a profile arms, whether a sequence is admissible,
and coincident-event ambiguity all belong to
`stability.ibr_event_schedule` and `stability.ts_prevalidate_events`. There is
exactly one ordering authority, and it is those two.
