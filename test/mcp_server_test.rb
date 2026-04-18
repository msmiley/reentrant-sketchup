# frozen_string_literal: true
#
# Standalone test suite for mcp_server.rb.
#
# Runs outside SketchUp with lightweight stubs for the Sketchup / UI
# modules. Verifies the reliability-pass behaviors end to end:
#   * safe_eval: ok / error / wrap_op=false / truncation / inspect results
#   * probe:     snapshot sentinel / refresh / staleness / post-write /
#                error-no-refresh / live / per-field isolation
#   * execute_ruby_file: validation, happy path, oversize, syntax error
#   * timeout:   deadline honored, pump not wedged, inner error raised
#   * backward-compat of the tools/call dispatch envelope
#   * probe snapshot returns while a long execute_ruby is in flight
#
# Run: ruby test/mcp_server_test.rb

require 'json'

# --- Stubs --------------------------------------------------------------

module Sketchup
  class Model
    attr_reader :ops
    attr_accessor :title

    def initialize
      @ops = []
      @entities = MockEntities.new
      @title = 'smoke'
    end

    def start_operation(name, _disable = true); @ops << [:start, name]; true; end
    def commit_operation; @ops << [:commit]; true; end
    def abort_operation; @ops << [:abort]; true; end
    def entities; @entities; end
    def path; '/tmp/smoke.skp'; end
    def definitions; [1, 2, 3]; end
    def materials; [1, 2]; end
    def layers; [1]; end
    def active_entities; @entities; end
    def active_path; nil; end
    def selection; []; end
  end

  class MockEntities
    def initialize; @count = 0; end
    def count; @count; end
    def to_a; []; end
    def bump; @count += 1; end
  end

  @model = Model.new
  def self.active_model; @model; end
  def self.reset!; @model = Model.new; end
end

module UI
  def self.start_timer(*); :stub; end
  def self.stop_timer(_); end
  def self.messagebox(_); end
end

module ReentrantSketchup
  PLUGIN_VERSION = '0.0.0-test'
end

load File.expand_path('../src/reentrant_sketchup/mcp_server.rb', __dir__)
S = ReentrantSketchup::McpServer

# --- Tiny assertion helper ---------------------------------------------

$failures = []
def test(name)
  print "  #{name} ... "
  yield
  puts 'ok'
rescue StandardError => e
  puts "FAIL"
  $failures << "#{name}: #{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
end

def eq!(actual, expected, msg = nil)
  return if actual == expected
  raise "#{msg || 'mismatch'}: expected #{expected.inspect}, got #{actual.inspect}"
end

# --- Tests -------------------------------------------------------------

puts 'safe_eval'

test 'ok path: structured fields, inspect result, op committed' do
  Sketchup.reset!
  r = S.safe_eval('Sketchup.active_model.entities.bump; "hello"', op_name: 'ok_case')
  eq!(r[:status], 'ok')
  eq!(r[:result], '"hello"', 'inspect should quote strings')
  eq!(r[:result_class], 'String')
  eq!(r[:op_name], 'ok_case')
  eq!(r[:entity_count], 1)
  eq!(S.open_operations_count, 0, 'op counter should decrement')
  raise 'elapsed_ms missing' unless r[:elapsed_ms].is_a?(Integer)
  ops = Sketchup.active_model.ops.map(&:first)
  raise "ops: #{ops}" unless ops.include?(:start) && ops.include?(:commit)
end

test 'error path: op aborted, counter at 0, structured error' do
  Sketchup.reset!
  r = S.safe_eval('raise ArgumentError, "nope"', op_name: 'err_case')
  eq!(r[:status], 'error')
  eq!(r[:error], 'ArgumentError')
  eq!(r[:message], 'nope')
  eq!(S.open_operations_count, 0)
  ops = Sketchup.active_model.ops.map(&:first)
  raise "abort missing: #{ops}" unless ops.include?(:abort)
  raise "commit happened: #{ops}" if ops.include?(:commit)
end

test 'wrap_op=false skips start/commit/abort' do
  Sketchup.reset!
  r = S.safe_eval('41 + 1', wrap_op: false, op_name: 'no_op')
  eq!(r[:status], 'ok')
  eq!(r[:result], '42')
  raise "ops happened: #{Sketchup.active_model.ops}" unless Sketchup.active_model.ops.empty?
end

test 'truncation appends suffix for oversized results' do
  Sketchup.reset!
  r = S.safe_eval('"x" * 10000', op_name: 'trunc')
  raise 'not truncated' unless r[:result].include?('truncated, 10002 total bytes')
end

puts 'probe / snapshot'

test 'pending sentinel before first refresh' do
  # Reset the server state so this test is independent of load order.
  S.instance_variable_set(:@snapshot, { fetched_at_ms: nil, status: 'pending' }.freeze)
  p = S.read_snapshot_for_probe
  eq!(p[:status], 'pending')
  eq!(p[:source], 'snapshot')
  raise "age should be nil: #{p}" unless p[:snapshot_age_ms].nil?
