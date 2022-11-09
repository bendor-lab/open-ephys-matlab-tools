classdef BinaryNetworkEventsReader < NetworkEventsReader
    
    properties
        eventDirectory
    end
    
    methods
        function self = BinaryNetworkEventsReader(rec_path)
           self = self@NetworkEventsReader(rec_path);
           self.eventDirectory = fullfile(rec_path, 'events', 'MessageCenter');
        end
        
        function [timestamps, messages, info] = readMessages(self)
            info = struct();
            timestamps = readNPY(fullfile(self.eventDirectory, 'timestamps.npy'));
            texts = readNPY(fullfile(self.eventDirectory, 'text.npy'));
            messages = arrayfun(@(x) strrep(texts(x,:), char(0), ''), ...
                1:size(texts,1),...
                'UniformOutput', false);
        end
        
    end
end

