% MIT License

% Copyright (c) 2021 Open Ephys

% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, including without limitation the rights
% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
% copies of the Software, and to permit persons to whom the Software is
% furnished to do so, subject to the following conditions:

% The above copyright notice and this permission notice shall be included in all
% copies or substantial portions of the Software.

% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
% SOFTWARE.

classdef BinaryRecording < Recording

    properties

        info
        syncMessages

    end

    methods 

        function self = BinaryRecording(directory, experimentIndex, recordingIndex) 
            
            self = self@Recording(directory, experimentIndex, recordingIndex);
            self.format = 'Binary';

            self.info = jsondecode(fileread(fullfile(self.directory,'structure.oebin')));
            self.syncMessages = [];
        end

        function self = loadContinuous(self, downsample_factor)
            Utils.log("Loading continuous data...");

            Utils.log("Loading streams: ");

            for j = 1:length(self.info.continuous)
                streamName = self.info.continuous(j).folder_name;
                streamName = streamName(1:(end-1));
                self.loadContinuousStream(downsample_factor, streamName);
            end
            Utils.log("Finished loading continuous data!");
        end
        
        function self = loadContinuousStream(self, downsample_factor, streamName, channel_nums)

            folder_names = arrayfun(@(j) string(self.info.continuous(j).folder_name),...
                1:numel(self.info.continuous));
            i = find(contains(folder_names, streamName), 1);
            
            if isempty(i)
                error('Could not find stream %s', streamName);
            end
            
            if nargin < 4
                channel_nums = 1:self.info.continuous(i).num_channels;
            end
            directory = fullfile(self.directory, 'continuous', self.info.continuous(i).folder_name);

            Utils.log("Loading data from directory: ", directory);

            stream = {};

            stream.metadata.sampleRate = self.info.continuous(i).sample_rate / downsample_factor;
            stream.metadata.numChannels = self.info.continuous(i).num_channels;
            stream.metadata.processorId = self.info.continuous(i).source_processor_id;
            stream.metadata.streamName = self.info.continuous(i).folder_name(1:end-1);

            stream.metadata.names = {};
            for j = 1:length(self.info.continuous(i).channels)
                stream.metadata.names{j} = self.info.continuous(i).channels(j).channel_name;
            end

            Utils.log("Searching for start timestamp for stream: ");
            Utils.log("    ", stream.metadata.streamName);

            stream.metadata.id = num2str(stream.metadata.streamName);

            stream.timestamps = readNPY(fullfile(directory, 'timestamps.npy'));
            nts = length(stream.timestamps);
            nchan = stream.metadata.numChannels;

            if downsample_factor == 1
                nts_per_chunk = 256 * 1024 * 5;
            else
                nts_per_chunk = lcm(256 * 1024, downsample_factor);
            end
            nchunks = ceil(nts / nts_per_chunk);
            m = memmapfile(fullfile(directory, 'continuous.dat'), ...
                'Format', {'int16', [nchan nts_per_chunk], 't'},...
                 'Offset', 0);

            samples_down = zeros(numel(channel_nums), ceil(nts/downsample_factor), 'int16');
            timestamps_down = downsample(stream.timestamps, downsample_factor);
            part_i = 1;
            nts_last_chunk = mod(nts, nts_per_chunk);
            for chunk_i = 1:nchunks
                Utils.log(sprintf("Reading continuous data chunk %d out of %d", chunk_i, nchunks));
                % Read last chunk seperately into array fitting its size
                if chunk_i == nchunks && nts_last_chunk > 0
                    m = memmapfile(fullfile(directory, 'continuous.dat'), ...
                        'Format', {'int16', [nchan nts_last_chunk], 't'},...
                        'Offset', (nchunks-1) * nts_per_chunk * nchan * 2); % 2 bytes per int16
                    data = m.Data(1).t;
                else
                    data = m.Data(chunk_i).t;
                end
                data = data(channel_nums, :);
                % Extend data to avoid edge effects in resampling
                resample_data = double([data repelem(data(:,end), 1, downsample_factor)]);
                samples_down_part = resample(resample_data, 1, downsample_factor, 'Dimension', 2);
                samples_down_part = samples_down_part(:, 1:(end-1));
                nsamples_down_part = size(samples_down_part, 2);
                part_idx = part_i : (part_i + nsamples_down_part - 1);
                samples_down(:,part_idx) = samples_down_part;
                part_i = part_i + nsamples_down_part;
            end
            if (part_i - 1) < numel(timestamps_down)
                warning('Read bin data from %d timepoints, expected %d', ...
                    part_i - 1, numel(timestamps_down));
            end

            stream.samples = samples_down;
            stream.timestamps = timestamps_down;
            syncMessages = self.loadSyncMessages();
            stream.metadata.startTimestamp = syncMessages(stream.metadata.id);

            self.continuous(stream.metadata.id) = stream;

        end

        function timestamps = readStreamTimestamps(self, stream_key)
            folder_names = arrayfun(@(j) string(self.info.continuous(j).folder_name),...
                1:numel(self.info.continuous));
            i = find(contains(folder_names, stream_key), 1);
            directory = fullfile(self.directory, 'continuous', self.info.continuous(i).folder_name);
            timestamps = readNPY(fullfile(directory, 'timestamps.npy'));
        end
        
        function self = loadEvents(self)

            Utils.log("Loading event data!");

            eventDirectories = glob(fullfile(self.directory, 'events', '*', 'TTL*'));
            
            streamIdx = 0;

            for i = 1:length(eventDirectories)

                files = regexp(eventDirectories{i},filesep,'split');

                fname = files{length(files)-2};
                processorIdStart = regexp(fname, '1\d\d');
                processorId = str2num(fname(processorIdStart:(processorIdStart+2)));
                node = regexp(files{length(files)-2},'-','split');
                
                channels = readNPY(fullfile(eventDirectories{i}, 'states.npy'));
                sampleNumbers = readNPY(fullfile(eventDirectories{i}, 'sample_numbers.npy'));
                timestamps = readNPY(fullfile(eventDirectories{i}, 'timestamps.npy'));

                id = fname;

                self.ttlEvents(id) = DataFrame(abs(channels), sampleNumbers, timestamps, processorId*ones(length(channels),1), streamIdx*ones(length(channels),1), channels > 0, ...
                    'VariableNames', {'channel','sample_number','timestamp','processor_id', 'stream_index', 'state'});
                
                streamIdx = streamIdx + 1;

            end

            Utils.log("Finished loading event data!");

            if length(self.ttlEvents.keys) > 0
                %TODO: Concatenate data frames?
            end

        end

        function self = loadSpikes(self)

            Utils.log("Loading spike data!");

            for i = 1:length(self.info.spikes)

                directory = fullfile(self.directory, 'spikes', self.info.spikes(i).folder);

                spikes = {};

                spikes.id = self.info.spikes(i).folder(1:end-1);

                spikes.timestamps = readNPY(fullfile(directory, 'timestamps.npy'));
                spikes.electrodes = readNPY(fullfile(directory, 'electrode_indices.npy'));
                spikes.waveforms = readNPY(fullfile(directory, 'waveforms.npy'));
                spikes.clusters = readNPY(fullfile(directory, 'clusters.npy'));
                spikes.sample_numbers = readNPY(fullfile(directory, 'sample_numbers.npy'));
                
                self.spikes(spikes.id) = spikes;  

            end

            Utils.log("Finished loading spike data!");

        end

        function syncMessages = loadSyncMessages(self)
            
            if ~isempty(self.syncMessages)
                syncMessages = self.syncMessages;
                return
            end

            Utils.log("Loading sync messages...");

            syncMessages = containers.Map();

            rawMessages = splitlines(fileread(fullfile(self.directory, 'sync_messages.txt')));

            for i = 1:length(rawMessages)-1

                message = strsplit(rawMessages{i});

                if message{1} == "Software"

                    % Found system time for start of the recording
                    % "Software Time (milliseconds since midnight Jan 1st 1970 UTC): 1660948389101"
                    syncMessages("Software") = str2double(message{end});

                else

                    % Found a processor string
                    %(e.g. "Start Time for File Reader (100) - Rhythm Data @ 40000 Hz: 80182")

                    processorMsgIdx = find(contains(message,'(') & contains(message,')'));
                    processorName = strjoin(message(4:(processorMsgIdx-1)),'_');
                    processorId = message{processorMsgIdx}(2:(end-1));
                    streamName = strjoin(message(processorMsgIdx+2:find(contains(message,'@'))-1), ' ');
                    samplingFreqHz = message{find(contains(message,'@'))+1};

                    streamId = strcat(processorName, "-", processorId, ".", streamName);

                    syncMessages(streamId) = str2double(message{end});

                end

            end

            Utils.log("Finished loading sync messages!");
            self.syncMessages = syncMessages;
        end
        
        
        function chan_nums = get_chan_nums(self, stream_key)
            chan_nums = {};
            for i = 1:size(self.info.continuous,1)
                cinfo = self.info.continuous(i);
                if strcmp(cinfo.folder_name(1:(end-1)), stream_key)
                    chan_nums = 1:cinfo.num_channels;
                    break
                end
            end
        end

        function sample_rate = getSampleRate(self, stream_key)
            for i = 1 : size(self.info.continuous, 1)
                cinfo = self.info.continuous(i,:);
                if strcmp(cinfo.folder_name(1:(end-1)), stream_key)
                    sample_rate = cinfo.sample_rate;
                    return
                end
            end
            error('Didnt find stream %s', stream_key)
        end
    end

    methods (Static)
        
        function detectedFormat = detectFormat(directory)

            detectedFormat = false;

            binaryFiles = glob(fullfile(directory, 'experiment*', 'recording*'));
        
            if length(binaryFiles) > 0
                detectedFormat = true;
            end

        end

        function recordings = detectRecordings(directory)

            Utils.log("Searching for recordings...");

            recordings = {};

            experimentDirectories = glob(fullfile(directory, 'experiment*'));
            %sort

            for expIdx = 1:length(experimentDirectories)

                recordingDirectories = glob(fullfile(experimentDirectories{expIdx}, 'recording*'));
                %sort

                for recIdx = 1:length(recordingDirectories)
                    recordings{end+1} = BinaryRecording(recordingDirectories{recIdx}, expIdx, recIdx);
                end

            end

            Utils.log("Finished searching for recordings!");
            
        end
        
    end

end