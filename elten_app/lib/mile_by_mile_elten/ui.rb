# frozen_string_literal: true

module MileByMileElten
  class UI
    include MileByMile

    DISTANCE_OPTIONS = [
      [700, 'Короткая партия (700 миль)'],
      [1000, 'Классическая партия (1000 миль)']
    ].freeze

    def initialize(program)
      @program = program
      @audio = Audio.new(program)
    end

    def main
      loop do
        index = selector(
          [_('Играть с ботом'), _('Правила'), _('Выход')],
          header: _('Миля за милей'),
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
      distance = choose_distance
      return if distance.nil?

      human = Player.new(_('Вы'))
      bot_player = Player.new(_('Бот'))
      game = Game.new([human, bot_player], distance_target: distance)
      bot = Bot.new(game, bot_player)

      alert(_('Игра началась. Дистанция: %{d} миль.') % { d: distance }, false)

      until game.finished?
        if game.current_player.equal?(human)
          @audio.your_turn
          human_turn(game, human, bot_player)
        else
          @audio.bot_turn
          bot_turn(game, bot, bot_player)
        end
      end

      announce_result(game, human)
    end

    def choose_distance
      labels = DISTANCE_OPTIONS.map { |_miles, label| _(label) }
      index = selector(labels, header: _('Выберите дистанцию'), start_index: 1, cancel_index: labels.size)
      return nil if index >= DISTANCE_OPTIONS.size

      DISTANCE_OPTIONS[index][0]
    end

    def human_turn(game, human, opponent)
      loop do
        header = "#{_('Ваш ход')}. #{status_for(human.car)}"
        options = human.hand.map(&:name)
        index = selector(options, header: header, start_index: 0)
        card = human.hand[index]
        target = card.opponent_only? ? opponent : nil

        begin
          game.play(card, target: target)
          @audio.card_played(card)
          return
        rescue MileByMile::Game::RuleViolation => e
          @audio.wasted
          alert(e.message, false)
        end
      end
    end

    def bot_turn(game, bot, bot_player)
      card, target = bot.choose_move
      if card.nil?
        # у бота нет карт вовсе (колода и рука пусты) — партия и так завершится
        return
      end

      begin
        game.play(card, target: target)
      rescue MileByMile::Game::RuleViolation
        fallback = bot_player.hand.find { |c| c.is_a?(RemedyCard) || c.is_a?(SafetyCard) }
        game.play(fallback, target: nil) if fallback
      end

      @audio.card_played(card)
      alert(_('Бот сыграл: %{card}') % { card: card.name }, false)
    end

    def status_for(car)
      parts = []
      parts << (_('%{d} миль') % { d: car.distance })
      parts << (car.running? ? _('на ходу') : _('не заведена'))
      parts << _('развёрнута назад') if car.reversed?
      parts << _('ограничение скорости') if car.speed_limited?
      parts.join(', ')
    end

    def announce_result(game, human)
      winner = game.winner
      if winner.equal?(human)
        @audio.win
        alert(_('Вы выиграли! Дистанция пройдена.'))
      elsif winner != nil
        @audio.lose
        alert(_('Бот выиграл. В следующий раз повезёт больше.'))
      else
        @audio.draw
        alert(_('Колода закончилась. Ничья.'))
      end
    end

    def show_help
      show_text(_('Правила'), [
        _('Цель — первым проехать заданное расстояние ровно, без превышения.'),
        _('Карты движения (25/50/75/100/200 миль) едут вперёд, если машина заведена и ничего не мешает.'),
        _('Карты вредительства играются на соперника: заглушить мотор, слить бензин, проколоть колесо, авария, развернуть назад, ограничить скорость, пропустить ход.'),
        _('Карты противодействия чинят вашу же машину: завестись, налить бензин, накачать колесо, починиться после аварии, развернуться вперёд, убрать ограничение скорости.'),
        _('Карты защиты ставятся на себя один раз и навсегда закрывают от одного вида вредительства. Если вы играете такую защиту впервые — ход остаётся у вас.'),
        _('Если карта не может подействовать (например, вы наливаете бензин в полный бак), она просто уходит в отбой и ход передаётся дальше.')
      ].join("\n\n"))
    end

    def show_text(header, text)
      field = EditBox.new(header, type: EditBox::Flags::MultiLine | EditBox::Flags::ReadOnly, text: text.to_s, quiet: false)
      loop do
        loop_update
        field.update
        break if key_pressed?(:key_escape) || key_pressed?(:key_enter)
      end
    end
  end
end
