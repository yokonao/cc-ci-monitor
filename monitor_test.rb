# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require_relative "monitor"

class MonitorTest < Minitest::Test
  def check(name, bucket) = { "name" => name, "bucket" => bucket, "link" => "https://ci.test/#{name}" }

  # Drive `run` with a scripted gh: each response is a checks array, or a String
  # to raise as a fetch failure. Returns [exit_code, emitted_events, stderr_log].
  def drive(*responses)
    queue = responses.dup
    fetch = lambda do |_pr|
      raise "script exhausted (run didn't terminate)" if queue.empty?
      r = queue.shift
      r.is_a?(String) ? raise(r) : r
    end
    out = StringIO.new
    err = StringIO.new
    code = Monitor.new("123", interval: 0, fetch: fetch, out: out, err: err).run
    events = out.string.each_line.map { |l| JSON.parse(l) }
    [code, events, err.string]
  end

  def test_all_green_passes
    code, events = drive([check("test", "pass"), check("lint", "skipping")])
    assert_equal 0, code
    assert_equal [{ "event" => "checks_passed", "data" => { "total" => 2 } }], events
  end

  def test_fix_loop_reports_failure_then_passes
    code, events = drive([check("test", "fail")], [check("test", "pass")])
    assert_equal 0, code
    assert_equal "check_failed", events[0]["event"]
    assert_equal({ "name" => "test", "url" => "https://ci.test/test" }, events[0]["data"])
    assert_equal "checks_passed", events[1]["event"]
  end

  def test_failure_emitted_once_while_still_red
    code, events = drive([check("test", "fail")], [check("test", "fail")], [check("test", "pass")])
    assert_equal 0, code
    assert_equal %w[check_failed checks_passed], events.map { |e| e["event"] }
  end

  def test_failure_re_reports_after_leaving_red
    code, events = drive(
      [check("test", "fail")],
      [check("test", "pending")],
      [check("test", "fail")],
      [check("test", "pass")]
    )
    assert_equal 0, code
    assert_equal %w[check_failed check_failed checks_passed], events.map { |e| e["event"] }
  end

  def test_each_red_check_reported
    code, events = drive([check("test", "fail"), check("lint", "cancel")], [check("test", "pass"), check("lint", "pass")])
    assert_equal 0, code
    assert_equal %w[test lint], events.select { |e| e["event"] == "check_failed" }.map { |e| e["data"]["name"] }
  end

  def test_waits_through_empty_checks
    code, events = drive([], [check("test", "pass")])
    assert_equal 0, code
    assert_equal %w[checks_passed], events.map { |e| e["event"] }
  end

  def test_gives_up_after_max_fetch_failures
    code, _events, log = drive(*Array.new(Monitor::MAX_FETCH_FAILURES, "gh boom"))
    assert_equal 1, code
    assert_includes log, "fetch failed (#{Monitor::MAX_FETCH_FAILURES}/#{Monitor::MAX_FETCH_FAILURES}): gh boom"
    assert_includes log, "giving up after #{Monitor::MAX_FETCH_FAILURES} consecutive fetch failures"
  end

  def test_fetch_failure_is_logged_with_count
    _code, _events, log = drive("gh boom", [check("test", "pass")])
    assert_includes log, "fetch failed (1/#{Monitor::MAX_FETCH_FAILURES}): gh boom"
  end

  def test_fetch_failures_reset_on_success
    code, events, log = drive("boom", "boom", "boom", "boom", [check("test", "pass")])
    assert_equal 0, code
    assert_equal %w[checks_passed], events.map { |e| e["event"] }
    refute_includes log, "giving up"
  end
end
