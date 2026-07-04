#!/usr/bin/env ruby
# frozen_string_literal: true
#
# monitor.rb — watch a PR's CI checks, emit line-delimited JSON events:
#
#   check_failed    a check went red     (emitted once per failure)
#   checks_passed   all settled green    (exit 0)
#
# Green is the only terminal: it exits. A red run isn't — a fix push starts a new
# run, so we keep watching until everything is green.
#
# Usage: ruby monitor.rb <pr | url | branch> [--interval SECONDS]

require "json"
require "open3"
require "set"

MAX_FETCH_FAILURES = 5 # consecutive gh failures before we give up
# @see https://cli.github.com/manual/gh_pr_checks
# When the --json flag is used, it includes a bucket field, which categorizes the state field into pass, fail, pending, skipping, or cancel.
GREEN = %w[pass skipping].freeze
RED   = %w[fail cancel].freeze

def emit(event, **data)
  line = { event: event, data: data }
  $stdout.puts JSON.generate(line)
  $stdout.flush
end

def log(msg) = $stderr.puts(msg)

# Current checks as [{"name","bucket","link"}, ...], or [] when none reported yet.
# gh exits non-zero while checks fail or pend but still prints JSON, so the signal
# is parseable output, not exit status. Raises on a real fetch failure.
def fetch_checks(pr)
  out, err, = Open3.capture3("gh", "pr", "checks", pr, "--json", "name,bucket,link")
  return JSON.parse(out) unless out.strip.empty?
  return [] if err =~ /no checks reported/i

  raise err.strip.empty? ? "no output from gh pr checks" : err.strip
rescue JSON::ParserError => e
  raise "unparseable gh output: #{e.message}"
end

pr = ARGV.reject { |a| a.start_with?("-") }.first
unless pr
  log "usage: ruby monitor.rb <pr | url | branch> [--interval SECONDS]"
  exit 2
end
i = ARGV.index("--interval")
interval = i ? ARGV[i + 1].to_i : 15
interval = 15 unless interval.positive?

seen_failed = Set.new # so each failure is emitted once
fetch_failures = 0

loop do
  begin
    checks = fetch_checks(pr)
    fetch_failures = 0
  rescue RuntimeError => e
    fetch_failures += 1
    log "fetch failed (#{fetch_failures}/#{MAX_FETCH_FAILURES}): #{e}"
    abort "giving up after #{MAX_FETCH_FAILURES} consecutive fetch failures" if fetch_failures >= MAX_FETCH_FAILURES
    sleep interval
    next
  end

  if checks.empty?
    log "no checks reported yet; waiting…"
    sleep interval
    next
  end

  # Announce each check the moment it turns red; forget it again if it leaves the
  # red state (a re-run went pending/green) so a later failure re-reports.
  checks.each do |c|
    if RED.include?(c["bucket"])
      emit "check_failed", name: c["name"], url: c["link"] if seen_failed.add?(c["name"])
    else
      seen_failed.delete(c["name"])
    end
  end

  # All green is the one terminal. Pending or red: keep watching (a fix push
  # restarts the run; check_failed already named each red).
  if checks.all? { |c| GREEN.include?(c["bucket"]) }
    emit "checks_passed", total: checks.size
    exit 0
  end

  sleep interval
end
