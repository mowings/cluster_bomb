require 'net/ssh'
require 'net/scp'
require 'net/sftp'
require 'cluster_bomb/logging'
require 'shellwords'

# Represents a cluster of hosts over which to operate
module ClusterBomb
  class Cluster
    include Logging
    class Host
      attr_accessor :name
      attr_accessor :buffer_stderr, :buffer_stdout, :buffer_console
      attr_accessor :exception
      attr_accessor :data
      attr_accessor :connected
      attr_accessor :connect_failed
      
      def initialize(name, cluster)
        self.name=name
        self.clear!
        self.data={}
        self.connected=false
        self.connect_failed=false
        @cluster = cluster
      end
      def nickname
        @cluster.nicknames[self.name]
      end
      def stdout
        buffer_stdout.join('')
      end
      def stderr
        buffer_stderr.join('')
      end    
      def console
        buffer_console.join('')
      end
      def clear!
        self.buffer_stderr=[]
        self.buffer_stdout=[]
        self.buffer_console=[]
        self.exception=nil
      end
      # match stdout, returning arrays
      def match(rex, default=nil)
        m = rex.match self.stdout
        if m
          if m.length > 2
            m[1..-1]
          else
            m[1]
          end
        else
          default
        end
      end
    end
      
    attr_accessor :hosts, :nicknames
    def initialize(user, options={})
      @user_name ||= user
      @connections=[]
      @hosts=[]
      @ssh_options=options
      @connection_mutex = Mutex.new
      @connected=false
      @connection_cache={}
      @nicknames={}
      @start_time =nil
      @max_time=nil
    end
    
    def connect!(host_list)
      return if host_list.empty?
      @hosts=[]
      # Build up results rray
      host_list.each {|hostname| @hosts << Host.new(hostname, self)}
    
      # Connect. Build up connections array
      # Seems like there would be an async call to do this -- but it looks like
      # Not -- so we resort to threads
      puts "Connecting to #{hosts.length} hosts"
      ensure_connected!
      @connected=true    
      puts "Connected to #{hosts.length} hosts"
    end
    
    # Credentials to be used for next connection attempt. 
    def credentials(user, ssh_opts)
       @ssh_options=ssh_opts
       @user_name = user
    end
    
    # Be sure all hosts are connected that have not previously failed to connect
    def ensure_connected!      
      if @ssh_options[:timeout]
        total_timeout = @ssh_options[:timeout] * 2
      else
        total_timeout = 30
      end
      # puts "Total timeout: #{total_timeout}"
      @connections=[]
      hosts_to_connect = @hosts.inject(0) {|sum,h| sum += (h.connect_failed ? 0:1)}
      # puts "#{hosts_to_connect} to connect"
      @hosts.each do |host|
        if @connection_cache[host.name] || host.connected
          @connection_mutex.synchronize { @connections << {:connection=>@connection_cache[host.name], :host=>host} }
          host.connected=true
        elsif !host.connect_failed
          Thread.new {
            begin
              #puts "Connecting #{host.name}"
              name, port = host.name.split(':')
              port ||= "22"
              c = Net::SSH.start(name, @user_name, @ssh_options.merge({:port=>port.to_i}))
              @connection_cache[host.name] = c
              @connection_mutex.synchronize { @connections << {:connection=>c, :host=>host} }
              host.connected=true
              #puts "Connected #{host.name}"
            rescue Exception => e
              host.connect_failed = true
              host.connected=false
              error "Unable to connect to #{host.name}\n#{e.message}"
              @connection_mutex.synchronize {@connections << {:connection=>nil, :host=>host} }
              host.exception=e
            end        
          }
        end
      end
      s = Time.now
      loop do
        l=0
        @connection_mutex.synchronize { l = @connections.length }
        break if l == hosts_to_connect
        sleep(0.1)
        if Time.now - s > total_timeout
          puts "Warning -- total connection time expired"
          puts "Failed to connect:"
          hosts.each do |h|
            unless h.connected
              puts "    #{h.name}" 
              h.connect_failed=true
              # TODO: Need to handle this situations much better. Attempt to kill thread and/or mark connection in cache as unreachable
            end
          end
          break
        end
      end      
    end
    
    def set_run_timer(options)
      if options[:max_run_time]
        @max_time = options[:max_run_time].to_i
        @start_time = Time.now
      else
        @max_time = nil
        @start_time = nil
      end
    end
    
    def download(remote, local, options={}, &task)
      ensure_connected!
      set_run_timer(options)
      @connections.each do |c|
        next if c[:connection].nil?
        c[:completed]=false      
        c[:connection].scp.download(remote,local)
      end
      event_loop(task)
      @hosts      
    end
    
    def upload(local, remote, options={}, &task)
      opts={:chunk_size=>16384}.merge(options)
      ensure_connected!
      set_run_timer(options)      
      @connections.each do |c|
        next if c[:connection].nil?
        c[:completed]=false      
        c[:connection].scp.upload(local,remote, opts)
      end
      event_loop(task)
      @hosts      
    end
       
    # Build sudo-fied command. Really only works for bash afaik   
    def mksudo(command)
      "sudo /bin/bash -c #{Shellwords.escape(command)}"
    end 
    
    def run(command, options={}, &task)
      # Execute
      ensure_connected!
      if options[:sudo]
        command=mksudo(command)
      end      
      # puts "Command: #{command}"
      set_run_timer(options)      
      @connections.each do |c|
        next if c[:connection].nil?
        c[:completed]=false
        c[:host].clear! if options[:echo] # Clear out before starting
        c[:connection].exec command do |ch, stream, data|
          c[:host].buffer_console << data
          if stream == :stderr
            c[:host].buffer_stderr << data
          else
            "#{c[:host].name}=> #{data}"
            c[:host].buffer_stdout << data
          end
          puts "#{c[:host].name}::#{data}" if options[:debug]
          print "." if options[:dotty]
        end
      end
      event_loop(task, options)
      @hosts
    end
    
    def event_loop(task, options={})
      # Event loop
      condition = Proc.new { |s| s.busy?(true) }
      # Count up non-nil connections
      count = 0
      @connections.each {|c| count +=1 if c[:connection]}
      loop do
        @connections.each do |conn|
          next if conn[:connection].nil? || conn[:completed]
          ex=nil
          busy=true
          begin
            busy = conn[:connection].process(0.1, &condition)
            if @start_time && Time.now - @start_time > @max_time
              # Soft exception here -- stay connected
              conn[:host].exception = Exception.new("Execution time exceeded: #{@max_time}")
              puts "Execution time exceeded: #{@max_time}"
              busy=false
            end
          rescue Exception => e
            # As far as I can tell, if we ever get here, the session is fucked. 
            # Close out the connection and indicate that we want to be reconnected later
            # In general, its upload/download exceptions that get us here. Even bad filenames can do the trick
            puts "#{e.message}"
            host = conn[:host]
            @connection_cache[host.name].close
            @connection_cache[host.name]=nil
            host.connected=false # disconnect
            busy=false
          end
          if !busy
            conn[:completed] = true
            count -=1 
            h = conn[:host]
            if task
              task.call(h)
            elsif options[:echo]
              puts "#{h.name}\n#{h.console}\n"
            end
          end
        end
        break if count <=0
      end
      # Reset these
      @start_time=nil
      @max_time = nil      
    end
  
    def connected?
      @connected
    end
  
    def disconnect!
      if @connections
        @connection_cache.each do |k, conn|
          begin
            conn.close
          rescue Exception=>e
            puts "Non-fatal EXCEPTION closing connection: #{e.message}"
          end
        end
      end
      @hosts.each {|h| h.connected=false}
      @connections=[]
      @connection_cache={}
      @connected=false
      @hosts=[]
    end
    
    def reset!
      @connections=[]
      @connected=false  
    end
  
    def clear!
      @hosts.each {|h| h.clear!}
    end
    def error(msg)
      puts msg
    end
  end
end
