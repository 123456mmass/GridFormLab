function style_result_table(app, mode)
%STYLE_RESULT_TABLE Apply lightweight table styling for common result modes.

try
    removeStyle(app.result_table);
catch
    % Older MATLAB releases may not expose removeStyle for all table states.
end

try
    switch mode
        case 'powerflow'
            voltage_style = uistyle('BackgroundColor', [0.90 0.97 1.00], ...
                'FontColor', [0.02 0.31 0.44], 'FontWeight', 'bold');
            angle_style = uistyle('BackgroundColor', [0.97 0.98 1.00]);
            addStyle(app.result_table, voltage_style, 'column', 4);
            addStyle(app.result_table, angle_style, 'column', 5);

        case 'cpf'
            lambda_style = uistyle('BackgroundColor', [1.00 0.94 0.90], ...
                'FontColor', [0.62 0.20 0.04], 'FontWeight', 'bold');
            addStyle(app.result_table, lambda_style, 'column', 1);

        case 'opf'
            dispatch_style = uistyle('BackgroundColor', [0.91 0.98 0.94], ...
                'FontColor', [0.10 0.38 0.20], 'FontWeight', 'bold');
            addStyle(app.result_table, dispatch_style, 'column', 3);

        case 'suite'
            method_style = uistyle('BackgroundColor', [0.93 0.95 1.00], ...
                'FontColor', [0.16 0.21 0.36], 'FontWeight', 'bold');
            addStyle(app.result_table, method_style, 'column', 1);

        case 'smib'
            eig_style = uistyle('BackgroundColor', [0.93 0.96 0.94], ...
                'FontColor', [0.10 0.38 0.20], 'FontWeight', 'bold');
            stable_style = uistyle('BackgroundColor', [0.90 0.97 1.00], ...
                'FontColor', [0.02 0.31 0.44], 'FontWeight', 'bold');
            if isfield(app, 'smib_table') && isvalid(app.smib_table)
                try; removeStyle(app.smib_table); catch; end
                addStyle(app.smib_table, eig_style, 'column', 1);
                addStyle(app.smib_table, stable_style, 'column', 6);
            end
    end
catch
    % Styling is cosmetic; never fail result rendering because of it.
end
end
