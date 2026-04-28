function update_dashboard_metrics(app, titles, values, captions, colors)
%UPDATE_DASHBOARD_METRICS Refresh the four dashboard metric cards.

if nargin < 5 || isempty(colors)
    colors = repmat({[0.02 0.44 0.62]}, 1, 4);
end

for i = 1:4
    title_field = sprintf('metric_title_%d', i);
    value_field = sprintf('metric_value_%d', i);
    caption_field = sprintf('metric_caption_%d', i);
    card_field = sprintf('metric_card_%d', i);

    if isfield(app, title_field)
        app.(title_field).Text = titles{i};
        app.(title_field).FontColor = colors{i};
    end
    if isfield(app, value_field)
        app.(value_field).Text = values{i};
    end
    if isfield(app, caption_field)
        app.(caption_field).Text = captions{i};
    end
    if isfield(app, card_field)
        app.(card_field).BorderColor = colors{i} + (1 - colors{i}) * 0.55;
    end
end
end
