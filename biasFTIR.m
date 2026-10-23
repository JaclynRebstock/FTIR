%% FTIR bias-dependent delta-absorbance analysis (JASCO .txt files)
% Imports <base>_<voltage>V.txt files + <base>_OCP.txt reference,
% baseline-corrects, computes dA = A(V) - A(OCP), plots with rainbow colors.

clear; clc; close all;

%% ---------------- USER SETTINGS ----------------
folder   = '';             % path to data folder, e.g. 'C:\data\K3_experiment'
                           %   '' (empty)  -> a folder-picker dialog opens
                           %   '.' or pwd  -> current MATLAB folder
outFolder = '';   % where to save the CSV; '' = same as data folder
baseName =  '';      % base filename used to find files, e.g. 'K3_experiment_'
                      %   ''  (empty) -> search ALL .txt files in folder instead
                      %   otherwise   -> only files matching baseName*.txt are used
refTag   = 'OCP';          % text that identifies the reference file (the file
                           % whose name CONTAINS refTag is used as the reference;
                           % all other matched .txt files are treated as bias files)

fileConversion = true;    % true  -> run jasco2txt(folder) first to generate
                           %          .txt files from raw JASCO data
                           % false -> skip conversion, use existing .txt files

xRange   = [2000 2160];    % wavenumber range to keep/plot (cm^-1)

% Baseline correction
baseMode  = 'modpoly';     % 'modpoly' = iterative polynomial fit (auto)
                           % 'anchors' = poly fit through absorption-free windows
polyOrder = 1;             % polynomial order
nIter     = 100;           % iterations for 'modpoly'
anchors   = [1900 2000; 2500 2600; 3900 4000];  % [lo hi] windows for 'anchors'

smoothPts = 1;             % optional moving-average on dA (points); 0 = off
flipX     = true;          % IR convention: high wavenumber on the left
reverseColors = true;      % true: reverse the rainbow order (first spectrum = red)
showLegend    = false;     % colorbar already labels the voltages; true adds a legend
%% ------------------------------------------------

%% Resolve folders
if isempty(folder)
    folder = uigetdir(pwd, 'Select the folder containing the FTIR .txt files');
    if isequal(folder, 0), error('No folder selected.'); end
end
if ~isfolder(folder), error('Folder does not exist: %s', folder); end
if isempty(outFolder), outFolder = folder; end
if ~isfolder(outFolder), mkdir(outFolder); end

%% Optional conversion from raw JASCO format to .txt
if fileConversion
    fprintf('Running jasco2txt on folder: %s\n', folder);
    jasco2txt(folder);
end

%% Find files
if isempty(baseName)
    files = dir(fullfile(folder, '*.txt'));        % all .txt files in folder
else
    files = dir(fullfile(folder, [baseName '*.txt']));
end
if isempty(files), error('No matching .txt files found in %s', folder); end

volts = []; names = {}; refName = '';
for k = 1:numel(files)
    [~, nm] = fileparts(files(k).name);
    if ~isempty(strfind(lower(nm), lower(refTag))) %#ok<STREMP>
        if ~isempty(refName)
            warning('Multiple files contain refTag "%s"; using the first match (%s).', ...
                    refTag, refName);
        else
            refName = files(k).name;
        end
        continue;
    end
    tok = regexp(nm, '(-?\d*[._]?\d+)[ _]?V', 'tokens', 'once');
    if isempty(tok), continue; end                % skip files with no voltage tag
    volts(end+1) = str2double(strrep(tok{1}, '_', '.')); %#ok<SAGROW>
    names{end+1} = files(k).name;                  %#ok<SAGROW>
end
if isempty(refName)
    error('No reference file found containing "%s" in its name in %s', refTag, folder);
end

[volts, idx] = sort(volts, 'descend');            % 0, -0.1, -0.2, ...
names = names(idx);
fprintf('Reference: %s\n', refName);
fprintf('Found %d bias files: %s V\n', numel(volts), mat2str(volts));

%% Load reference and define common wavenumber grid
[xRef, yRef] = readJasco(fullfile(folder, refName));
sel  = xRef >= min(xRange) & xRef <= max(xRange);
x    = xRef(sel);
Aref = baseline(x, yRef(sel), baseMode, polyOrder, nIter, anchors);

