module QueueingProxy
  class DSL
    def initialize(from_host, from_port)
      @from_host, @from_port = from_host, from_port
    end
    
    def to(host, port)
      @to_host = host
      @to_port = port
      self
    end

    def queue_with(beanstalk_host, tube)
      @beanstalk_host = beanstalk_host
      @tube = tube
      self
    end
    
    def run
      unless EM.reactor_running?
        EM.run{ run }
      else
        Queuer.new(@from_host, @from_port, @beanstalk_host, @tube).run
        Dispatcher.new(@to_host, @to_port, @beanstalk_host, @tube).run
      end
    end
  end
end