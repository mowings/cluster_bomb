module ClusterBomb
  module Logging
    DEFAULT_LOGFILENAME="logs/cb-#{Time.now().strftime('%m-%d-%Y')}.log"
    def self.log_init
      @logging_enabled=false
      @io=nil            
    end
    def self.log_enable(filename=DEFAULT_LOGFILENAME, filemode='a')
      filename ||= DEFAULT_LOGFILENAME
      filemode ||= 'a'
      log_dir = File.dirname(filename)
      `mkdir -p #{log_dir}` unless File.exists? log_dir
      @io = File.open(filename,filemode)
      @logging_enabled=true
    end
    def self.log_disable
      @io.close if @io
      @io=nil
      @logging_enabled=false
    end
    def self.log(msg)
      if @logging_enabled && @io
        @io.puts "#{Time.now().strftime('%m-%d-%Y %H:%M:%S')} - #{msg}"
        @io.flush
      end      
    end
    def self.puts(msg)      
      Kernel.puts msg
      self.log(msg)
    end
    def puts(msg)
      Logging.puts(msg)
    end
  end
end # ClusterBomb