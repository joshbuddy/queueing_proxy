require 'logger'

module QueueingProxy
  class DSL
    class Backend
      attr_reader :tube, :host

      def initialize(host='localhost', port=80, workers=4, &block)
        @host, @port, @workers, @beanstalk_host, @tube = host, port, workers, 'localhost', 'default'
        instance_exec(&block) if block_given?
        self
      end

      def queue_with(beanstalk, tube)
        @beanstalk, @tube = beanstalk, tube
        self
      end

      def workers(workers=nil)
        if workers
          @workers = workers
          self
        else
          (1..@workers).map { Worker.new(@logger, @host, @port, @beanstalk_host, @tube) }
        end
      end

      def logger(logger)
        @logger = logger
        self
      end
    end

    def initialize(&block)
      @logger = Logger.new($stdout)
      instance_eval(&block) if block
    end
    
    def to(host, port=80, &block)
      backends << Backend.new(host, port, &block)
      self
    end

    def from(host, port=80, &block)
      frontends << [host, port]
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
        frontends.each do |host, port|
          Frontend.new(@logger, host, port, backends).run
        end
        # Setup multiple backends
        backends.each {|b|
          b.logger @logger
          b.workers.each(&:run) 
        }
      end
    end

  private
    def frontends
      @frontends ||= []
    end

    def backends
      @backends ||= []
    end
  end
end