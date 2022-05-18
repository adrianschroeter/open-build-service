module Event
  class CreateProject < Base
    self.message_bus_routing_key = 'project.create'
    self.description = 'Project is created'
    payload_keys :project, :sender

    def subject
      "New Project #{payload['project']}"
    end

    private

    def metric_tags
      { home: ::Project.home?(payload['project']) }
    end

    def metric_fields
      { value: 1 }
    end
  end
end

# == Schema Information
#
# Table name: events
#
#  id          :bigint           not null, primary key
#  eventtype   :string(255)      not null, indexed
#  mails_sent  :boolean          default(FALSE), indexed
#  payload     :text(65535)
#  undone_jobs :integer          default(0)
#  created_at  :datetime         indexed
#  updated_at  :datetime
#
# Indexes
#
#  index_events_on_created_at  (created_at)
#  index_events_on_eventtype   (eventtype)
#  index_events_on_mails_sent  (mails_sent)
#
