module Roles
  def role(*args, &task)
    if args.length==2
      name=args[0]
      servers=args[1]
      ra=servers.split(',')       
    elsif args.length==1 && task != nil
      name=args[0]
      ra = yield(task)
    else
      raise "role command takes a role name and a list of hosts OR a block yielding a list of hosts"
    end    
    set_role(name, ra)
  end

  # Clear out role
  def clear_role(name)
    rl = @roles[name.to_sym]
    @roles[name.to_sym] =[] if rl
  end
  
  # produce a list of servers from role list
  # empty or nil role list implies all roles
  def servers(role_list)
    @roles ||={}
    ra=[]
    if role_list && !role_list.empty?
      if role_list.class==String
        ra = role_list.split(',').collect{|r| r.to_sym}
      else
        ra=role_list
      end
    end
    server_list=[]
    ra.each do |role|
      raise "Role #{role} not found" unless @roles[role]
      server_list += @roles[role]
    end
    server_list
  end
  
  def valid_role?(name)
    @roles[name.to_sym]
  end
  
  private
  def set_role(name, hosts)
    @roles ||={}
    @roles[name] ||=[]
    # puts "ROLE: #{name} #{hosts.inspect}"
    hosts.each do |host|
      host.strip!
      @roles[name] <<  host unless @roles[name].include? host
    end
  end
end
