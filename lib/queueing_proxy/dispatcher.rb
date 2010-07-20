module QueueingProxy
  class Dispatcher
    def initialize(to_host, to_port, beanstalk_host, tube)
      @to_host, @to_port, @beanstalk_host, @tube = to_host, to_port, beanstalk_host, tube
      @beanstalk = EMJack::Connection.new(:host => @beanstalk_host, :tube => @tube)
      @beanstalk.watch(@tube)
    end
    
    def run
      @beanstalk.reserve do |job|
        parsed_job = JSON.parse(job.body)
        EventMachine.connect(@to_host, @to_port, DispatchClient) { |c|
          c.payload = parsed_job['data']
          c.dispatcher = self
        }
      end
    end
    
    class DispatchClient < EventMachine::Connection
      
      attr_accessor :payload, :dispatcher
      
      def connection_completed
        send_data(payload)
      end

      def receive_data(data)
        puts "data: #{data}"
      end
      
    end
  end
end