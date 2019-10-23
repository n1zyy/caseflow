# frozen_string_literal: true

class VisualizationTaskSerializer
  include FastJsonapi::ObjectSerializer

  attribute :assigned_at
  attribute :started_at
  attribute :placed_on_hold_at
  attribute :closed_at

  attribute :type

  attribute :assigned_to_css_id do |object|
    object.assigned_to.css_id
  end

  attribute :appeal_receipt_date do |object|
    (object.appeal_type == LegacyAppeal.name) ? nil : object.appeal.receipt_date
  end
end
