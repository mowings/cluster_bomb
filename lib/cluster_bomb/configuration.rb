require 'yaml'
module ClusterBomb
  module Configuration
    HOME=File.join(ENV["HOME"], ".cluster_bomb")
    CFG_FILE_NAME = File.join(HOME,"config.yaml")
    KEYS={
      :screen_width=>{:default=>120},
      :logging=>{:default=>true},
      :logfile=>{:default=>"logs/cb-#{Time.now().strftime('%m-%d-%Y')}.log}"},
      :max_run_time=>{:default=>nil},
      :max_history=>{:default=>1000},
      :username=>{:default=>ENV["USER"]}
    }
    def initialize
      @configuration={}
      @ssh_options_for_user={} # By user
      Configuration.check_dir
    end
    # Check for home dir, and create it if it doesn't exist
    def self.check_dir
      `mkdir #{HOME}` unless File.exists? HOME
    end
    # Save it out
    def save
      Configuration.check_dir
      File.open(CFG_FILE_NAME,"w") {|f| f.write(@configuration.to_yaml)}
    end
    def configuration
      @configuration
    end  
    def set(key, val)
      k = key.class==Symbol ? key : key.to_sym
      # TODO: VALIDATION
      raise "Invalid setting [#{key}]" unless KEYS[k]
      @configuration[k] = val
    end
    def get(key)
      k = key.class==Symbol ? key : key.to_sym
      raise "Config.get ==> Uknown key #{k}" unless (@configuration.has_key? k or KEYS.has_key? k)
      ret = @configuration[k] || KEYS[k][:default]
      ret
    end
    def keys
      KEYS.keys
    end
    def valid_key?(k)
      KEYS.has_key? k.to_sym
    end
    def load!
      Configuration.check_dir
      begin
        buf = File.read(CFG_FILE_NAME)
      rescue
        `touch #{CFG_FILE_NAME}`
        buf = File.read(CFG_FILE_NAME)
      end
      unless buf.empty?
        @configuration = YAML.load(buf)
      end
    end
    def ssh_options(username)
      if has_ssh_options? username
        if !@ssh_options_for_user[username]
          @ssh_options_for_user[username] = YAML.load(File.read(File.join(HOME,"ssh_#{username}.yml")))
        end
      end
      @ssh_options_for_user[username] || {}
    end
    def has_ssh_options?(username)
      return true if  @ssh_options_for_user[username] 
      File.exists? File.join(HOME,"ssh_#{username}.yml")
    end    
    def method_missing(symbol, *args)
      str = symbol.to_s
      if str.match(/=$/)
        self.set(str.sub('=', ''),args[0])
      else
        self.get(str)
      end
    end
  end
end

