require 'json'
require 'open-uri'
require 'ostruct'

module Tracon
  module JSONAPI
    class Resource
      attr_reader :id, :type, :attributes, :relationships

      def initialize(params)
        @id = params[:id]
        @type = params[:type]
        @attributes = params[:attributes]
        @relationships = params[:relationships]
      end

      class << self
        def create(link, params)
          uri = URI(link)
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            req = Net::HTTP::Post.new(uri)
            req.content_type = 'application/vnd.api+json'
            req.body = {
              data: {
                type: params[:type],
                attributes: params[:attributes],
                relationships: params[:relationships],
              }
            }.to_json
            response = http.request(req)
            self.parse(response.body)
          end
        end

        def load_launch_cluster(cluster)
          base_url = ENV['LAUNCH_API_BASE_URL']
          link = "#{base_url}/api/v1/clusters/#{cluster.uuid}"
          load_resource(link)
        rescue OpenURI::HTTPError
          if $!.io.status.first == '404'
            # Launch doesn't have a record of this cluster.
            return nil
          end
          raise
        end

        def load_resource(link)
          uri = URI(link)
          self.parse(uri.open.read)
        end

        def parse(json_string)
          document = JSON.parse(json_string, object_class: OpenStruct)
          if document.data
            self.new(document.data)
          else
            puts "Unable to create JSONAPI::Resource: no data in response document #{document.inspect}"
          end
        end
      end

      def load_relationship(relation_name)
        return nil if relationships.nil?
        return nil if relationships[relation_name].nil?
        return nil if relationships[relation_name].links.related.nil?

        self.class.load_resource(relationships[relation_name].links.related)
      end
    end
  end
end
