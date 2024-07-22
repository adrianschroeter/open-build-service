require 'browser_helper'

RSpec.describe 'Requests Index' do
  let(:submitter) { create(:confirmed_user, login: 'kugelblitz') }
  let(:receiver) { create(:confirmed_user, login: 'titan') }
  let(:target_project) { create(:project_with_package, package_name: 'goal', maintainer: receiver) }
  let(:source_project) { create(:project_with_package, package_name: 'ball', maintainer: submitter) }
  let(:other_source_project) { create(:project_with_package, package_name: 'package_2', maintainer: submitter) }

  let!(:incoming_request) do
    create(:bs_request_with_submit_action, description: 'Please take this',
                                           creator: submitter,
                                           source_package: source_project.packages.first,
                                           target_project: target_project)
  end

  let!(:other_incoming_request) do
    create(:bs_request_with_submit_action, description: 'This is very important',
                                           creator: submitter,
                                           source_package: other_source_project.packages.first,
                                           target_project: target_project)
  end

  let!(:outgoing_request) do
    create(:bs_request_with_submit_action, description: 'How about this?',
                                           creator: receiver,
                                           source_package: source_project.packages.first,
                                           target_project: other_source_project)
  end

  before do
    Flipper.enable(:request_index)
    login receiver
    visit requests_path
  end

  it 'lists all requests by default' do
    expect(page).to have_link(href: "/request/show/#{incoming_request.number}")
    expect(page).to have_link(href: "/request/show/#{other_incoming_request.number}")
    expect(page).to have_link(href: "/request/show/#{outgoing_request.number}")
  end

  it 'filters incoming requests' do
    find_by_id('requests-dropdown-trigger').click if mobile? # open the filter dropdown
    choose('Incoming')

    expect(page).to have_link(href: "/request/show/#{incoming_request.number}")
    expect(page).to have_link(href: "/request/show/#{other_incoming_request.number}")
    expect(page).to have_no_link(href: "/request/show/#{outgoing_request.number}")
  end

  it 'filters outgoing requests' do
    find_by_id('requests-dropdown-trigger').click if mobile? # open the filter dropdown
    choose('Outgoing')

    expect(page).to have_link(href: "/request/show/#{outgoing_request.number}")
    expect(page).to have_no_link(href: "/request/show/#{incoming_request.number}")
    expect(page).to have_no_link(href: "/request/show/#{other_incoming_request.number}")
  end
end