end

test 'refresh publishes real fields' do
  Sketchup.reset!
  S.refresh_snapshot
  s = S.read_snapshot_for_probe
  eq!(s[:status], 'ok')
  eq!(s[:title], 'smoke')
  eq!(s[:entity_count], 0)
  eq!(s[:active_context], 'model')
  eq!(s[:open_operations], 0)
  eq!(s[:extension_version], '0.0.0-test')
  raise 'age nil' if s[:snapshot_age_ms].nil?
end

test 'snapshot_age_ms grows monotonically' do
  a = S.read_snapshot_for_probe[:snapshot_age_ms]
  sleep 0.05
  b = S.read_snapshot_for_probe[:snapshot_age_ms]
  raise "age did not grow: #{a} -> #{b}" unless b >= a + 40
end

test 'safe_eval post-write refresh (read-your-writes)' do
  before = S.read_snapshot_for_probe[:entity_count]
  S.safe_eval('Sketchup.active_model.entities.bump', op_name: 'ryw')
  after = S.read_snapshot_for_probe[:entity_count]
  eq!(after, before + 1)
  age = S.read_snapshot_for_probe[:snapshot_age_ms]
  raise "age not reset: #{age}" if age > 50
end

test 'failed safe_eval does not refresh the snapshot' do
  S.refresh_snapshot
  sleep 0.08
  before_age = S.read_snapshot_for_probe[:snapshot_age_ms]
  S.safe_eval('raise "boom"', op_name: 'no_refresh')
  after_age = S.read_snapshot_for_probe[:snapshot_age_ms]
  raise "should not refresh: #{before_age} -> #{after_age}" if after_age < before_age - 5
  eq!(S.open_operations_count, 0, 'no op leak on error')
end

test 'tool_probe_live tags source=live and refreshes' do
  S.refresh_snapshot
  sleep 0.05
  Sketchup.active_model.instance_variable_get(:@entities).bump
  live = S.tool_probe_live
  eq!(live[:source], 'live')
  raise "age stale on live: #{live[:snapshot_age_ms]}" if live[:snapshot_age_ms] > 10
end

test 'per-field accessor exception isolated to that field' do
  bad = Sketchup::Model.new
  def bad.title; raise 'broken'; end
  Sketchup.instance_variable_set(:@model, bad)
  S.refresh_snapshot
  s = S.read_snapshot_for_probe
  raise "title should be nil: #{s}" unless s[:title].nil?
  eq!(s[:entity_count], 0, 'other fields should survive')
end

test 'open_operations visible in snapshot' do
  Sketchup.reset!
  S.instance_variable_set(:@open_operations, 2)
  S.refresh_snapshot
  eq!(S.read_snapshot_for_probe[:open_operations], 2)
  S.instance_variable_set(:@open_operations, 0)
end

puts 'execute_ruby_file'

test 'missing path: structured ArgumentError' do
  r = S.tool_execute_ruby_file({})
  eq!(r[:status], 'error')
  raise "msg: #{r[:message]}" unless r[:message].include?('required')
end

test 'relative path rejected' do
  r = S.tool_execute_ruby_file('path' => 'rel/script.rb')
  eq!(r[:status], 'error')
  raise "msg: #{r[:message]}" unless r[:message].include?('absolute')
end

test 'nonexistent path: structured error' do
  r = S.tool_execute_ruby_file('path' => "/tmp/missing_#{Process.pid}_#{rand(1 << 30)}.rb")
  eq!(r[:status], 'error')
  raise "msg: #{r[:message]}" unless r[:message].include?('not found')
end

test 'happy path: reads file, returns safe_eval shape + source fields' do
  Sketchup.reset!
  script = "/tmp/exec_file_happy_#{Process.pid}_#{rand(1 << 30)}.rb"
  File.write(script, '40 + 2')
  begin
    r = S.tool_execute_ruby_file('path' => script, 'op_name' => 'file_happy')
    eq!(r[:status], 'ok')
    eq!(r[:result], '42')
    eq!(r[:op_name], 'file_happy')
    eq!(r[:source_file], script)
    eq!(r[:source_bytes], 6)
  ensure
    File.unlink(script) if File.exist?(script)
  end
end

test 'oversize file rejected' do
  big = "/tmp/exec_file_big_#{Process.pid}_#{rand(1 << 30)}.rb"
  File.write(big, 'x' * (2 * 1024 * 1024))
  begin
    r = S.tool_execute_ruby_file('path' => big)
    eq!(r[:status], 'error')
    raise "msg: #{r[:message]}" unless r[:message].include?('too large')
  ensure
    File.unlink(big) if File.exist?(big)
  end
end

