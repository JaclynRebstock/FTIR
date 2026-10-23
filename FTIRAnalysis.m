clear; clc;

%% ------------------------- USER SETTINGS -------------------------------

filename   = '/Users/jaclynrebstock/Desktop/UW Local Desktop/Data/20261019 FeRuFe FTIR/FeRuFe_DIW_25micron_anodicsweep_+1.5V.txt';   % <-- path to your FTIR .txt file

% --- Baseline correction ---
baselineMethod = 'auto';   % 'auto'   = iterative polynomial (no clicking)
                             % 'manual' = you click anchor points on the plot
polyOrder      = 4;        % polynomial order for the baseline (typ. 2-6)
maxIter        = 100;      % max iterations for 'auto' method
tol            = 1e-4;     % convergence tolerance for 'auto' method

% % --- Wavenumber range 
xBaselineRange = [2000 2300];
xFittingRange = [2000 2300];
 

%% ------------------------------ IMPORT ---------------------------------

[wavenumber, intensity, headerLines] = import_ftir_txt(filename);

% Pull axis units out of the header (e.g. JASCO's XUNITS/YUNITS fields)
% so the plots below label themselves correctly regardless of file.
xLabelStr = get_header_field(headerLines, 'XUNITS', 'Wavenumber (cm^{-1})');
yLabelStr = get_header_field(headerLines, 'YUNITS', 'Intensity');
if strcmpi(xLabelStr, '1/CM'); xLabelStr = 'Wavenumber (cm^{-1})'; end
if strcmpi(yLabelStr, 'ABSORBANCE'); yLabelStr = 'Absorbance'; end


%% --------------------------- BASELINE FIT ------------------------------
idx = wavenumber >= xBaselineRange(1) & wavenumber <= xBaselineRange(2);
wavenumberBaseline = wavenumber(idx);
intensityBaseline = intensity(idx);

switch lower(baselineMethod)
    case 'auto'
        baseline = fit_baseline_auto(wavenumberBaseline, intensityBaseline, polyOrder, ...
            maxIter, tol);
    case 'manual'
        baseline = fit_baseline_manual(wavenumberBaseline, intensityBaseline, polyOrder, ...
            reverseXAxis);
    otherwise
        error('baselineMethod must be ''auto'' or ''manual''.');
end

intensity_corrected = intensityBaseline - baseline;

idx = wavenumberBaseline >= xFittingRange(1) & wavenumberBaseline <= xFittingRange(2);
wavenumberFit = wavenumberBaseline(idx);
intensityFit = intensity_corrected(idx);

[centerFreq, fwhm, fitOut] = fit_gaussian_peak(wavenumberFit, intensityFit);
fprintf('Center frequency: %.2f cm^-1\n', centerFreq);
fprintf('FWHM: %.2f cm^-1\n', fwhm);



% %% ------------------------------- PLOTS ---------------------------------
figure('Name', 'FTIR Baseline & Gaussian Fit', 'Color', 'w', ...
    'Position', [100 100 900 700]);

subplot(2,2,1);
plot(wavenumber, intensity, 'b-', 'LineWidth', 1); hold on;
plot(wavenumberBaseline, baseline, 'r--', 'LineWidth', 1.5);
xlabel(xLabelStr); ylabel(yLabelStr);
title('Raw Spectrum with Fitted Baseline');
legend('Raw data', 'Baseline', 'Location', 'best');
grid on;

subplot(2,2,2);
plot(wavenumberBaseline, intensityBaseline, 'b-', 'LineWidth', 1); hold on;
plot(wavenumberBaseline, baseline, 'r--', 'LineWidth', 1.5);
xlabel(xLabelStr); ylabel(yLabelStr);
title('Raw Spectrum with Fitted Baseline');
legend('Raw data', 'Baseline', 'Location', 'best');
grid on;

subplot(2,2,3);
plot(wavenumberBaseline, intensity_corrected, 'k-', 'LineWidth', 1);
xlabel(xLabelStr); ylabel(yLabelStr);
title('Baseline-Corrected Spectrum');
grid on;

subplot(2,2,4);
plot(wavenumberFit, intensityFit, 'ko', 'MarkerSize', 3); hold on;
plot(wavenumberFit, fitOut.curve, 'b-', 'LineWidth', 1.5);
set(gca, 'XDir', 'reverse');
xlabel('Wavenumber (cm^{-1})'); ylabel('Intensity');
title(sprintf('Center = %.2f cm^{-1}, FWHM = %.2f cm^{-1}', centerFreq, fwhm));


%% ========================================================================
%                            LOCAL FUNCTIONS
%  ========================================================================

function value = get_header_field(headerLines, fieldName, defaultValue)
% GET_HEADER_FIELD  Look up a "KEY<tab/whitespace>VALUE" pair (e.g.
% JASCO's XUNITS/YUNITS lines) from the imported header lines. Returns
% defaultValue if the field isn't present.

    value = defaultValue;
    for i = 1:numel(headerLines)
        line = strtrim(headerLines{i});
        parts = regexp(line, '[\t]+', 'split', 'once');
        if numel(parts) < 2
            parts = regexp(line, '\s{2,}', 'split', 'once');
        end
        if numel(parts) >= 2 && strcmpi(strtrim(parts{1}), fieldName)
            candidate = strtrim(parts{2});
            if ~isempty(candidate)
                value = candidate;
            end
            return;
        end
    end
end


function [x, y, headerLines] = import_ftir_txt(filename)
% IMPORT_FTIR_TXT  Auto-detect header vs. numeric X/Y data in an FTIR
% text export and return the parsed vectors.
%
%   Handles files where columns are separated by whitespace, commas, or
%   tabs, and where an unknown number of header/parameter lines precede
%   the data table.

    if ~isfile(filename)
        error('File not found: %s', filename);
    end

    fid = fopen(filename, 'rt');
    if fid == -1
        error('Could not open file: %s', filename);
    end
    rawLines = {};
    tline = fgetl(fid);
    while ischar(tline)
        rawLines{end+1} = tline; %#ok<AGROW>
        tline = fgetl(fid);
    end
    fclose(fid);

    numLines = numel(rawLines);
    isDataLine = false(numLines, 1);
    xVals = nan(numLines, 1);
    yVals = nan(numLines, 1);

    for i = 1:numLines
        line = strtrim(rawLines{i});
        if isempty(line)
            continue;
        end
        % Split on comma, tab, or whitespace
        parts = regexp(line, '[,\t\s]+', 'split');
        parts = parts(~cellfun(@isempty, parts));
        if numel(parts) >= 2
            v1 = str2double(parts{1});
            v2 = str2double(parts{2});
            if ~isnan(v1) && ~isnan(v2)
                isDataLine(i) = true;
                xVals(i) = v1;
                yVals(i) = v2;
            end
        end
    end

    % Require a run of consecutive data lines at the end of the file to
    % avoid stray numeric-looking header lines (e.g. "Scans: 32 16")
    % being mistaken for data. We take the longest contiguous block of
    % data lines.
    d = [0; isDataLine; 0];
    starts = find(diff(d) == 1);
    ends   = find(diff(d) == -1) - 1;
    if isempty(starts)
        error(['No numeric X/Y data could be detected in "%s". ' ...
            'Check the file format / delimiter.'], filename);
    end
    [~, longestIdx] = max(ends - starts);
    dataStart = starts(longestIdx);
    dataEnd   = ends(longestIdx);

    x = xVals(dataStart:dataEnd);
    y = yVals(dataStart:dataEnd);
    headerLines = rawLines(1:dataStart-1);
end


function baseline = fit_baseline_auto(x, y, polyOrder, maxIter, tol)
% FIT_BASELINE_AUTO  Iterative polynomial baseline estimation
% (Lieber & Mahadevan-Jansen "ModPoly"-style method). No user
% interaction required: fits a polynomial, clips the working signal down
% to the fit wherever the signal exceeds it (i.e. peaks), and repeats
% until the polynomial coefficients converge. This pulls the polynomial
% down toward the true baseline instead of chasing the peaks.

    workingY = y;
    prevCoeffs = [];

    for iter = 1:maxIter
        coeffs = polyfit(x, workingY, polyOrder);
        fitY = polyval(coeffs, x);

        % Clip: anywhere the original signal is above the current fit,
        % replace with the fit value so peaks stop influencing the baseline
        workingY = min(y, fitY);

        if ~isempty(prevCoeffs)
            change = norm(coeffs - prevCoeffs) / max(norm(prevCoeffs), eps);
            if change < tol
                break;
            end
        end
        prevCoeffs = coeffs;
    end

    baseline = polyval(coeffs, x);
end


function baseline = fit_baseline_manual(x, y, polyOrder, reverseXAxis)
% FIT_BASELINE_MANUAL  Click on the plot to select baseline anchor
% points (regions with no peaks), then fits a polynomial of order
% polyOrder through those points.

    f = figure('Name', 'Select Baseline Points', 'Color', 'w');
    plot(x, y, 'b-'); hold on;
    if reverseXAxis, set(gca, 'XDir', 'reverse'); end
    xlabel('Wavenumber (cm^{-1})'); ylabel('Intensity / Absorbance');
    title({'Click to select baseline anchor points (avoid peaks).', ...
        'Press ENTER when done.'});
    grid on;

    [xi, yi] = ginput; %#ok<ASGLU> % yi collected but we re-sample from data
    close(f);

    if numel(xi) < polyOrder + 1
        error(['Need at least %d points to fit a polynomial of order %d. ' ...
            'Re-run and select more points.'], polyOrder + 1, polyOrder);
    end

    % Snap clicked x-locations to the nearest actual data point so the
    % fitted y-value comes from the real spectrum, not the click location.
    yi = zeros(size(xi));
    for k = 1:numel(xi)
        [~, idx] = min(abs(x - xi(k)));
        yi(k) = y(idx);
    end

    coeffs = polyfit(xi, yi, polyOrder);
    baseline = polyval(coeffs, x);
end

function [centerFreq, fwhm, fitOut] = fit_gaussian_peak(x, y)
x = x(:);
y = y(:);
xmin = min(x);
xmax = max(x);

[yMax, iMax] = max(y);
A0      = yMax;
x0_0    = x(iMax);
sigma0  = (xmax - xmin) / 8;
offset0 = median(y([1:round(numel(y)*0.1), end-round(numel(y)*0.1):end]));

% --- Bounded reparametrization so the optimizer can't wander outside
% the data range for the center, and can't produce negative sigma. ---
% x0    = xmin + (xmax-xmin) * (tanh(u)+1)/2        -> confined to (xmin,xmax)
% sigma = exp(v)                                    -> confined to (0, Inf)
toFree = @(x0, sigma) deal( ...
    atanh( max(min(2*(x0-xmin)/(xmax-xmin) - 1, 0.999), -0.999) ), ...
    log(max(sigma, eps)));
[u0, v0] = toFree(x0_0, sigma0);

gaussModel = @(p, x) p(1)*exp(-(x - p(2)).^2 / (2*p(3)^2)) + p(4);
freeToPhys = @(pf) [pf(1), ...
    xmin + (xmax-xmin)*(tanh(pf(2))+1)/2, ...
    exp(pf(3)), ...
    pf(4)];

sse = @(pf) sum((gaussModel(freeToPhys(pf), x) - y).^2);

pf0 = [A0, u0, v0, offset0];
options = optimset('Display', 'off', 'TolX', 1e-10, 'TolFun', 1e-10, 'MaxFunEvals', 5000);
pfFit = fminsearch(sse, pf0, options);
pFit = freeToPhys(pfFit);

amplitude  = pFit(1);
centerFreq = pFit(2);
sigma      = pFit(3);
offset     = pFit(4);
fwhm       = 2*sqrt(2*log(2)) * sigma;

yFitCurve = gaussModel(pFit, x);
rmse = sqrt(mean((yFitCurve - y).^2));

if centerFreq <= xmin + 1e-6 || centerFreq >= xmax - 1e-6
    warning('fit_gaussian_peak:edgeFit', ...
        ['Fitted center (%.2f) landed right at the edge of your data range ' ...
         '[%.2f %.2f]. This usually means there is no clean single peak in ' ...
         'this window, or the baseline correction left a residual slope. ' ...
         'Plot intensity_corrected vs wavenumberFit to check.'], ...
        centerFreq, xmin, xmax);
end

fitOut = struct('amplitude', amplitude, 'sigma', sigma, 'offset', offset, ...
    'rmse', rmse, 'curve', yFitCurve, 'params', pFit);

end