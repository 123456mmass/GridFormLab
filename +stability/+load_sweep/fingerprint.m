function fp = fingerprint(case_data)
%FINGERPRINT  Load-sweep fingerprint contract (distinct from wizard-config / Section-H).
%   FP = stability.load_sweep.fingerprint(CASE_DATA) returns a struct fingerprint
%   covering schema-owned numerical/source fields of a power_case/1.0 or
%   smib_verification/1.0 case. Used to record base-case and scaled-case
%   identity in the load-sweep audit; NOT a wizard-config or Section-H
%   fingerprint and must not be reused with a different meaning elsewhere.

fp = struct();
fp.schema_version = '';
if isstruct(case_data)
    if isfield(case_data,'schema_version') && ~isempty(case_data.schema_version)
        fp.schema_version = char(case_data.schema_version);
    end
    if isfield(case_data,'system_name') && ~isempty(case_data.system_name)
        fp.system_name = char(case_data.system_name);
    end
    if isfield(case_data,'base_values') && isstruct(case_data.base_values)
        bv = case_data.base_values;
        keys = {'S_base_MVA','V_base_kV','frequency_Hz'};
        for k = 1:numel(keys)
            if isfield(bv,keys{k}) && ~isempty(bv.(keys{k}))
                fp.(keys{k}) = bv.(keys{k});
            end
        end
    end
    if isfield(case_data,'bus_data') && ismatrix(case_data.bus_data)
        fp.bus_count = size(case_data.bus_data,1);
        fp.bus_ids = case_data.bus_data(:,1).';
        fp.Pload_pu_sum = sum(case_data.bus_data(:,7));
        fp.Qload_pu_sum = sum(case_data.bus_data(:,8));
    end
    if isfield(case_data,'mpc') && isstruct(case_data.mpc) && ...
            isfield(case_data.mpc,'bus') && ismatrix(case_data.mpc.bus)
        fp.mpc_Pd_MW_sum = sum(case_data.mpc.bus(:,3));
        fp.mpc_Qd_MVAr_sum = sum(case_data.mpc.bus(:,4));
    end
    if isfield(case_data,'smib_verification') && isstruct(case_data.smib_verification)
        sv = case_data.smib_verification;
        fp.smib_kind = char(sv.kind);
        fp.smib_V_terminal = sv.V_terminal;
        fp.smib_P_terminal_pu = sv.P_terminal_pu;
        fp.smib_Q_terminal_pu = sv.Q_terminal_pu;
        fp.smib_Z_line_pu = sv.Z_line_pu;
    end
    if isfield(case_data,'smib_loaded_ibr') && isstruct(case_data.smib_loaded_ibr)
        ml = case_data.smib_loaded_ibr;
        fp.smib_loaded_kind = char(ml.kind);
        fp.smib_loaded_V_infinite = ml.V_infinite_pu;
        fp.smib_loaded_Z_line = ml.Z_line_pu;
        fp.smib_loaded_P_load = ml.P_load_base_pu;
        fp.smib_loaded_Q_load = ml.Q_load_base_pu;
        fp.smib_loaded_P_ibr = ml.P_ibr_base_pu;
        fp.smib_loaded_Q_ibr = ml.Q_ibr_base_pu;
    end
end
% Checksum: assemble the available load-sum fields across schemas into a
% stable dimensionless key. Fields absent for a given schema are skipped.
checksum_fields = {};
checksum_values = [];
if isfield(fp,'Pload_pu_sum')
    checksum_fields{end+1} = 'Pload_pu_sum'; %#ok<AGROW>
    checksum_values(end+1) = fp.Pload_pu_sum; %#ok<AGROW>
end
if isfield(fp,'Qload_pu_sum')
    checksum_fields{end+1} = 'Qload_pu_sum'; %#ok<AGROW>
    checksum_values(end+1) = fp.Qload_pu_sum; %#ok<AGROW>
end
if isfield(fp,'mpc_Pd_MW_sum')
    checksum_fields{end+1} = 'mpc_Pd_MW_sum'; %#ok<AGROW>
    checksum_values(end+1) = fp.mpc_Pd_MW_sum; %#ok<AGROW>
end
if isfield(fp,'mpc_Qd_MVAr_sum')
    checksum_fields{end+1} = 'mpc_Qd_MVAr_sum'; %#ok<AGROW>
    checksum_values(end+1) = fp.mpc_Qd_MVAr_sum; %#ok<AGROW>
end
if isfield(fp,'smib_loaded_P_load')
    checksum_fields{end+1} = 'smib_loaded_P_load'; %#ok<AGROW>
    checksum_values(end+1) = fp.smib_loaded_P_load; %#ok<AGROW>
end
if isfield(fp,'smib_loaded_Q_load')
    checksum_fields{end+1} = 'smib_loaded_Q_load'; %#ok<AGROW>
    checksum_values(end+1) = fp.smib_loaded_Q_load; %#ok<AGROW>
end
fp.checksum_fields = checksum_fields;
fp.checksum = matlab.lang.makeValidName(mat2str(round(checksum_values,12)), ...
    'ReplacementStyle','underscore');
end
