require "http/parser"

module QueueingProxy
  class Dispatcher
    attr_reader :logger

    def initialize(logger, to_host, to_port, beanstalk_host, tube)
      @logger, @to_host, @to_port, @beanstalk_host, @tube = logger, to_host, to_port, beanstalk_host, tube
    end

    # Setup a beanstalk connection
    def beanstalk
      @beanstalk ||= EMJack::Connection.new(:host => @beanstalk_host, :tube => @tube)
    end

    # Run the beanstalk consumer that pops the job off the queue and passes it 
    # to a connection object that makes an upstream connection
    def run
      logger.debug "Worker #{object_id} reporting again for duty"
      beanstalk.reserve {|job|
        logger.info "Worker #{object_id} reserved #{job}"
        upstream = Upstream.new(job.body, @to_host, @to_port, 15, logger).request
        upstream.errback{
          logger.info "Worker #{object_id} upstream connection timed-out with #{job}. Requeueing."
          job.release(:delay => 5)
          run
        }
        upstream.callback {
          case status = Integer(upstream.response.status_code)
          when 200..299
            logger.info "Worker #{object_id}. Deleting #{job.jobid}."
            job.delete
          else
            logger.info "Worker #{object_id}. Burying #{job} for inspection."
            job.bury Queuer::Priority::Lowest
          end
          run
        }
      }.errback{|status|
        case status
        when :disconnected
          logger.error "Worker #{object_id} reservation error. Rescheduling."
        else
          logger.error "Worker #{object_id} unhandled error #{status}."
        end
        run
      }
    end

    # Defferable upstream connection
    class Upstream
      include EventMachine::Deferrable

      # The connection handler for EM.
      module Client
        attr_accessor :upstream

        # Succesful connection!
        def connection_completed
          # Setup our callback for when the upstream response hits us
          upstream.response.on_headers_complete = Proc.new {
            upstream.succeed
            close_connection
            :stop
          }

          # Send the HTTP request upstream
          send_data upstream.payload
        end

        # Read the response of the upstream proxy
        def receive_data(data)
          upstream.response << data
        end

        # If something bad happens to the connection, bind gets called
        def unbind
          upstream.fail
        end
      end

      attr_accessor :payload, :host, :port, :timeout, :logger
      attr_reader :response

      def initialize(payload, host, port, timeout, logger)
        @response = Http::Parser.new
        @payload, @host, @port, @timeout, @logger = payload, host, port, timeout, logger
      end

      # Connect to the upstream server and send the HTTP payload
      def request
        begin
          EventMachine.connect(host, port, Client) {|c|
            c.upstream = self
            c.comm_inactivity_timeout = timeout
            c.pending_connect_timeout = timeout
          }

          # TODO - Is this async/deferrable?
        rescue => e
          logger.error e
          fail # If something explodes here, fail the defferable
        end
        self
      end
    end
  end
end