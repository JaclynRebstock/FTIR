% This script reads in JASCO .jsw FTIR data, converts them to .txt files,
% organizes an array of the data with variables names, and saves to 
% .xlsx file to be used for further processing/plotting

clear; clc; close all;

% Specify folder path
folder   = '/Users/jaclynrebstock/Library/CloudStorage/OneDrive-UW/Projects and Data/Potassium ferricyanide/Formamide/20261118 formamide/trial2/';
             %   '' (empty)  -> a folder-picker dialog opens
             %   '.' or pwd  -> current MATLAB folder
outFolder = '';   % where to save the CSV; '' = same as data folder

baseName = 'sample';    % base filename used to find files, e.g. 'K3_experiment_'
                      %   ''  (empty) -> search ALL .txt files in folder instead
                      %   otherwise   -> only files matching baseName*.txt are used

fileConversion = false;     % true -> run jasco2txt function and convert files
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
    fprintf('Files converted to .txt.\n');
end

%% Find files
if isempty(baseName)
    files = dir(fullfile(folder, '*.txt'));
else
    files = dir(fullfile(folder, [baseName '*.txt']));
end

if isempty(files)
    error('No matching .txt files found in %s', folder);
end

%% Sort files by the number in the filename
% This prevents alphabetical ordering such as:
% biasdependence1, biasdependence10, biasdependence11, ..., biasdependence2
files = sortFilesNumerically(files);

fprintf('Import order:\n');
for idx = 1:numel(files)
    fprintf('  %d: %s\n', idx, files(idx).name);
end

%% Load files
Data = [];
filenames = strings(numel(files), 1);

for jdx = 1:numel(files)
    filenames(jdx) = string(files(jdx).name);
    [x, y] = readJasco(fullfile(folder, files(jdx).name));

    if jdx == 1
        Data = nan(numel(x), numel(files) + 1);
        Data(:,1) = x;
    elseif numel(x) ~= size(Data,1) || any(abs(x - Data(:,1)) > 1e-8)
        error('Wavenumber axis in %s does not match the first file.', files(jdx).name);
    end

    Data(:,jdx+1) = y;
end

Data = array2table(Data);
fprintf('Imported %d files to Data in natural numeric order.\n', numel(files));

%% Assign filenames from FileLog
if ~isempty(fileLog)
    fileInfo = readcell(fullfile(folder, fileLog));
    fprintf('Imported FileLog.\n');

    if size(fileInfo,1)-1 < numel(files)
        error('FileLog contains fewer entries than imported files.');
    end

    VarNames = cell(1, numel(files));
    fileNumber = zeros(1, numel(files));

    for kdx = 1:numel(files)
        fileNumber(kdx) = fileInfo{kdx+1, 1};
        VarNames{kdx} = string(fileInfo{kdx+1, 2}) + ' V';
    end

    % Pad the numeric labels for the output column names.
    for kdx = 1:numel(fileNumber)
        VarNames{kdx} = sprintf('%02d_%s', fileNumber(kdx), VarNames{kdx});
    end
else
    % Use the imported filenames if no FileLog is supplied.
    VarNames = cellstr(erase(filenames, '.txt'))';
end

VarNames = [{'wavenumber'}, VarNames];
Data.Properties.VariableNames = matlab.lang.makeValidName(VarNames);

fprintf('Example data point name: %s\n', Data.Properties.VariableNames{2});

%% Save processed data
outputFile = fullfile(outFolder, 'RawFTIRData.xlsx');
writetable(Data, outputFile);
fprintf('Saved: %s\n', outputFile);

