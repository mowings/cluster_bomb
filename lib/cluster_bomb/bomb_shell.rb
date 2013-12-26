require 'rb-readline'
require 'cluster_bomb/history.rb'
require 'cluster_bomb/logging.rb'
require 'cluster_bomb/dispatcher.rb'
require 'cluster_bomb/shawties.rb'
# TODO: upgrade command history (persist, no repeats)
# TODO: settings
module ClusterBomb
  class BombShell  
    include History
    include Dispatcher
    include Shawties
    WELCOME="Welcome to the BombShell v 0.2.1, Cowboy\n:help -- quick help"
    def initialize(bomb)
      @bomb=bomb
      @bomb.interactive=true
      @stty_save = `stty -g`.chomp
      # Default settings
      @roles=[]
    end

    def loop
      puts WELCOME
      load_history @bomb.configuration.max_history
      init_autocomplete
      load_shawties!
      while true
        cmd = read_line
        break if cmd.nil?
        next if cmd.empty?
        # See if we're repezating a command
        if m = cmd.match(/^:(\d+)$/)
          cmd = Readline::HISTORY[m[1].to_i]
          next if cmd.nil?
          puts cmd
          Readline::HISTORY.pop
          Readline::HISTORY.push(cmd)
        end
        Logging.log(cmd)
        break if !process_input(cmd)
      end
      save_history
      puts "Exiting..."
      Logging.log_disable
    end

    def process_input(buf, reprocess=false)
      if buf.index(':')==0
        return false if !process_cmd(buf[1..-1])
      elsif buf.index('!')==0
        self.shell(buf)
      elsif buf.index('\\')==0 && !reprocess
        self.shawtie(buf)
      else
        begin
          run(buf)
        rescue Exception => e
          puts "Exception on run command: #{e.message}"
          puts e.backtrace
        end
      end
      return true      
    end
    
    def shawtie(cmd)
      if cmd.index(/^\\d /) == 0
        m = cmd.match(/^\\d +(\w+) +(\d+)/)
        if m
          sdef = Readline::HISTORY[m[2].to_i]
          if sdef
            puts "Defined short #{m[1]} :: #{sdef}"
            define_shawtie(m[1],sdef)
          end
        else
          m = cmd.match(/^\\d +(\w+) +(.+)$/)   
          if m.nil?
            m = cmd.match(/^\\d +(\w+)/)
            define_shawtie(m[1],nil)
            puts "Undefed short #{m[1]}"            
          else
            define_shawtie(m[1],m[2])
            puts "Defined short #{m[1]} - [#{m[2]}]"            
          end
        end
      elsif cmd.index(/^\\l$/) == 0
        shawties_list
      else
        m=cmd.match(/\\(\w+)/)
        if !m
          shawties_list
        else
          sdef = get_shawtie(m[1])
          if sdef
            puts "Run short: #{m[1]} :: #{sdef}"
            self.process_input(sdef)
          end
        end
      end
    end
    
    def read_line
      total_hosts = @bomb.hosts.length
      total_connected_hosts = 0
      @bomb.hosts.each {|h| total_connected_hosts +=1 if h.connected}
      begin
        sm = @bomb.sudo_mode ? '[SUDO] ' : ''
        line = Readline.readline("#{sm}(#{@bomb.username}) #{total_connected_hosts}/#{total_hosts}> ", true)
        if line =~ /^\s*$/ || Readline::HISTORY.to_a[-2] == line
            Readline::HISTORY.pop
        end        
      rescue Interrupt => e
        system('stty', @stty_save)
        return nil
      end
      return line if line.nil? # Ctrl-d
      line.strip!
      return line
    end
    
    def shell(cmd)
      cmdline=cmd[1..-1].strip
      puts `#{cmdline}`
    end
    
    def disconnect(p)
      @bomb.disconnect!
    end
    
    def history(p)
      Readline::HISTORY.to_a.each_with_index do |h,i|
        if p.nil?
          puts "   #{i}: #{h}"
        else
          puts "   #{i}: #{h}" if h.match(p)
        end
      end
    end
    def set(p)
      return if p.nil? || p=='shell'
      parts = p.split('=')
      if parts.length > 2
        puts "syntax: set <name>=<value"
      end
      k = parts[0].strip.to_sym
      unless @bomb.configuration.valid_key? k
        puts "Unknown configuration setting #{k}"
        return
      end
      if parts.length == 2
        @bomb.configuration.set(k,parts[1].strip)
      else
        @bomb.configuration.set(k,nil)
      end
    end
    def list(p)
      tg = {}
      @bomb.task_list.each do |t|
        tg[t.group] ||=[]
        tg[t.group] << t
      end
      puts "Available tasks (usually autocompletable):"
      tg.to_a.sort{|a,b|a[0]<=>b[0] }.each do |ta|
        puts "  #{ta[0]}"
        t_sorted = ta[1].sort {|a,b| a.name.to_s <=> b.name.to_s}
        t_sorted.each do |t|
          puts "    [#{t.name}] - #{t.description}"
        end
      end
    end
    def exec(p)
      return if p=='shell'
      task_name = p.split(' ').first unless p.nil?
      if task_name.nil? || !@bomb.valid_task?(task_name.to_sym)
        puts "Task missing or not found"
        self.list(nil)
        return
      end
      # @bomb.clear_env!
      roles=@roles
      opts = @bomb.get_task(task_name.to_sym).options || {}
      roles = opts[:roles] if opts[:roles] && opts[:sticky_roles]
      self.process_task_args(p)
      puts "NOTE Using sticky roles defined on task: #{roles.inspect}" if opts[:sticky_roles]
      @bomb.clear
      begin
        unless roles.empty?
          @bomb.exec(task_name.to_sym, {:roles=>roles}) 
        else
          @bomb.exec(task_name.to_sym) 
        end
      rescue Exception=>e
        puts "ERROR: #{e.message}"
        # p e.backtrace
      end
      # Cheesy -- clear out enviroment variables passed in with task to prevent accidental reuse
      @bomb.clear_env!
    end
    
    def process_task_args(p)
      arg_keys=[]
      args=p.split(' ')
      return [] if args.length <=1
      args[1..-1].each do |kv|
        pair = kv.split('=')
        if pair.length == 2
          k = pair[0].strip.to_sym
          arg_keys << k
          @bomb.set(k,pair[1].strip)
        end
      end
      arg_keys # Return these so we can clear them when the task is done
    end
    
    def use(p)
      unless p.nil?
        match = p.strip.match(/(.*?) +(.*)/)
        if match
          host_list = match[1]
          cmd=match[2].strip
        else
          host_list = p  
        end
        hosts=host_list.split(',').collect{|r|r.strip}
      else
        puts("Host list argument required")
        return
      end
      @roles=[] # Nil this out so future commands hit this host
      begin 
        self.run(cmd, hosts)
      rescue Exception => e
        puts "ERROR: #{e.message}"
      end      
    end
    
    def with(p)
      unless p.nil?
        match = p.strip.match(/(.*?) +(.*)/)
        if match
          role_list = match[1]
          cmd=match[2].strip
        else
          role_list = p  
        end
        roles=role_list.split(',').collect{|r|r.strip.to_sym}
        bad_role=roles.detect{|r| !@bomb.valid_role? r }        
      end      
      if p.nil? || bad_role
        p.nil? ? puts("Role argument required") : puts("Unknown role: #{bad_role}")
        puts "Available roles:"
        @bomb.role_list.each do |r|
          puts "    #{r[:name]} (#{r[:hostnames].length} hosts)"
        end     
        return
      end
      @roles=roles
      begin 
        @bomb.reconnect!(@roles)
        run cmd if cmd
      rescue Exception => e
        puts "ERROR: #{e.message}"
      end
    end
    
    def upload(p)
      source, dest = p.split(' ') unless p.nil?
      if source.nil? || dest.nil? || p.nil?
        puts "syntax: upload sourcepath destpath (no wildcards)"
        return true
      end
      begin 
        @bomb.upload(source, dest)
      rescue Exception => e
        puts "ERROR: #{e.message}"
      end
    end
    
    def help(p=nil)
      puts "Anything entered at the shell prompt will be executed on the current set of remote servers. "
      puts "Anything preceded by a : will be interpreted as a cluster_bomb command"
      puts "Available cluster_bomb commands:"
      Dispatcher::COMMANDS.each do |cr|
        puts "    #{cr[:name]} - #{cr[:description]}"
      end
      puts ":<nnn> will re-execute a command from the history"
      puts "Use the bang (!) to execute something in the local shell. ex !ls -la"
    end
    
    def host_list(p)
      Logging.puts "Roles in use: #{@roles.join(',')}"
      hl = @bomb.hosts.collect {|h| h.name}
      Logging.puts "#{hl.length} active hosts"
      Logging.puts "#{hl.join(',')}"
    end
    
    def switch(p)
      return if p.empty?
      @bomb.switch_user(p)
    end
    def sudo(p)
      @bomb.sudo_mode = !@bomb.sudo_mode
    end
    def run(cmd, host_list=nil)
      @bomb.clear
      opts={}
      opts[:hosts]=host_list if host_list
      opts[:sudo] = true if @sudo_mode
      @bomb.run(cmd, opts) do |r|
        if r.exception
          puts "#{r.name} => EXCEPTION: #{r.exception.message}" 
        else
          output = r.console
          ll = output.length + r.name.length + 3
          if ll > @bomb.configuration.screen_width.to_i || output.index('\n')
            Logging.puts "=== #{r.name} ==="
            Logging.puts output
          else
            Logging.puts "#{r.name} => #{output}" 
          end
        end
      end
    end  
  end # Bombshell
end # Module

