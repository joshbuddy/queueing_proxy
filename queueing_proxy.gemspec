# -*- encoding: utf-8 -*-

require File.join(File.dirname(__FILE__), 'lib', 'queueing_proxy', 'version')

Gem::Specification.new do |s|
  s.name = 'queueing_proxy'
  s.version = QueueingProxy::VERSION
  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Joshua Hull"]
  s.date = '2010-07-21'
  s.summary = "Queueing proxy backed by EM/Beanstalk for a very weird purpose."
  s.description = "Queueing proxy backed by EM/Beanstalk for a very weird purpose."
  s.email = %q{joshbuddy@gmail.com}
  s.extra_rdoc_files = []
  s.files = `git ls-files`.split("\n")
  s.homepage = %q{http://github.com/joshbuddy/queueing_proxy}
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.7}
  s.test_files = `git ls-files`.split("\n").select{|f| f =~ /^spec/}
  s.rubyforge_project = 'queueing_proxy'

  # dependencies
  s.add_runtime_dependency 'eventmachine'
  s.add_runtime_dependency 'em-jack'
  s.add_runtime_dependency 'thin'
  s.add_runtime_dependency 'json'
  s.add_runtime_dependency 'thor', '>= 0.13.8'
  s.add_runtime_dependency 'http_parser.rb'

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end

