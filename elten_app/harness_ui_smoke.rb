# frozen_string_literal: true

require_relative '../lib/mile_by_mile'
require_relative 'lib/mile_by_mile_elten/bot'
require_relative 'lib/mile_by_mile_elten/audio'
require_relative 'lib/mile_by_mile_elten/ui'

# --- минимальные стабы Elten API, чтобы UI мог выполниться вне Elten ---
def _(s) = s.to_s
def n_(a, b, n) = n == 1 ? a : b

ALERTS = []
def alert(text, _wait = true)
  ALERTS << text
end

# selector: если задан $selector_script (массив индексов), берём по очереди,
# иначе всегда выбираем первый доступный вариант (индекс 0)
$selector_script = []
def selector(options, header: '', start_index: 0, cancel_index: nil, **_kw)
  idx = $selector_script.empty? ? 0 : $selector_script.shift
  idx = [options.size - 1, idx].min
  idx
end

def key_pressed?(_key) = true
def loop_update; end

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

# --- прогон N партий полностью через MileByMileElten::UI ---
GAMES = (ARGV[0] || 30).to_i
crashes = 0

GAMES.times do |i|
  ALERTS.clear
  program = FakeProgram.new
  ui = MileByMileElten::UI.new(program)
  # сценарий: выбрать вариант карт (0=cars/1=horses случайно), дистанцию,
  # затем всегда играть первую доступную карту в руке до конца партии
  $selector_script = [i.even? ? 0 : 1, i % 2]

  begin
    ui.send(:play_vs_bot)
  rescue StandardError => e
    crashes += 1
    puts "ИГРА ##{i} УПАЛА: #{e.class}: #{e.message}"
    puts e.backtrace.first(6)
  end
end

puts "Готово: #{GAMES} партий через UI (человек всегда берёт первую карту в руке), крашей: #{crashes}"
puts "Пример финального алерта: #{ALERTS.last.inspect}" if ALERTS.any?
exit(crashes.zero? ? 0 : 1)
