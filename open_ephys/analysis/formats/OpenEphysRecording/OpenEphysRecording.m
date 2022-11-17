% MIT License
% 
% Copyright (c) 2021 Open Ephys
% 
% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, including without limitation the rights
% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
% copies of the Software, and to permit persons to whom the Software is
% furnished to do so, subject to the following conditions:
% 
% The above copyright notice and this permission notice shall be included in all
% copies or substantial portions of the Software.
% 
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
% SOFTWARE.

classdef OpenEphysRecording < Recording

    properties (Constant)

        NUM_HEADER_BYTES = 1024;
        SAMPLES_PER_RECORD = 1024;
        BYTES_PER_SAMPLE = 2;
        RECORD_MARKER = [0 1 2 3 4 5 6 7 8 255];
        EVENT_RECORD_SIZE = 32;

    end

    properties

        experimentId;
        recordSize;
        oeVersion;
        streams;

    end

    methods 

        function self = OpenEphysRecording(directory, experimentIndex, recordingIndex) 
         
            self = self@Recording(directory, experimentIndex, recordingIndex);
            self.format = 'OpenEphys';

            self.recordSize = 4 + 8 + self.SAMPLES_PER_RECORD * self.BYTES_PER_SAMPLE + length(self.RECORD_MARKER);

            if experimentIndex == 1
                self.experimentId = '';
            else
                self.experimentId = ['_', num2str(experimentIndex)];
            end

            self = self.loadStructure();

        end

        function self = loadStructure(self)
            continuousInfo = glob(fullfile(self.directory, ['*' self.experimentId '.openephys']));
            data = readstruct(continuousInfo{1}, "FileType", "xml");
            if isfield(data, 'versionAttribute')
                self.oeVersion = data.versionAttribute;
            else
                self.oeVersion = data.format_versionAttribute;
            end
            self.streams = containers.Map;
            
            if (self.oeVersion < 0.5)
                streamData = data.RECORDING.PROCESSOR;
            else
                streamData = data.RECORDING(self.recordingIndex).STREAM;
            end

            for i = 1:length(streamData)

                stream = {};
                if (self.oeVersion < 0.5)
                    stream.nodeId = streamData.idAttribute;
                    stream.name = "";
                    stream.sampleRate = data.RECORDING.samplerateAttribute;
                else
                    stream.nodeId = streamData(i).source_node_idAttribute;
                    stream.name = replace(replace(streamData(i).nameAttribute, "_", "-"), " ", "");
                    stream.sampleRate = streamData(i).sample_rateAttribute;
                end

                stream.channels = {};

                for j = 1:length(streamData(i).CHANNEL)

                    cdata = {};

                    cdata.name = streamData(i).CHANNEL(j).nameAttribute;
                    cdata.num = str2double(strrep(strrep(strrep(cdata.name, "CH", ""), "LFP", ""), "AP", ""));
                    cdata.bitVolts = streamData(i).CHANNEL(j).bitVoltsAttribute;
                    cdata.position = streamData(i).CHANNEL(j).positionAttribute;
                    cdata.filename = streamData(i).CHANNEL(j).filenameAttribute;

                    stream.channels{end+1} = cdata;

                end

                if (self.oeVersion < 0.5)
                    stream.events.filename = 'all_channels.events';
                else
                    stream.events.filename = streamData(i).EVENTS.filenameAttribute;
                end

                if (isfield(streamData(i), 'SPIKECHANNEL'))

                    stream.spikes = {};
    
                    for j = 1:length(streamData(i).SPIKECHANNEL)
    
                        data = {};
    
                        data.name = streamData(i).SPIKECHANNEL(j).nameAttribute;
                        data.bitVolts = streamData(i).SPIKECHANNEL(j).bitVoltsAttribute;
                        data.filename = streamData(i).SPIKECHANNEL(j).filenameAttribute;
    
                        stream.spikes{end+1} = data;
    
                    end

                end
                
                nodeID = num2str(stream.nodeId);
                if stream.name ~= ""
                    nodeID = strcat(nodeID, "_", stream.name);
                end
                self.streams(nodeID) = stream;
                
            end

        end

        function self = loadContinuous(self, downsample_factor)

            % Get list of all continuous files
            files = self.findContinuousFiles();

            streamNames = self.streams.keys();
            for i = 1:length(streamNames)

                % Find all continuous files belonging to this stream
                streamFiles = {};
                for j = 1:length(files)
                    if contains(files{j}, streamNames{i}) && isfile(files{j})
                        streamName = split(streamNames{i}, '_');
                        processorId = streamName{1};
                        streamFiles{end+1} = files{j};
                    end
                end
                if isempty(streamFiles)
                    continue
                end
                [timestamps, ~, ~] = self.loadContinuousFile(streamFiles{1}, downsample_factor);
                stream = {};

                stream.metadata = {};

                stream.metadata.names = [];
                stream.metadata.processorId = processorId;
                stream.metadata.startTimestamp = timestamps(1);
                stream.metadata.sampleRate = self.streams(processorId).sampleRate / downsample_factor;

                stream.timestamps = timestamps;

                stream.samples = zeros(length(streamFiles), length(timestamps));

                channels = zeros(1,numel(streamFiles));
                for j = 1:length(streamFiles)
            
                    [~, samples, header] = self.loadContinuousFile(streamFiles{j}, downsample_factor);

                    stream.samples(j,:) = samples';
                    chan_name = header('channel');
                    chan_name = chan_name(4:(end-1));
                    channels(j) = int16(str2double(chan_name));
                end
                stream.metadata.channels = channels;
                self.continuous(streamNames{i}) = stream;

            end

        end

        function self = loadEvents(self)

            streamNames = self.streams.keys();

            for i = 1:length(streamNames)

                filename = fullfile(self.directory, self.streams(streamNames{i}).events.filename);

                s = dir(filename);
                if isempty(s)
                    continue
                end
                if s.bytes == 1024
                    fprintf("Event file at %s does not contain any event data!\n", filename);
                    return
                end
    
                [timestamps, processorId, state, channel, header] = self.loadEventsFile(filename);
                timestamps = double(timestamps) / str2double(header('sampleRate'));
                self.ttlEvents(streamNames{i}) = DataFrame(channel + 1, timestamps, processorId, state, 'VariableNames', {'channel','timestamp','nodeID','state'});

            end 

        end

        function self = loadSpikes(self)

            streamNames = self.streams.keys();

            for i = 1:length(streamNames)

                if isfield(self.streams(streamNames{i}), 'spikes')

                    for j = 1:length(self.streams(streamNames{i}).spikes)

                        filename = fullfile(self.directory, self.streams(streamNames{i}).spikes{j}.filename);

                        [timestamps, waveforms, header] = self.loadSpikeFile(filename, self.recordingIndex);
    
                        spikes = {};
    
                        spikes.waveforms = waveforms';
                        spikes.timestamps = timestamps;
            
                        self.spikes(header('electrode')) = spikes;
    
                    end

                end

            end

        end

        function files = findContinuousFiles(self)

            %Find all continuous files that belong to this experiment

            paths = glob(fullfile(self.directory, '*continuous'));
            f = cellfun(@(x) regexp(x, '[\\/]', 'split'), paths, 'UniformOutput', false); f = vertcat(f{:});
            f = cellfun(@(x) regexp(x, '[._]', 'split'), f(:,end), 'UniformOutput', false);

            files = {}; 

            for i = 1:length(f)

                experimentIndex = 1;
                if length(f{i}) > 4
                    experimentIndex = str2double(f{i}{end-1});
                end
                if experimentIndex == self.experimentIndex
                    files{end+1} = paths{i};
                end
            end

        end

        function files = findSpikeFiles(self, fileType)

            searchString = containers.Map();
            searchString('single electrode') = 'SE';
            searchString('stereotrode') = 'ST';
            searchString('tetrode') = 'TT';

            if self.experimentIndex == 1
                paths = glob(fullfile(self.directory, [searchString(fileType), '*spikes']));
            else
                paths = glob(fullfile(self.directory, [searchString(fileType), '*', self.experimentIndex, '*spikes']));
            end

            files = paths;

        end

        function [timestamps, samples, header] = loadContinuousFile(self, filename, downsample_factor)
            
            header = self.readHeader(filename);
            numRecords = self.getNumRecords(filename);

            %TODO: Use memory mapping based on file size. If file size is too small, memory mapping will waste space. 
            useMemoryMapping = true;

            if ~useMemoryMapping

                %TODO: Test and fix non-memory mapped version
                
                fid = fopen(filename);
                fread(fid, self.NUM_HEADER_BYTES, 'char*1'); %header

                timestamps = [];
                samples = [];

                for i = 1:numRecords
                    
                    timestamp = fread(fid, 1, 'int64',0,'l');
                    N = fread(fid, 1, 'uint16',0,'l');
                    recordingNumber = fread(fid, 1, 'uint16', 0, 'l');
                    if recordingNumber == self.recordingIndex
                        samples = [samples; fread(fid, N, 'int16',0,'b')]; %big-endian
                        timestamps = [timestamps, timestamp:(timestamp + N - 1)];
                    elseif recordingNumber > self.recordingIndex
                        break;
                    end
                    fread(fid, 10, 'char*1'); %recordMarker
                    
                end
                
                fclose(fid);
                
            else %Use memory mapping to load data
                
                %Load all data after the header into a memory mapped file as int16
                data = memmapfile(filename, 'Writable', false, 'Format', 'int16', 'Offset', self.NUM_HEADER_BYTES);

                %Reshape into recorded blocks
                dataSamples = reshape(data.Data, [floor(self.recordSize / 2), numRecords]);
                
                %Get mask for current recording
                recIndex = self.recordingIndex - 1;
                if self.oeVersion < 0.5
                    recIndex = self.recordingIndex;
                end
                validRecords = dataSamples(6,:) == recIndex;
                
                %Isolate valid samples and convert to big endian
                validSamples = swapbytes(dataSamples(7:end-5,validRecords));
                
                %Vectorize
                samples = validSamples(:);
                
                %Generate timestamps
                firstRecord = find(validRecords,1,'first');
                data = memmapfile(filename, 'Writable', false, 'Format', 'int64', 'Offset', self.NUM_HEADER_BYTES + firstRecord*self.recordSize, 'Repeat', 1);
                startTimestamp = data.Data(1) - 1024;
                timestamps = startTimestamp:(startTimestamp + length(samples) - 1);

            end
            
            [samples, timestamps] = self.downsample_data(samples, timestamps, downsample_factor);
            timestamps = double(timestamps) / str2double(header('sampleRate'));
        end

        function [timestamps, processorId, state, channel, header ] = loadEventsFile(self, filename)

            header = self.readHeader(filename);

            timestamps = memmapfile(filename, 'Writable', false, 'Offset', 1024, 'Format', 'int64');

            timestamps = timestamps.Data(1:2:end);

            data = memmapfile(filename, 'Writable', false, 'Offset', 1024);
            data = reshape(data.Data, floor(self.EVENT_RECORD_SIZE / 2), length(timestamps));
            
            recordingNumber = data(15,:);

            recIndex = self.recordingIndex - 1;
            if self.oeVersion < 0.5
                recIndex = self.recordingIndex;
            end
            mask = recordingNumber == recIndex;
            
            timestamps = timestamps(mask);
            processorId = data(12,mask)';
            state = data(13,mask)';
            channel = data(14,mask)';

        end
        
        function [timestamps, waveforms, header] = loadSpikeFile(self, filename, recordingNumber)

            header = self.readHeader(filename);

            fid = fopen(filename);
            fread(fid, 1043, 'char*1');
            numChannels = fread(fid, 1, 'uint16', 0, 'l');
            numSamples = fread(fid, 1, 'uint16', 0, 'l');
            fclose(fid);

            SPIKE_RECORD_SIZE = 42 + 2 * numChannels * numSamples + 4 * numChannels + 2 * numChannels + 2;

            POST_BYTES = 4 * numChannels + 2 * numChannels + 2;

            s = dir(filename);
            numSpikes = floor(( s.bytes - self.NUM_HEADER_BYTES ) / SPIKE_RECORD_SIZE);

            timestamps = zeros(numSpikes,1);

            fid = fopen(filename);
            fread(fid, self.NUM_HEADER_BYTES+1, 'char*1');

            for i  = 1:length(timestamps)
                timestamps(i) = fread(fid, 1, 'int64');
                fseek(fid, self.NUM_HEADER_BYTES + 1 + SPIKE_RECORD_SIZE * i, -1);
            end

            data = memmapfile(filename, 'Writable', false, 'Offset', self.NUM_HEADER_BYTES, 'Format', 'uint16');
            data = reshape(data.Data, floor(SPIKE_RECORD_SIZE / 2), numSpikes);

            recIndex = self.recordingIndex - 1;
            if self.oeVersion < 0.5
                recIndex = self.recordingIndex;
            end
            mask = recordingNumber == recIndex;

            timestamps = timestamps(mask==1);

            [r,~] = size(data);
            waveforms = single(data(22:(r - floor(POST_BYTES/2)), mask==1));
            waveforms = waveforms - 32768;
            %waveforms = waveforms / 20000;
            %waveforms = waveforms * 1000;

        end

        function numRecords = getNumRecords(self, filename)

            s = dir(filename);

            numRecords = ( s.bytes - self.NUM_HEADER_BYTES ) / self.recordSize;

            assert(mod(numRecords,1) == 0);

        end

        function header = readHeader(self, filename)

            %Return header as a containers.Map (matlab dictionary)
            header = containers.Map();
            fr = matlab.io.datastore.DsFileReader(filename);
            rawHeader = strrep(native2unicode(read(fr, self.NUM_HEADER_BYTES))', 'header.', '');
            rawHeader = strsplit(rawHeader,'\n');
            for i = 1:length(rawHeader)
                keyVal = strsplit(rawHeader{i},"=");
                if length(keyVal) > 1
                    key = strtrim(keyVal{1});
                    value = strtrim(erase(keyVal{2},";"));
                    header(key) = value;
                end
            end

        end
        
        function chan_nums = get_chan_nums(self, stream_key)
            chan_nums = self.continuous(stream_key).metadata.channels;
        end
        
        function sample_rate = getSampleRate(self, stream_key)
            sample_rate = self.continuous(stream_key).metadata.sampleRate;
        end
    end

    methods (Static)
        
        function detectedFormat = detectFormat(directory)

            detectedFormat = false;

            openEphysFiles = glob(fullfile(directory, '*.events'));
        
            if ~isempty(openEphysFiles)
                detectedFormat = true;
            end

        end

        function recordings = detectRecordings(directory)

            recordings = {};

            messageFiles = glob(fullfile(directory, 'messages*events'));
            %TODO: sort

            for i = 1:length(messageFiles)
                
                experimentIndex = i - 1;

                if i == 1
                    experimentId = '';
                else
                    experimentId = ['_' num2str(i)];
                end

                continuousInfo = glob(fullfile(directory, ['*' experimentId '.openephys']));

                foundRecording = false;

                if ~isempty(continuousInfo)

                    for j = 1:length(continuousInfo)

                        info = xml2struct(continuousInfo{j});

                        experimentIndex = str2num(info.EXPERIMENT.Attributes.number);

                        for k = 1:length(info.EXPERIMENT.RECORDING)

                            if length(info.EXPERIMENT.RECORDING) > 1
                                recordingIndex = str2num(info.EXPERIMENT.RECORDING{1,k}.Attributes.number);
                            else
                                recordingIndex = str2num(info.EXPERIMENT.RECORDING.Attributes.number);
                            end
                            
                            recordings{end+1} = OpenEphysRecording(directory, experimentIndex, recordingIndex);

                        end

                    end
                    
                    foundRecording = true;

                end

                if ~foundRecording

                    eventFile = glob(fullfile(directory, ['all_channels' experimentId '.events']));

                    if ~isempty(eventFile)
                        
                        timestamps = memmapfile(eventFile{1}, 'Writable', false, 'Offset', 1024, 'Format', 'int64');
                        timestamps = timestamps.Data(1:2:end);

                        data = memmapfile(eventFile{1}, 'Writable', false, 'Offset', 1024);
                        data = reshape(data.Data, floor(OpenEphysRecording.EVENT_RECORD_SIZE / 2), length(timestamps));
                       
                        recordingIndeces = unique(data(15,:));
                        
                        for j = 1:length(recordingIndeces)
                            
                            recordings{end+1} = OpenEphysRecording(directory, experimentIndex, recordingIndeces(j)); 
                            
                        end
                        
                    end
                    
                    foundRecording = true;

                end
                
                if ~foundRecording

                    spikesFile = glob(fullfile(directory, ['*n[0-9]' experimentId '.spikes']));

                    if ~isempty(spikesFile)
                        
                        fid = fopen(spikesFile{1});
                        fread(fid, 1043, 'char*1');
                        numChannels = fread(fid, 1, 'uint16', 0, 'l');
                        numSamples = fread(fid, 1, 'uint16', 0, 'l');
                        fclose(fid);

                        SPIKE_RECORD_SIZE = 42 + 2 * numChannels * numSamples + 4 * numChannels + 2 * numChannels + 2;

                        s = dir(spikesFile{1});
                        numSpikes = floor(( s.bytes - OpenEphysRecording.NUM_HEADER_BYTES ) / SPIKE_RECORD_SIZE);

                        data = memmapfile(spikesFile{1}, 'Writable', false, 'Offset', OpenEphysRecording.NUM_HEADER_BYTES, 'Format', 'uint16');
                        data = reshape(data.Data, floor(SPIKE_RECORD_SIZE / 2), numSpikes);
                        
                        recordingIndeces = unique(data(end,:));
                        
                        for j = 1:length(recordingIndeces)
                            
                            recordings{end+1} = OpenEphysRecording(directory, experimentIndex, recordingIndeces(j));
                            
                        end
                        
                    end
                    
                    foundRecording = true;
                    
                end
                
                if ~foundRecording
                    fprintf("Could not find any data files\n");
                end
                
            end
            
        end

    end    
end