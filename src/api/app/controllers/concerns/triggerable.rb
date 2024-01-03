module Triggerable
  def set_project
    # By default we operate on the package association
    @project = @token.package.try(:project)
    # If the token has no package, let's find one from the parameters or the step intructions
    @project ||= Project.get_by_name(@project_name)
    # Remote projects are read-only, can't trigger something for them.
    # See https://github.com/openSUSE/open-build-service/wiki/Links#project-links
    raise Project::Errors::UnknownObjectError, "Sorry, triggering tokens for remote project \"#{@project_name}\" is not possible." unless @project.is_a?(Project)
  end

  def set_package(package_find_options: {})
    package_find_options = @token.package_find_options if package_find_options.blank?
    # By default we operate on the package association
    @package = @token.package
    return if @package
    # If the token has no package, let's find one from the parameters
    if @package_name.present?
      @package ||= Package.get_by_project_and_name(@project,
                                                   @package_name,
                                                   package_find_options)
    end
    return if @package
    return unless @project.links_to_remote? || @project.scmsync.present?

    # In remote or scmsync case we have no database object, but the package
    # may still be there. It will get validated by the backend.
    # Strip multibuild part as the code will add it later again in the model
    @package ||= @package_name.gsub(/:.*/, '')
    # TODO: This should not happen right? But who knows...
    raise ActiveRecord::RecordNotFound unless @package
  end

  def set_object_to_authorize
    @token.object_to_authorize = package_from_project_link? ? @project : @package
  end

  def set_multibuild_flavor
    # Do NOT use @package.multibuild_flavor? here because the flavor need to be checked for the right source revision
    @multibuild_container = @package_name.gsub(/.*:/, '') if @package_name.present? && @package_name.include?(':')
  end

  def package_from_project_link?
    # a remote package is always included via project link
    !(@package.is_a?(Package) && @package.project == @project)
  end
end
