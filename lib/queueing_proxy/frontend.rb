module QueueingProxy
  class Frontend
    attr_reader :logger

    def initialize(logger, host, port, backends)
      @logger, @host, @port, @backends = logger, host, port, backends
      logger.info "Starting queuer on #{host}:#{port} using beanstalk at #{backends.map{|b| "#{b.tube}@#{b.host}"}.join(', ')}"
    end

    def beanstalks
      @beanstalks ||= @backends.map {|b|
        connection = EMJack::Connection.new(:host => b.host, :tube => b.tube)
        connection.errback { logger.error "Couldn't connect to beanstalk" }
        connection
      }
    end

    def run
      app = proc do |env|
        logger.info "Frontend frontend #{env['HTTP_VERSION']} #{env['PATH_INFO']} #{env['REQUEST_METHOD']}"
        [204, {}, []]
      end
      backend = FakeBackend.new

      EM.start_server(@host, @port, Queuer) do |conn|
        conn.beanstalks = beanstalks
        conn.app = app
        conn.backend = backend
        conn.logger = logger
      end
    end

    # We need this to make Thin happy
    class FakeBackend
      def connection_finished(conn)
      end

      def ssl?
      end
    end

    class Queuer < Thin::Connection
      attr_accessor :beanstalks, :logger

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
          beanstalks.each {|b|
            b.put(@data) {|id|
              logger.info "Frontend enqueued job #{id} to #{b}"
            }
          }
        end
      end
    end
  end
end