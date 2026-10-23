%% Publication-quality FTIR spectrum plot
clear; close all; clc;

%% === USER INPUT ===
% Replace with your processed data
% wn = wavenumber (cm^-1)
% absorbance = intensity (Abs or a.u.)
load('MBNFTIRData.mat'); % should contain wn and absorbance
% OR:
wn = M(:,1);        % first column = wavenumber
absorbance = M(:,2);    % second column = absorbance (or whatever)

%% === SORT (important if needed) ===
% Ensure increasing or decreasing order is consistent
[wn, idx] = sort(wn);
absorbance = absorbance(idx);

%% === CREATE FIGURE ===
fig = figure('Units','inches','Position',[1 1 4.5 3.5]); % good journal size
hold on;

%% === PLOT ===
plot(wn, absorbance, 'k-', 'LineWidth', 1.5);

%% === AXIS FORMATTING ===
set(gca, ...
    'LineWidth', 1.2, ...
    'FontSize', 12, ...
    'FontName', 'Arial', ...
    'TickDir', 'out', ...
    'Box', 'off');

% Reverse x-axis for FTIR (typical convention)
set(gca, 'XDir','reverse');

xlabel('Wavenumber (cm^{-1})', 'FontSize', 13);
ylabel('Absorbance (a.u.)', 'FontSize', 13);

%% === OPTIONAL: LIMITS ===
% xlim([1800 2200]); % example for CO region
% ylim([min(absorbance) max(absorbance)]);

%% === OPTIONAL: TICKS ===
% Customize ticks if needed
% xticks(1800:50:2200);

%% === OPTIONAL: GRID (usually off for publication) ===
grid off;

%% === EXPORT SETTINGS ===
set(fig, 'Color', 'w'); % white background
box on
set(gca,'TickDir','in')
ylim([-0.0002 0.004])

% High-res PNG
exportgraphics(fig, 'FTIR_spectrum.png', 'Resolution', 600);

% Vector PDF (preferred for journals)
exportgraphics(fig, 'FTIR_spectrum.pdf', 'ContentType', 'vector');

%% === OPTIONAL: EPS (some journals still want it) ===
% print(fig, 'FTIR_spectrum.eps', '-depsc2', '-painters');
