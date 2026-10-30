# ontologies_api_client init (default config works for the UI)
require 'ontologies_api_client'

# The pinned client omits this model; keep DOI request links distinct from ADMS identifiers.
unless LinkedData::Client::Models.const_defined?(:IdentifierRequest, false)
  module LinkedData
    module Client
      module Models
        class IdentifierRequest < LinkedData::Client::Base
          include LinkedData::Client::Collection
          include LinkedData::Client::ReadWrite

          @media_type = 'http://data.bioontology.org/metadata/IdentifierRequest'
          @include_attrs = 'all'
        end
      end
    end
  end

  client_base = LinkedData::Client::Base
  client_base.remove_instance_variable(:@media_type_class_map) if client_base.instance_variable_defined?(:@media_type_class_map)
end

LinkedData::Client.config do |config|
  config.cache        = $CLIENT_REQUEST_CACHING
  config.rest_url     = $REST_URL
  config.purl_prefix  = $PURL_PREFIX
  config.debug_client = $DEBUG_RUBY_CLIENT || false
  config.debug_client_keys = $DEBUG_RUBY_CLIENT_KEYS || []
  config.apikey = $API_KEY
  # Federated portals are administered at runtime through the catalog, the connections
  # are opened from there: see FederationHelper#sync_federated_connections
  config.federated_portals = {}
end
