module Tracon
  class Node
    attr_accessor :name

    def initialize(name, queue)
      @name = name
      @queue = queue
    end

    def exists?
      @exists ||= node_data.present? && node_data.key?(:name)
    end

    def shoot
      AWS.shoot_node(@name)
    end

    private
    def node_data
      @node_data ||= AWS.node(@queue.cluster.domain, @queue.cluster.name, @queue.name, @name)
    end
  end
end
