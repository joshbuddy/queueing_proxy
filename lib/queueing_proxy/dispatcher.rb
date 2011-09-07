require "http/parser"

module QueueingProxy
  class Dispatcher
    attr_reader :logger

    def initialize(logger, to_host, to_port, beanstalk_host, tube)
      @logger, @to_host, @to_port, @beanstalk_host, @tube = logger, to_host, to_port, beanstalk_host, tube
      @beanstalk = EMJack::Connection.new(:host => @beanstalk_host, :tube => @tube)
      @beanstalk.watch(@tube)
      logger.info "Starting dispatcher on #{to_host}:#{to_port} using beanstalk at #{tube}@#{beanstalk_host}"
    end
    
    def run
      @beanstalk.reserve do |job|
        logger.info "Dispatching #{job.jobid}"
        parsed_job = JSON.parse(job.body)
        begin
          EventMachine.connect(@to_host, @to_port, UpstreamDispatcher) { |c|
            c.payload = parsed_job['data']
            c.dispatcher = self
            c.logger = logger
            c.job = job
            c.dispatcher = self
          }
        rescue EventMachine::ConnectionError
          job.release(:delay => 5)
          logger.info("Problem connecting")
          EM.add_timer(5){ run }
        end
      end
    end

    class UpstreamDispatcher < EventMachine::Connection
      attr_accessor :payload, :dispatcher, :logger, :dispatcher, :job
      
      def connection_completed
        # Kill the connection and start processing the response.
        parser.on_headers_complete {
          process_http_status_code parser.status_code
          close_connection
          :stop
        }
        # Send the HTTP request upstream
        send_data(payload)
      end

      def receive_data(data)
        parser << data
      end

      # Figure out what to do with the beanstalk job if we 
      def process_http_status_code(status)
        case Integer(status)
        when 200
          logger.info "Done dispatching #{job.jobid}"
          job.delete
        when 500..599 # If our server has a problem, bury the job so we can inspect it later.
          logger.info "Error #{status}: burying #{job.jobid}"
          job.bury Queuer::Priority::Lowest
        else
          logger.info "Done dispatching #{job.jobid} -- #{status}"
          job.delete
        end
      end
      
      def unbind
        dispatcher.run
      end

    private
      def parser
        @parser ||= Http::Parser.new
      end
    end
  end
end