module Tracon
  # For clusters which have a quota for their queue usage, validate that the
  # quota won't be exceeded.
  class QuotaValidator
    attr_reader :errors

    def initialize(cluster, desired, queue)
      @errors = []
      @cluster = cluster
      @desired = desired
      @queue = queue
    end

    def valid?
      unless @cluster.cu_max == 0 || @cluster.cu_in_use + cu_desired <= @cluster.cu_max
        @errors << 'quota exceeded'
      end

      @errors.empty?
    end

    private

    def cu_desired
      if @queue.exists?
        # The additional number of compute units modifying this queue will
        # cost.
        (@desired - @queue.size) * @queue.cu_per_node
      else
        # The number of compute units creating this queue will cost.
        @desired * @queue.cu_per_node
      end
    end
  end
end
