require "http/parser"

module QueueingProxy
  class Dispatcher
    attr_reader :logger, :beanstalk

    def initialize(logger, to_host, to_port, beanstalk_host, tube)
      @logger, @to_host, @to_port, @beanstalk_host, @tube = logger, to_host, to_port, beanstalk_host, tube
      @beanstalk = EMJack::Connection.new(:host => @beanstalk_host, :tube => @tube)
      # beanstalk.watch(@tube) # Connect to the tube and listen
    end

    def run
      logger.info "Worker #{object_id} at your service"
      beanstalk.reserve do |job|
        logger.info "Reserved #{job}"
        upstream = Upstream.new(job.body, @to_host, @to_port, 15, logger).request
        upstream.errback{
          logger.info "Ruh roh! Errback. Try again in 5 seconds. #{job}"
          job.release(:delay => 5)
          run # Call again
        }
        upstream.callback {
          case status = Integer(upstream.response.status_code)
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
          run
        }
      end
    end

    # Defferable upstream connection
    class Upstream
      include EventMachine::Deferrable

      # The connection handler for EM.
      module Client
        attr_accessor :client

        # Succesful connection!
        def connection_completed
          # Setup our callback for when the upstream response hits us
          client.response.on_headers_complete = Proc.new {
            client.succeed
            close_connection
            :stop
          }

          # Send the HTTP request upstream
          send_data client.payload
        end

        # Read the response of the upstream proxy
        def receive_data(data)
          # Send the upstream response into the HTTP parser
          client.response << data
        end

        # If something bad happens to the connection, bind gets called
        def unbind
          client.fail
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
          @connection = EventMachine.connect(host, port, Client) {|c|
            c.client = self
            c.comm_inactivity_timeout = timeout
            c.pending_connect_timeout = timeout
          }
        rescue => e
          logger.error e
          fail # If something explodes here, fail the defferable
        end
        self
      end
    end
  end
end