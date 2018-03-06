module Tracon
  module JSONAPI
    class Document
      attr_reader :meta, :resources, :resource

      def initialize(doc)
        @meta = doc[:meta]
        data = doc[:data]

        case data
        when nil
          puts "Unable to create JSONAPI::Resource: no data in response document #{document.inspect}"
        when Array
          @resources = data.map {|datum| Resource.new(datum) }
        else
          @resource = Resource.new(data)
        end
      end
    end
  end
end
