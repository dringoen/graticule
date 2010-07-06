module Graticule #:nodoc:
  module Geocoder #:nodoc:

    # Example:
    #
    #   gg = Graticule.service(:google).new
    #   location = gg.locate('1600 Amphitheater Pkwy, Mountain View, CA')
    #   p location.coordinates
    #   #=> [37.423111, -122.081783]
    #
    class Google < Base
      PRECISION = {
        :political                   => Precision::Unknown,
        :colloquial_area             => Precision::Unknown,
        :natural_feature             => Precision::Unknown,
        :country                     => Precision::Country,
        :administrative_area_level_1 => Precision::Region,
        :administrative_area_level_2 => Precision::Region,
        :administrative_area_level_3 => Precision::Region,
        :locality                    => Precision::Locality,
        :sublocality                 => Precision::PostalCode,
        :neighborhood                => Precision::PostalCode,
        :postal_code                 => Precision::PostalCode,
        :intersection                => Precision::Street,
        :route                       => Precision::Street,
        :street_address              => Precision::Address,
        :premise                     => Precision::Premise,
        :subpremise                  => Precision::Premise,
        :airport                     => Precision::Premise,
        :park                        => Precision::Premise,
        :point_of_interest           => Precision::Premise
      }

      def initialize
        @url = URI.parse('http://maps.google.com/maps/api/geocode/xml')
      end

      # Locates +address+ returning a Location
      def locate(address)
        get :address => address.is_a?(String) ? address : location_from_params(address).to_s
      end

      private

      class AddressComponent
        include HappyMapper
        tag 'address_component'
        element :long_name, String
        element :short_name, String
        has_many :types, String, :tag => 'type'
      end

      class Result
        include HappyMapper
        tag 'result'
        element :lat, Float, :deep => true
        element :lng, Float, :deep => true
        has_many :types, String, :tag => 'type'
        has_many :address_components, AddressComponent

        def precision
          self.types.map { |type| PRECISION[type.to_sym] }.compact.min || :unknown
        end

        def street
          address_component_value('route')
        end

        def locality
          address_component_value('locality')
        end

        def postal_code
          address_component_value('postal_code')
        end

        def country
          address_component_value('country')
        end

        def region
          address_component_value('administrative_area_level_1') ||
          address_component_value('administrative_area_level_2') ||
          address_component_value('administrative_area_level_3')
        end

        private

        def address_component_value(address_component_type)
          address_components.detect { |address_component| address_component.types.include?(address_component_type) }.try(:long_name)
        end
      end

      class Response
        include HappyMapper
        tag 'GeocodeResponse'
        element :status, String
        has_many :results, Result
      end

      def prepare_response(xml)
        Response.parse(xml, :single => true)
      end

      def parse_response(response) #:nodoc:
        result = response.results.first
        Location.new(
          :latitude    => result.lat,
          :longitude   => result.lng,
          :street      => result.street,
          :locality    => result.locality,
          :region      => result.region,
          :postal_code => result.postal_code,
          :country     => result.country,
          :precision   => result.precision
        )
      end

      # Extracts and raises an error from +xml+, if any.
      def check_error(response) #:nodoc:
        case response.status
        when 'OK'               then # No error, do nothing
        when 'ZERO_RESULTS'     then raise AddressError.new('Address not found!')
        when 'OVER_QUERY_LIMIT' then raise CredentialsError.new('Too many queries!')
        when 'REQUEST_DENIED'   then raise CredentialsError.new('Request denied! Did you include the sensor parameter?')
        when 'INVALID_REQUEST'  then raise CredentialsError.new('Invalid request. Did you include an address or latlng?')
        else                         raise StandardError.new("Unknown error: #{response.code}")
        end
      end

      def make_url(params) #:nodoc:
        super params.merge(:sensor => false)
      end
    end
  end
end