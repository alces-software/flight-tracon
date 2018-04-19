module Tracon
  module JSONAPI
    class Resource
      attr_reader :id, :type, :attributes, :relationships

      def initialize(params, document)
        @id = params[:id]
        @type = params[:type]
        @attributes = params[:attributes]
        @relationships = params[:relationships]
        @document = document
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

        JSONAPI.load_document(uri, user: auth_user, password: auth_password)
      end

      private

      def auth_user
        @document.auth_user
      end

      def auth_password
        @document.auth_password
      end
    end
  end
end
