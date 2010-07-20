module QueueingProxy
  class Queuer
    def initialize(host, port, beanstalk_host, tube)
      @host, @port, @beanstalk_host, @tube = host, port, beanstalk_host, tube
    end

    def run
      beanstalk = EMJack::Connection.new(:host => @beanstalk_host, :tube => @tube)
      app = proc{|env| [200, {}, []]}
      backend = FakeBackend.new
      EM.start_server(@host, @port, QueuerConnection) do |conn|
        conn.beanstalk = beanstalk
        conn.app = app
        conn.backend = backend
      end
    end

    class FakeBackend
      def connection_finished(conn)
      end
    end
    
    class QueuerConnection < Thin::Connection
      attr_accessor :beanstalk

      def post_init
        @data = ''
        super
      end

      def receive_data(data)
        @data << data
        super(data)
      end

      def post_process(pre_process)
        queue_data
        super(pre_process)
      end

      def queue_data
        beanstalk.put({:data => @data, :time => Time.new.to_i}.to_json)
      end
    end
  end
end