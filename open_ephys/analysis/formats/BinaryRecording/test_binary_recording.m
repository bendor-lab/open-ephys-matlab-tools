%% Prepare data
test_dir = 'testdata\binaryrecording-test';
tmp_dir = fullfile('C:\Temp', test_dir);
copyfile(test_dir, tmp_dir);
session_dir = tmp_dir;
directory = fullfile(session_dir, 'Record Node 101\experiment1\recording1\continuous\Neuropix-PXI-100.ProbeA-AP');
mkdir(directory)
timestamps_fpath = fullfile(directory, 'timestamps.npy');

ntimestamps = 1000;
diff_timestamps = ones(ntimestamps, 1) * 0.00001;
new_timestamps = cumsum(diff_timestamps);
writeNPY(new_timestamps, timestamps_fpath)


fileID = fopen(fullfile(directory, 'continuous.dat'),'w');
nchan = 385;
downsample_factor = 2;

vals = randi([0 1], [1 100]);
x_down = repelem(vals, nchan, ntimestamps / numel(vals) / downsample_factor);
x = resample(x_down, downsample_factor, 1, 'Dimension', 2);
fwrite(fileID,x,'int16');
fclose(fileID);

%% Read data to check ok
session = Session(session_dir);
rNode = session.recordNodes{1};
rec = rNode.recordings{1};
rec.loadContinuous(downsample_factor);
x_read = rec.continuous('Neuropix-PXI-100.ProbeA-AP').samples;

ntimestamps_down = ntimestamps / downsample_factor;
isequal(double(x_read), x_down)
