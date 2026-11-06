clear; clc; close all;

folder   = '/Users/jaclynrebstock/Desktop/UW Local Desktop/FTIR Data/20261105 potassium ferricyanide/';             % path to data folder, e.g. 'C:\data\K3_experiment'
                           %   '' (empty)  -> a folder-picker dialog opens
                           %   '.' or pwd  -> current MATLAB folder
outFolder = '';   % where to save the CSV; '' = same as data folder

baseName =  '';      % base filename used to find files, e.g. 'K3_experiment_'
                      %   ''  (empty) -> search ALL .txt files in folder instead
                      %   otherwise   -> only files matching baseName*.txt are used

fileConversion = false;  % true -> run jasco2txt function and convert files
                        % flase -> skip file conversion
                      
fileLog = 'FileLog.xlsx';



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
    fprintf('Files converted to .txt :)\n')
end

%% Find files
if isempty(baseName)
    files = dir(fullfile(folder, '*.txt'));        % all .txt files in folder
else
    files = dir(fullfile(folder, [baseName '*.txt']));
end

if isempty(files), error('No matching .txt files found in %s', folder); end

%% Load files
filenames = {};
for idx = 1:numel(files)
    [~, nm] = fileparts(files(idx).name);
    filenames(idx) = {nm};
end

for jdx = 1:numel(files)
    [x, y] = readJasco(fullfile(folder, string(filenames{jdx})+'.txt'));
    Data(:,jdx+1) = y;
    Data(:,1) = x;
end
Data = array2table(Data);

fprintf('Imported %d files to Data\n', size(files,1));

%% Assign filesnames
if ~isempty(fileLog)
    fileInfo = readcell(fullfile(folder,fileLog));
    fprintf('Imported FileLog\n')
end

VarNames = {fileInfo{2:end,2}};
for kdx = 1:numel(VarNames)
    VarNames{kdx} = string(VarNames{kdx})+' V';
end

fileNumber = [fileInfo{2:end,1}];
padfileNumber = cell(1,length(fileNumber));
for ldx = 1:numel(fileNumber)
    padfileNumber{ldx} = num2str(fileNumber(ldx),'%02d');
end

for mdx = 1:numel(fileNumber)
    VarNames{mdx} = string(padfileNumber{mdx})+'_'+string(VarNames{mdx});
end

VarNames = ['wavenumber' VarNames{:}];
fprintf('Imported file names, and added numerical padding\nExample data point name is: '+string(VarNames(2)+'\n'))

Data.Properties.VariableNames = VarNames;

%% Save processed data
writetable(Data,'ProcessedFTIRData.xlsx');

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