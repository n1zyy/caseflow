# frozen_string_literal: true

class ColocatedTaskDistributor < RoundRobinTaskDistributor
  def initialize(assignee_pool: Colocated.singleton.non_admins.sort_by(&:id),
                 task_class: Task)
    super
  end

  def next_assignee(options = {})
    open_assignee = options.dig(:appeal)
      &.tasks
      &.open
      &.find_by(assigned_to: assignee_pool)
      &.assigned_to

    log_state(invoker: "colocated", existing_assignee: open_assignee, appeal: options.dig(:appeal))

    open_assignee || super()
  end
end
