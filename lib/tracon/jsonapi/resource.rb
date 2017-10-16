module Tracon
  module JSONAPI
    class Resource
      def initialize(params={})
        @id = params[:id]
        @type = params[:type]
        @attributes = params[:attributes]
        @relationships = params[:relationships]
      end

      def create(link)
        uri = URI(link)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          req = Net::HTTP::Post.new(uri)
          req.content_type = 'application/vnd.api+json'
          req.body = {
            data: {
              type: @type,
              attributes: @attributes,
              relationships: @relationships,
            }
          }.to_json
          http.request(req)
        end
      end
    end
  end
end
