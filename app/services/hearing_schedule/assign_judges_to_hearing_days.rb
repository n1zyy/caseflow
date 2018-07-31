require "business_time"
require "set"

class HearingSchedule::AssignJudgesToHearingDays
  attr_reader :judges, :video_co_hearing_days

  TB_ADDITIONAL_NA_DAYS = 3

  class HearingDaysNotAllocated < StandardError; end
  class NoJudgesProvided < StandardError; end
  class CannotAssignJudges < StandardError; end

  def initialize(schedule_period)
    @video_co_hearing_days = []
    @judges = {}
    @schedule_period = schedule_period

    fetch_judge_non_availabilities
    fetch_judge_details
    fetch_hearing_days_for_schedule_period
  end

  # rubocop:disable Metrics/MethodLength
  def match_hearing_days_to_judges
    @video_co_hearing_days = @video_co_hearing_days.shuffle

    # sorts judges and gets their ordered css ids
    sorted_judges = sort_judge_by_non_available_days
    assigned_hearing_days = []
    hearing_days_assigned = false
    already_assigned = {}

    until hearing_days_assigned
      catch :hearing_days_assigned do
        num_days_assigned = assigned_hearing_days.length
        sorted_judges.each do |css_id|
          index = 0

          while index < @video_co_hearing_days.length
            current_hearing_day = @video_co_hearing_days[index]
            hearing_date = current_hearing_day.hearing_date

            unless @judges[css_id][:non_availabilities].include?(hearing_date) ||
                   already_assigned[current_hearing_day.hearing_pkseq]
              assigned_hearing_days << assign_judge_to_hearing_day(current_hearing_day, css_id)
              already_assigned[current_hearing_day.hearing_pkseq] = true
              break
            end
            index += 1
            hearing_days_assigned = @video_co_hearing_days.length == assigned_hearing_days.length
            throw :hearing_days_assigned if hearing_days_assigned
          end
        end
        verify_assignments(num_days_assigned, assigned_hearing_days, hearing_days_assigned)
      end
    end

    assigned_hearing_days
  end
  # rubocop:enable Metrics/MethodLength

  private

  def verify_assignments(num_days_assigned, assigned_hearing_days, hearing_days_assigned)
    fail CannotAssignJudges if
          (num_days_assigned == assigned_hearing_days.length) && !hearing_days_assigned
  end

  # It's expected that the judge validations have been run before
  # running the algorithm. This assumes that the judge information
  # already exists in VACOLS and in Caseflow database.
  def fetch_judge_details
    fail NoJudgesProvided if @judges.keys.empty?

    VACOLS::Staff.load_users_by_css_ids(@judges.keys).map do |judge|
      user = User.find_by(css_id: judge.sdomainid)
      @judges[judge.sdomainid][:staff_info] = judge
      @judges[judge.sdomainid][:user_info] = user
    end
  end

  def sort_judge_by_non_available_days
    @judges.sort_by { |_k, v| v[:non_availabilities].count }.to_h.keys.reverse
  end

  def assign_judge_to_hearing_day(hearing_day, css_id)
    is_central_hearing = co_hearing_day?(hearing_day)

    HearingDayMapper.hearing_day_field_validations(
      hearing_pkseq: hearing_day.hearing_pkseq,
      hearing_type: get_hearing_type(is_central_hearing),
      hearing_date: hearing_day.hearing_date,
      room_info: hearing_day.room,
      regional_office: is_central_hearing ? nil : hearing_day.folder_nr.split(" ")[1],
      judge_id: @judges[css_id][:staff_info].sattyid,
      judge_name: get_judge_name(css_id)
    )
  end

  def get_hearing_type(is_central_hearing)
    if is_central_hearing
      HearingDay::HEARING_TYPES[:central]
    else
      HearingDay::HEARING_TYPES[:video]
    end
  end

  def get_judge_name(css_id)
    if @judges[css_id][:user_info]
      @judges[css_id][:user_info].full_name
    else
      staff_info = @judges[css_id][:staff_info]
      "#{staff_info.snamef} #{staff_info.snamemi} #{staff_info.snamel}"
    end
  end

  def weekend?(day)
    day.saturday? || day.sunday?
  end

  def fetch_judge_non_availabilities
    non_availabilities = @schedule_period.non_availabilities

    non_availabilities.each do |non_availability|
      next unless non_availability.instance_of? JudgeNonAvailability
      css_id = non_availability.object_identifier
      @judges[css_id] ||= {}
      @judges[css_id][:non_availabilities] ||= Set.new
      @judges[css_id][:non_availabilities] << non_availability.date
    end
  end

  def fetch_hearing_days_for_schedule_period
    hearing_days = HearingDay.load_days(@schedule_period.start_date, @schedule_period.end_date)
    @video_co_hearing_days = filter_co_hearings(hearing_days[0].to_a)

    # raises an exception if hearing days have not already been allocated
    fail HearingDaysNotAllocated if @video_co_hearing_days.empty?
    filter_travel_board_hearing_days(hearing_days[1])
  end

  def filter_co_hearings(video_co_hearing_days)
    video_co_hearing_days.map do |hearing_day|
      day = OpenStruct.new(hearing_day.attributes)
      day.hearing_date = day.hearing_date.to_date

      unless (co_hearing_day?(day) && !day.hearing_date.wednesday?) ||
             hearing_day_already_assigned(day)
        day
      end
    end.compact
  end

  def hearing_day_already_assigned(hearing_day)
    assigned = !hearing_day.board_member.nil?

    if assigned
      @judges.each do |css_id, judge|
        if judge[:staff_info].sattyid == hearing_day.board_member
          @judges[css_id][:non_availabilities] << hearing_day.hearing_date
        end
      end
    end
    assigned
  end

  def co_hearing_day?(hearing_day)
    hearing_day.folder_nr.nil?
  end

  # Adds 3 days and 3 days prior non-available days for each Judge assigned to a
  # travel board.
  def filter_travel_board_hearing_days(tb_hearing_days)
    tb_hearing_days_formatted = TravelBoardScheduleMapper.convert_from_vacols_format(tb_hearing_days)

    tb_hearing_days_formatted.each do |tb_record|
      # assign non-availability days to all the travel board judges
      tb_judge_ids = [tb_record[:tbmem_1], tb_record[:tbmem_2], tb_record[:tbmem_3], tb_record[:tbmem_4]].compact
      judges = @judges.select { |_key, judge| tb_judge_ids.include?(judge[:staff_info].sattyid) }

      judges.each_value do |judge_staff_info|
        css_id = judge_staff_info[:staff_info].sdomainid

        @judges[css_id][:non_availabilities] ||= Set.new
        @judges[css_id][:non_availabilities] +=
          (TB_ADDITIONAL_NA_DAYS.business_days.before(tb_record[:start_date])..TB_ADDITIONAL_NA_DAYS.business_days
            .after(tb_record[:end_date])).reject { |date| weekend?(date) }
      end
    end
  end
end
