require 'readline'

class Test
  @stty_save = `stty -g`.chomp
  def run()
    Readline.completion_proc=proc {|s| self.main_completion_proc(s)}
    Readline.completer_word_break_characters = 7.chr  
    Readline.completion_case_fold = true
    Readline.completion_append_character = ''
    while(true) do
      line = read_line
      break if !line
    end
  end
  def read_line
    begin
      line = Readline.readline("> ", true)
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
   
  def main_completion_proc(s)      
    # No line buffer for mac, so no way to get command context
    # Very lame with libedit. Will not return candidates, and 
    # We cannot get the current line so we can do context-based 
    # edits
    cmds = ['foo','bar','plushy','food','bear','plum','ls','los','lsu']
    ret=[]
    tokens = s.split(' ')
    if s =~ /^\w.* $/
      tokens << ''
    end
    # Initial command only
    if tokens.length <= 1
      ret = cmds.grep(/^#{s}/)
    else
      if tokens[0]=='ls'
        ret = foo_completion_proc(tokens)
      end
    end
    ret
  end  
  def foo_completion_proc(tokens)
    files=Dir.glob('*')
    if tokens[1]==''
      candidates=files
      candidates
    else
      candidates = files.grep(/^#{tokens[1]}/)
      candidates.collect {|c| "#{tokens[0]} #{c}"}
    end
  end
end

Test.new.run