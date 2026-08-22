function out = write_sssa_modes_compact(src_file, dst_file)
%WRITE_SSSA_MODES_COMPACT  Five-column projection of a generated modal table.
%   The new English report requests a modal table showing
%   `No. | eigenvalue | f | damping ratio | dominant state`. This function
%   PROJECTS COLUMNS out of the already-generated five-column table produced by
%   `generate_gfl_gfm_sssa_tables`. It is a presentation-only transform:
%
%     * no eigenvalue, frequency or damping ratio is recomputed, reformatted,
%       rounded or reordered;
%     * the retained dominant entry is the FIRST (largest) normalised
%       participation entry exactly as the generator ranked and printed it;
%     * only the trailing participation entries are dropped, not altered.
%
%   Deriving the compact table from the generated table (instead of
%   re-deriving participation factors from the selector cache) guarantees
%   that both tables in the report carry bit-identical numbers.
%
%   out = WRITE_SSSA_MODES_COMPACT(src_file, dst_file)

arguments
    src_file (1,1) string
    dst_file (1,1) string
end

if ~exist(src_file,'file')
    error('write_sssa_modes_compact:missingSource', ...
        'Generated modal table %s does not exist.', src_file);
end

txt = string(splitlines(string(fileread(src_file))));

hdr_kept = 0; rows = strings(0,1); prov = strings(0,1);
for i = 1:numel(txt)
    L = strtrim(txt(i));
    if startsWith(L,"%")
        prov(end+1,1) = txt(i); %#ok<AGROW>
        continue
    end
    % A data row is `N & $...$ & $f$ & $zeta$ & participation \\`
    if ~startsWith(L,"\") && contains(L,"&") && endsWith(L,"\\")
        parts = split(erase(L,"\\"), "&");
        if numel(parts) < 5, continue, end
        no   = strtrim(parts(1));
        lam  = strtrim(parts(2));
        fhz  = strtrim(parts(3));
        zeta = strtrim(parts(4));
        domf = strtrim(strjoin(parts(5:end),"&"));
        % keep only the leading (dominant) participation entry
        semi = strfind(domf,";");
        if ~isempty(semi), domf = strtrim(extractBefore(domf,semi(1))); end
        if double(no) ~= round(double(no)) || isnan(double(no)), continue, end
        rows(end+1,1) = sprintf('%s & %s & %s & %s & %s \\\\', ...
            no, lam, fhz, zeta, domf); %#ok<AGROW>
        hdr_kept = hdr_kept + 1;
    end
end

if isempty(rows)
    error('write_sssa_modes_compact:noRows', ...
        'No modal rows were recognised in %s.', src_file);
end

head = [ ...
    "% Presentation-only five-column projection of " + src_file + "."
    "% Numbers are copied verbatim; only trailing participation entries are dropped."
    prov
    "\begingroup\footnotesize\setlength{\tabcolsep}{5pt}"
    "\begin{longtable}{@{}r l r r l@{}}"
    "\toprule"
    "No. & Eigenvalue $\lambda$ (s$^{-1}$) & $f$ (Hz) & $\zeta$ & Dominant state \\ \midrule"
    "\endfirsthead"
    "\toprule"
    "No. & Eigenvalue $\lambda$ (s$^{-1}$) & $f$ (Hz) & $\zeta$ & Dominant state \\ \midrule"
    "\endhead"];

tail = [ ...
    "\bottomrule"
    "\end{longtable}\endgroup"];

fid = fopen(dst_file,'w');
if fid < 0
    error('write_sssa_modes_compact:openFailed','Cannot write %s.', dst_file);
end
cleaner = onCleanup(@() fclose(fid));
fprintf(fid,'%s\n', head{:});
fprintf(fid,'%s\n', rows{:});
fprintf(fid,'%s\n', tail{:});

out = struct('source',src_file,'target',dst_file,'rows',numel(rows));
end
