require "rails_helper"

def click_dropdown(opt_idx, container = page)
  dropdown = container.find(".Select-control")
  dropdown.click
  yield if block_given?
  dropdown.sibling(".Select-menu-outer").find("div[id$='--option-#{opt_idx}']").click
end

def generate_text(length)
  charset = ("A".."Z").to_a.concat(("a".."z").to_a)
  Array.new(length) { charset.sample }.join
end

def generate_words(n_words)
  Array.new(n_words).map do
    word_length = [rand(12), 3].max
    generate_text(word_length)
  end.join(" ")
end

RSpec.feature "Checkout flows" do
  let(:attorney_user) { FactoryBot.create(:default_user) }
  let!(:vacols_atty) { FactoryBot.create(:staff, :attorney_role, sdomainid: attorney_user.css_id) }

  let(:judge_user) { FactoryBot.create(:user, station_id: User::BOARD_STATION_ID, full_name: "Aaron Judge") }
  let!(:vacols_judge) { FactoryBot.create(:staff, :judge_role, sdomainid: judge_user.css_id) }

  let(:colocated_user) { FactoryBot.create(:user) }
  let!(:vacols_colocated) { FactoryBot.create(:staff, :colocated_role, sdomainid: colocated_user.css_id) }

  before do
    FeatureToggle.enable!(:test_facols)
  end

  after do
    FeatureToggle.disable!(:test_facols)
  end

  context "given a valid appeal and an attorney user" do
    let!(:appeal) do
      FactoryBot.create(
        :appeal,
        number_of_claimants: 1,
        request_issues: FactoryBot.build_list(:request_issue, 1, description: "Tinnitus")
      )
    end

    before do
      root_task = FactoryBot.create(:root_task)
      parent_task = FactoryBot.create(:ama_judge_task, assigned_to: judge_user, appeal: appeal, parent: root_task)

      FactoryBot.create(
        :ama_attorney_task,
        :in_progress,
        assigned_to: attorney_user,
        assigned_by: judge_user,
        parent: parent_task,
        appeal: appeal
      )

      User.authenticate!(user: attorney_user)
    end

    scenario "submits draft decision" do
      visit "/queue"
      click_on "(#{appeal.veteran_file_number})"
      click_dropdown 0
      click_label "radiation"

      click_on "Continue"

      # Ensure we can reload the flow and the special issue is saved
      click_on "Cancel"
      click_on "Yes, cancel"

      click_dropdown 0

      # Radiation should still be checked
      expect(page).to have_field("radiation", checked: true, visible: false)

      # Radiation should also be marked in the database
      expect(appeal.special_issue_list.radiation).to eq(true)
      click_on "Continue"

      expect(page).to have_content "Select Dispositions"

      issue_rows = page.find_all("tr[id^='table-row-']")
      expect(issue_rows.length).to eq(appeal.request_issues.length)

      issue_rows.each do |row|
        row.find(".Select-control").click
        row.find("div[id$='--option-0']").click
      end

      click_on "Continue"
      expect(page).to have_content("Submit Draft Decision for Review")

      document_id = Array.new(35).map { rand(10) }.join
      fill_in "document_id", with: document_id
      expect(page.find("#document_id").value.length).to eq 30

      fill_in "notes", with: "note"

      safe_click "#select-judge"
      click_dropdown 0

      click_on "Continue"
      sleep 5
      expect(page.current_path).to eq("/queue")
    end
  end

  context "given a valid legacy appeal and an attorney user" do
    let!(:appeal) do
      FactoryBot.create(
        :legacy_appeal,
        :with_veteran,
        vacols_case: FactoryBot.create(
          :case,
          :assigned,
          user: attorney_user,
          case_issues: case_issues
        )
      )
    end

    before { User.authenticate!(user: attorney_user) }

    context "with a single issue" do
      let(:case_issues) { FactoryBot.create_list(:case_issue, 1) }

      scenario "attorney checkout flow from case detail view loads" do
        visit "/queue"
        click_on "#{appeal.veteran_full_name} (#{appeal.sanitized_vbms_id})"
        click_dropdown 0

        expect(page).to have_content "Select Dispositions"

        cancel_button = page.find "#button-cancel-button"
        expect(cancel_button.text).to eql "Cancel"
        cancel_button.click

        cancel_modal = page.find ".cf-modal"
        expect(cancel_modal.matches_css?(".active")).to eq true
        cancel_modal.find(".usa-button-warning").click

        click_dropdown 1

        expect(page).to have_content "Submit OMO for Review"

        cancel_button = page.find "#button-cancel-button"
        expect(cancel_button.text).to eql "Cancel"

        back_button = page.find "#button-back-button"
        expect(back_button.text).to eql "Back"
      end

      scenario "fails to submit omo decision when lacking required fields" do
        visit "/queue"

        click_on "#{appeal.veteran_full_name} (#{appeal.sanitized_vbms_id})"
        click_dropdown 1

        expect(page).to have_content "Back"

        click_on "Continue"

        expect(page).to have_content("This field is required")
        expect(page.find_all(".usa-input-error-message").length).to eq(3)
      end
    end

    context "with three issues" do
      let(:case_issues) { FactoryBot.create_list(:case_issue, 3) }

      scenario "selects issue dispositions" do
        visit "/queue"
        click_on "#{appeal.veteran_full_name} (#{appeal.sanitized_vbms_id})"
        click_dropdown 0

        expect(page).to have_content("Select Dispositions")

        table_rows = page.find_all("tr[id^='table-row-']")
        expect(table_rows.length).to eq(appeal.issues.length)

        # do not select all dispositions
        table_rows[0..0].each { |row| click_dropdown 1, row }

        click_on "Continue"

        table_rows[1..-1].each do |row|
          dropdown_border = row.find(".issue-disposition-dropdown").native.css_value("border-left")
          expect(dropdown_border).to eq("4px solid rgb(205, 32, 38)")
        end

        # select all dispositions
        table_rows.each { |row| click_dropdown 2, row }

        click_on "Continue"

        expect(page.current_path).to eq("/queue/appeals/#{appeal.vacols_id}/submit")
      end

      scenario "submits draft decision" do
        visit "/queue"
        click_on "#{appeal.veteran_full_name} (#{appeal.sanitized_vbms_id})"
        click_dropdown 0

        issue_rows = page.find_all("tr[id^='table-row-']")
        expect(issue_rows.length).to eq(appeal.issues.length)

        issue_rows.each do |row|
          row.find(".Select-control").click
          row.find("div[id$='--option-#{issue_rows.index(row) % 7}']").click
        end

        click_on "Continue"
        expect(page).to have_content("Select Remand Reasons")
        expect(page).to have_content(appeal.issues.first.note)

        page.execute_script("return document.querySelectorAll('div[class^=\"checkbox-wrapper-\"]')")
          .sample(4)
          .each(&:click)

        page.find_all("input[type='radio'] + label").to_a.each_with_index do |label, idx|
          label.click unless (idx % 2).eql? 0
        end

        click_on "Continue"
        expect(page).to have_content("Submit Draft Decision for Review")

        document_id = Array.new(35).map { rand(10) }.join
        fill_in "document_id", with: document_id
        expect(page.find("#document_id").value.length).to eq 30

        fill_in "notes", with: "this is a decision note"

        # Expect this to be populated with all judge_staff we've created
        # by way of FactoryBot.create(:staff, :judge_role...
        safe_click "#select-judge"
        click_dropdown 0
        expect(page).to have_content(judge_user.full_name)

        click_on "Continue"
        sleep 5
        expect(page.current_path).to eq("/queue")
      end

      scenario "submits omo request" do
        visit "/queue"
        click_on "#{appeal.veteran_full_name} (#{appeal.sanitized_vbms_id})"
        click_dropdown 1

        expect(page).to have_content("Submit OMO for Review")

        click_label("omo-type_OMO - VHA")
        click_label("overtime")
        fill_in "document_id", with: "12345"

        click_on "Continue"
        expect(page).to have_content(COPY::FORM_ERROR_FIELD_INVALID)
        fill_in "document_id", with: "V1234567.1234"
        click_on "Continue"
        expect(page).not_to have_content(COPY::FORM_ERROR_FIELD_INVALID)

        dummy_note = generate_words 100
        fill_in "notes", with: dummy_note
        expect(page).to have_content(dummy_note[0..349])

        safe_click("#select-judge")
        click_dropdown 0
        expect(page).to have_content(judge_user.full_name)

        click_on "Continue"
        sleep 1
        expect(page.current_path).to eq("/queue")

        case_review = AttorneyCaseReview.all.first
        expect(case_review.note.length).to eq 350
        expect(case_review.task_id.start_with?(appeal.vacols_id)).to be_truthy
      end

      scenario "deletes issue" do
        visit "/queue"
        click_on "#{appeal.veteran_full_name} (#{appeal.sanitized_vbms_id})"
        click_dropdown 0

        expect(page).to have_content("Select Dispositions")

        issue_rows = page.find_all("tr[id^='table-row-']")
        expect(issue_rows.length).to eq(appeal.issues.length)

        safe_click("a[href='/queue/appeals/#{appeal.vacols_id}/dispositions/edit/1']")
        expect(page).to have_content("Edit Issue")

        issue_idx = appeal.issues.index { |i| i.vacols_sequence_id.eql? 1 }

        # Before we delete the issue lets copy the count of issues before this action to new variable.
        old_issues_count = appeal.issues.length

        click_on "Delete Issue"
        expect(page).to have_content "Delete Issue?"
        click_on "Delete issue"

        expect(page).to have_content("You deleted issue #{issue_idx + 1}.")

        visit "/queue"

        issue_count = find(:xpath, "//tbody/tr[@id='table-row-#{appeal.vacols_id}']/td[4]").text
        expect(issue_count.to_i).to eq(old_issues_count - 1)
      end
    end

    context "with a single issue with nil disposition" do
      # Default issue disposition is nil.
      let(:case_issues) { FactoryBot.create_list(:case_issue, 1) }

      def select_issue_level_options(opts)
        Array.new(5).map.with_index do |*, row_idx|
          # Issue level 2 and diagnostic code dropdowns render based on earlier
          # values, so we have to re-get elements per loop. There are at most 5
          # dropdowns rendered: Program, Type, Levels 1, 2, Diagnostic Code
          field_options = page.find_all ".Select--single"
          row = field_options[row_idx]

          next unless row

          row.find(".Select-control").click

          if opts[row_idx].eql? "*"
            # there're about 800 diagnostic code options, but getting the count
            # of '.Select-option's from the DOM takes a while
            row.find("div[id$='--option-#{rand(800)}']").click
          elsif opts[row_idx].is_a? String
            row.find("div[id$='--option-#{opts[row_idx]}']").click
          end
          row.find(".Select-value-label").text
        end
      end

      scenario "edits issue information" do
        visit "/queue"
        click_on "#{appeal.veteran_full_name} (#{appeal.sanitized_vbms_id})"
        click_dropdown 0

        expect(page).to have_content("Select Dispositions")

        safe_click("a[href='/queue/appeals/#{appeal.vacols_id}/dispositions/edit/1']")
        expect(page).to have_content("Edit Issue")

        enabled_fields = page.find_all(".Select--single:not(.is-disabled)")

        field_values = enabled_fields.map do |row|
          # changing options at the top of the form affects what options are enabled further down
          next if row.matches_css? ".is-disabled"

          click_dropdown 1, row
          row.find(".Select-value-label").text
        end
        fill_in "Notes:", with: "this is the note"

        click_on "Continue"

        expect(page).to have_content "You updated issue 1."
        expect(page).to have_content "Program: #{field_values.first}"
        expect(page).to have_content "Issue: #{field_values.second}"
        expect(page).to have_content field_values.last # diagnostic code
        expect(page).to have_content "Note: this is the note"
      end

      scenario "shows/hides diagnostic code option" do
        visit "/queue"
        click_on "#{appeal.veteran_full_name} (#{appeal.sanitized_vbms_id})"
        click_dropdown 0

        expect(page).to have_content "Select Dispositions"

        diag_code_no_l2 = %w[4 5 0 *]
        no_diag_code_no_l2 = %w[4 5 1]
        diag_code_w_l2 = %w[4 8 0 1 *]
        no_diag_code_w_l2 = %w[4 8 0 2]

        [diag_code_no_l2, no_diag_code_no_l2, diag_code_w_l2, no_diag_code_w_l2].each do |opt_set|
          safe_click "a[href='/queue/appeals/#{appeal.vacols_id}/dispositions/edit/1']"
          expect(page).to have_content "Edit Issue"
          selected_vals = select_issue_level_options(opt_set)
          click_on "Continue"
          selected_vals.each { |v| expect(page).to have_content v }
        end
      end

      scenario "adds issue" do
        visit "/queue"
        click_on "#{appeal.veteran_full_name} (#{appeal.sanitized_vbms_id})"
        click_dropdown 0

        expect(page).to have_content "Select Dispositions"

        click_on "Add Issue"
        expect(page).to have_content "Add Issue"

        delete_btn = find("button", text: "Delete Issue")
        expect(delete_btn.disabled?).to eq true

        program = "BVA Original Jurisdiction"
        issue = "Motions"
        level = "Rule 608 motion to withdraw"

        find(".Select-control", text: "Select program").click
        find("div", class: "Select-option", text: program).click

        find(".Select-control", text: "Select issue").click
        find("div", class: "Select-option", text: issue).click

        find(".Select-control", text: "Select level 1").click
        find("div", class: "Select-option", text: level).click

        fill_in "Notes:", with: "added issue"

        click_on "Continue"

        expect(page).to have_content "You created a new issue."
        expect(page).to have_content "Program: #{program}"
        expect(page).to have_content "Issue: #{issue}"
        expect(page).to have_content level
        expect(page).to have_content "Note: added issue"

        visit "/queue"

        expect(appeal.reload.issues.length).to eq 2
      end
    end
  end

  context "given a valid legacy appeal with single issue assigned to current judge user" do
    let!(:appeal) do
      FactoryBot.create(
        :legacy_appeal,
        :with_veteran,
        vacols_case: FactoryBot.create(
          :case,
          :assigned,
          user: judge_user,
          assigner: attorney_user,
          case_issues: [
            FactoryBot.create(:case_issue, :disposition_allowed),
            FactoryBot.create(:case_issue, :disposition_granted_by_aoj)
          ],
          work_product: work_product
        )
      )
    end

    before do
      FeatureToggle.enable!(:judge_case_review_checkout)

      User.authenticate!(user: judge_user)
    end

    after do
      FeatureToggle.disable!(:judge_case_review_checkout)
    end

    context "where work product is decision draft" do
      let(:work_product) { :draft_decision }

      scenario "starts dispatch checkout flow" do
        visit "/queue"
        click_on "#{appeal.veteran_full_name} (#{appeal.sanitized_vbms_id})"

        click_dropdown 0 do
          visible_options = page.find_all(".Select-option")
          expect(visible_options.length).to eq 1
          expect(visible_options.first.text).to eq COPY::JUDGE_CHECKOUT_DISPATCH_LABEL
        end

        # one issue is decided, excluded from checkout flow
        expect(appeal.issues.length).to eq 2
        expect(page.find_all(".issue-disposition-dropdown").length).to eq 1

        click_on "Continue"
        expect(page).to have_content("Evaluate Decision")

        click_on "Continue"
        expect(page).to have_content("Choose one")
        sleep 2

        radio_group_cls = "cf-form-showhide-radio cf-form-radio usa-input-error"
        case_complexity_opts = page.find_all(:xpath, "//fieldset[@class='#{radio_group_cls}'][1]//label")
        case_quality_opts = page.find_all(:xpath, "//fieldset[@class='#{radio_group_cls}'][2]//label")

        expect(case_quality_opts.first.text).to eq(
          "5 - #{Constants::JUDGE_CASE_REVIEW_OPTIONS['QUALITY']['outstanding']}"
        )
        expect(case_quality_opts.last.text).to eq(
          "1 - #{Constants::JUDGE_CASE_REVIEW_OPTIONS['QUALITY']['does_not_meet_expectations']}"
        )

        [case_complexity_opts, case_quality_opts].each { |l| l.sample(1).first.click }
        # areas of improvement
        page.find_all(".question-label").sample(2).each(&:double_click)

        dummy_note = generate_words 200
        fill_in "additional-factors", with: dummy_note
        expect(page).to have_content(dummy_note[0..599])

        click_on "Continue"

        expect(page).to have_content(COPY::JUDGE_CHECKOUT_DISPATCH_SUCCESS_MESSAGE_TITLE % appeal.veteran_full_name)
      end
    end

    context "where work product is omo request" do
      let(:work_product) { :omo_request }

      scenario "completes assign to omo checkout flow" do
        visit "/queue"
        click_on "#{appeal.veteran_full_name} (#{appeal.sanitized_vbms_id})"

        click_dropdown 0 do
          visible_options = page.find_all(".Select-option")
          expect(visible_options.length).to eq 1
          expect(visible_options.first.text).to eq COPY::JUDGE_CHECKOUT_OMO_LABEL
        end

        expect(page).to have_content(COPY::JUDGE_CHECKOUT_OMO_SUCCESS_MESSAGE_TITLE % appeal.veteran_full_name)
      end
    end
  end

  context "given a valid legacy appeal and a colocated user" do
    let!(:appeal) do
      FactoryBot.create(
        :legacy_appeal,
        :with_veteran,
        vacols_case: FactoryBot.create(
          :case,
          :assigned,
          user: colocated_user,
          case_issues: FactoryBot.create_list(:case_issue, 1)
        )
      )
    end
    let!(:appeal_with_translation_task) do
      FactoryBot.create(
        :legacy_appeal,
        :with_veteran,
        vacols_case: FactoryBot.create(
          :case,
          :assigned,
          user: colocated_user,
          case_issues: FactoryBot.create_list(:case_issue, 1)
        )
      )
    end
    let!(:colocated_action) do
      FactoryBot.create(
        :colocated_task,
        appeal: appeal,
        assigned_to: colocated_user,
        assigned_by: attorney_user,
        action: "pending_scanning_vbms"
      )
    end
    let!(:translation_action) do
      FactoryBot.create(
        :colocated_task,
        appeal: appeal_with_translation_task,
        assigned_to: colocated_user,
        assigned_by: attorney_user,
        action: "translation"
      )
    end

    before do
      FeatureToggle.enable!(:colocated_queue)
      User.authenticate!(user: colocated_user)
    end

    after do
      FeatureToggle.disable!(:colocated_queue)
    end

    scenario "reassigns task to assigning attorney" do
      visit "/queue"

      appeal = colocated_action.appeal

      vet_name = appeal.veteran_full_name
      attorney_name = colocated_action.assigned_by_display_name
      attorney_name_display = "#{attorney_name.first[0]}. #{attorney_name.last}"

      click_on "#{vet_name.split(' ').first} #{vet_name.split(' ').last} (#{appeal.sanitized_vbms_id})"
      click_dropdown 0
      expect(page).to have_content(COPY::COLOCATED_ACTION_SEND_BACK_TO_ATTORNEY_BUTTON)
      click_on COPY::COLOCATED_ACTION_SEND_BACK_TO_ATTORNEY_BUTTON

      expect(page).to have_content(
        format(COPY::COLOCATED_ACTION_SEND_BACK_TO_ATTORNEY_CONFIRMATION, vet_name, attorney_name_display)
      )

      expect(colocated_action.reload.status).to eq "completed"
      expect(colocated_action.assigned_at.to_date).to eq Time.zone.today
    end

    scenario "places task on hold" do
      visit "/queue"

      appeal = colocated_action.appeal

      vet_name = appeal.veteran_full_name
      click_on "#{vet_name.split(' ').first} #{vet_name.split(' ').last} (#{appeal.sanitized_vbms_id})"

      expect(page).to have_content("Actions")

      click_dropdown 1

      expect(page).to have_content(
        format(COPY::COLOCATED_ACTION_PLACE_HOLD_HEAD, vet_name, appeal.sanitized_vbms_id)
      )

      click_dropdown 6
      expect(page).to have_content(COPY::COLOCATED_ACTION_PLACE_CUSTOM_HOLD_COPY)

      hold_duration = [rand(100), 1].max
      fill_in COPY::COLOCATED_ACTION_PLACE_CUSTOM_HOLD_COPY, with: hold_duration

      instructions = generate_words 5
      fill_in "instructions", with: instructions
      click_on "Place case on hold"

      expect(page).to have_content(
        format(COPY::COLOCATED_ACTION_PLACE_HOLD_CONFIRMATION, vet_name, hold_duration)
      )
      expect(colocated_action.reload.on_hold_duration).to eq hold_duration
      expect(colocated_action.status).to eq "on_hold"
      expect(colocated_action.instructions).to eq instructions
    end

    scenario "sends task to team" do
      visit "/queue"

      appeal = translation_action.appeal
      vacols_case = appeal.case_record

      team_name = Constants::CO_LOCATED_ADMIN_ACTIONS[translation_action.action]
      vet_name = appeal.veteran_full_name
      click_on "#{vet_name.split(' ').first} #{vet_name.split(' ').last} (#{appeal.sanitized_vbms_id})"

      click_dropdown 0

      expect(page).to have_content(
        format(COPY::COLOCATED_ACTION_SEND_TO_ANOTHER_TEAM_HEAD, team_name)
      )
      expect(page).to have_content(
        format(COPY::COLOCATED_ACTION_SEND_TO_ANOTHER_TEAM_COPY, vet_name, appeal.sanitized_vbms_id)
      )

      click_on COPY::COLOCATED_ACTION_SEND_TO_ANOTHER_TEAM_BUTTON

      expect(page).to have_content(
        format(COPY::COLOCATED_ACTION_SEND_TO_ANOTHER_TEAM_CONFIRMATION, vet_name, team_name)
      )

      expect(translation_action.reload.status).to eq "completed"
      expect(vacols_case.reload.bfcurloc).to eq LegacyAppeal::LOCATION_CODES[translation_action.action.to_sym]
    end
  end
end
