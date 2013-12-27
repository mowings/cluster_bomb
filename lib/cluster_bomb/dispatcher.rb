require 'readline'
module ClusterBomb
  module Dispatcher
    COMMANDS = [
      {:rex=> /^qu.*/, :method=>:quit, :name=>':quit', :description=>'Quit. Ctrl-d also works'},
      {:rex=> /^wi.*/, :method=>:with, :name=>':with', :description=>'Set roles in use. This will determine the remote host set. ex: :with apache,database'},
      {:rex=> /^use.*/, :method=>:use, :name=>':use', :description=>'Run a command against a host or hosts. Ex. use foo.bar.com,x.y.com ls -la'},
      {:rex=> /^ex.*/, :method=>:exec, :name=>':exec', :description=>'Execute a configured task task'},
      {:rex=> /^li.*/, :method=>:list, :name=>':list', :description=>'List available tasks to run'},
      {:rex=> /^his.*/, :method=>:history, :name=>':history', :description=>'Command history. Can be followed by a filter regexp'},      
      {:rex=> /^disc.*/, :method=>:disconnect, :name=>':disconnect', :description=>'Disconnect all cached connections.'},
      {:rex=> /^up.*/, :method=>:upload, :name=>':upload', :description=>'Upload one or more files to servers. Supports wildcards and autocomplete for source filename. ex: upload sourcepath destpath'},          
      {:rex=> /^he.*/, :method=>:help, :name=>':help', :description=>'Quick help.'},    
      {:rex=> /^se.*/, :method=>:set, :name=>':set', :description=>'Set a variable'},          
      {:rex=> /^ho.*/, :method=>:host_list, :name=>':hosts', :description=>'List current hosts'},
      {:rex=> /^switch/, :method=>:switch, :name=>':switch', :description=>'Switch user'},
      {:rex=> /^sudo/, :method=>:sudo, :name=>':sudo', :description=>'Sudo mode on/off'}      
      ]
    COMMAND_AUTOCOMPLETE = COMMANDS.collect{|c|c[:name]} + ['with','use']
    def init_autocomplete
      Readline.completion_proc=proc {|s| self.dispatcher_completion_proc(s)}
      Readline.completer_word_break_characters = 7.chr
      Readline.completion_case_fold = true
      Readline.completion_append_character = ''
    end
    def process_cmd(line)
       # cmd = cmd.strip.downcase
       m=line.match(/([^ ]+) *?(.*)/)
       return true unless m
       cmd = m[1]
       params = m[2] || ""
       params.strip!
       return false if cmd =~ /^q.*/
       found=false
       COMMANDS.each do |cr|
         if cmd =~ cr[:rex]
           # p = cmd_param(cmd)
           self.send cr[:method], params
           found=true
           break
         end
       end
       if !found
         puts "Available commands:"
         COMMANDS.each do |cr|
           puts "    #{cr[:name]} - #{cr[:description]}"
         end
       end
       return true
    end

    def dispatcher_completion_proc(s)      
      # No line buffer for mac, so no way to get command context
      # Very lame with libedit. Will not return candidates, and 
      # We cannot get the current line so we can do context-based 
      # edits
      ret=[]
      tokens = s.split(' ')
      if s =~ /^:?\w.* $/
        tokens << ''
      elsif s =~ /^\\\w*/
        tokens << ''
      end
      # Initial command only
      if tokens.length  <= 1 && tokens[0] != '\\'
        ret = COMMAND_AUTOCOMPLETE.grep(/^#{s}/)
      else
        if tokens[0]=~/:?with.*/
          ret = secondary_completion_proc(tokens, @bomb.role_list.collect{|r| r[:name].to_s})
        elsif tokens[0]=~/:?use.*/ && @bomb.valid_role?(:all)
          ret = secondary_completion_proc(tokens, @bomb.servers([:all]))
        elsif tokens[0]=~/:exec.*/
          ret = secondary_completion_proc(tokens, @bomb.task_list.collect{|t| t.name.to_s})
        elsif tokens[0]=~/:upload.*/
          ret = dir_completion_proc(tokens)
        elsif tokens[0]=~/:set.*/
          ret = secondary_completion_proc(tokens, @bomb.configuration.keys)
        elsif tokens[0]=~/^\\/
          ret = shawtie_names.grep(/#{tokens[0][1..-1]}/)
          ret = ret.collect {|r|"\\#{r}"}
        end

      end
      ret
    end

    def dir_completion_proc(tokens)
      choices=dir_list(tokens[1])
      secondary_completion_proc(tokens,choices)
    end

    def dir_list(token)
      m = token.match(/(.*\/).*$/)
      if m && m[1]
        ret=Dir.glob("#{m[1]}*")
      else
        ret=Dir.glob("*")
      end      
      ret.collect {|p| (File.directory? p) ? "#{p}/" : "#{p}"}
    end

    def secondary_completion_proc(tokens, choices)
      if tokens[1]==''
        choices.collect {|c| "#{tokens[0]} #{c}"}
      else
        tokens[1] = tokens[1].gsub(/\./,'\.')
        choices.grep(/^#{tokens[1]}/).collect {|c| "#{tokens[0]} #{c}"}
      end
    end
  end # dispatcher
end # clusterbomb
