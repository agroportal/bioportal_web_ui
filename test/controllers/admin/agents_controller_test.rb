# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class Admin::AgentsControllerTest < ActionController::TestCase
  ADMIN = OpenStruct.new('admin?' => true, flipper_id: 'User;admin')

  test 'opens the agents table on the page forwarded by the admin tabs' do
    LinkedData::Client::Models::Agent.stub(:all, []) do
      get :index, params: { page: '14' }, session: { user: ADMIN }
    end

    assert_response :success
    assert_select '[data-table-component-page-value="14"]'
  end
end
