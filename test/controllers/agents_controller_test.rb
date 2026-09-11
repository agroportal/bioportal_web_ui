# frozen_string_literal: true

require 'test_helper'

class AgentsControllerTest < ActionController::TestCase
  test 'opens the agents table on the linked page' do
    get :index, params: { page: '14' }

    assert_response :success
    assert_select '[data-table-component-page-value="14"]'
  end
end
