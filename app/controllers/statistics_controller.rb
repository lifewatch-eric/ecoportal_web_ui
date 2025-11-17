class StatisticsController < ApplicationController
  include StatisticsHelper, ComponentsHelper

  layout :determine_layout

  def index
    cutoff_date = Date.parse('2019-12-31T23:59:59Z')

    projects = LinkedData::Client::Models::Project.where({include: 'created'}) { |p| p.created.to_date > cutoff_date }
    users = LinkedData::Client::Models::User.where({ include: 'created' }) { |u| u.created.to_date > cutoff_date }
    year_month_count,  @year_month_visits = ontologies_by_year_month
    @merged_data = merge_time_evolution_data([group_by_year_month(users),
                                              group_by_year_month(projects),
                                              year_month_count])
  end
end
