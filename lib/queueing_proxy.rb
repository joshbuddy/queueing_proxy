require 'thin'
require 'eventmachine'
require 'em-jack'
require 'json'

require 'queueing_proxy/cli'
require 'queueing_proxy/dsl'
require 'queueing_proxy/queuer'
require 'queueing_proxy/version'
require 'queueing_proxy/dispatcher'
require 'queueing_proxy/statistics'

module QueueingProxy

  def self.from(host, port)
    DSL.new.from(host, port)
  end

end

def QueueingProxy(&blk)
  QueueingProxy::DSL.new(&blk)
end