require "http/parser"

module QueueingProxy
  class Dispatcher
    attr_reader :logger

    def initialize(logger, to_host, to_port, beanstalk_host, tube)
      @logger, @to_host, @to_port, @beanstalk_host, @tube = logger, to_host, to_port, beanstalk_host, tube
      beanstalk.watch(@tube) # Connect to the tube and listen
    end

    def beanstalk
      logger.info "Listening on #{@to_host}:#{@to_port} using beanstalk at #{@tube}@#{@beanstalk_host}"
      @beanstalk ||= EMJack::Connection.new(:host => @beanstalk_host, :tube => @tube)
    end

    def run
      beanstalk.reserve do |job|
        begin
          parsed_job = JSON.parse(job.body)
          logger.info "Dispatching #{job.jobid}"
          logger.debug parsed_job['data'] # Spit out the HTTP request we're gonn send upstream

          EventMachine.connect(@to_host, @to_port, UpstreamDispatcher) { |c|
            c.payload = parsed_job['data']
            c.dispatcher = self
            c.logger = logger
            c.job = job
            c.dispatcher = self
          }
        rescue EventMachine::ConnectionError
          job.release(:delay => 5)
          logger.error "Problem connecting. Releasing job."
          EM.add_timer(5){ run } # Try that again in 5 more seconds
        rescue Exception => e
          logger.error "Exception processing job #{job.id} (I buried it so you can look at it): #{e.inspect}: #{e.backtrace}"
          job.bury Queuer::Priority::Lowest
        end
      end
    end

    class UpstreamDispatcher < EventMachine::Connection
      attr_accessor :payload, :dispatcher, :logger, :dispatcher, :job
      
      def connection_completed
        response_parser.on_headers_complete = Proc.new {
          process_http_status_code response_parser.status_code
          close_connection # Kill the upstream EM connection
          :stop # Stops HTTP parser
        }
        # Send the HTTP request upstream
        send_data(payload)
      end

      def receive_data(data)
        # Send the upstream response into the HTTP parser
        response_parser << data
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
      def response_parser
        @response_parser ||= Http::Parser.new
      end
    end
  end
end