# frozen_string_literal: true

# Two-sided multiplayer smoke test. Simulates host and guest as two UI
# instances connected through an in-memory transport, each driven by its own
# thread. Both humans always play the first card in their hand (ListBox stub).
# Verifies: handshake order, that both engines finish in sync, and that the
# winners agree.

require_relative '../lib/mile_by_mile'
require_relative '../elten_app/lib/mile_by_mile_elten/bot'
require_relative '../elten_app/lib/mile_by_mile_elten/audio'
require_relative '../elten_app/lib/mile_by_mile_elten/ui'

# --- minimal Elten API stubs ---
def _(s) = s.to_s
def n_(a, b, n) = n == 1 ? a : b

ALERTS = []
def alert(text, _wait = true)
  ALERTS << text
end

$selector_script = []
def selector(options, header: '', start_index: 0, cancel_index: nil, **_kw)
  idx = $selector_script.empty? ? 0 : $selector_script.shift
  idx = [options.size - 1, idx].min
  idx
end

$confirm_result = true
def confirm(_text = '')
  $confirm_result
end

def dialog_open; end
def dialog_close; end

SPEECH = []
def speak(text, stop: true, **_kw)
  SPEECH << text
end

$input_text_result = 'Guest'
def input_text(_header, **_kw)
  $input_text_result
end

module EltenLink
  def self.client(ctx)
    ctx
  end

  module Profiles
    def self.card(_client, user)
      UserCard.new(name: user, status: Status.new(online: true))
    end
  end
end

class Status
  attr_reader :online

  def initialize(online:)
    @online = online
  end
end

class UserCard
  attr_reader :name, :status

  def initialize(name:, status:)
    @name = name
    @status = status
  end
end

$form_values_script = []
class ChoiceListBox
  attr_reader :rows

  def initialize(rows, header: '', index: 0, quiet: false, flags: 0, **_kw)
    @rows = rows
  end

  def value(row)
    @rows[row][2]
  end

  def update; end
end

class Button
  def initialize(label)
    @label = label
    @events = Hash.new { |h, k| h[k] = [] }
  end

  def on(event, &block)
    @events[event] << block
    self
  end

  def press
    @events[:press].each(&:call)
  end

  def update; end
end

class Form
  attr_accessor :accept_button, :cancel_button

  def initialize(fields, index: 0)
    @fields = fields
  end

  def wait
    vals = $form_values_script.empty? ? [0, 0, 0] : $form_values_script.shift
    @fields.each_with_index do |field, i|
      field.rows[0][2] = vals[i] if field.is_a?(ChoiceListBox) && vals[i]
    end
    accept_button.press if accept_button
  end

  def resume; end

  def update; end
end

DISPLAYED_TEXT = []
def display_text(text, header: '', **_kw)
  DISPLAYED_TEXT << [header, text]
end

class ListBox
  module Flags
    MultiSelection = 1
    AnyDir = 16
    HotKeys = 32
  end

  attr_reader :index, :options

  def initialize(options, header: '', index: 0, flags: 0, quiet: false, **_kw)
    @options = options
    @index = index
    @events = Hash.new { |h, k| h[k] = [] }
    @updated = false
  end

  def on(event, &block)
    @events[event] << block
    self
  end

  def focus(*_args); end

  def update
    return if @updated || @options.empty?

    @updated = true
    @index = 0
    @events[:select].each { |block| block.call([@index]) }
  end
end

# Endless Runner (until stop) with wall-clock one-shot/every timers — the real
# Elten Runner blocks until stopped, which is what multiplayer waits need.
class Runner
  attr_reader :result

  def initialize(frame_interval: 0.0)
    @timers = []
    @key_handlers = []
    @tick = nil
    @running = false
    @result = nil
  end

  def after(delay, phase: :timer, &block)
    @timers << { phase: :after, block: block, fired: false, delay: delay }
    self
  end

  def every(_interval, **_, &block)
    @timers << { phase: :every, block: block, fired: false, delay: 0 }
    self
  end

  def on_key(_key, **_kw, &block)
    @key_handlers << block
    self
  end

  def on_tick(&block)
    @tick = block
    self
  end

  def run
    @running = true
    @result = nil
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @timers.each { |t| t[:fire_at] = start + t[:delay].to_f }
    while @running
      @tick.call(self) if @tick
      break unless @running

      @timers.each do |t|
        next if t[:fired]
        next unless Process.clock_gettime(Process::CLOCK_MONOTONIC) >= t[:fire_at]

        t[:fired] = true
        t[:block].call(self)
      end
      sleep 0.001
    end
    @result
  end

  def stop(result = nil)
    @result = result
    @running = false
    result
  end
