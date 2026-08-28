# frozen_string_literal: true

module MileByMileElten
  class UI
    include MileByMile

    DISTANCE_OPTIONS = [700, 1000].freeze
    VARIANTS = [
      [:cars, 'Cars'],
      [:horses, 'Horses']
    ].freeze

    def initialize(program)
      @program = program
      @audio = Audio.new(program)
    end

    def main
      loop do
        index = selector(
          [_('Play against the bot'), _('Rules'), _('Exit')],
          header: _('Mile by Mile'),
          start_index: 0,
          cancel_index: 2
        )
        case index
        when 0 then play_vs_bot
        when 1 then show_help
        else break
        end
      end
    end

    private

    def play_vs_bot
      variant = choose_variant
      return if variant.nil?

      distance = choose_distance
      return if distance.nil?

      @audio.variant = variant
      deck_class = variant == :horses ? Variants::HorseDeck : Deck

      human = Player.new(_('You'))
      bot_player = Player.new(_('Bot'))
      game = Game.new([human, bot_player], distance_target: distance, deck_class: deck_class)
      bot = Bot.new(game, bot_player)

      @audio.welcome
      alert(_('The game has started. Distance: %{d} miles.') % { d: distance }, false)

      @pending_bot_message = nil
      @pending_draw_message = nil

      until game.finished?
        if game.current_player.equal?(human)
          announce_turn_start
          human_turn(game, human, bot_player)
        else
          bot_turn(game, bot, bot_player)
        end
      end

      announce_result(game, human)
    end

    def choose_variant
      labels = VARIANTS.map { |_id, label| _(label) }
      index = selector(labels, header: _('Choose a card set'), start_index: 0, cancel_index: labels.size)
      return nil if index >= VARIANTS.size

      VARIANTS[index][0]
    end

    def choose_distance
      labels = DISTANCE_OPTIONS.map { |d| _('%{d} miles') % { d: d } }
      index = selector(labels, header: _('Choose the distance'), start_index: 1, cancel_index: labels.size)
      return nil if index >= DISTANCE_OPTIONS.size

      DISTANCE_OPTIONS[index]
    end

    def human_turn(game, human, opponent)
      header = "#{_('Your turn')}. #{status_for(human.car)}"
      options = human.hand.map { |c| _(c.name) }
      index = selector(options, header: header, start_index: 0)
      card = human.hand[index]
      target = card.opponent_only? ? opponent : nil

      before = human.hand.dup
      begin
        game.play(card, target: target)
      rescue MileByMile::Game::RuleViolation => e
        alert(e.message, false)
        return human_turn(game, human, opponent)
      end

      @audio.card_played(card)
      drawn = (human.hand - before).first
      if drawn
        @audio.card_drawn(drawn)
        @pending_draw_message = _('You drew %{card}.') % { card: _(drawn.name) }
      else
        @pending_draw_message = nil
      end
    end

    def bot_turn(game, bot, bot_player)
      card, target = bot.choose_move
      return if card.nil?

      begin
        game.play(card, target: target)
      rescue MileByMile::Game::RuleViolation
        fallback = bot_player.hand.find { |c| c.is_a?(RemedyCard) || c.is_a?(SafetyCard) }
        game.play(fallback, target: nil) if fallback
        card = fallback || card
      end

      @audio.card_played(card)
      @pending_bot_message =
        if card.is_a?(DistanceCard)
          _('%{player} moved %{miles} miles.') % { player: bot_player.name, miles: card.miles }
        else
          _('%{player} played: %{card}.') % { player: bot_player.name, card: _(card.name) }
        end
    end

    # Озвучка перед ходом человека: что сделал соперник + что вы взяли + ваш ход.
    # Пример: "Bot moved 50 miles. You drew 100 miles. Your turn."
    def announce_turn_start
      parts = [@pending_bot_message, @pending_draw_message, _('Your turn.')].compact
      alert(parts.join(' '), false) unless parts.empty?
      @pending_bot_message = nil
      @pending_draw_message = nil
    end

    def status_for(car)
      parts = []
      parts << (_('%{d} miles') % { d: car.distance })
      parts << (car.running? ? _('running') : _('not started'))
      parts << _('turned around') if car.reversed?
      parts << _('speed limited') if car.speed_limited?
      parts.join(', ')
    end

    def announce_result(game, human)
      winner = game.winner
      if winner.equal?(human)
        @audio.win
        alert(_('You won! The distance is covered.'))
      elsif winner != nil
        alert(_('The bot won. Better luck next time.'))
      else
        alert(_('The deck ran out. Draw.'))
      end
    end

    def show_help
      display_text([
        _('The goal is to be the first to cover the target distance exactly, without overshooting.'),
        _('Distance cards (25/50/75/100/200 miles) move you forward once your car is started and nothing blocks it.'),
        _('Hazard cards are played against an opponent: stall the engine, empty the tank, flat tire, accident, U-turn, speed limit, skip a turn.'),
        _('Remedy cards fix your own car: start the engine, refuel, fix the tire, repair after accident, end of U-turn, end of speed limit.'),
        _('Safety cards are played on yourself once and permanently block one kind of hazard. Playing one for the first time keeps your turn.'),
        _("If a card can't take effect (for example, refueling a full tank), it is simply discarded and the turn passes on.")
      ].join("\n\n"), header: _('Rules'))
    end
  end
end
