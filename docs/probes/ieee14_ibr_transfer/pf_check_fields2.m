%PF_CHECK_FIELDS2  Detailed SG vs IBR struct field listing (Phase B root-cause).
%   STATUS: DIAGNOSTIC/WIP. Unreachable from production.
cd('/home/birds/Documents/Power-flow');
path(path,pwd); pf_init_paths; rehash; clear functions; clear classes; rehash; rehash path; rehash toolbox;
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
disp = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},'mode',{'gfl','gfl','gfl','gfl'});
[ibr_devs, ~] = ibr.build_ieee14_ibr_devices(c, modes, disp);
sg = stability.sg_composite_device(c, "SG1", 1, 1, [1:14]', 1.06, struct());
sgf = fieldnames(sg); ibf = fieldnames(ibr_devs(1));
fprintf('SG fields (%d):\n', numel(sgf));
for i=1:numel(sgf), fprintf('  %s\n', sgf{i}); end
fprintf('IBR fields (%d):\n', numel(ibf));
for i=1:numel(ibf), fprintf('  %s\n', ibf{i}); end
fprintf('in IBR not SG:\n');
for s = setdiff(ibf, sgf), fprintf('  %s\n', s{1}); end
fprintf('in SG not IBR:\n');
for s = setdiff(sgf, ibf), fprintf('  %s\n', s{1}); end
