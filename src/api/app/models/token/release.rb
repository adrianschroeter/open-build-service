class Token::Release < Token
  # FIXME: refactor this out of the helper to get access to the method release_package
  include MaintenanceHelper

  def self.token_name
    'release'
  end

  def call(_options)
    # release from remote is not supported
    raise ActiveRecord::RecordNotFound if package_from_association_or_params.nil?
    manual_release_targets = package_from_association_or_params.project.release_targets.where(trigger: 'manual')
    raise NoReleaseTargetFound, "#{package_from_association_or_params.project} has no release targets that are triggered manually" unless manual_release_targets.any?

    manual_release_targets.each do |release_target|
      opts = { filter_source_repository: release_target.repository,
                        manual: true,
                        comment: 'Releasing via trigger event' }
      opts[:multibuild_container] = package_name.gsub(/.*:/, '') if package_name.include?(':')
      release_package(package_name,
                      release_target.target_repository,
                      package_from_association_or_params.release_target_name,
		      opts)
    end
  end

  def package_find_options
    { use_source: true, follow_project_links: false, follow_multibuild: false }
  end
end

# == Schema Information
#
# Table name: tokens
#
#  id         :integer          not null, primary key
#  string     :string(255)      indexed
#  type       :string(255)
#  package_id :integer          indexed
#  user_id    :integer          not null, indexed
#
# Indexes
#
#  index_tokens_on_string  (string) UNIQUE
#  package_id              (package_id)
#  user_id                 (user_id)
#
# Foreign Keys
#
#  tokens_ibfk_1  (user_id => users.id)
#  tokens_ibfk_2  (package_id => packages.id)
#
