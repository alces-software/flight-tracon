module Tracon
  module JSONAPI
    class Document
      attr_reader :meta, :resources, :resource
      attr_accessor :auth_user, :auth_password

      def initialize(doc)
        @meta = doc[:meta]
        data = doc[:data]

        case data
        when nil
          puts "Unable to create JSONAPI::Resource: no data in response document #{document.inspect}"
        when Array
          @resources = data.map {|datum| Resource.new(datum, self) }
        else
          @resource = Resource.new(data, self)
        end
      end
    end
  end
end
