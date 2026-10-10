function labels = shorten_labels(labels)
%DEPRECATED (Phase C): superseded by the Studio GUI (+studio/launch.m).
%   Header banner only; behavior unchanged.
labels = regexprep(labels, 'Saadat ', '');
labels = regexprep(labels, 'IEEE ', 'IEEE');
labels = regexprep(labels, '-bus', '');
end
