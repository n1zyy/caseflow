# frozen_string_literal: true

require "rails_helper"
require "support/intake_helpers"

feature "End Product Correction (EP 930)" do
  include IntakeHelpers

  let!(:current_user) do
    User.authenticate!(roles: ["Mail Intake"])
  end

  let(:veteran) do
    create(:veteran,
           first_name: "Ed",
           last_name: "Merica")
  end

  let(:benefit_type) { "compensation" }
  let(:receipt_date) { Time.zone.today - 20 }
  let(:promulgation_date) { receipt_date - 2.days }
  let(:profile_date) { promulgation_date.to_datetime }
  let(:ep_code) { "030HLRR" }

  let(:cleared_end_product) do
    Generators::EndProduct.build(
      veteran_file_number: veteran.file_number,
      bgs_attrs: { status_type_code: "CLR" }
    )
  end

  let(:cleared_end_product_establishment) do
    create(:end_product_establishment,
           source: claim_review,
           synced_status: "CLR",
           code: ep_code,
           reference_id: cleared_end_product.claim_id)
  end

  let!(:rating) do
    Generators::Rating.build(
      participant_id: veteran.participant_id,
      promulgation_date: promulgation_date,
      profile_date: profile_date,
      issues: [
        { reference_id: "abc123", decision_text: "Left knee granted" },
        { reference_id: "def456", decision_text: "PTSD denied" },
        { reference_id: "abcdef", decision_text: "Back pain" }
      ]
    )
  end

  let!(:cleared_request_issue) do
    create(
      :request_issue,
      decision_review: claim_review,
      contested_rating_issue_reference_id: "def456",
      decision_date: promulgation_date,
      contested_rating_issue_profile_date: profile_date,
      contested_issue_description: "PTSD denied",
      end_product_establishment: cleared_end_product_establishment
    )
  end

  feature "with cleared end product on higher level review" do
    let(:claim_review_type) { "higher_level_review" }
    let!(:claim_review) do
      create(claim_review_type.to_sym, veteran_file_number: veteran.file_number, receipt_date: receipt_date)
    end
    let(:edit_path) { "#{claim_review_type.pluralize}/#{cleared_end_product.claim_id}/edit" }
    let(:ep_code) { "030HLRR" }

    it "edits are prevented if correct claim reviews feature is not enabled" do
      visit edit_path
      check_page_not_editable(claim_review_type)
    end

    context "when correct claim reviews feature is enabled" do
      before { enable_features }
      after { disable_features }

      context "when a user corrects an existing issue" do
        it "creates a correction issue and EP, and closes the existing issue with no decision" do
          visit edit_path
          correct_existing_request_issue
        end
      end

      context "when a user adds a rating issue" do
        it "creates a correction issue and EP" do
          visit edit_path
          check_adding_rating_correction_issue
        end
      end

      context "when a user adds a nonrating issue" do
        let(:ep_code) { "030HLRNR" }

        it "creates a correction issue and EP" do
          visit edit_path
          check_adding_nonrating_correction_issue
        end
      end

      context "when a user adds an unidentified issue" do
        it "creates a correction issue and EP" do
          visit edit_path
          check_adding_unidentified_correction_issue
        end
      end
    end
  end

  feature "with cleared end product on supplemental claim" do
    let(:claim_review_type) { "supplemental_claim" }
    let!(:claim_review) do
      create(claim_review_type.to_sym, veteran_file_number: veteran.file_number, receipt_date: receipt_date)
    end
    let(:edit_path) { "#{claim_review_type.pluralize}/#{cleared_end_product.claim_id}/edit" }
    let(:ep_code) { "040SCR" }

    it "edits are prevented if correct claim reviews feature is not enabled" do
      visit edit_path
      check_page_not_editable(claim_review_type)
    end

    context "when correct claim reviews feature is enabled" do
      before { enable_features }
      after { disable_features }

      context "when a user corrects an existing issue" do
        it "creates a correction issue and EP, and closes the existing issue with no decision" do
          visit edit_path
          correct_existing_request_issue
        end
      end

      context "when a user adds a rating issue" do
        it "creates a correction issue and EP" do
          visit edit_path
          check_adding_rating_correction_issue
        end
      end

      context "when a user adds a nonrating issue" do
        let(:ep_code) { "040SCNR" }

        it "creates a correction issue and EP" do
          visit edit_path
          check_adding_nonrating_correction_issue
        end
      end

      context "when a user adds an unidentified issue" do
        it "creates a correction issue and EP" do
          visit edit_path
          check_adding_unidentified_correction_issue
        end
      end
    end
  end
end

def check_page_not_editable(type)
  expect(page).to have_current_path("/#{type}s/#{cleared_end_product.claim_id}/edit/cleared_eps")
  expect(page).to have_content("Issues Not Editable")
  expect(page).to have_content(Constants.INTAKE_FORM_NAMES.send(type))
end

def correct_existing_request_issue
  click_correct_intake_issue_dropdown("PTSD denied")
  click_edit_submit
  confirm_930_modal
end

def visit_edit_page(type)
  visit "#{type}/#{cleared_end_product.claim_id}/edit/"
  expect(page).to have_content("Edit Issues")
  expect(page).to have_content("Cleared, waiting for decision")
end

def check_adding_rating_correction_issue
  click_intake_add_issue
  add_intake_rating_issue("Left knee granted")
  click_edit_submit
  safe_click ".confirm"
  confirm_930_modal
end

def check_adding_nonrating_correction_issue
  click_intake_add_issue
  click_intake_no_matching_issues
  add_intake_nonrating_issue(date: promulgation_date.mdY)
  click_edit_submit
  safe_click ".confirm"
  confirm_930_modal
end

def check_adding_unidentified_correction_issue
  click_intake_add_issue
  add_intake_unidentified_issue
  click_edit_submit
  safe_click "#Unidentified-issue-button-id-1"
  safe_click ".confirm"
  confirm_930_modal
end

def confirm_930_modal
  expect(page).to have_content("You are now creating a 930 EP in VBMS")
  click_button("Yes, establish")
  expect(page).to have_content("Claim Issues Saved")
end

def enable_features
  FeatureToggle.enable!(:correct_claim_reviews)
  FeatureToggle.enable!(:withdraw_decision_review)
end

def disable_features
  FeatureToggle.disable!(:correct_claim_reviews)
  FeatureToggle.disable!(:withdraw_decision_review)
end
