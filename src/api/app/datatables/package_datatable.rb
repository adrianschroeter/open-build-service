# NOTE: Folowing: https://github.com/jbox-web/ajax-datatables-rails#using-view-helpers
class PackageDatatable < Datatable
  def_delegator :@view, :link_to
  def_delegator :@view, :package_show_path
  def_delegator :@view, :time_ago_in_words
  def_delegator :@view, :tag
  def_delegator :@view, :safe_join

  def initialize(params, opts = {})
    @project = opts[:project]
    super
  end

  def view_columns
    # Declare strings in this format: ModelName.column_name
    # or in aliased_join_table.column_name format
    @view_columns ||= {
      name: { source: 'Package.name' },
      labels: { source: 'Package.labels' },
      changed: { source: 'Package.updated_at', searchable: false }
    }
  end

  # rubocop:disable Naming/AccessorMethodName
  def get_raw_records
    @project.packages
  end
  # rubocop:enable Naming/AccessorMethodName

  def data
    records.eager_load(:package_kinds).select("packages.*, bit_or(kind = 'link') AS kind_link").group('packages.id').map do |record|
      {
        name: name_with_link(record),
        labels: labels_list(record.labels),
        changed: format('%{duration} ago',
                        duration: time_ago_in_words(Time.at(record.updated_at.to_i)))
      }
    end
  end

  def name_with_link(record)
    name = []
    name << link_to(record.name, package_show_path(package: record, project: @project))
    name << tag.span('Link', class: 'badge text-bg-info') if record.kind_link == 1
    safe_join(name, ' ')
  end

  def labels_list(labels)
    return nil unless labels.any?

    list = labels.map { |label| tag.span(label.name, class: "badge label-#{label.id}") }
    safe_join(list, ' ')
  end
end
