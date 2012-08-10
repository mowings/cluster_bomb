# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{cluster_bomb}
  s.version = "0.2.6"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["hayzeus"]
  s.date = %q{2011-11-10}
  s.default_executable = %q{cb}
  s.description = %q{Capistrano-like multi-host shell and task execution}
  s.email = %q{mikey@swampgas.com}
  s.executables = ["cb"]
  s.files = ["bin/cb", "lib/cluster_bomb/actest.rb", "lib/cluster_bomb/bomb.rb", "lib/cluster_bomb/bomb_shell.rb", "lib/cluster_bomb/cli.rb", "lib/cluster_bomb/cluster.rb", "lib/cluster_bomb/configuration.rb", "lib/cluster_bomb/dispatcher.rb", "lib/cluster_bomb/history.rb", "lib/cluster_bomb/logging.rb", "lib/cluster_bomb/roles.rb", "lib/cluster_bomb/shawties.rb", "lib/cluster_bomb/stdtasks.rb"]
  s.homepage = %q{http://www.swampgas.com}
  s.require_paths = ["lib"]
  s.required_ruby_version = Gem::Requirement.new(">= 1.8.6")
  s.rubygems_version = %q{1.3.7}
  s.summary = %q{Do stuff across clusters}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<net-ssh>, [">= 2.0.0"])
      s.add_runtime_dependency(%q<net-scp>, [">= 1.0.0"])
      s.add_runtime_dependency(%q<net-sftp>, [">= 2.0.0"])
    else
      s.add_dependency(%q<net-ssh>, [">= 2.0.0"])
      s.add_dependency(%q<net-scp>, [">= 1.0.0"])
      s.add_dependency(%q<net-sftp>, [">= 2.0.0"])
    end
  else
    s.add_dependency(%q<net-ssh>, [">= 2.0.0"])
    s.add_dependency(%q<net-scp>, [">= 1.0.0"])
    s.add_dependency(%q<net-sftp>, [">= 2.0.0"])
  end
end
