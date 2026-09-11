# frozen_string_literal: true

require 'application_system_test_case'
require 'minitest/mock'

# Agents tables are deep linkable: ?page=N opens them on page N and paging
# keeps the param in sync. The API is faked (35 agents, 4 pages of 10) so the
# page count is known and nothing gets written to it.
class AgentsPaginationTest < ApplicationSystemTestCase
  PAGE_SIZE = 10
  LAST_PAGE = 4
  AGENTS = Array.new(35) do |i|
    LinkedData::Client::Models::Agent.new(values: {
      id: "http://data.agroportal.eu/Agents/agent-#{i}",
      name: format('Agent %02d', i),
      acronym: "A#{i}",
      agentType: 'person',
      affiliations: [],
      identifiers: [],
      usages: {},
      created: (Date.new(2026, 1, 1) + i).iso8601
    })
  end

  test 'the agents page opens on the linked page' do
    with_fake_agents do
      visit '/agents?page=2'

      assert_current_page 2
      assert_selector '#agents-table tbody tr:first-child', text: 'Agent 10'
      assert_current_path '/agents?page=2'
    end
  end

  test 'a page past the end lands on the last one' do
    with_fake_agents do
      visit '/agents?page=99'

      assert_current_page LAST_PAGE
      assert_current_path "/agents?page=#{LAST_PAGE}"
    end
  end

  test 'paging keeps the url in sync' do
    with_fake_agents do
      visit '/agents'
      assert_current_page 1

      find('#agents-table_next').click
      assert_current_page 2
      assert_current_path '/agents?page=2'

      # The first page is the default, so it leaves no param behind.
      find('#agents-table_previous').click
      assert_current_page 1
      assert_current_path '/agents'
    end
  end

  test 'the admin agents tab opens on the linked page' do
    with_fake_agents do
      login_as_fake_admin

      visit '/admin?section=agents&page=2'
      assert_current_page 2
      assert_current_path '/admin?section=agents&page=2'

      visit '/admin?section=agents&page=99'
      assert_current_page LAST_PAGE
      assert_current_path "/admin?section=agents&page=#{LAST_PAGE}"
    end
  end

  private

  def with_fake_agents(&block)
    LinkedData::Client::Models::Agent.stub(:all, method(:fake_agents), &block)
  end

  # /agents asks for one page at a time, the admin tab for every agent.
  def fake_agents(options = {})
    return AGENTS unless options[:page]

    size = options[:pagesize] || PAGE_SIZE
    start = (options[:page].to_i - 1) * size
    [OpenStruct.new(collection: AGENTS[start, size] || [], totalCount: AGENTS.size)]
  end

  # Logging in for real creates the user through the API; authenticate a
  # local admin instead.
  def login_as_fake_admin
    admin = LinkedData::Client::Models::User.new(values: {
      username: 'admin',
      role: ['ADMINISTRATOR'],
      apikey: LinkedData::Client.settings.apikey,
      customOntology: []
    })

    # A lambda, as API models answer every method, `call` included.
    LinkedData::Client::Models::User.stub(:authenticate, ->(*) { admin }) do
      visit login_index_url
      fill_in 'user_username', with: admin.username
      fill_in 'user_password', with: 'password'
      click_button 'Login'

      # Holds the stub until the login request is served.
      assert_current_path root_path
    end
  end

  def assert_current_page(number)
    assert_selector '#agents-table_paginate .paginate_button.current', exact_text: number.to_s
  end
end
