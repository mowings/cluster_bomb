require 'cluster_bomb/configuration.rb'
module ClusterBomb
  module Shawties
    SHAWTIES_FILE_NAME=File.join(Configuration::HOME,'shawties')
  
    def define_shawtie(name, command)
      @shawties ||={}
      unless command.nil?
        @shawties[name]=command
      else
        @shawties.delete name
      end
      save_shawties
    end
    def get_shawtie(name)
      @shawties[name]
    end
    def load_shawties!
      @shawties ||={}
      Configuration.check_dir
      begin
        buf = File.read(SHAWTIES_FILE_NAME)
      rescue
        `touch #{SHAWTIES_FILE_NAME}`
        buf = File.read(SHAWTIES_FILE_NAME)
      end
      unless buf.empty?
        @shawties = YAML.load(buf)
      end    
    end
    def save_shawties
      Configuration::check_dir    
      File.open(SHAWTIES_FILE_NAME,"w") {|f| f.write(@shawties.to_yaml)}    
    end
    def shawtie_names
      (@shawties.keys + ['d','l']).sort
    end
    def shawties_list
      keys = @shawties.keys.sort
      puts "Available shorts:"
      keys.each do |k|
        puts "#{k}\n    #{@shawties[k]}"
      end
    end
  end
end