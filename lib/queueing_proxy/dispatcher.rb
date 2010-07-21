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
          EventMachine.connect(@to_host, @to_port, DispatchClient) { |c|
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
    
    class DispatchClient < EventMachine::Connection
      attr_accessor :payload, :dispatcher, :logger, :dispatcher, :job
      
      def connection_completed
        send_data(payload)
      end

      def receive_data(data)
        status = Integer(data[/^HTTP\/(1\.1|1\.0) (\d+)/, 2])
        close_connection
        if status == 200
          logger.info "Done dispatching #{job.jobid}"
          job.delete
        else
          logger.info "Error #{status}"
          job.release(:delay => 5)
        end
      end
      
      def unbind
        dispatcher.run
      end
    end
  end
end