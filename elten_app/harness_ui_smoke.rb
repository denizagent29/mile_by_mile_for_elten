# frozen_string_literal: true

require_relative '../lib/mile_by_mile'
require_relative 'lib/mile_by_mile_elten/bot'
require_relative 'lib/mile_by_mile_elten/audio'
require_relative 'lib/mile_by_mile_elten/ui'

# --- minimal Elten API stubs so the UI can run outside Elten ---
def _(s) = s.to_s
def n_(a, b, n) = n == 1 ? a : b

ALERTS = []
def alert(text, _wait = true)
  ALERTS << text
end

# selector: if $selector_script (array of indices) is set, consume it in order,
# otherwise always pick the first available option (index 0)
$selector_script = []
def selector(options, header: '', start_index: 0, cancel_index: nil, **_kw)
  idx = $selector_script.empty? ? 0 : $selector_script.shift
  idx = [options.size - 1, idx].min
  idx
end

def key_pressed?(_key) = true
def loop_update; end

DISPLAYED_TEXT = []
def display_text(text, header: '', **_kw)
  DISPLAYED_TEXT << [header, text]
end

class EditBox
  module Flags
    MultiLine = 1
    ReadOnly = 2
  end

  def initialize(header, type:, text:, quiet:); end
  def update; end
end

class FakeProgram
  def play_app_sound(name, **_kw)
    true
  end
end

# --- run N full games through MileByMileElten::UI ---
GAMES = (ARGV[0] || 30).to_i
crashes = 0

GAMES.times do |i|
  ALERTS.clear
  program = FakeProgram.new
  ui = MileByMileElten::UI.new(program)
  # scenario: pick card variant (0=cars/1=horses alternating), distance,
  # then always play the first available card in hand until the game ends
  $selector_script = [i.even? ? 0 : 1, i % 2]

  begin
    ui.send(:play_vs_bot)
  rescue StandardError => e
    crashes += 1
    puts "GAME ##{i} CRASHED: #{e.class}: #{e.message}"
    puts e.backtrace.first(6)
  end
end

# the Rules screen must render via Elten's display_text (regression: a
# hand-rolled show_text used to NoMethodError against the real Elten API)
help_crashes = 0
begin
  DISPLAYED_TEXT.clear
  ui = MileByMileElten::UI.new(FakeProgram.new)
  ui.send(:show_help)
  help_crashes = DISPLAYED_TEXT.empty? ? 1 : 0
rescue StandardError => e
  help_crashes += 1
  puts "HELP CRASHED: #{e.class}: #{e.message}"
  puts e.backtrace.first(6)
end

puts "Done: #{GAMES} games via the UI (human always plays the first card in hand), crashes: #{crashes}"
puts "Rules screen rendered via display_text: #{help_crashes.zero? ? 'yes' : 'NO'}"
puts "Sample final alert: #{ALERTS.last.inspect}" if ALERTS.any?
exit(crashes.zero? && help_crashes.zero? ? 0 : 1)
