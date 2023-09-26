require 'rails_helper'
require 'webmock/rspec'

RSpec.describe Webui::Packages::BuildReasonController do
  describe 'GET #index' do
    let(:user) { create(:confirmed_user, :with_home, login: 'tom') }
    let(:project) { user.home_project }
    let(:package) { create(:package, name: 'package', project: project) }
    let(:repository) { create(:repository, project: project, architectures: ['i586']) }
    let(:valid_request_params) do
      {
        package_name: package.name,
        project: project.name,
        repository: repository.name,
        arch: repository.architectures.first.name
      }
    end

    context 'without a valid respository' do
      before do
        get :index, params: { package_name: package, project: project, repository: 'fake_repo', arch: 'i586' }
      end

      it { expect(flash[:error]).not_to be_empty }

      it {
        expect(response).to redirect_to(project_package_repository_binaries_path(package_name: package, project_name: project,
                                                                                 repository_name: 'fake_repo'))
      }
    end

    context 'without a valid architecture' do
      before do
        login(user)
        get :index, params: { package_name: package, project: project, repository: repository.name, arch: 'i58' }
      end

      it { expect(flash[:error]).not_to be_empty }

      it 'redirects to package_binaries_path' do
        expect(response).to redirect_to(project_package_repository_binaries_path(package_name: package,
                                                                                 project_name: project,
                                                                                 repository_name: repository.name))
      end
    end

    context 'for packages without a build reason' do
      before do
        path = "#{CONFIG['source_url']}/build/#{project.name}/#{repository.name}/" \
               "#{repository.architectures.first.name}/#{package.name}/_reason"
        stub_request(:get, path).and_return(body:
        %(<reason>\n <explain/>  <time/>  <oldsource/>  </reason>))

        get :index, params: valid_request_params
      end

      it { expect(flash[:notice]).not_to be_blank }

      it 'redirects to package_binaries_path' do
        expect(response).to redirect_to(project_package_repository_binaries_path(package_name: package,
                                                                                 project_name: project,
                                                                                 repository_name: repository.name))
      end
    end

    context 'for valid requests' do
      before do
        path = "#{CONFIG['source_url']}/build/#{project.name}/#{repository.name}/" \
               "#{repository.architectures.first.name}/#{package.name}/_reason"
        stub_request(:get, path).and_return(body:
        %(<reason>\n  <explain>source change</explain>  <time>1496387771</time>  <oldsource>1de56fdc419ea4282e35bd388285d370</oldsource></reason>))

        get :index, params: valid_request_params
      end

      it 'responds with 200 OK' do
        expect(response).to have_http_status(:success)
      end

      it 'has build reason' do
        expect(assigns(:details)).to be_a(PackageBuildReason)
      end
    end
  end
end
