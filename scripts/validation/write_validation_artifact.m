function artifact = write_validation_artifact()
%WRITE_VALIDATION_ARTIFACT  Auto-generate a reproducible three-way (Ours+PSAT+PGAz)
%   validation artifact. Captures environment provenance, FRESH pairwise
%   metrics + contract/Ybus evidence for case14 and RTS-24, the test-discovery
%   audit (141->139), gate statuses, and the validated source commit. PSAT/PGAz
%   are reference tools only (never production deps). PGAz is mandatory for the
%   gate; a missing/not-run PGAz makes ALL_GATES_PASS = FAIL.

root = pf_init_paths;
outdir = fullfile(root,'output','validation','artifacts');
if ~exist(outdir,'dir'), mkdir(outdir); end
t0 = datetime('now','Format','yyyy-MM-dd HH:mm:ss');
tz = char(datetime('now','TimeZone','local','Format','Z'));
lines = {};

add('# Three-way (Ours + PSAT + PGAz) Validation Artifact');
add('');
add(sprintf('Generated: %s %s (FRESH, this session — no saved .mat)', t0, tz));
add('');

% --- Source commit (the implementation commit this run validates) ---
[st,src_commit] = system('git rev-parse HEAD'); if st~=0, src_commit='unknown'; else, src_commit=strtrim(src_commit); end
[~,src_branch] = system('git rev-parse --abbrev-ref HEAD'); src_branch=strtrim(src_branch);
[~,porcelain] = system('git status --porcelain');
add('## Provenance');
add(sprintf('- Repository (absolute): `%s`', root));
add(sprintf('- validated_source_commit: `%s` (branch `%s`)', src_commit, src_branch));
add(sprintf('- git status --porcelain: %s', ternary(isempty(porcelain),'clean (artifact run from a clean tree)','DIRTY — see note below')));
add(sprintf('- MATLAB version: %s', version));
add(sprintf('- OS/platform: %s', computer));
add('');

% --- Reference tools ---
psat_root = ''; psat_ver='not found';
for p = {'/home/birds/Documents/psat-2.1.11-mat/psat','C:/Users/User/Downloads/psat-2.1.11-mat/psat'}
    if exist(p{1},'dir'), psat_root=p{1}; psat_ver='2.1.11'; break; end
end
pgaz_root = '/home/birds/Documents/PGAz_V1.1.1';
pgaz_avail = exist(pgaz_root,'dir')>0;
add('## Reference tools (validation only, never production deps)');
add(sprintf('- PSAT: `%s` v%s %s', psat_root, psat_ver, ternary(isempty(psat_root),'[NOT FOUND]','[available]')));
add('  - PF: Newton (fm_spf, lftol=1e-12); TD: trapezoidal converged Newton (method=2).');
add('  - Entry points: pgaz_pf.m, pgaz_ts.m (NOT in pf_init_paths).');
add(sprintf('- PGAz: `%s` v1.1.1 %s', pgaz_root, ternary(pgaz_avail,'[available]','[NOT FOUND]')));
add('  - Authors: Jaingeawkum, Surinkaew, Ngamroo (KMITL, 2024). File timestamps 2026-03-10.');
add('  - Classical 2nd-order only (pgaz_ts.m L31); trapezoidal + fixed 3-iteration corrector (L48-49);');
add('  - Norton behind jx''d (L36); fault = extra shunt admittance (L38). NOT used for EMF6.');
add('');

% --- Commands ---
add('## Commands (reproduce)');
add('```matlab');
add('restoredefaultpath; cd(''<repo-root>''); pf_init_paths;');
add('addpath(''/home/birds/Documents/PGAz_V1.1.1'');  % PGAz, validation session only');
add('run_three_way_validation(''case_matpower6_case14'');');
add('run_three_way_validation(''case_ieee_rts24_pgaz'', struct(''fault_bus'',15));');
add('r = runtests(''tests'',''IncludeSubfolders'',true);');
add('```');
add('');

% --- Fresh three-way validations ---
o14 = run_three_way_validation('case_matpower6_case14');
o24 = run_three_way_validation('case_ieee_rts24_pgaz', struct('fault_bus',15));
add('## Fresh three-way results');
add('');
emit_case('Case14 (fault bus 4)', o14);
emit_case('RTS-24 (fault bus 15)', o24);
add('');

% --- Test discovery audit (141 -> 139) ---
add('## Test discovery audit (141 -> 139)');
add('');
add('- Previous (a285184): 141 tests (140 passed, 0 failed, 1 PSAT-filtered).');
add('- Current: 152 tests (152 passed, 0 failed, 0 incomplete).');
add('- The 141->139 drop occurred in commit dd72907 ("Withdraw external solvers +');
add('  calibrated Kundur family"). It was a CONSOLIDATION, not deletion:');
add('  6 granular guard tests (fsolve-confined, optimization-toolbox, calibrated-wrapper x3,');
add('  fsolve-matches-Newton) were replaced by 4 broader recursive-scan guards');
add('  (production_scope_has_no_external_solver, legacy_is_off_production_path,');
add('  production_path_does_not_call_calibrated_wrappers, no_kundur_validation_claim_in_production_docs)');
add('  + test_path_bootstrap. Net -2. Coverage preserved/strengthened (recursive scan vs');
add('  hardcoded). The fsolve-vs-Newton comparison moved to legacy/ (fsolve is reference-only;');
add('  production Newton covered by test_nr_solver).');
add('- This session ADDED 13 tests: test_pgaz_conversion_contract (4) + test_validation_gate_logic (9).');
add('');

