require "minitest/autorun"
require "json"
require "time"
require "asc_doctor"

# «내 심사 대기가 정상인가» — 커뮤니티에서 가장 많이 나오는 질문.
# doctor가 답할 수 있는 건 ① 큐에 들어가 있는가 ② 며칠째인가 두 가지다.
class ReviewProgressTest < Minitest::Test
  NOW = Time.utc(2026, 9, 20, 12, 0, 0)

  def sub(state, submitted, id: "s1")
    { "id" => id, "type" => "reviewSubmissions",
      "attributes" => { "state" => state, "submittedDate" => submitted, "platform" => "IOS" } }
  end

  def test_no_submission_history_says_not_in_queue
    r = AscDoctor.check_review_progress({ "data" => [] }, NOW)
    assert_equal :skip, r.status
    assert_includes r.message, "애플 큐에 들어가 있지 않다"
  end

  def test_ready_for_review_draft_is_not_in_queue
    r = AscDoctor.check_review_progress({ "data" => [sub("READY_FOR_REVIEW", nil)] }, NOW)
    assert_equal :skip, r.status
    assert_includes r.message, "아직 애플 큐에 없음"
    assert_includes r.message, "아직 제출되지 않았다"
  end

  def test_unresolved_issues_explains_block
    r = AscDoctor.check_review_progress({ "data" => [sub("UNRESOLVED_ISSUES", nil)] }, NOW)
    assert_equal :skip, r.status
    assert_includes r.message, "해결 안 된 항목"
  end

  def test_waiting_under_a_day_reports_hours
    r = AscDoctor.check_review_progress({ "data" => [sub("WAITING_FOR_REVIEW", "2026-09-20T02:00:00Z")] }, NOW)
    assert_equal :ok, r.status
    assert_includes r.message, "애플 큐에서 대기 10시간째"
    assert_nil r.fix, "하루도 안 됐는데 문의를 권하면 안 된다"
  end

  def test_waiting_past_threshold_offers_inquiry
    r = AscDoctor.check_review_progress({ "data" => [sub("WAITING_FOR_REVIEW", "2026-09-11T12:00:00Z")] }, NOW)
    assert_equal :ok, r.status
    assert_includes r.message, "9일째"
    assert_includes r.fix, "문의하기"
  end

  def test_in_review_labels_differently
    r = AscDoctor.check_review_progress({ "data" => [sub("IN_REVIEW", "2026-09-18T12:00:00Z")] }, NOW)
    assert_includes r.message, "심사 중 2일째"
  end

  def test_complete_reports_finished
    r = AscDoctor.check_review_progress({ "data" => [sub("COMPLETE", "2026-09-01T12:00:00Z")] }, NOW)
    assert_equal :ok, r.status
    assert_includes r.message, "심사 종료"
    assert_nil r.fix
  end

  def test_picks_most_recent_submission
    j = { "data" => [sub("COMPLETE", "2026-09-01T12:00:00Z", id: "old"),
                     sub("WAITING_FOR_REVIEW", "2026-09-19T12:00:00Z", id: "new")] }
    r = AscDoctor.check_review_progress(j, NOW)
    assert_includes r.message, "애플 큐에서 대기"
    assert_includes r.message, "1일째"
  end

  def test_missing_submitted_date_does_not_crash
    r = AscDoctor.check_review_progress({ "data" => [sub("WAITING_FOR_REVIEW", nil)] }, NOW)
    assert_equal :ok, r.status
    assert_includes r.message, "제출 시각 없음"
  end

  def test_progress_never_adds_a_failure_to_the_gate
    # 제출 가능 여부는 check_submission이 판정한다. 진행 상황은 실패로 세지 않는다.
    states = ["READY_FOR_REVIEW", "UNRESOLVED_ISSUES", "WAITING_FOR_REVIEW", "IN_REVIEW", "COMPLETE"]
    states.each do |st|
      r = AscDoctor.check_review_progress({ "data" => [sub(st, "2026-09-01T12:00:00Z")] }, NOW)
      refute_equal :fail, r.status, "#{st}이 제출 가능 판정을 뒤집으면 안 된다"
    end
  end
end
