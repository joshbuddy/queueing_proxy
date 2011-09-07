module QueueingProxy
  # Track an aggregate of connection statuses for this server & connection. 
  class Statistics
    def initialize
      reset
    end

    # Process responses to update the status of this thing.
    def process(http_parser)
      @count += 1
      @response_codes[http_parser.status_code][:count] += 1
    end

    # Print out a hash that we can easily dump into a socket after a to_s
    def to_hash
      {
        :count => count,
        :status_codes => @response_codes
      }
    end

    # Reset all the counters, etc.
    def reset
      @count = 0
      @started_at = Time.now
      @response_codes = Hash.new do |h,v|
        h[v] = { :count => 0 }
      end
    end
  end

  # Mount the status into a server so that we can read these from munin or whatever
  class Statistics::Server < EventMachine::Connection
    attr_reader :statistics

    Host = '/tmp/queueing_proxy_statistics.socket' # Its a local unix socket
    Port = nil

    # Setup stats counter
    def initialize(statistics)
      @statistics = statistics
      super
    end

    # Dump out the stats and close down the connection
    def post_init
      send_date @statistics.to_hash.to_yaml
      close_connection_after_writing
    end

    # Open up a connection
    def self.start(host=Host,port=Port,statistics=Statistics.new)
      EM::connect host, port, self, statistics
    end
  end
end