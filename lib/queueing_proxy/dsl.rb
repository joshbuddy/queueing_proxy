require 'logger'

module QueueingProxy
  class DSL
    def initialize(&block)
      @dispatcher_count = 1
      @logger = Logger.new(STDOUT)
      instance_eval(&block) if block
    end
    
    def to(host, port)
      @to_host = host
      @to_port = port
      self
    end

    def from(host, port)
      @from_host = host
      @from_port = port
      self
    end

    def times(count)
      @dispatcher_count = count
      self
    end

    def queue_with(beanstalk_host, tube)
      @beanstalk_host = beanstalk_host
      @tube = tube
      self
    end
    
    def logger(logger)
      @logger = logger
      self
    end
    
    def run
      unless EM.reactor_running?
        EM.run{ run }
      else
        Queuer.new(@logger, @from_host, @from_port, @beanstalk_host, @tube).run
        @dispatcher_count.times { Dispatcher.new(@logger, @to_host, @to_port, @beanstalk_host, @tube).run }
      end
    end
  end
end