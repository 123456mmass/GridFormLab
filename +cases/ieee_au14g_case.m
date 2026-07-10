function c = ieee_au14g_case(case_id)
%IEEE_AU14G_CASE Load IEEE PES AU14G benchmark parameters from RAW/DYR files.
% This loader intentionally reads network and dynamic model parameters, not
% the published A matrix.  It is the entry point for model-reconstruction
% validation of the AU14G benchmark.

if nargin < 1, case_id = 1; end
root = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'docs', 'benchmark_sources', 'ieee_au14g', 'modeldata', 'AU14GenModelData_Ver04');
raw = fullfile(root, sprintf('LF_Case%02d_R4_S.raw', case_id));
dyr = fullfile(root, sprintf('PSSE_DYN_Case%02d.dyr', case_id));
if ~isfile(raw) || ~isfile(dyr)
    error('ieee_au14g_case:missingFiles', 'AU14G RAW/DYR files not found. Run the benchmark data download step first.');
end
c = struct();
c.name = sprintf('IEEE PES AU14G Case %02d', case_id);
c.raw_file = raw;
c.dyr_file = dyr;
c.raw = parse_raw_minimal(raw);
c.dyn = parse_dyr_minimal(dyr);
c.gen_buses = [c.dyn.generators.bus].';
c.generator_count = numel(c.dyn.generators);
c.sbase = c.raw.sbase;
c=cases.standardize_study_case(c,'dynamic_benchmark');
end

function raw = parse_raw_minimal(path)
lines = readlines(path); lines = strip(lines);
header = split(lines(1), ',');
raw.sbase = str2double(strtrim(header(2)));
raw.buses = struct('bus',{},'name',{},'basekv',{},'type',{},'vm',{},'va_deg',{});
raw.loads = struct('bus',{},'id',{},'pl',{},'ql',{});
section = 'bus';
for i = 2:numel(lines)
    ln = char(lines(i));
    if isempty(strtrim(ln)), continue; end
    if startsWith(strtrim(ln),'0 / END OF BUS DATA'), section = 'load'; continue; end
    if startsWith(strtrim(ln),'0 / END OF LOAD DATA'), break; end
    if strcmp(section,'bus')
        parts = split_csv_psse(ln);
        if numel(parts) >= 9
            raw.buses(end+1,1) = struct('bus',str2double(parts{1}), 'name',strip_quotes(parts{2}), ...
                'basekv',str2double(parts{3}), 'type',str2double(parts{4}), ...
                'vm',str2double(parts{8}), 'va_deg',str2double(parts{9}));
        end
    elseif strcmp(section,'load')
        parts = split_csv_psse(ln);
        if numel(parts) >= 8
            raw.loads(end+1,1) = struct('bus',str2double(parts{1}), 'id',strip_quotes(parts{2}), ...
                'pl',str2double(parts{6}), 'ql',str2double(parts{7}));
        end
    end
end
end

function dyn = parse_dyr_minimal(path)
lines = readlines(path);
dyn.generators = struct('bus',{},'model',{},'id',{},'params',{},'comment',{});
dyn.exciters = struct('bus',{},'model',{},'id',{},'params',{},'comment',{});
dyn.pss = struct('bus',{},'model',{},'id',{},'params',{},'comment',{});
for i = 1:numel(lines)
    ln = char(strip(lines(i)));
    if isempty(ln) || startsWith(ln,'//'), continue; end
    if ~contains(ln, ''''), continue; end
    comment = '';
    slash = strfind(ln,'/');
    if ~isempty(slash)
        comment = strtrim(ln(slash(1)+1:end));
        ln = strtrim(ln(1:slash(1)-1));
    end
    toks = regexp(ln, '''([^'']+)''|[-+]?\d*\.?\d+(?:[Ee][-+]?\d+)?', 'match');
    if numel(toks) < 3, continue; end
    bus = str2double(toks{1}); model = strip_quotes(toks{2}); id = str2double(toks{3});
    params = nan(max(0,numel(toks)-3),1);
    for k = 4:numel(toks), params(k-3) = str2double(toks{k}); end
    rec = struct('bus',bus,'model',model,'id',id,'params',params,'comment',comment);
    if any(strcmp(model, {'GENROE','GENSAL'}))
        dyn.generators(end+1,1) = rec;
    elseif any(strcmp(model, {'ESST1A','ESAC1A'}))
        dyn.exciters(end+1,1) = rec;
    elseif any(strcmp(model, {'IEEEST'}))
        dyn.pss(end+1,1) = rec;
    end
end
end

function parts = split_csv_psse(ln)
% Split PSS/E CSV-ish line while preserving quoted names.
parts = regexp(ln, ',(?=(?:[^'']*''[^'']*'')*[^'']*$)', 'split');
for k=1:numel(parts), parts{k}=strtrim(parts{k}); end
end

function s = strip_quotes(s)
s = strtrim(char(s));
if startsWith(s,'''') && endsWith(s,'''')
    s = s(2:end-1);
end
end
