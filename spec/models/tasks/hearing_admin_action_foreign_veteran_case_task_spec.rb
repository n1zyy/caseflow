# frozen_string_literal: true

require "rails_helper"

RSpec.feature HearingAdminActionForeignVeteranCaseTask do
  let!(:veteran) { create(:veteran) }
  let!(:appeal) { create(:appeal, veteran: veteran) }
  let(:root_task) { create(:root_task, appeal: appeal) }
  let(:distribution_task) { create(:distribution_task, parent: root_task, appeal: appeal) }
  let(:parent_hearing_task) { create(:hearing_task, parent: distribution_task, appeal: appeal) }
  let!(:schedule_hearing_task) { create(:schedule_hearing_task, parent: parent_hearing_task, appeal: appeal) }
  let!(:foreign_veteran_case_task) do
    HearingAdminActionForeignVeteranCaseTask.create!(
      appeal: appeal,
      parent: schedule_hearing_task,
      assigned_to: HearingsManagement.singleton,
      assigned_to_type: "Organization"
    )
  end
  let!(:user) { create(:user) }
  let!(:instructions_text) { "Instructions for the Schedule Hearing Task!" }

  context "as a hearing user" do
    before do
      OrganizationsUser.add_user_to_organization(user, HearingsManagement.singleton)

      RequestStore[:current_user] = user
    end

    it "has cancel, hold, and send to schedule veteran list actions" do
      available_actions = foreign_veteran_case_task.available_actions(user)

      expect(available_actions.length).to eq 3
      expect(available_actions).to include(
        Constants.TASK_ACTIONS.CANCEL_FOREIGN_VETERANS_CASE_TASK.to_h,
        Constants.TASK_ACTIONS.PLACE_TIMED_HOLD.to_h,
        Constants.TASK_ACTIONS.SEND_TO_SCHEDULE_VETERAN_LIST.to_h
      )
    end
  end

  context "after update" do
    let!(:regional_office_code) { "RO50"}

    before do
      OrganizationsUser.add_user_to_organization(user, HearingsManagement.singleton)

      RequestStore[:current_user] = user

      payload = {
        "status": Constants.TASK_STATUSES.completed,
        "instructions": instructions_text,
        "business_payloads": {
          "values": {
            "regional_office_value": regional_office_code
          }
        }
      }

      foreign_veteran_case_task.update_from_params(payload, user)
    end

    it "updates status code to completed" do
      expect(foreign_veteran_case_task.status).to eq Constants.TASK_STATUSES.completed
    end

    it "updates instructions on parent schedule hearing task" do
      expect(schedule_hearing_task.instructions.size).to eq 1
      expect(schedule_hearing_task.instructions[0]).to eq instructions_text
    end

    it "update RO on appeal" do
      expect(appeal.closest_regional_office).to eq regional_office_code
    end
  end

  context "UI tests" do
    before do
      OrganizationsUser.add_user_to_organization(user, HearingsManagement.singleton)

      User.authenticate!(user: user)
    end

    context "on queue appeal page" do
      before do
        visit("/queue/appeals/#{appeal.uuid}")
      end

      it "has foreign veteran task" do
        expect(page).to have_content(foreign_veteran_case_task.label)
      end

      it "has 'Send to Schedule Veterans list' action" do
        click_dropdown(text: Constants.TASK_ACTIONS.SEND_TO_SCHEDULE_VETERAN_LIST.label)
      end

      context "in 'Send to Schedule Veterans list' modal" do
        before do
          click_dropdown(text: Constants.TASK_ACTIONS.SEND_TO_SCHEDULE_VETERAN_LIST.label)
        end

        it "has Regional Office dropdown and notes field" do
          expect(page).to have_field("regionalOffice")
          expect(page).to have_field("notes")
        end

        it "can't submit form without specifying a Regional Office" do
          click_button("Confirm")

          expect(page).to have_content COPY::REGIONAL_OFFICE_REQUIRED_MESSAGE
        end

        it "can submit form with Regional Office and no notes" do
          click_dropdown(text: "St. Petersburg, FL")

          click_button("Confirm")

          expect(page).to have_content COPY::SEND_TO_SCHEDULE_VETERAN_LIST_MESSAGE_TITLE
        end

        it "can submit form with Regional Office and notes" do
          click_dropdown(text: "St. Petersburg, FL")
          fill_in("Notes", with: instructions_text)

          click_button("Confirm")

          expect(page).to have_content COPY::SEND_TO_SCHEDULE_VETERAN_LIST_MESSAGE_TITLE
        end
      end

      context "submitted 'Send to Schedule Veterans list' with notes" do
        let!(:user) { create(:user, roles: ["Build HearSched"]) }

        before do
          click_dropdown(text: Constants.TASK_ACTIONS.SEND_TO_SCHEDULE_VETERAN_LIST.label)

          click_dropdown(text: "St. Petersburg, FL")
          fill_in("Notes", with: instructions_text)

          click_button("Confirm")
        end

        it "has notes in schedule hearing task instructions" do
          expect(page).to have_content COPY::TASK_SNAPSHOT_VIEW_TASK_INSTRUCTIONS_LABEL

          click_button(COPY::TASK_SNAPSHOT_VIEW_TASK_INSTRUCTIONS_LABEL)

          expect(page).to have_content instructions_text
        end

        it "case shows up in schedule veterans list" do
          allow(HearingDay).to receive(:load_days).and_return([create(:hearing_day)])

          visit("/hearings/schedule/assign?roValue=RO17")

          click_button("AMA Veterans Waiting")

          expect(page).to have_content appeal.veteran_file_number
        end
      end
    end
  end
end