classdef (Abstract) NetworkEventsReader
    
    properties
        rec_path
    end
    
    
    methods
        function obj = NetworkEventsReader(rec_path)
            %NETWORKEVENTSREADER Construct an instance of this class
            %   Detailed explanation goes here
            obj.rec_path = rec_path;
        end
        
    end
    
    
    methods(Abstract)
        [timestamp, text, info] = readMessages(self)
    end
    
    
    methods(Static)
        function events_reader = create_events_reader(rec)
            events_reader = struct();
            if strcmp(rec.format, 'Binary')
                events_reader = BinaryNetworkEventsReader(rec.directory);
            end
            if strcmp(rec.format, 'OpenEphys')
                events_reader = OpenEphysNetworkEventsReader(rec.directory, rec.oeVersion);
            end
        end
    end
end

