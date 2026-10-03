class StatisticsController < ApplicationController
  include StatisticsHelper, ComponentsHelper

  layout :determine_layout

  def index
    cutoff_date = Date.parse('2019-12-31T23:59:59Z')

    @merged_data, @year_month_visits = Rails.cache.fetch("statistics_index_data-#{$SITE}", expires_in: 24.hours) do
      projects = LinkedData::Client::Models::Project.where({ include: 'created' }) { |project| project.created.to_date > cutoff_date }
      users = LinkedData::Client::Models::User.where({ include: 'created' }) { |user| user.created.to_date > cutoff_date }
      agents = LinkedData::Client::Models::Agent.where({ include: 'created' }) { |agent| agent.created.blank? || agent.created.to_date > cutoff_date }
      year_month_count, year_month_visits = ontologies_by_year_month

      users_grouped = group_by_year_month(users)
      projects_grouped = group_by_year_month(projects)

      fallback = [users_grouped.keys.first,
                  projects_grouped.keys.first,
                  year_month_count.keys.sort.first].compact.min
      agents_grouped = group_by_year_month(agents, fallback: fallback)

      merged_data = merge_time_evolution_data([users_grouped,
                                               projects_grouped,
                                               year_month_count,
                                               agents_grouped])

      [merged_data, year_month_visits]
    end
  end
end
