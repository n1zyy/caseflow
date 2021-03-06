# frozen_string_literal: true

describe DocketSwitchRulingTask, :postgres do
  let(:task_class) { DocketSwitchRulingTask }
  let(:judge) { create(:user) }
  let(:appeal) { create(:appeal) }

  describe ".additional_available_actions" do
    let(:task) { task_class.create!(appeal: appeal, assigned_to: judge) }

    subject { task.additional_available_actions(judge) }

    context "without docket_change feature toggle" do
      it "returns the available_actions as defined by Task" do
        expect(subject).to eq([])
      end
    end

    context "with docket_change feature toggle" do
      before { FeatureToggle.enable!(:docket_change) }
      after { FeatureToggle.disable!(:docket_change) }

      it "returns the available_actions as defined by Task" do
        expect(subject).to eq([Constants.TASK_ACTIONS.DOCKET_SWITCH_JUDGE_RULING.to_h])
      end
    end
  end
end
