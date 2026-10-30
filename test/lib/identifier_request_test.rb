require 'minitest/autorun'
require 'ontologies_api_client'

# Prime the client's cached registry before the initializer registers compatibility models.
LinkedData::Client::Base.class_for_type('http://data.bioontology.org/metadata/Ontology')
require_relative '../../config/initializers/ontologies_api_client'

class IdentifierRequestTest < Minitest::Test
  def test_doi_request_type_resolves_to_its_own_client_model
    model = LinkedData::Client::Base.class_for_type('http://data.bioontology.org/metadata/IdentifierRequest')

    refute_nil model
    assert_equal 'LinkedData::Client::Models::IdentifierRequest', model.name
    assert_includes model.ancestors, LinkedData::Client::Collection
    assert_includes model.ancestors, LinkedData::Client::ReadWrite
    refute_equal LinkedData::Client::Models::Identifier, model
  end

  def test_other_type_mappings_remain_available
    assert_equal LinkedData::Client::Models::Ontology,
                 LinkedData::Client::Base.class_for_type('http://data.bioontology.org/metadata/Ontology')
    assert_equal LinkedData::Client::Models::Identifier,
                 LinkedData::Client::Base.class_for_type('http://www.w3.org/ns/adms#Identifier')
  end

  def test_loading_initializer_again_preserves_the_existing_model
    model = LinkedData::Client::Base.class_for_type('http://data.bioontology.org/metadata/IdentifierRequest')

    load File.expand_path('../../config/initializers/ontologies_api_client.rb', __dir__)

    assert_same model, LinkedData::Client::Base.class_for_type('http://data.bioontology.org/metadata/IdentifierRequest')
  end
end
