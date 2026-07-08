module CollectionsHelper
  include MultiLanguagesHelper, UrlsHelper


  def get_collections(ontology, add_colors: false)
    collections = ontology.explore.collections(include: 'all', language: request_lang)
    generate_collections_colors(collections) if add_colors
    collections.sort_by{ |x| main_language_label(x.prefLabel) || ''  } if collections
  end

  def get_collection(ontology, collection_uri)
    ontology.explore.collections({ include: 'all', language: request_lang},collection_uri)
  end

  def get_collection_label(collection)
    if collection['prefLabel'].nil? || collection['prefLabel'].empty?
      extract_label_from(collection['@id']).html_safe
    else
      collection['prefLabel']
    end
  end

  def get_collections_labels(collections, main_uri = '')

    selected_label = nil
    collections_labels = []
    collections.each do  |x|
      id = x['@id']
      label = select_language_label(get_collection_label(x))
      if id.eql? main_uri
        selected_label = { 'prefLabel' => label, '@id' => id }
      else
        collections_labels.append( { 'prefLabel' => label, '@id' => id , 'color' => x['color'] })
      end
    end

    collections_labels = sorted_labels(collections_labels)
    collections_labels.unshift selected_label if selected_label
    [collections_labels, selected_label]
  end

  def no_collections?
    @collections.nil? || @collections.empty?
  end

  def no_collections_alert
    render Display::AlertComponent.new do
      t('collections.no_collections_alert', acronym: @ontology.acronym)
    end
  end

  def collection_path(collection_id: '', ontology_id: @ontology.acronym, language: request_lang)
    "/ontologies/#{ontology_id}/collections/show?id=#{escape(collection_id)}&language=#{language}"
  end

  def request_collection_id
    params[:id] || params[:collectionid] || params[:concept_collection]
  end

  def sort_collections_label(collections_labels)
    sorted_labels(collections_labels)
  end

  def collections_tree(collections = @collections, selected_collection_id = request_collection_id)
    nodes = {}
    sources = {}

    collections.each do |collection|
      id = resource_identifier(collection)
      next if id.blank?

      sources[id] = collection
      node = OpenStruct.new(collection.to_h)
      node.id = id
      node.prefLabel = get_collection_label(collection)
      node.children = []
      node['hasChildren'] = false
      node['expanded?'] = false
      nodes[id] = node
    end

    child_ids = Set.new

    nodes.each do |id, node|
      children = collection_members(sources[id]).filter_map do |member|
        member_id = resource_identifier(member)
        next if member_id.blank? || member_id.eql?(node.id)
        nodes[member_id]
      end.uniq { |child| child.id }

      next if children.empty?

      node.children = sort_collection_nodes(children)
      node['hasChildren'] = true
      node['expanded?'] = true
      child_ids.merge(node.children.map(&:id))
    end

    root = OpenStruct.new(children: collection_root_nodes(nodes, child_ids))
    [root, nodes[selected_collection_id] || root.children.first]
  end

  def link_to_collection(collection, selected_collection_id)
    pref_label_lang, pref_label_html = get_collection_label(collection)
    tooltip  = pref_label_lang.to_s.eql?('@none') ? '' :  "data-controller='tooltip' data-tooltip-position-value='right' title='#{pref_label_lang.upcase}'"
    <<-EOS
          <a id="#{collection['@id']}" href="#{collection_path(collection_id: collection['@id'], ontology_id: @ontology.acronym, language: request_lang)}"
            data-turbo="true" data-turbo-frame="collection" data-collectionid="#{collection['@id']}"
           #{tooltip}
            class="#{selected_collection_id.eql?(collection['@id']) ? 'active' : nil}">
              #{pref_label_html}
          </a>
    EOS
  end

  private

  require 'color'

  def random_color
    hue = rand(0..360)
    saturation = rand(50..100) # Higher saturation for more vibrant colors
    lightness = rand(30..70) # Middle lightness to avoid extremes

    Color::HSL.new(hue, saturation, lightness).html
  end

  def generate_collections_colors(collections)
    collections.each do |c|
      c.color = random_color
    end
  end

  def collection_root_nodes(nodes, child_ids)
    roots = nodes.reject { |id, _| child_ids.include?(id) }.values
    sort_collection_nodes(roots.presence || nodes.values)
  end

  def sort_collection_nodes(nodes)
    Array(nodes).sort_by do |node|
      main_language_label(node.prefLabel) || node.id.to_s
    end
  end

  def collection_members(collection)
    members = []
    if collection.respond_to?(:properties) && collection.properties.present?
      members = Array(collection.properties[:'http://www.w3.org/2004/02/skos/core#member'])
    end
    members.compact
  end

  def resource_identifier(resource)
    return if resource.nil?
    return resource if resource.is_a?(String)
    return resource.id if resource.respond_to?(:id) && resource.id.present?
    return resource_identifier(resource.first) if resource.is_a?(Array) && resource.length == 1

    if resource.is_a?(Array)
      hash_candidate = resource.find do |value|
        next false if value.is_a?(Array) || value.is_a?(String)
        resource_identifier_hash(value).present?
      end
      string_candidate = resource.find { |value| value.is_a?(String) }
      return resource_identifier(hash_candidate) if hash_candidate.present?
      return string_candidate if string_candidate.present?
      return
    end

    hash = resource_identifier_hash(resource) || {}
    return hash['@id'] if hash['@id'].present?
    return hash['id'] if hash['id'].present?

    resource.id if resource.respond_to?(:id)
  end

  def resource_identifier_hash(resource)
    hash =
      if resource.is_a?(Hash)
        resource
      elsif resource.respond_to?(:to_h)
        resource.to_h
      else
        {}
      end

    hash = hash.transform_keys(&:to_s) if hash.respond_to?(:transform_keys)
    hash || {}
  rescue StandardError
    {}
  end
end
