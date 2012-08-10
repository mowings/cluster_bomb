require 'readline'
module ClusterBomb
  module History
    HISTORY_FILE=File.join(Configuration::HOME,'history')
    
    def save_history
      save_history =  Readline::HISTORY.to_a.dup
      start=0
      start = save_history.length - @max_history if save_history.length > @max_history
      
      File.open(HISTORY_FILE, "w") do |f|
        save_history[start..-1].each {|l| f.puts(l)}
      end
    end
    
    def load_history(max_history=500)
      @max_history = max_history      
      return unless File.exists? HISTORY_FILE
      File.open(HISTORY_FILE, "r") do |f|
        c=0
        while line = f.gets
          Readline::HISTORY.push(line.strip)
          if c==0 && libedit? # libedit work-around 
            Readline::HISTORY.push(line.strip)
          end
          c+=1
        end
      end
    end
    # Cheesy check to see if libedit is in use -- will affect history
    def libedit?
      libedit = false
      # If NotImplemented then this might be libedit
      begin
        Readline.emacs_editing_mode
      rescue NotImplementedError
        libedit = true
      end
      libedit
    end    
  end # History
end # ClusterBomb