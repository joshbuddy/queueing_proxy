module QueueingProxy
  class Queuer
    # 4294967295 is from the Beanstalkd protocol as the least important 
    # possible job priority. 0 is the highest pri.
    module Priority
      Lowest = 4294967295
      Highest = 0
    end

    attr_reader :logger

    def initialize(logger, host, port, beanstalk_host, tube)
      @logger, @host, @port, @beanstalk_host, @tube = logger, host, port, beanstalk_host, tube
      logger.info "Starting queuer on #{host}:#{port} using beanstalk at #{tube}@#{beanstalk_host}"
    end

    def run
      beanstalk = EMJack::Connection.new(:host => @beanstalk_host, :tube => @tube)
      app = proc do |env|
        logger.info "Queueing #{env['HTTP_VERSION']} #{env['PATH_INFO']} #{env['REQUEST_METHOD']}"
        [200, {}, []]
      end
      backend = FakeBackend.new
      EM.start_server(@host, @port, QueuerConnection) do |conn|
        conn.beanstalk = beanstalk
        conn.app = app
        conn.backend = backend
        conn.logger = logger
      end
    end

    class FakeBackend
      def connection_finished(conn)
      end
    end
    
    class QueuerConnection < Thin::Connection
      attr_accessor :beanstalk, :logger

      def post_init
        @data = ''
        super
      end

      def receive_data(data)
        @data << data
        super(data)
      end

      def unbind
        queue_data
        super
      end

      def queue_data
        if @data != ''
          beanstalk.put({:data => @data, :time => Time.new.to_i}.to_json) { |id|
            logger.info "Job queued #{id}"
          }
        end
      end
    end
  end
end