test 'syntax error inside script: structured error, source_file preserved' do
  Sketchup.reset!
  bad = "/tmp/exec_file_syntax_#{Process.pid}_#{rand(1 << 30)}.rb"
  File.write(bad, 'def foo(\n')
  begin
    r = S.tool_execute_ruby_file('path' => bad)
    eq!(r[:status], 'error')
    eq!(r[:source_file], bad)
  ensure
    File.unlink(bad) if File.exist?(bad)
  end
end

puts 'transport timeout'

pump_thread = Thread.new do
  loop do
    S.pump_queue
    sleep 0.02
  end
end
sleep 0.05

test 'fast task returns value' do
  v = S.on_main_thread(timeout_s: 2) { 41 + 1 }
  eq!(v, 42)
end

test 'slow task hits deadline: returns sentinel' do
  t0 = Time.now
  v = S.on_main_thread(timeout_s: 0.2) { sleep 1; :late }
  elapsed = Time.now - t0
  eq!(v, S.const_get(:MAIN_THREAD_TIMEOUT))
  raise "elapsed #{elapsed}" if elapsed > 0.6 || elapsed < 0.15
end

test 'pump not wedged after a timed-out task completes late' do
  sleep 1.2
  v = S.on_main_thread(timeout_s: 2) { 7 * 6 }
  eq!(v, 42)
end

test 'inner error propagates as an exception' do
  begin
    S.on_main_thread(timeout_s: 1) { raise ArgumentError, 'boom' }
    raise 'should have raised'
  rescue ArgumentError => e
    eq!(e.message, 'boom')
  end
end

test 'tool_timeout_for clamps to [1, 600] with DEFAULT on junk' do
  eq!(S.tool_timeout_for({}), 30)
  eq!(S.tool_timeout_for('timeout_s' => -5), 30)
  eq!(S.tool_timeout_for('timeout_s' => 0), 30)
  eq!(S.tool_timeout_for('timeout_s' => 5000), 600)
  eq!(S.tool_timeout_for('timeout_s' => 45), 45)
end

test 'probe snapshot returns while execute_ruby is blocking main thread' do
  S.refresh_snapshot  # seed
  # Fire off a long tool call in another thread (simulates a real HTTP worker).
  blocker = Thread.new do
    S.on_main_thread(timeout_s: 5) { sleep 0.6; :done }
  end
  sleep 0.05
  t0 = Time.now
  snap = S.read_snapshot_for_probe
  elapsed = Time.now - t0
  raise "probe slow: #{elapsed}s" if elapsed > 0.05
  raise "snap not readable: #{snap}" unless snap[:status] == 'ok' || snap[:status] == 'pending'
  blocker.join
end

pump_thread.kill

# --- Backward compat test for the tools/call envelope ------------------

puts 'tools/call envelope'

test 'legacy client: JSON.parse(text)["result"] still yields an inspect string' do
  # Start a tiny pump so on_main_thread completes.
  t = Thread.new { loop { S.pump_queue; sleep 0.02 } }
  begin
    Sketchup.reset!
    msg = {
      'jsonrpc' => '2.0',
      'id' => 7,
      'method' => 'tools/call',
      'params' => { 'name' => 'execute_ruby', 'arguments' => { 'code' => '1 + 2' } }
    }
    envelope = S.dispatch(msg)
    text = envelope[:result][:content][0][:text]
    raise 'no isError expected' if envelope[:result][:isError]
    parsed = JSON.parse(text)
    eq!(parsed['status'], 'ok')
    eq!(parsed['result'], '3')  # what a legacy client reading .result sees
  ensure
    t.kill
  end
end

test 'tools/call: error payload sets isError=true' do
  t = Thread.new { loop { S.pump_queue; sleep 0.02 } }
  begin
    Sketchup.reset!
    msg = {
      'jsonrpc' => '2.0',
      'id' => 8,
      'method' => 'tools/call',
      'params' => { 'name' => 'execute_ruby', 'arguments' => { 'code' => 'raise "x"' } }
    }
    envelope = S.dispatch(msg)
    eq!(envelope[:result][:isError], true)
    parsed = JSON.parse(envelope[:result][:content][0][:text])
    eq!(parsed['status'], 'error')
  ensure
    t.kill
  end
end

test 'tools/call: probe with default args uses snapshot path' do
  S.refresh_snapshot
  msg = {
    'jsonrpc' => '2.0',
    'id' => 9,
    'method' => 'tools/call',
    'params' => { 'name' => 'probe', 'arguments' => {} }
  }
  envelope = S.dispatch(msg)
  parsed = JSON.parse(envelope[:result][:content][0][:text])
  eq!(parsed['source'], 'snapshot')
end

# --- Summary ------------------------------------------------------------

puts
if $failures.empty?
  puts "ALL TESTS PASSED"
  exit 0
else
  puts "#{$failures.size} FAILURE(S):"
  $failures.each { |f| puts "  - #{f}" }
  exit 1
end