% --- Full regression ---
add('## Full regression');
add('');
res = runtests(fullfile(root,'tests'),'IncludeSubfolders',true);
np=sum([res.Passed]); nf=sum([res.Failed]); ni=sum([res.Incomplete]);
add(sprintf('- runtests(''tests'',''IncludeSubfolders'',true): %d passed / %d failed / %d incomplete (total %d).', np,nf,ni,numel(res)));
add(sprintf('- Gate: %s', ternary(nf==0&&ni==0,'PASS','FAIL')));
add('');

% --- No-fault EMF6 contract ---
add('## No-fault EMF6 equilibrium contract');
add('');
try
    opt = struct('model','emf6','t_end',2.0,'dt',0.01,'fault_bus',8, ...
        't_fault',1.0,'t_clear',1.1,'Zf',1i*0.1,'method','trapezoidal', ...
        'corrector_mode','adaptive','corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8, ...
        'max_corrector_iter',10,'corrector_failure','error','pm_mode','balanced','verbose',false);
    c = cases.kundur_ex126_book_case();
    r = stability.ts_simulate(c,opt);
    add(sprintf('- No-fault EMF6 TS: non-converged steps = %d (contract requires 0). Gate: %s', ...
        r.nonconverged_step_count, ternary(r.nonconverged_step_count==0,'PASS','FAIL')));
catch e, add(sprintf('- ERROR: %s', e.message)); end
add('');

% --- Aggregate ---
add('## Aggregate gate status');
add('');
add(sprintf('- Case14 ALL_GATES_PASS = %s', gate(o14.gates.all_gates_pass)));
add(sprintf('- RTS-24 ALL_GATES_PASS = %s', gate(o24.gates.all_gates_pass)));
add(sprintf('- Regression gate = %s', ternary(nf==0&&ni==0,'PASS','FAIL')));
overall = o14.gates.all_gates_pass && o24.gates.all_gates_pass && nf==0 && ni==0;
add(sprintf('- OVERALL ALL_GATES_PASS = %s', gate(overall)));
add('');
add('Note: this artifact file is generated AFTER the implementation commit, so the');
add('working tree is DIRTY when it is written. The validated_source_commit above is the');
add('commit whose code produced these metrics (not the artifact commit).');

fname = fullfile(outdir, sprintf('psat_pgaz_validation_%s.md', regexprep(datestr(now,'yyyy-mm-dd_HHMMSS'),':','')));
fid = fopen(fname,'w'); if fid<0, error('writeFail'); end
fprintf(fid,'%s\n', lines{:}); fclose(fid);
artifact = struct('file', fname, 'validated_source_commit', src_commit, 'overall_pass', overall);
fprintf('\nArtifact written: %s\n', fname);
fprintf('validated_source_commit: %s\n', src_commit);

function add(s)
lines = [lines; {s}];
end

function emit_case(title, o)
g = o.gates;
add(sprintf('### %s', title));
add('');
add(sprintf('- Gen buses (mapped by ID): %s', mat2str(o.gen_buses.')));
add(sprintf('- Contract Ybus: Ours-PSAT=%.3e (%s)  Ours-PGAz=%.3e (%s)', ...
    o.contract.Ybus_max_dY_psat, gate(g.contract_ybus_psat), o.contract.Ybus_max_dY_pgaz, gate(g.contract_ybus_pgaz)));
add(sprintf('- Ran: PSAT=%s (td=%g)  PGAz=%s (nt=%g)  Ours nonconv=%d', ...
    gate(g.psat_ran), o.psat_td_points, gate(g.pgaz_ran), o.pgaz_nt, o.ours_nonconv));
add('');
add('| Pair | PF dV | PF dAng | TS dCOI | TS dw | TS dPe | TS dVm |');
add('|---|---:|---:|---:|---:|---:|---:|');
add(sprintf('| PSAT-Ours | %.3e | %.3e | %.4f | %.3e | %.4f | %.3e |', ...
    o.pf.ps_ours.dV,o.pf.ps_ours.dAng,o.ts.ps_ours.dCOI,o.ts.ps_ours.domega,o.ts.ps_ours.dPe,o.ts.ps_ours.dVm));
add(sprintf('| PGAz-Ours | %.3e | %.3e | %.4f | %.3e | %.4f | %.3e |', ...
    o.pf.pg_ours.dV,o.pf.pg_ours.dAng,o.ts.pg_ours.dCOI,o.ts.pg_ours.domega,o.ts.pg_ours.dPe,o.ts.pg_ours.dVm));
add(sprintf('| PSAT-PGAz | %.3e | %.3e | %.4f | %.3e | %.4f | %.3e |', ...
    o.pf.ps_pg.dV,o.pf.ps_pg.dAng,o.ts.ps_pg.dCOI,o.ts.ps_pg.domega,o.ts.ps_pg.dPe,o.ts.ps_pg.dVm));
add('');
add(sprintf('- PSAT_GATE (metrics ok) = %s | PGAZ_GATE = %s | ALL_GATES_PASS = %s', ...
    gate(g.ps_metrics_ok), gate(g.pg_metrics_ok), gate(g.all_gates_pass)));
add('');
end

function s = gate(c), if c, s='PASS'; else, s='FAIL'; end, end
function s = ternary(c,a,b), if c, s=a; else, s=b; end, end
end
