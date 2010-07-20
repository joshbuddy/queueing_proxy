require 'thor'

module QueueingProxy
  class CLI < Thor
    
    def initialize
      super
    end
    
    default_task :start
    
    desc "start", "Start a proxy"
    def start(config = '/etc/queueing_proxy.yml')
      
    end
  end
end