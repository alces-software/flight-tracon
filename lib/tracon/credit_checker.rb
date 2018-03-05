module Tracon
  class CreditChecker
    attr_reader :errors

    def initialize(cluster)
      @errors = []
      @cluster = cluster
    end

    # If the cluster consumes credits, check that the cluster's user has
    # enough credits.
    def valid?
      @launch_cluster = JSONAPI::Resource.load_launch_cluster(@cluster)
      return true if @launch_cluster.nil?
      return true unless using_ongoing_credits?
      return false if owner.nil?

      validate_owner_has_compute_credits

      @errors.empty?
    end

    private

    def using_ongoing_credits?
      payment = @launch_cluster.load_relationship(:payment)
      return false if payment.nil?
      payment.attributes.paymentMethod == 'credits:ongoing'
    end

    def owner
      @owner ||= @launch_cluster.load_relationship(:owner)
    end

    def validate_owner_has_compute_credits
      unless owner.attributes.computeCredits > 0
        @errors << 'credits exhausted'
      end
    end
  end
end
