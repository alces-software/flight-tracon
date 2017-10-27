require 'json'
require 'open-uri'
require 'ostruct'

require 'tracon/jsonapi/resource'

module Tracon
  class CreditUsage
    def initialize(cluster)
      @cluster = cluster
    end
    
    def create
      resource = JSONAPI::Resource.new(
        id: nil,
        type: 'creditUsages',
        attributes: {
          cuInUse: @cluster.cu_in_use(reload: true),
        },
        relationships: {
          'cluster': {
            data: { type: 'clusters', id: @cluster.uuid }
          }
        }
      )
      resource.create(credit_usage_url)
    end

    private

    def credit_usage_url
      base_url = ENV['FlightLaunchEndpoint']
      "#{base_url}/api/v1/credit-usages"
    end
  end
end
