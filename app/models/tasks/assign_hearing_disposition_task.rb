# frozen_string_literal: true

##
# Task assigned to the BvaOrganization after a hearing is scheduled, created after the ScheduleHearingTask
# is completed.
#
# When the associated hearing's disposition is set, the appropriate tasks are set as children
#   - held: For legacy, task is set to be completed; for AMA, TranscriptionTask is created as child and
#         EvidenceSubmissionWindowTask is also created as child unless the veteran/appellant has waived
#         the 90 day evidence hold
#   - Cancelled: Task is cancelled and EvidenceWindowSubmissionWindow task is created as a child of RootTask
#   - No show: NoShowHearingTask is created as a child of this task
#   - Postponed: 2 options: Schedule new hearing or cancel HearingTask tree and create new ScheduleHearingTask
#
# The task is marked complete when the children tasks are completed.

class AssignHearingDispositionTask < Task
  include RunAsyncable

  validates :parent, presence: true
  before_create :check_parent_type
  delegate :hearing, to: :hearing_task, allow_nil: true

  class HearingDispositionNotCanceled < StandardError; end
  class HearingDispositionNotPostponed < StandardError; end
  class HearingDispositionNotNoShow < StandardError; end
  class HearingDispositionNotHeld < StandardError; end
  class HearingAssociationMissing < StandardError
    def initialize(hearing_task_id)
      super(format(COPY::HEARING_TASK_ASSOCIATION_MISSING_MESASAGE, hearing_task_id))
    end
  end

  class << self
    def create_assign_hearing_disposition_task!(appeal, parent, hearing)
      assign_hearing_disposition_task = create!(
        appeal: appeal,
        parent: parent,
        assigned_to: Bva.singleton
      )

      HearingTaskAssociation.create!(hearing: hearing, hearing_task: parent)

      assign_hearing_disposition_task
    end
  end

  def self.label
    "Select hearing disposition"
  end

  def default_instructions
    [COPY::ASSIGN_HEARING_DISPOSITION_TASK_DEFAULT_INSTRUCTIONS]
  end

  def hearing_task
    @hearing_task ||= parent
  end

  def available_actions(user)
    hearing_admin_actions = available_hearing_user_actions(user)

    if HearingsManagement.singleton.user_has_access?(user)
      [Constants.TASK_ACTIONS.POSTPONE_HEARING.to_h] | hearing_admin_actions
    else
      hearing_admin_actions
    end
  end

  def update_from_params(params, user)
    payload_values = params.delete(:business_payloads)&.dig(:values)

    if params[:status] == Constants.TASK_STATUSES.cancelled && payload_values[:disposition].present?
      created_tasks = update_hearing_and_self(params: params, payload_values: payload_values)

      [self] + created_tasks
    else
      super(params, user)
    end
  end

  def cancel!
    if hearing&.disposition != Constants.HEARING_DISPOSITION_TYPES.cancelled
      fail HearingDispositionNotCanceled
    end

    evidence_task = if appeal.is_a? Appeal
                      EvidenceSubmissionWindowTask.find_or_create_by!(
                        appeal: appeal,
                        parent: hearing_task.parent,
                        assigned_to: MailTeam.singleton
                      )
                    end

    update!(status: Constants.TASK_STATUSES.cancelled, closed_at: Time.zone.now)

    [evidence_task].compact
  end

  def postpone!
    if hearing&.disposition != Constants.HEARING_DISPOSITION_TYPES.postponed
      fail HearingDispositionNotPostponed
    end

    schedule_later
  end

  def no_show!
    if hearing&.disposition != Constants.HEARING_DISPOSITION_TYPES.no_show
      fail HearingDispositionNotNoShow
    end

    [NoShowHearingTask.create_with_hold(self)]
  end

  def hold!
    if hearing&.disposition != Constants.HEARING_DISPOSITION_TYPES.held
      fail HearingDispositionNotHeld
    end

    if appeal.is_a?(LegacyAppeal)
      update!(status: Constants.TASK_STATUSES.completed)

      [] # Not creating any tasks, just updating self
    else
      create_transcription_and_maybe_evidence_submission_window_tasks
    end
  end

  private

  def clean_up_virtual_hearing
    if hearing.virtual?
      perform_later_or_now(VirtualHearings::DeleteConferencesJob)
    end
  end

  def update_children_status_after_closed
    update_args = { status: status }
    update_args[:closed_at] = Time.zone.now unless open?
    update_args[:cancelled_by_id] = RequestStore[:current_user]&.id if cancelled?
    children.open.update_all(update_args)
  end

  def cascade_closure_from_child_task?(_child_task)
    true
  end

  def update_hearing_and_self(params:, payload_values:)
    created_tasks = case payload_values[:disposition]
                    when Constants.HEARING_DISPOSITION_TYPES.cancelled
                      mark_hearing_cancelled
                    when Constants.HEARING_DISPOSITION_TYPES.held
                      mark_hearing_held
                    when Constants.HEARING_DISPOSITION_TYPES.no_show
                      mark_hearing_no_show
                    when Constants.HEARING_DISPOSITION_TYPES.postponed
                      mark_hearing_postponed(
                        instructions: params["instructions"],
                        after_disposition_update: payload_values[:after_disposition_update]
                      )
                    else
                      fail ArgumentError, "unknown disposition"
                    end

    update_with_instructions(instructions: params[:instructions]) if params[:instructions].present?

    created_tasks
  end

  def update_hearing_disposition(disposition:)
    # Ensure the hearing exists
    fail HearingAssociationMissing, hearing_task&.id if hearing.nil?

    if hearing.is_a?(LegacyHearing)
      hearing.update_caseflow_and_vacols(disposition: disposition)
    else
      hearing.update(disposition: disposition)
    end
  end

  def check_parent_type
    if parent.type != HearingTask.name
      fail(
        Caseflow::Error::InvalidParentTask,
        task_type: self.class.name,
        assignee_type: assigned_to.class.name
      )
    end
  end

  def reschedule(hearing_day_id:, scheduled_time_string:, hearing_location: nil, virtual_hearing_attributes: nil)
    multi_transaction do
      new_hearing_task = hearing_task.cancel_and_recreate

      new_hearing = HearingRepository.slot_new_hearing(hearing_day_id,
                                                       appeal: appeal,
                                                       hearing_location_attrs: hearing_location&.to_hash,
                                                       scheduled_time_string: scheduled_time_string)
      if virtual_hearing_attributes.present?
        @alerts = VirtualHearings::ConvertToVirtualHearingService
          .convert_hearing_to_virtual(new_hearing, virtual_hearing_attributes)
      end

      [new_hearing_task, self.class.create_assign_hearing_disposition_task!(appeal, new_hearing_task, new_hearing)]
    end
  end

  def mark_hearing_cancelled
    multi_transaction do
      update_hearing_disposition(disposition: Constants.HEARING_DISPOSITION_TYPES.cancelled)
      clean_up_virtual_hearing
      cancel!
    end
  end

  def mark_hearing_held
    multi_transaction do
      update_hearing_disposition(disposition: Constants.HEARING_DISPOSITION_TYPES.held)
      hold!
    end
  end

  def mark_hearing_no_show
    multi_transaction do
      update_hearing_disposition(disposition: Constants.HEARING_DISPOSITION_TYPES.no_show)
      no_show!
    end
  end

  def mark_hearing_postponed(instructions: nil, after_disposition_update: nil)
    multi_transaction do
      update_hearing_disposition(disposition: Constants.HEARING_DISPOSITION_TYPES.postponed)
      clean_up_virtual_hearing
      reschedule_or_schedule_later(instructions: instructions, after_disposition_update: after_disposition_update)
    end
  end

  def reschedule_or_schedule_later(instructions: nil, after_disposition_update:)
    case after_disposition_update[:action]
    when "reschedule"
      new_hearing_attrs = after_disposition_update[:new_hearing_attrs]
      reschedule(
        hearing_day_id: new_hearing_attrs[:hearing_day_id],
        scheduled_time_string: new_hearing_attrs[:scheduled_time_string],
        hearing_location: new_hearing_attrs[:hearing_location],
        virtual_hearing_attributes: new_hearing_attrs[:virtual_hearing_attributes]
      )
    when "schedule_later"
      schedule_later(
        instructions: instructions,
        with_admin_action_klass: after_disposition_update[:with_admin_action_klass],
        admin_action_instructions: after_disposition_update[:admin_action_instructions]
      )
    else
      fail ArgumentError, "unknown disposition action"
    end
  end

  def schedule_later(instructions: nil, with_admin_action_klass: nil, admin_action_instructions: nil)
    new_hearing_task = hearing_task.cancel_and_recreate

    schedule_task = ScheduleHearingTask.create!(
      appeal: appeal,
      instructions: instructions.present? ? [instructions] : nil,
      parent: new_hearing_task
    )
    admin_action_task = if with_admin_action_klass.present?
                          with_admin_action_klass.constantize.create!(
                            appeal: appeal,
                            assigned_to: HearingsManagement.singleton,
                            instructions: admin_action_instructions.present? ? [admin_action_instructions] : nil,
                            parent: schedule_task
                          )
                        end

    [new_hearing_task, schedule_task, admin_action_task].compact
  end

  def create_transcription_and_maybe_evidence_submission_window_tasks
    transcription_task = TranscriptionTask.create!(
      appeal: appeal,
      parent: self,
      assigned_to: TranscriptionTeam.singleton
    )

    evidence_task = unless hearing&.evidence_window_waived
                      EvidenceSubmissionWindowTask.create!(
                        appeal: appeal,
                        parent: self,
                        assigned_to: MailTeam.singleton
                      )
                    end

    [transcription_task, evidence_task].compact
  end
end
