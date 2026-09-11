# frozen_string_literal: true

require 'test_helper'

class AdminControllerTest < ActionController::TestCase
  ADMIN = OpenStruct.new('admin?' => true, flipper_id: 'User;admin')

  test 'forwards the agents table page to its lazy tab' do
    get :index, params: { section: 'agents', page: '14' }, session: { user: ADMIN }

    assert_response :success
    assert_select 'turbo-frame#agents-list[src=?]', '/admin/agents?page=14'
  end
end
