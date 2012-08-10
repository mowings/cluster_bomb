require 'cluster_bomb/cluster.rb'
require 'cluster_bomb/roles.rb'
require 'cluster_bomb/configuration.rb'
require 'cluster_bomb/logging.rb'

# TODO: persistent configuration
# TODO: logging
module ClusterBomb
  # Task Runner module
  # Loads task files and runs tasks
  # All tasks run within the context of the class implementing this module
  module Bomb
    include Roles
    include Logging
    class Task
      attr_accessor :proc, :roles, :description, :sudo
      attr_reader   :group, :name, :filename
      attr_reader   :options 
      def initialize(name, group, filename=nil, filetime=nil, opts={})
        @name=name
        self.roles=[]
        @filename=filename
        @group = group
        @filetime=filetime  
        @options=opts      
        @sudo = opts[:sudo]
      end
      def updated?
        return false if !self.filename
        File.stat(self.filename).mtime  != @filetime
      end
    end
    
    class Config
      include Configuration
    end

    attr_accessor :env, :auto_reload, :configuration,:interactive, :username, :sudo_mode
    def initialize
      @sudo_mode = false
      @tasks||={}
      @cluster||=nil
      self.env={}   
      @reloading=false
      @current_load_file=nil
      @current_load_file_time=nil
      self.auto_reload=true
      @configuration = Config.new
      @configuration.load!
      @username = @configuration.username
      raise "Unable to get a default user name. Exiting..." unless @username
      @interactive=false
      super
    end

    def interactive?
      @interactive
    end
    
    def group(str)
      @current_group=str
    end
    
    def desc(str)
      @current_desription=str
    end
  
    def task(name, options={}, &task)
      t = Task.new(name, @current_group, @current_load_file,@current_load_file_time, options )
      raise "task #{t.name} is already defined" if @tasks[t.name] && !@reloading
      @tasks[t.name]=t
      t.proc = task
      t.roles=options[:roles]
      t.description=@current_desription
      
      @current_description=''
    end
    def role_list
      ret=[]
      @roles.each do |k,v|
        ret << {:name=>k, :hostnames=>v}
      end
      ret
    end
    def load_str(str)
      begin
        self.instance_eval(str)
      rescue Exception => e
        puts "Exception while loading: #{@current_load_file}"
        raise e
      end
      ssh_options = @configuration.ssh_options(username)
      @cluster = Cluster.new(username,ssh_options) unless @cluster
      @current_load_file=nil
      @current_load_file_time=nil           
    end    

    def reload(fn)
      @reloading=true
      load(fn)
      @reloading=false
    end
    
    def load(fn)
      @current_group=fn.split('/').last
      s = File.read(fn)
      @current_load_file=fn
      @current_load_file_time=File.stat(fn).mtime
      self.load_str(s)
    end
      
    def set(name, value=nil)
      self.env[name.to_sym]=value
      code=<<-EODEF
      def #{name}
        self.env[:#{name}]
      end
      def #{name}=(rhs)
        self.env[:#{name}]=rhs
      end      
      EODEF
      self.instance_eval(code)
    end
    
    def ensure_var(name, value=nil)
      return if env.has_key? name.to_sym
      set(name, value)
    end
    
    def exists?(attrname)
      env.has_key? attrname.to_sym
    end
    
    def clear_env!
      env.each_key do |k|
        self.instance_eval("undef #{k.to_s}; undef #{k.to_s}=")
      end
      self.env={}
    end
    
    def switch_user(user)
      if @configuration.has_ssh_options? user
        ssh_options = @configuration.ssh_options(user)
        @username = user
        @cluster.credentials(@username, ssh_options)
        @cluster.disconnect!
      else
        raise "No credentials for user #{username}"
      end
    end
    
    def exec(name, options={}) 
      sudo_save = @sudo_mode
      # @cluster.reset!
      server_list=server_list_from_options(options)
      t = @tasks[name]
      raise "TASK NOT FOUND: #{name}" unless t
      @sudo_mode = true if t.sudo # Turn it on if sudo is true
      raise "Task not found: #{name}" if t.nil?      
      if self.auto_reload && t.updated?
        puts "Reloading #{t.filename}"
        reload(t.filename)
        t = @tasks[name]
      end
      raise "Task not found: #{name}" if t.nil?
      server_list = self.servers(t.roles) if server_list.empty?
      # puts "CONNECTED: #{@cluster.connected?}"
      @cluster.connect!(server_list) unless @cluster.connected? && (!options[:roles] && !options[:hosts])
      raise "Task #{name} not found" unless t
      t.proc.call
      @sudo_mode = sudo_save
    end  
  
    def download(remote, local, options={}, &task)
      @cluster.download(remote, local, options={}, &task)
    end
    
    def upload(local, remote, options={}, &task)
      files=[]
      
      server_list=[]
      if options[:roles]
        server_list = self.servers(options[:roles])
      elsif options[:hosts]
        server_list=options[:hosts]
      end
      if !server_list.empty?
        @cluster.reset!
        @cluster.connect!(server_list)
      end
            
      if local.index('*')
        files=Dir.glob(local)
      else
        files << local
      end
      files.each do |f|
        next if File.stat(f).directory?
        puts "Uploading: #{f}"
        @cluster.upload(f, remote, options, &task)
      end
    end
        
    def run(command, options={}, &task)
      server_list=server_list_from_options(options)
      if !server_list.empty?
        @cluster.reset!
        @cluster.connect!(server_list)
      end
      options[:sudo] =  @sudo_mode unless options.has_key? :sudo
      # use max_run_time environment variable if not passed in by caller
      options[:max_run_time] = self.configuration.max_run_time unless options[:max_run_time]
      @cluster.run(command, options, &task)
    end
    
    def server_list_from_options(options)
      server_list=[]
      if options[:roles]
        server_list = self.servers(options[:roles])
      elsif options[:hosts]
        server_list=options[:hosts]
      end
      server_list
    end
    
    # primarily for shell use to change roles
    def reconnect!(roles)
      @cluster.reset!
      @cluster.connect!(self.servers(roles))
    end
    
    def valid_task?(name)
      @tasks[name] ? true : false
    end
    
    def get_task(name)
      @tasks[name]      
    end
    
    def disconnect!
      @cluster.disconnect!
    end
    
    def task_list
      ret=[]
      @tasks.each{|k,v| ret << v }
      ret
    end
    def clear
      @cluster.clear!
    end  
    def hosts
      @cluster.hosts
    end
  end
end
