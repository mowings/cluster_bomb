group "Built in tasks"
desc "Quick help"
task :help do
  puts <<-EOHELP 
syntax: cb <task> [options]
options:
    cp status roles=<role list> ex. roles=database,webservers
  EOHELP
end

desc "BombShell -- the cluster bomb shell interface."
task :shell do
  require 'cluster_bomb/bomb_shell'
  b = ClusterBomb::BombShell.new(self)
  b.loop  
end