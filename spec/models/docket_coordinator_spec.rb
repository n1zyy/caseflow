# frozen_string_literal: true

describe DocketCoordinator do
  describe "direct review docket pace setting" do
    before do
      FeatureToggle.enable!(:test_facols)
      Timecop.freeze(Time.utc(2020, 4, 1, 12, 0, 0))

      4.times do
        team = JudgeTeam.create_for_judge(create(:user))
        create_list(:user, 5).each do |attorney|
          team.add_user(attorney)
        end
      end

      allow_any_instance_of(DirectReviewDocket)
        .to receive(:nonpriority_receipts_per_year)
        .and_return(nonpriority_receipts_per_year)

      allow(Docket)
        .to receive(:nonpriority_decisions_per_year)
        .and_return(nonpriority_decisions_per_year)
    end

    after do
      FeatureToggle.disable!(:test_facols)
      Timecop.return
    end

    let(:nonpriority_receipts_per_year) { 100 }
    let(:nonpriority_decisions_per_year) { 1000 }

    let(:docket_coordinator) { DocketCoordinator.new }

    let(:priority_case_count) { 10 }
    let!(:priority_cases) do
      (0...priority_case_count).map do |i|
        create(
          :case,
          :aod,
          bfd19: 2.years.ago,
          bfac: "1",
          bfmpro: "ACT",
          bfcurloc: "81",
          bfdloout: i.days.ago,
          folder: build(
            :folder,
            tinum: "1801#{format('%<index>03d', index: i)}",
            titrnum: "123456789S"
          )
        )
      end
    end

    let(:nonpriority_legacy_count) { 10 }
    let!(:nonpriority_legacy_cases) do
      (0...nonpriority_legacy_count).map do |i|
        create(
          :case,
          bfd19: 3.years.ago,
          bfac: "1",
          bfmpro: "ACT",
          bfcurloc: "81",
          bfdloout: i.days.ago,
          folder: build(
            :folder,
            tinum: "1701#{format('%<index>03d', index: i)}",
            titrnum: "123456789S"
          )
        )
      end
    end

    let(:due_direct_review_count) { 10 }
    let!(:due_direct_review_cases) do
      (0...due_direct_review_count).map do
        create(
          :appeal,
          :with_post_intake_tasks,
          docket_type: Constants.AMA_DOCKETS.direct_review,
          receipt_date: 11.months.ago,
          target_decision_date: 1.month.from_now
        )
      end
    end

    let(:days_before_goal_due) { DirectReviewDocket::DAYS_BEFORE_GOAL_DUE_FOR_DISTRIBUTION }
    let(:days_to_decision_goal) { DirectReviewDocket::DAYS_TO_DECISION_GOAL }

    let!(:other_direct_review_cases) do
      (0...10).map do
        create(
          :appeal,
          :with_post_intake_tasks,
          docket_type: Constants.AMA_DOCKETS.direct_review,
          receipt_date: (days_before_goal_due + 1).days.ago,
          target_decision_date: (days_to_decision_goal - days_before_goal_due + 35).days.from_now
        )
      end
    end

    let(:other_docket_count) { 5 }

    let!(:evidence_submission_cases) do
      (0...other_docket_count).map do
        create(
          :appeal,
          :with_post_intake_tasks,
          docket_type: Constants.AMA_DOCKETS.evidence_submission
        )
      end
    end

    let!(:hearing_cases) do
      (0...other_docket_count).map do
        create(
          :appeal,
          :with_post_intake_tasks,
          docket_type: Constants.AMA_DOCKETS.hearing
        )
      end
    end

    context "when there are due direct reviews" do
      it "uses the number of due direct reviews as a proportion of the docket margin net of priority" do
        expect(docket_coordinator.docket_proportions).to eq(
          legacy: 0.4,
          direct_review: 0.2,
          evidence_submission: 0.2,
          hearing: 0.2
        )
        expect(docket_coordinator.pacesetting_direct_review_proportion).to eq(0.1)
        expect(docket_coordinator.interpolated_minimum_direct_review_proportion).to eq(0.067)
        expect(docket_coordinator.target_number_of_ama_hearings(2.years)).to eq(400)
      end

      context "with appeals that have already been marked in range" do
        let(:appeals_count) { docket_coordinator.dockets[:hearing].appeals.count }
        let(:number_of_appeals_in_range) { 2 }

        before do
          docket_coordinator.dockets[:hearing]
            .appeals
            .limit(number_of_appeals_in_range)
            .update(docket_range_date: Time.utc(2019, 1, 1))
        end

        it "returns appeals that have not been marked in range" do
          expect(
            docket_coordinator
              .upcoming_appeals_in_range(2.years, Time.utc(2019, 1, 1))
              .pluck(:id)
              .count
          )
            .to eq(other_docket_count)
        end
      end

      context "when the direct review proportion would exceed 80%" do
        let(:due_direct_review_count) { 170 }

        it "caps the percentage at 80%" do
          expect(docket_coordinator.docket_proportions).to include(
            legacy: 0.1,
            direct_review: 0.8
          )
        end
      end

      context "when the legacy proportion would dip below 10%" do
        let(:priority_case_count) { 0 }
        let(:due_direct_review_count) { 60 }
        let(:nonpriority_legacy_count) { 12 }
        let(:other_docket_count) { 12 }

        it "ensures a minimum of 10%" do
          expect(docket_coordinator.docket_proportions).to include(
            legacy: 0.1,
            direct_review: 0.8
          )
        end

        context "unless there aren't that many cases" do
          let(:nonpriority_legacy_count) { 3 }

          it "uses the maximum number possible" do
            expect(docket_coordinator.docket_proportions).to include(
              legacy: 0.05,
              direct_review: 0.8
            )
          end
        end
      end
    end

    context "when there are no due direct reviews" do
      let(:due_direct_review_count) { 0 }
      let(:nonpriority_receipts_per_year) { 1000 }
      let(:nonpriority_decisions_per_year) { 1340 }
      let(:nonpriority_legacy_count) { 80 }

      it "uses the pacesetting direct review proportion" do
        expect(docket_coordinator.docket_proportions).to include(
          legacy: 0.8,
          evidence_submission: 0.05,
          hearing: 0.05
        )
        expect(docket_coordinator.interpolated_minimum_direct_review_proportion).to be_within(0.001).of(0.1)
      end
    end
  end

  shared_examples "correct priority count" do
    let(:judge) { create(:user, :with_vacols_judge_record) }

    let(:tied_legacy_case_count) { 5 }
    let(:genpop_legacy_case_count) { 4 }
    let(:tied_ama_hearing_case_count) { 3 }
    let(:genpop_ama_hearing_case_count) { 2 }
    let(:genpop_direct_case_count) { 2 }
    let(:genpop_evidence_case_count) { 2 }

    let(:genpop_priority_cases_count) do
      genpop_legacy_case_count + genpop_ama_hearing_case_count + genpop_direct_case_count + genpop_evidence_case_count
    end
    let(:all_priority_cases_count) do
      genpop_priority_cases_count + tied_legacy_case_count + tied_ama_hearing_case_count
    end

    before do
      tied_legacy_case_count.times { create(:case, :aod, :ready_for_distribution, :tied_to_judge, tied_judge: judge) }
      genpop_legacy_case_count.times { create(:case, :aod, :ready_for_distribution) }
      tied_ama_hearing_case_count.times do
        create(
          :appeal,
          :hearing_docket,
          :ready_for_distribution,
          :advanced_on_docket_due_to_age,
          :held_hearing,
          :tied_to_judge,
          tied_judge: judge,
          adding_user: judge
        )
      end
      genpop_ama_hearing_case_count.times do
        create(
          :appeal,
          :hearing_docket,
          :ready_for_distribution,
          :advanced_on_docket_due_to_age,
          :held_hearing,
          adding_user: judge
        )
      end
      genpop_direct_case_count.times do
        create(:appeal, :direct_review_docket, :ready_for_distribution, :advanced_on_docket_due_to_age)
      end
      genpop_evidence_case_count.times do
        create(:appeal, :evidence_submission_docket, :ready_for_distribution, :advanced_on_docket_due_to_age)
      end
    end

    it "returns the count of all priority cases that are ready to be distributed" do
      expect(subject).to eq expected_priority_count
    end
  end

  describe "#priority_count" do
    subject { DocketCoordinator.new.priority_count }

    let(:expected_priority_count) { all_priority_cases_count }

    it_behaves_like "correct priority count"
  end

  describe "#genpop_priority_count" do
    subject { DocketCoordinator.new.genpop_priority_count }

    let(:expected_priority_count) { genpop_priority_cases_count }

    it_behaves_like "correct priority count"
  end
end
