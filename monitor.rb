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
require "optparse"
require "set"

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

# The watch loop. `fetch` is the only side-channel to the outside world, so a test
# can hand in a scripted stub and drive the whole loop end-to-end.
class Monitor
  # @see https://cli.github.com/manual/gh_pr_checks
  # When the --json flag is used, bucket categorizes state into pass, fail, pending, skipping, or cancel.
  GREEN = %w[pass skipping].freeze
  RED   = %w[fail cancel].freeze

  MAX_FETCH_FAILURES = 5 # consecutive gh failures before we give up
  DEFAULT_INTERVAL = 30  # seconds between polls

  def initialize(pr, interval: DEFAULT_INTERVAL, fetch: method(:fetch_checks), out: $stdout, err: $stderr)
    @pr = pr
    @interval = interval
    @fetch = fetch
    @out = out
    @err = err
    @seen_failed = Set.new # so each failure is emitted once
    @fetch_failures = 0
  end

  # Runs until all green (returns 0) or too many consecutive fetch failures (1).
  def run
    loop do
      begin
        checks = @fetch.call(@pr)
        @fetch_failures = 0
      rescue RuntimeError => e
        @fetch_failures += 1
        log "fetch failed (#{@fetch_failures}/#{MAX_FETCH_FAILURES}): #{e}"
        if @fetch_failures >= MAX_FETCH_FAILURES
          log "giving up after #{MAX_FETCH_FAILURES} consecutive fetch failures"
          return 1
        end
        sleep @interval
        next
      end

      if checks.empty?
        log "no checks reported yet; waiting…"
        sleep @interval
        next
      end

      events, done = tick(checks)
      events.each { |event, data| emit(event, **data) }
      return 0 if done

      sleep @interval
    end
  end

  # checks -> [events, done?]   where events is [[:check_failed, {...}], ...]
  def tick(checks)
    events = []

    # Announce each check the moment it turns red, keyed by [name, run URL] so a
    # fresh failing run re-reports even when the intervening pending/green state
    # fell between polls and was never observed.
    checks.each do |c|
      next unless RED.include?(c["bucket"])

      events << [:check_failed, { name: c["name"], url: c["link"] }] if @seen_failed.add?([c["name"], c["link"]])
    end

    # All green is the one terminal. Pending or red: keep watching.
    done = !checks.empty? && checks.all? { |c| GREEN.include?(c["bucket"]) }
    events << [:checks_passed, { total: checks.size }] if done

    [events, done]
  end

  private

  def emit(event, **data)
    @out.puts JSON.generate({ event: event, data: data })
    @out.flush
  end

  def log(msg) = @err.puts(msg)
end

def main
  interval = Monitor::DEFAULT_INTERVAL
  parser = OptionParser.new do |o|
    o.banner = "usage: ruby monitor.rb <pr | url | branch> [--interval SECONDS]"
    o.on("--interval SECONDS", Integer, "seconds between polls (default #{interval})") do |v|
      raise OptionParser::InvalidArgument, v.to_s unless v.positive?

      interval = v
    end
  end
  parser.parse!(ARGV)

  pr = ARGV.first
  unless pr
    $stderr.puts parser.banner
    exit 2
  end

  exit Monitor.new(pr, interval: interval).run
rescue OptionParser::ParseError => e
  $stderr.puts e.message
  exit 2
end

main if __FILE__ == $PROGRAM_NAME
