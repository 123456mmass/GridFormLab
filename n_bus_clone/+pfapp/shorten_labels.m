function labels = shorten_labels(labels)
labels = regexprep(labels, 'Saadat ', '');
labels = regexprep(labels, 'IEEE ', 'IEEE');
labels = regexprep(labels, '-bus', '');
end
