classdef OpenEphysNetworkEventsReader < NetworkEventsReader
    
    properties
        messages_events_fpath
        oeVersion
        sample_rate
    end
    
    methods
        function self = OpenEphysNetworkEventsReader(rec_path, oeVersion)
           self = self@NetworkEventsReader(rec_path);
           messages_events_file = dir(fullfile(rec_path, '*messages*.events*'));
           assert(numel(messages_events_file) == 1)
           self.messages_events_fpath = fullfile(messages_events_file.folder, messages_events_file.name);
           self.oeVersion = oeVersion;
        end
        
        function [timestamps, messages, info] = readMessages(self)
            info = struct();
            messages = readlines(self.messages_events_fpath);
            % Ignore messages sent at time 0 - these are stale info
            messages(startsWith(messages, '0 ')) = [];
            ts_str = regexp(messages, '\d+', 'match', 'once');
            processor_info = self.read_oe_processor_info(messages);
            timestamps = str2double(ts_str) / processor_info.sample_rate;
        end
        
        function [processor_info] = read_oe_processor_info(self, messages)
            if self.oeVersion < 0.5
            % Read sampling frequency from messages to translate clock ticks to seconds
                line_selector = 'start time: (?<clock>\d+)@(?<sample_rate>\d+)Hz';
            else
                line_selector = '(?<clock>\d+), Start Time for Acquisition Board .* @ (?<sample_rate>\d+) Hz';
            end
            processor_info_array = regexp(messages, line_selector, 'names');
            processor_info_array_filt = arrayfun(@(i) ... 
                size(processor_info_array{i},1) > 0, 1 : numel(processor_info_array));
            processor_info = processor_info_array{processor_info_array_filt};
            processor_info.clock = str2double(processor_info.clock);
            processor_info.sample_rate = str2double(processor_info.sample_rate);
            processor_info.start_time_sec = processor_info.clock / processor_info.sample_rate;
        end
    end
end