%% Load, baseline-correct, and compute delta absorbance
nV = numel(volts);
dA = zeros(numel(x), nV);
for k = 1:nV
    [xk, yk] = readJasco(fullfile(folder, names{k}));
    yk = interp1(xk, yk, x, 'linear', 'extrap');  % ensure same grid as reference
    Ak = baseline(x, yk, baseMode, polyOrder, nIter, anchors);
    dA(:,k) = Ak - Aref;
    if smoothPts > 1, dA(:,k) = movmean(dA(:,k), smoothPts); end
end

%% Plot (rainbow)
try, cmap = turbo(nV); catch, cmap = jet(nV); end   % turbo needs R2020b+
if reverseColors, cmap = flipud(cmap); end
figure('Color','w'); hold on; box on;
for k = 1:nV
    plot(x, dA(:,k), 'Color', cmap(k,:), 'LineWidth', 1.2);
end
xlabel('Wavenumber (cm^{-1})'); ylabel('\DeltaAbsorbance (vs. OCP)');
title(strrep(("Bias-Dependent FTIR "+string(baseName)), '_', '\_'));
xlim(xRange);
if flipX, set(gca, 'XDir', 'reverse'); end
set(gca, 'FontSize', 12, 'LineWidth', 1);
colormap(cmap); cb = colorbar;
if nV > 1
    caxis([1 nV]); cb.Ticks = 1:nV; cb.TickLabels = compose('%g V', volts);
end
cb.Label.String = 'Bias';
if showLegend
    legend(compose('%g V', volts), 'Location', 'best', 'Box', 'off');
end

%% Save processed data
out = [x(:), dA];
hdr = ['wavenumber', compose(',dA_%gV', volts)];
writecell([hdr; num2cell(out)], fullfile(outFolder, [baseName '_deltaA.csv']));
fprintf('Saved: %s\n', fullfile(outFolder, [baseName '_deltaA.csv']));

%% ---------------- Local functions ----------------
function [x, y] = readJasco(fname)
    % Detect encoding (some instrument exports are UTF-16)
    fid = fopen(fname, 'r'); b = fread(fid, 4, 'uint8')'; fclose(fid);
    if numel(b) >= 2 && isequal(b(1:2), [255 254]),     enc = 'UTF-16LE';
    elseif numel(b) >= 2 && isequal(b(1:2), [254 255]), enc = 'UTF-16BE';
    elseif numel(b) >= 4 && b(2) == 0 && b(4) == 0,     enc = 'UTF-16LE';
    else,                                               enc = 'ISO-8859-1';
    end
    txt = fileread(fname, 'Encoding', enc);
    txt = strrep(txt, char(0), '');
    txt = strrep(txt, char(65279), '');           % stray BOM

    % Take every line that consists of exactly two numbers (x, y).
    % This ignores the header/footer and does not depend on the XYDATA marker.
    num = '([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)';
    tok = regexp(txt, ['^[ \t]*' num '[ \t,;]+' num '[ \t\r]*$'], ...
                 'tokens', 'lineanchors');
    if isempty(tok)
        fprintf('First 300 characters of %s:\n%s\n', fname, ...
                txt(1:min(300, numel(txt))));
        error('No numeric x/y data found in %s (see text above).', fname);
    end
    d = str2double(vertcat(tok{:}));
    x = d(:,1); y = d(:,2);
    [x, u] = unique(x); y = y(u);                 % ascending, no duplicates
end

function yc = baseline(x, y, mode, order, nIter, anchors)
    xs = (x - mean(x)) / (max(x) - min(x)) * 2;   % scale for numerical stability
    switch lower(mode)
        case 'modpoly'                            % Lieber & Mahadevan-Jansen
            yw = y;
            for it = 1:nIter
                p  = polyfit(xs, yw, order);
                b  = polyval(p, xs);
                yw = min(yw, b);
            end
            base = b;
        case 'anchors'
            m = false(size(x));
            for j = 1:size(anchors,1)
                m = m | (x >= anchors(j,1) & x <= anchors(j,2));
            end
            p    = polyfit(xs(m), y(m), order);
            base = polyval(p, xs);
        otherwise
            error('Unknown baseline mode: %s', mode);
    end
    yc = y - base;
end
