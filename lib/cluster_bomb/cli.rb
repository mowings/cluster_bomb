require 'cluster_bomb/bomb'
require 'cluster_bomb/logging'
require 'getoptlong'
class Cli
  include ClusterBomb::Bomb
  def initialize
    @execution_environment={}
    super
    self.load File.join(File.dirname(__FILE__),'stdtasks.rb')
    if File.exists? 'Bombfile'
      self.load 'Bombfile'
    else
      puts "WARNING: no Bombfile in current directory"
    end
  end
  def process_args
    if ARGV.length < 1
      puts "syntax: cb <task> [options]"
      puts "available tasks: "
      @tasks.each do |n,t|
        puts "   #{t.name} - #{t.description}"
      end
      exit
    end
    @task=ARGV[0].to_sym  
    
    # Get program opts
    opts = GetoptLong.new(
      [ '--logfile', '-l', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--logmode', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--user', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--nolog', GetoptLong::NO_ARGUMENT ]      
    )
    logfile=nil
    logmode=nil
    nolog=false
    @user=nil
    opts.each do |opt, arg|
      case opt
      when '--logfile'
        logfile=arg
      when '--logmode'
        raise "valid log modes are a or w" unless ['a','w'].include? arg
        logmode=arg
      when '--nolog'
        nolog=true
      when '--user'
        @user=arg        
      end      
    end    
    if logfile && !logmode
      logmode='a'
    end
    unless nolog
      ClusterBomb::Logging.log_init
      ClusterBomb::Logging.log_enable(logfile,logmode)
    end
    # Set up environment, with special attention to roles
    ARGV[1..-1].each do |arg|
      pair = arg.split('=')
      if pair.length == 2
        k = pair[0].strip.to_sym
        if k == :roles
          list=pair[1].split(',').collect{|r|r.strip.to_sym}
          @execution_environment[:roles]=list
        elsif k == :hosts
          list=pair[1].split(',').collect{|r|r.strip}
          @execution_environment[:hosts]=list
        else
          self.set(k,pair[1].strip)
        end
      end
    end  
  end
  def main
    process_args
    switch_user(@user) if @user   
    exec @task, {:roles=>@execution_environment[:roles], :hosts=>@execution_environment[:hosts]}
  end
end

Cli.new.main