end

class EditBox
  module Flags
    MultiLine = 1
    ReadOnly = 2
  end

  def initialize(header, type:, text:, quiet:); end
  def update; end
end

# --- transport: routes signals between two UI instances ---
class Transport
  def initialize
    @peers = {}
    @mutex = Mutex.new
  end

  def register(nick, ui)
    @peers[nick] = ui
  end

  def signal(from, to, packet)
    @mutex.synchronize do
      peer = @peers[to]
      peer&.handle_signal(from, packet)
    end
  end
end

class FakeProgram
  attr_reader :sent

  def initialize(nick, transport)
    @nick = nick
    @transport = transport
    @sent = []
  end

  def signal(user, packet)
    @sent << [user, packet]
    @transport.signal(@nick, user, packet)
  end

  def play_app_sound(name, **_kw)
    true
  end
end

# --- run the two-sided game ---
GAMES = (ARGV[0] || 5).to_i
errors = 0

GAMES.times do |i|
  ALERTS.clear
  SPEECH.clear
  transport = Transport.new
  host_prog = FakeProgram.new('Host', transport)
  guest_prog = FakeProgram.new('Guest', transport)

  host_ui = MileByMileElten::UI.new(host_prog)
  guest_ui = MileByMileElten::UI.new(guest_prog)
  transport.register('Host', host_ui)
  transport.register('Guest', guest_ui)

  $form_values_script = [[0, 1, 3]] # cars, 2000 miles, 3 common decks
  $input_text_result = 'Guest'

  host_result = nil
  guest_result = nil
  host_thread = Thread.new { host_result = host_ui.send(:host_game) }
  guest_thread = Thread.new { guest_result = guest_ui.send(:wait_for_invite) }

  # watchdog: fail loudly instead of hanging forever on a desync
  watchdog = Thread.new do
    sleep 30
    host_thread.kill
    guest_thread.kill
    abort "MP SMOKE ##{i} HUNG (possible desync)"
  end

  host_thread.join
  guest_thread.join
  watchdog.kill

  hg = host_ui.instance_variable_get(:@game)
  gg = guest_ui.instance_variable_get(:@game)
  host_moves = host_prog.sent.count { |_u, p| p[:type] == 'move' }
  guest_moves = guest_prog.sent.count { |_u, p| p[:type] == 'move' }

  ok = true
  ok = false unless host_result == :played
  ok = false unless guest_result == :played
  ok = false unless hg.finished? && gg.finished?
  ok = false unless host_moves + guest_moves > 0
  # имена игроков на двух сторонах разные (каждый называет себя "You"),
  # поэтому сверяем ПОЗИЦИЮ победителя в массиве игроков — движки идентичны
  widx_h = hg.players.index(hg.winner)
  widx_g = gg.players.index(gg.winner)
  ok = false unless widx_h == widx_g

  puts "MP GAME ##{i}: host=#{host_result.inspect} guest=#{guest_result.inspect} " \
       "host_finished=#{hg.finished?} guest_finished=#{gg.finished?} " \
       "moves(host=#{host_moves},guest=#{guest_moves}) " \
       "winner_slot(h=#{widx_h.inspect},g=#{widx_g.inspect}) sync=#{ok ? 'yes' : 'NO'}"

  # handshake order check
  types = host_prog.sent.map { |_u, p| p[:type] }.join(',')
  ok = false unless types.include?('invite') && types.include?('start')
  types_g = guest_prog.sent.map { |_u, p| p[:type] }.join(',')
  ok = false unless types_g.include?('accept')

  errors += 1 unless ok
end

puts errors.zero? ? 'ALL MP GAMES IN SYNC' : "MP FAILURES: #{errors}"
exit(errors.zero? ? 0 : 1)