%% ---------------- Local functions ----------------
function files = sortFilesNumerically(files)
    % Sort by the final number before .txt, not alphabetically.
    % Example: 1, 2, 3, ..., 10, 11 instead of 1, 10, 11, ..., 2.
    n = nan(numel(files), 1);
    names = {files.name};

    for k = 1:numel(files)
        token = regexp(names{k}, '(\d+)(?=\.txt$)', 'tokens', 'once');
        if ~isempty(token)
            n(k) = str2double(token{1});
        end
    end

    % Files with numeric suffixes come first; ties are sorted by name.
    hasNumber = ~isnan(n);
    numericIdx = find(hasNumber);
    nonNumericIdx = find(~hasNumber);

    [~, orderNumeric] = sortrows([n(numericIdx), (1:numel(numericIdx))']);
    numericIdx = numericIdx(orderNumeric);

    [~, orderText] = sort(lower(names(nonNumericIdx)));
    nonNumericIdx = nonNumericIdx(orderText);

    files = files([numericIdx; nonNumericIdx]);
end

function [x, y] = readJasco(fname)
    % Function written by Claude -
    % Detect encoding; some instrument exports are UTF-16.
    fid = fopen(fname, 'r');
    if fid < 0, error('Could not open file: %s', fname); end
    b = fread(fid, 4, 'uint8')';
    fclose(fid);

    if numel(b) >= 2 && isequal(b(1:2), [255 254])
        enc = 'UTF-16LE';
    elseif numel(b) >= 2 && isequal(b(1:2), [254 255])
        enc = 'UTF-16BE';
    elseif numel(b) >= 4 && b(2) == 0 && b(4) == 0
        enc = 'UTF-16LE';
    else
        enc = 'ISO-8859-1';
    end

    txt = fileread(fname, 'Encoding', enc);
    txt = strrep(txt, char(0), '');
    txt = strrep(txt, char(65279), '');

    % Keep only lines containing exactly two numeric values: x and y.
    num = '([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)';
    tok = regexp(txt, ['^[ \t]*' num '[ \t,;]+' num '[ \t\r]*$'], ...
        'tokens', 'lineanchors');

    if isempty(tok)
        fprintf('First 300 characters of %s:\n%s\n', fname, ...
            txt(1:min(300, numel(txt))));
        error('No numeric x/y data found in %s.', fname);
    end

    d = str2double(vertcat(tok{:}));
    x = d(:,1);
    y = d(:,2);

    [x, u] = unique(x, 'stable');
    y = y(u);
end

function jasco2txt(inPath, varargin)
%JASCO2TXT Converts *.jws or *.jwb files to human-readable text files.
%
%   jasco2txt(inPath) converts all .jws/.jwb files found in inPath
%   (a single file or a folder, searched recursively) to .txt files.
%
%   jasco2txt(inPath, 'OutDir', outDir, 'Delimiter', '\t', ...
%              'Comments', true, 'Header', true)
%
%   Name-Value options (defaults match the original Python script):
%       OutDir     - output folder (default: inPath)
%       Delimiter  - delimiter used in saved text files (default: '\t')
%       Comments   - logical, write sample information (default: true)
%       Header     - logical, write header (default: true)
%
%   This is a full MATLAB port of the Python package jws2txt
%   (https://github.com/jzftran/jws2txt), including a from-scratch
%   reader for the OLE/Compound File Binary (CFB) container format
%   that JASCO .jws/.jwb files use (equivalent to Python's `olefile`).
%
    p = inputParser;
    addRequired(p, 'inPath', @(x) ischar(x) || isstring(x));
    addParameter(p, 'OutDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'Delimiter', sprintf('\t'), @(x) ischar(x) || isstring(x));
    addParameter(p, 'Comments', true, @islogical);
    addParameter(p, 'Header', true, @islogical);
    parse(p, inPath, varargin{:});

    inPath    = char(p.Results.inPath);
    outDir    = char(p.Results.OutDir);
    delimiter = char(p.Results.Delimiter);
    writeComments = p.Results.Comments;
    writeHeader   = p.Results.Header;

    if ~exist(inPath, 'file') && ~exist(inPath, 'dir')
        error('jasco2txt:fileNotFound', '%s does not exist.', inPath);
    end

    if isempty(outDir)
        outDir = inPath;
    end

    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    % Gather candidate files: either inPath itself (if a file) or
    % everything under it (recursive walk), matching .jwb/.jws.
    if isfolder(inPath)
        files = [dir(fullfile(inPath, '**', '*.jwb')); ...
                 dir(fullfile(inPath, '**', '*.jws'))];
    else
        [~, ~, ext] = fileparts(inPath);
        if ~ismember(lower(ext), {'.jwb', '.jws'})
            error('jasco2txt:badExt', '%s is not a .jwb or .jws file.', inPath);
        end
        files = dir(inPath);
    end

    for k = 1:numel(files)
        fileName   = files(k).name;
        fileFolder = files(k).folder;
        jwsFilePath = fullfile(fileFolder, fileName);

        [~, baseName, ~] = fileparts(fileName);
        outFilePath = fullfile(outDir, [baseName, '.txt']);

        writeJWSData(jwsFilePath, outFilePath, delimiter, writeComments, writeHeader);
    end
end

% ========================================================================
% Writing
% ========================================================================

function writeJWSData(jwsFilePath, outFilePath, delimiter, writeComments, writeHeader)
%WRITEJWSDATA Reads a JASCO .jws/.jwb file and writes it out as text.
%   Mirrors Python's JWSFile(...).write_data(...).

    if exist(outFilePath, 'file')
        fprintf('Error: File ''%s'' already exists.\n', outFilePath);
        return;
    end

    data = readJWSFile(jwsFilePath);

    fid = fopen(outFilePath, 'w');
    if fid == -1
        error('jasco2txt:fileOpen', 'Could not open %s for writing.', outFilePath);
    end
    cleanupObj = onCleanup(@() fclose(fid));

    if writeComments
        fprintf(fid, '%s\r\n', data.sampleName);
        fprintf(fid, '%s\r\n', data.comment);
    end

    headerNames = data.headerNames;
    numCols = size(data.values, 2);
    if writeHeader
        if numel(headerNames) < numCols
            diffN = numCols - numel(headerNames);
            if isempty(headerNames)
                headerNames = repmat({'undefined'}, 1, diffN);
            else
                headerNames = [headerNames, repmat(headerNames(end), 1, diffN)];
            end
        end
        if numel(headerNames) == numCols
            fprintf(fid, '%s\r\n', strjoin(headerNames, delimiter));
        end
    end

    fmtRow = strjoin(repmat({'%.10g'}, 1, numCols), delimiter);
    for i = 1:size(data.values, 1)
        fprintf(fid, [fmtRow, '\r\n'], data.values(i, :));
    end
end

% ========================================================================
% JASCO/JWS parsing (equivalent of Python's JWSFile class)
% ========================================================================

function data = readJWSFile(jwsFilePath)
%READJWSFILE Parses a JASCO binary .jws/.jwb (OLE compound file) and
%   returns a struct with the same information as Python's JWSFile.

    cfb = cfbOpen(jwsFilePath);

    dataInfoBytes = cfbGetStream(cfb, 'DataInfo');
    if numel(dataInfoBytes) < 96
        error('jasco2txt:dataInfo', 'DataInfo should be at least 96 bytes!');
    end
    dataInfoBytes = dataInfoBytes(1:96);

    % fmt "<LLLLLLdddLLLLdddd" -> 6x uint32, 3x double, 4x uint32, 4x double
    L = typecast(dataInfoBytes(1:24), 'uint32');            % elements 1-6
    d1 = typecast(dataInfoBytes(25:48), 'double');           % elements 7-9
    L2 = typecast(dataInfoBytes(49:64), 'uint32');            % elements 10-13
    d2 = typecast(dataInfoBytes(65:96), 'double');            % elements 14-17

    numChannels = double(L(4));             % python data_tuple[3]
    npoints     = double(L(6));             % python data_tuple[5]
    xForFirst   = d1(1);                    % python data_tuple[6]
    xForLast    = d1(2);                    % python data_tuple[7]
    xIncrement  = d1(3);                    % python data_tuple[8]

    if npoints < 2 || mod(npoints, 1) ~= 0
        error('jasco2txt:npoints', 'Invalid npoints.');
    end

    if xIncrement == 0
        span = xForLast - xForFirst;
        if span == 0
            error('jasco2txt:xIncrement', ...
                'Cannot compute x_increment: identical first/last points.');
        end
        xIncrement = span / (npoints - 1);
    end

    % dedup, stable, first-occurrence of python data_tuple[9:13] == L2(1:4)
    codes4 = double(L2(1:4));
    headerCodes = [];
    for i = 1:4
        if ~ismember(codes4(i), headerCodes)
            headerCodes(end+1) = codes4(i); %#ok<AGROW>
        end
    end
    headerNames = cell(1, numel(headerCodes));
    for i = 1:numel(headerCodes)
        headerNames{i} = getChannelName(headerCodes(i));
    end

    if ~cfbHasStream(cfb, 'Y-Data')
        error('jasco2txt:yData', 'Y-Data not found!');
    end
    yData = cfbGetStream(cfb, 'Y-Data');

    try
        yMatrix = unpackYData(yData, npoints, numChannels);
    catch
        numChannels = double(L(2)); % python data_tuple[1], works for *.jwb
        yMatrix = unpackYData(yData, npoints, numChannels);
    end

    xData = xForFirst + (0:npoints-1)' * xIncrement;
    data.values = [xData, double(yMatrix)];
    data.headerNames = headerNames;

    sampleName = '';
    comment = '';
    try
        if cfbHasStream(cfb, 'SampleInfo')
            sampleInfoBytes = cfbGetStream(cfb, 'SampleInfo');
            sampleInfoBytes = sampleInfoBytes(9:end); % skip first 8 bytes
            parts = splitBytes(sampleInfoBytes, uint8([0, 0, 8, 0]));

            if numel(parts) == 2
                nameParts = splitBytes(parts{1}, uint8([0, 0]));
                sampleName = unpackSampleInfo(nameParts{1});

                commentParts = splitBytes(parts{2}, uint8([0, 0]));
                if numel(commentParts) >= 2
                    comment = unpackSampleInfo(commentParts{2});
                end
            elseif numel(parts) == 1
                nameParts = splitBytes(parts{1}, uint8([0, 0]));
                sampleName = unpackSampleInfo(nameParts{1});
                comment = '';
            end
        end
    catch
        sampleName = '';
        comment = '';
    end
    data.sampleName = sampleName;
    data.comment = comment;
end

function yMatrix = unpackYData(yData, npoints, numChannels)
%UNPACKYDATA Unpacks the Y-Data stream into an npoints x numChannels
%   matrix of single-precision floats (one column per channel), matching
%   Python's chunked unpack("f"*npoints, chunk).
    nBytes = numel(yData);
    if numChannels <= 0 || mod(nBytes, numChannels) ~= 0
        error('jasco2txt:unpackYData', 'Cannot split Y-Data into channels.');
    end
    chunkSizeBytes = nBytes / numChannels;
    if chunkSizeBytes ~= npoints * 4
        error('jasco2txt:unpackYData', 'Incorrect number of channels.');
    end
    floats = typecast(yData(:), 'single');
    yMatrix = reshape(floats, npoints, numChannels);
end

function name = getChannelName(code)
    persistent map
    if isempty(map)
        map = containers.Map('KeyType', 'double', 'ValueType', 'char');
        map(536871427) = 'TIME';
        map(268435715) = 'WAVELENGTH';
        map(4097)       = 'CD';
        map(8193)       = 'HT VOLTAGE';
        map(3)          = 'ABSORBANCE';
        map(14)         = 'FLUORESCENCE';
    end
    if isKey(map, code)
        name = map(code);
    else
        name = 'undefined';
    end
end

function str = unpackSampleInfo(bytesIn)
%UNPACKSAMPLEINFO Mirrors Python's __unpack_sample_info: pads with a
%   trailing null byte if needed, then decodes as UTF-16LE.
    bytesIn = uint8(bytesIn(:)');
    if ~isempty(bytesIn) && bytesIn(end) ~= 0
        bytesIn(end+1) = 0;
    end
    if mod(numel(bytesIn), 2) ~= 0
        bytesIn(end+1) = 0; % defensive padding to keep UTF-16 pairs intact
    end
    if isempty(bytesIn)
        str = '';
        return;
    end
    codeUnits = typecast(bytesIn, 'uint16');
    str = strtrim(char(codeUnits));
    str = deblank(str);
end

function parts = splitBytes(data, pattern)
%SPLITBYTES Splits a uint8 vector on exact, non-overlapping occurrences
%   of `pattern` (uint8 vector), analogous to Python bytes.split().
    data = uint8(data(:)');
    pattern = uint8(pattern(:)');
    pLen = numel(pattern);
    parts = {};
    if pLen == 0
        parts = {data};
        return;
    end
    startIdx = 1;
    i = 1;
    n = numel(data);
    while i <= n - pLen + 1
        if isequal(data(i:i+pLen-1), pattern)
            parts{end+1} = data(startIdx:i-1); %#ok<AGROW>
            i = i + pLen;
            startIdx = i;
        else
            i = i + 1;
        end
    end
    parts{end+1} = data(startIdx:end);
end

% ========================================================================
% Minimal OLE2 / Compound File Binary (CFB) reader
% (equivalent to the subset of Python's `olefile` used here)
% ========================================================================

function cfb = cfbOpen(filePath)
    fid = fopen(filePath, 'r');
    if fid == -1
        error('jasco2txt:cfbOpen', 'Could not open %s.', filePath);
    end
    raw = fread(fid, Inf, 'uint8=>uint8');
    fclose(fid);
    raw = raw(:)';

    sig = raw(1:8);
    if ~isequal(sig, uint8([0xD0 0xCF 0x11 0xE0 0xA1 0xB1 0x1A 0xE1]))
        error('jasco2txt:cfbSig', '%s is not a valid OLE compound file.', filePath);
    end

    sectorShift     = double(typecast(raw(31:32), 'uint16'));
    miniSectorShift = double(typecast(raw(33:34), 'uint16'));
    numFATSectors   = typecast(raw(45:48), 'uint32'); %#ok<NASGU>
    firstDirSector  = typecast(raw(49:52), 'uint32');
    miniCutoff      = double(typecast(raw(57:60), 'uint32'));
    firstMiniFAT    = typecast(raw(61:64), 'uint32');
    numMiniFAT      = double(typecast(raw(65:68), 'uint32')); %#ok<NASGU>
    firstDIFAT      = typecast(raw(69:72), 'uint32');
    numDIFATSectors = double(typecast(raw(73:76), 'uint32'));

    sectorSize = 2^sectorShift;
    miniSectorSize = 2^miniSectorShift;

    FREESECT = uint32(hex2dec('FFFFFFFF'));
    ENDOFCHAIN = uint32(hex2dec('FFFFFFFE'));

    getSectorBytes = @(n) getSector(raw, double(n), sectorSize);

    % --- Build DIFAT (list of FAT sector numbers) ---
    difat = typecast(raw(77:512), 'uint32');
    sector = firstDIFAT;
    remaining = numDIFATSectors;
    while remaining > 0 && sector ~= ENDOFCHAIN && sector ~= FREESECT
        sBytes = getSectorBytes(sector);
        entries = typecast(sBytes, 'uint32');
        difat = [difat, entries(1:end-1)]; %#ok<AGROW>
        sector = entries(end);
        remaining = remaining - 1;
    end

    % --- Build FAT ---
    FAT = uint32([]);
    for i = 1:numel(difat)
        v = difat(i);
        if v == FREESECT
            continue;
        end
        sBytes = getSectorBytes(v);
        FAT = [FAT, typecast(sBytes, 'uint32')]; %#ok<AGROW>
    end

    % --- Read directory sectors & parse entries ---
    dirBytes = followChain(getSectorBytes, FAT, firstDirSector, ENDOFCHAIN, FREESECT, Inf);
    numEntries = floor(numel(dirBytes) / 128);
    entries = struct('name', {}, 'objectType', {}, 'startSector', {}, 'size', {});
    rootEntry = [];
    for i = 1:numEntries
        off = (i-1)*128;
        nameLen = double(typecast(dirBytes(off+65:off+66), 'uint16'));
        objType = dirBytes(off+67);
        if nameLen == 0
            continue;
        end
        nChars = max(0, floor((nameLen - 2) / 2));
        nameBytes = dirBytes(off+1 : off+1+2*nChars-1);
        if nChars > 0
            name = char(typecast(nameBytes, 'uint16'));
        else
            name = '';
        end
        startSector = typecast(dirBytes(off+117:off+120), 'uint32');
        streamSize = typecast(dirBytes(off+121:off+128), 'uint64');

        e.name = name;
        e.objectType = objType;
        e.startSector = startSector;
        e.size = double(streamSize);
        entries(end+1) = e; %#ok<AGROW>

        if objType == 5
            rootEntry = e;
        end
    end

    if isempty(rootEntry)
        error('jasco2txt:cfbRoot', 'Root Entry not found in %s.', filePath);
    end

    % --- Build Mini FAT and Mini Stream (root entry's regular stream) ---
    miniFATBytes = followChain(getSectorBytes, FAT, firstMiniFAT, ENDOFCHAIN, FREESECT, Inf);
    miniFAT = typecast(miniFATBytes, 'uint32');

    miniStreamData = followChain(getSectorBytes, FAT, rootEntry.startSector, ...
        ENDOFCHAIN, FREESECT, rootEntry.size);

    cfb.entries = entries;
    cfb.FAT = FAT;
    cfb.miniFAT = miniFAT;
    cfb.miniStreamData = miniStreamData;
    cfb.miniSectorSize = miniSectorSize;
    cfb.sectorSize = sectorSize;
    cfb.miniCutoff = miniCutoff;
    cfb.getSectorBytes = getSectorBytes;
    cfb.ENDOFCHAIN = ENDOFCHAIN;
    cfb.FREESECT = FREESECT;
end

function sBytes = getSector(raw, n, sectorSize)
    startByte = (n + 1) * sectorSize; % 0-based byte offset
    idx1 = startByte + 1;
    idx2 = startByte + sectorSize;
    if idx2 > numel(raw)
        idx2 = numel(raw);
    end
    if idx1 > numel(raw)
        sBytes = uint8.empty(1, 0);
        return;
    end
    sBytes = raw(idx1:idx2);
    if numel(sBytes) < sectorSize
        sBytes = [sBytes, zeros(1, sectorSize - numel(sBytes), 'uint8')];
    end
end

function outBytes = followChain(getSectorBytes, FAT, startSector, ENDOFCHAIN, FREESECT, maxSize)
%FOLLOWCHAIN Concatenates sectors following a FAT-style chain, truncated
%   to maxSize bytes (pass Inf for no truncation).
    outBytes = uint8.empty(1, 0);
    sector = startSector;
    guard = 0;
    maxIter = numel(FAT) + 2; % safety against malformed/circular chains
    while sector ~= ENDOFCHAIN && sector ~= FREESECT && guard < maxIter
        outBytes = [outBytes, getSectorBytes(sector)]; %#ok<AGROW>
        if ~isfinite(maxSize) == false && numel(outBytes) >= maxSize
            break;
        end
        idx = double(sector) + 1;
        if idx < 1 || idx > numel(FAT)
            break;
        end
        sector = FAT(idx);
        guard = guard + 1;
    end
    if isfinite(maxSize) && numel(outBytes) > maxSize
        outBytes = outBytes(1:maxSize);
    end
end

function tf = cfbHasStream(cfb, name)
    tf = false;
    for i = 1:numel(cfb.entries)
        if strcmp(cfb.entries(i).name, name) && cfb.entries(i).objectType == 2
            tf = true;
            return;
        end
    end
end

function dataBytes = cfbGetStream(cfb, name)
    entry = [];
    for i = 1:numel(cfb.entries)
        if strcmp(cfb.entries(i).name, name) && cfb.entries(i).objectType == 2
            entry = cfb.entries(i);
            break;
        end
    end
    if isempty(entry)
        error('jasco2txt:cfbStream', 'Stream "%s" not found.', name);
    end

    if entry.size < cfb.miniCutoff
        % Mini stream: addressed in miniSectorSize chunks within the
        % root entry's regular-stream data, chained via miniFAT.
        getMiniSectorBytes = @(n) getMiniSector(cfb.miniStreamData, double(n), cfb.miniSectorSize);
        dataBytes = followChain(getMiniSectorBytes, cfb.miniFAT, entry.startSector, ...
            cfb.ENDOFCHAIN, cfb.FREESECT, entry.size);
    else
        dataBytes = followChain(cfb.getSectorBytes, cfb.FAT, entry.startSector, ...
            cfb.ENDOFCHAIN, cfb.FREESECT, entry.size);
    end
end

function sBytes = getMiniSector(miniStreamData, n, miniSectorSize)
    startByte = n * miniSectorSize;
    idx1 = startByte + 1;
    idx2 = startByte + miniSectorSize;
    if idx1 > numel(miniStreamData)
        sBytes = uint8.empty(1, 0);
        return;
    end
    if idx2 > numel(miniStreamData)
        idx2 = numel(miniStreamData);
    end
    sBytes = miniStreamData(idx1:idx2);
    if numel(sBytes) < miniSectorSize
        sBytes = [sBytes, zeros(1, miniSectorSize - numel(sBytes), 'uint8')];
    end
end
