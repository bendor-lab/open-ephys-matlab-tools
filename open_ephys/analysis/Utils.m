classdef Utils
    %UTILS Contains helper functions 
    %   Detailed explanation goes here
    
    properties (Constant)
        DEBUG = 0;
        INFO = 1;
        WARN = 2;
    end
    
    properties
        loglevel;
    end
    
    methods(Access = private)
        function obj = Utils(loglevel)
            obj.loglevel = loglevel;
        end
    end
    
   
    methods(Static)
        function singleton = logger(varargin)
             persistent localObj;
             persistent loglevel;
             
             if isempty(loglevel)
                 loglevel = Utils.INFO;
             end
             
             changed_loglevel = false;
             if ~isempty(varargin)
                 loglevel = varargin{1};
                 changed_loglevel = true;
             end 
             
             if isempty(localObj) || changed_loglevel
                  localObj = Utils(loglevel);
             end
             singleton = localObj;
        end

        function log(varargin)
            Utils.logger().info(varargin{:});
        end
    end
    
    methods
        
        function msg(self, loglevel, varargin)
            if self.loglevel > loglevel
                return
            end
            
            switch loglevel
            case 0
               loglevelstr = "DEBUG";
            case 1
                loglevelstr = 'INFO';
            case 2
                loglevelstr = 'WARN';
            end
            
            fprintf("[%s] ", loglevelstr);
            for i = 1:length(varargin)
                fprintf('%s ', varargin{i});
            end
            fprintf("\n");
        end
        
        function debug(self, varargin)
            self.msg(self.DEBUG, varargin{:});
        end
        
        function info(self, varargin)
            self.msg(self.INFO, varargin{:});
        end
        
        function warn(self, varargin)
            self.msg(self.WARN, varargin{:});
        end
        
        function latest_recording = getLatestRecording(dataPath)
            %getLatestRecording Gets the latest recording in the basePath
            %   Returns the path to the latest recording 
            files = dir(dataPath);
            files = files(~cellfun(@(x) strcmp(x(1), '.'), {files.name}));
            if isempty(files)
                error('No files found in the data path');
            end
            [~,idx] = sort([files.datenum]);
            files = files(idx);
            latest_recording = files(end);
        end
    end
end

