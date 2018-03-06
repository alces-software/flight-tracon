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

      def load_relationship(relation_name, query={})
        return nil if relationships.nil?
        return nil if relationships[relation_name].nil?
        return nil if relationships[relation_name].links.related.nil?

        uri = URI(relationships[relation_name].links.related)
        if uri.query
          uri.query = "#{uri.query}&#{URI.encode_www_form(query)}"
        else
          uri.query = URI.encode_www_form(query)
        end

        JSONAPI.load_document(uri)
      end
    end
  end
end
