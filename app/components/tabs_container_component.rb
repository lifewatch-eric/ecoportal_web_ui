# frozen_string_literal: true

class TabsContainerComponent < ViewComponent::Base

  renders_many :items, TabItemComponent
  renders_many :item_contents
  renders_one :pinned_right

  def initialize(url_parameter: nil, pill: false)
    super
    @url_parameter = url_parameter
    @pill = pill
  end

  def container_class
    @pill ? 'pill-tabs-container' : 'tabs-container'
  end

  def tabs_container_data(item)
    {
      toggle: 'tab',
      target: item.target,
      'tab-id': item.id,
      'tab-title': item.title,
      'url-parameter': @url_parameter,
      action: 'click->tabs-container#selectTab'
    }
  end
end
