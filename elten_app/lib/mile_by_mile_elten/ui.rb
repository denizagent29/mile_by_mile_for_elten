# frozen_string_literal: true

module MileByMileElten
  class UI
    include MileByMile

    DISTANCE_OPTIONS = [1000, 2000, 3000, 4000, 5000].freeze
    VARIANTS = [
      [:cars, 'Cars'],
      [:horses, 'Horses']
    ].freeze
    # Количество общих колод: N полных колод, перемешанных вместе.
    DECK_COPY_COUNTS = [1, 2, 3, 4, 5].freeze
    DECK_LABELS = {
      1 => '1 common deck',
      2 => '2 common decks',
      3 => '3 common decks',
      4 => '4 common decks',
      5 => '5 common decks'
    }.freeze
    # Индекс «3 общие колоды» в списке [своя у каждого, 1..5 общих].
    DEFAULT_DECK_INDEX = 3

    # В Elten 3.0 функциональные клавиши распознаются только по VK-коду
    # (символы вида :key_f2 дают keycode 0 и никогда не срабатывают).
    KEY_F2 = 0x71
    KEY_F3 = 0x72

    IMMOBILIZING = %i[stall empty_tank flat_tire accident].freeze

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

    # Elten's gettext reads .mo strings as ASCII-8BIT; re-tag to UTF-8 so
    # join/% with UTF-8 literals don't raise Encoding::CompatibilityError.
    def _(msgid)
      super(msgid).dup.force_encoding(Encoding::UTF_8)
    end

    def play_vs_bot
      settings = choose_settings
      return if settings.nil?

      variant, distance, deck_mode, deck_copies = settings

      @audio.variant = variant
      deck_class = variant == :horses ? Variants::HorseDeck : Deck

      @human = Player.new(_('You'))
      @bot_player = Player.new(_('Bot'))
      @game = Game.new([@human, @bot_player], distance_target: distance, deck_class: deck_class, deck_mode: deck_mode, deck_copies: deck_copies)
      @bot = Bot.new(@game, @bot_player)

      @move_history = []
      @pending_bot_actions = []
      @pending_draw_message = nil

      @audio.welcome
      alert(start_announcement, false)
      return if play_rounds == :aborted

      announce_result
    end

    # Настройки одной формой: три переключателя (набор карт, дистанция,
    # количество колод) и кнопки ОК/Отмена. По умолчанию — 3 общие колоды.
    # Возвращает [variant, distance, deck_mode, deck_copies] или nil.
    def choose_settings
      variant_labels = VARIANTS.map { |_id, label| _(label) }
      distance_labels = DISTANCE_OPTIONS.map { |d| _('%{d} miles') % { d: d } }
      deck_labels = [_('Each player has their own deck')]
      DECK_COPY_COUNTS.each { |n| deck_labels << _(DECK_LABELS[n]) }

      fields = [
        ChoiceListBox.new([[_('Card set'), variant_labels, 0]], header: _('Card set')),
        ChoiceListBox.new([[_('Distance'), distance_labels, 0]], header: _('Distance')),
        ChoiceListBox.new([[_('Number of decks'), deck_labels, DEFAULT_DECK_INDEX]], header: _('Number of decks'))
      ]
      accept = Button.new(_('OK'))
      cancel = Button.new(_('Cancel'))
      fields << accept << cancel
      form = Form.new(fields, index: 0)
      form.accept_button = accept
      form.cancel_button = cancel
      confirmed = false
      accept.on(:press) { confirmed = true; form.resume }
      cancel.on(:press) { form.resume }
      form.wait
      return nil unless confirmed

      variant = VARIANTS[fields[0].value(0)][0]
      distance = DISTANCE_OPTIONS[fields[1].value(0)]
      deck_idx = fields[2].value(0)
      deck_mode = deck_idx.zero? ? :separate : :shared
      deck_copies = [deck_idx, 1].max
      [variant, distance, deck_mode, deck_copies]
    end

    # Стартовый анонс: «Поехали! По воле судьбы первым ходите вы / ходит бот.»,
    # а для человека ещё и первая карта руки: «Вы взяли завестись.»
    def start_announcement
      phrase =
        if @game.current_player.equal?(@human)
          _('By fate\'s will, you move first.')
        else
          _('By fate\'s will, the bot moves first.')
        end
      text = "#{_('Let\'s go!')} #{phrase}"
      first_card = @game.current_player.equal?(@human) ? @human.hand.first : nil
      text += " #{draw_phrase(@human, first_card)}" if first_card
      text
    end

    # Основной цикл партии. Возвращает :aborted, если игрок подтвердил выход.
    def play_rounds
      until @game.finished?
        if @game.current_player.equal?(@human)
          announce_turn_start
          return :aborted if human_turn == :aborted
        else
          return :aborted if bot_turn == :aborted
        end
      end
      nil
    end

    # --- ход игрока ---

    def human_turn
      loop do
        return nil if @human.hand.empty?

        card = pick_card
        return :aborted if card == :aborted

        target = card.opponent_only? ? @bot_player : nil
        before = @human.hand.dup
        begin
          result = @game.play(card, target: target)
        rescue MileByMile::Game::RuleViolation => e
          alert(e.message, false)
          next
        end

        @audio.card_played(card)
        action = record_move(@human, card, target: target, result: result)
        drawn = (@human.hand - before).first
        @pending_draw_message = drawn ? draw_phrase(@human, drawn) : nil

        if @game.finished?
          alert(action, false)
          return nil
        elsif @game.current_player.equal?(@human)
          # карта сохранила ход (первая защита) — анонсируем и продолжаем
          alert(action, false)
        else
          alert("#{action} #{_('The bot moves.')}", false)
          return nil
        end
      end
    end

    # Список карт руки на ListBox внутри Runner: Enter выбирает карту,
    # F2/F3/Escape активны всё время хода. Возвращает карту или :aborted.
    def pick_card
      loop do
        options = @human.hand.map { |c| _(c.name) }
        header = "#{_('Your turn')}. #{status_for(@human.car)}"
        picked = nil
        runner = Runner.new
        runner.on_key(KEY_F2) { safely { say_last_move } }
        runner.on_key(KEY_F3) { safely { say_status } }
        runner.on_key(:key_escape) do |current|
          current.stop(:aborted) if confirm(_('End the game?'))
        end
        list = ListBox.new(options, header: header, index: 0, flags: ListBox::Flags::AnyDir, quiet: false)
        list.on(:select) { |selection| picked = selection[0] }
        runner.on_tick do
          list.update
          runner.stop if picked != nil
        end
        list.focus
        return :aborted if runner.run == :aborted
        return @human.hand[picked] if picked
      end
    end

    # --- ход бота ---

    def bot_turn
      return :aborted if bot_think == :aborted

      card, target = @bot.choose_move
      return nil if card.nil?

      begin
        result = @game.play(card, target: target)
      rescue MileByMile::Game::RuleViolation
        fallback = @bot_player.hand.find { |c| c.is_a?(RemedyCard) || c.is_a?(SafetyCard) }
        return nil unless fallback

        result = @game.play(fallback, target: nil)
        card = fallback
      end

      @audio.card_played(card)
      (@pending_bot_actions ||= []) << record_move(@bot_player, card, target: target, result: result)
      nil
    end

    # Пауза перед ходом бота: рандом 2-4 секунды (сложный выбор — до ~5.5).
    # В это время F2/F3/Escape активны. Анонс «Бот думает...» не перебивает
    # предыдущую речь (stop: false).
    def bot_think
      runner = Runner.new
      runner.on_key(KEY_F2) { safely { say_last_move } }
      runner.on_key(KEY_F3) { safely { say_status } }
      runner.on_key(:key_escape) do |current|
        current.stop(:aborted) if confirm(_('End the game?'))
      end
      runner.after(@bot.think_duration) { |current| current.stop }
      speak(_('The bot is thinking...'), stop: false)
      runner.run == :aborted ? :aborted : nil
    end

    # Озвучка перед ходом человека: что сделал бот, что вы взяли, ваш ход.
    def announce_turn_start
      # стартовый анонс уже назвал первого ходящего — повторять «Ваш ход» не нужно
      return if @move_history.empty?

      parts = []
      parts.concat(@pending_bot_actions) unless @pending_bot_actions.nil?
      parts << @pending_draw_message
      parts << _('Your turn.')
      alert(parts.compact.join(' '), true)
      @pending_bot_actions = []
      @pending_draw_message = nil
    end

    # --- история ходов и статусы ---

    def record_move(player, card, target: nil, result:)
      text = action_phrase(player, card, target: target, result: result)
      @move_history << text
      @move_history.shift if @move_history.size > 100
      text
    end

    # Фраза действия: что сыграл (или сбросил) игрок. Именно её NVDA читает
    # после хода, поэтому она же попадает в историю для F2.
    def action_phrase(player, card, target: nil, result:)
      me = player.equal?(@human)
      return discard_phrase(player, card) if result == :wasted

      case card
      when DistanceCard
        distance_phrase(me, player.car.reversed?, card)
      when RemedyCard
        remedy_phrase(me, card.type)
      when SafetyCard
        me ? _('You protected yourself from %{hazard}.') % { hazard: hazard_genitive(card.type) } : _('The bot protected itself from %{hazard}.') % { hazard: hazard_genitive(card.type) }
      when HazardCard
        hazard_phrase(me, card.type)
      when RemoveAllSafetiesCard
        me ? _('You stripped the bot\'s protections.') : _('The bot stripped your protections.')
      end
    end

    def distance_phrase(me, backward, card)
      if backward
        me ? _('You drove back %{miles}.') % { miles: _(card.name) } : _('The bot drove back %{miles}.') % { miles: _(card.name) }
      else
        me ? _('You drove %{miles}.') % { miles: _(card.name) } : _('The bot drove %{miles}.') % { miles: _(card.name) }
      end
    end

    def remedy_phrase(me, type)
      case type
      when :start then me ? _('You started your car.') : _('The bot started its engine.')
      when :refuel then me ? _('You refueled.') : _('The bot refueled.')
      when :repair_tire then me ? _('You fixed the tire.') : _('The bot fixed the tire.')
      when :repair then me ? _('You repaired your car.') : _('The bot repaired its car.')
      when :turn_forward then me ? _('You turned forward.') : _('The bot turned forward.')
      when :remove_speed_limit then me ? _('You removed the speed limit.') : _('The bot removed the speed limit.')
      end
    end

    # Родительный падеж после «защитился от ...» — как в ушной игре.
    def hazard_genitive(type)
      case type
      when :stall then _('engine stalling')
      when :empty_tank then _('fuel draining')
      when :flat_tire then _('a flat tire')
      when :accident then _('an accident')
      when :turned_back then _('being turned around')
      when :speed_limit then _('the speed limit')
      when :skip_turn then _('skipping a turn')
      end
    end

    def hazard_phrase(me, type)
      case type
      when :stall then me ? _('You stalled the bot\'s engine.') : _('The bot stalled your engine.')
      when :empty_tank then me ? _('You drained the bot\'s tank.') : _('The bot drained your tank.')
      when :flat_tire then me ? _('You gave the bot a flat tire.') : _('The bot gave you a flat tire.')
      when :accident then me ? _('You crashed the bot.') : _('The bot crashed you.')
      when :turned_back then me ? _('You turned the bot around.') : _('The bot turned you around.')
      when :speed_limit then me ? _('You limited the bot\'s speed.') : _('The bot limited your speed.')
      when :skip_turn then me ? _('You made the bot skip a turn.') : _('The bot made you skip a turn.')
      end
    end

    def draw_phrase(player, card)
      me = player.equal?(@human)
      me ? _('You drew %{card}.') % { card: _(card.name) } : _('The bot drew %{card}.') % { card: _(card.name) }
    end

    def discard_phrase(player, card)
      me = player.equal?(@human)
      me ? _('You discarded %{card}.') % { card: _(card.name) } : _('The bot discarded %{card}.') % { card: _(card.name) }
    end

    # F2: последний ход
    def say_last_move
      if @move_history && @move_history.any?
        speak(@move_history.last)
      else
        speak(_('No moves yet.'))
      end
    end

    # F3: дистанция и можно ли ехать (что мешает — если мешает)
    def say_status
      return speak(_('No game in progress.')) unless @human && @game

      car = @human.car
      blockers = move_blockers(car)
      text =
        if blockers.empty?
          _('%{d} miles. You can move.') % { d: car.distance }
        else
          _('%{d} miles. You cannot move: %{reasons}.') % { d: car.distance, reasons: blockers.join(', ') }
        end
      speak(text)
    end

    # Что мешает ехать — фразами ушной игры («Мотор заглушен», «Бензин слит»...).
    def move_blockers(car)
      blockers = []
      blockers << _('Fuel drained') if car.stalled_by?(:empty_tank)
      blockers << _('Tire flat') if car.stalled_by?(:flat_tire)
      blockers << _('In an accident') if car.stalled_by?(:accident)
      immobilized = IMMOBILIZING.any? { |t| car.stalled_by?(t) }
      blockers << _('Engine stalled') if car.stalled_by?(:stall) || (!car.running? && !immobilized)
      blockers << _('Speed limited') if car.speed_limited?
      blockers << _('Turned back') if car.reversed?
      blockers
    end

    # Короткий статус для заголовка списка карт: «1000 миль, Можно ехать».
    def status_for(car)
      blockers = move_blockers(car)
      ([_('%{d} miles') % { d: car.distance }] + (blockers.empty? ? [_('You can move.')] : blockers)).join(', ')
    end

    # Обёртка для обработчиков F2/F3: ни одно исключение не должно вылететь
    # из обработчика клавиш внутрь Runner (защита от вылета Elten).
    def safely
      yield
    rescue StandardError
      begin
        speak(_('Cannot display the status.'))
      rescue StandardError
        nil
      end
    end

    def announce_result
      winner = @game.winner
      if winner.equal?(@human)
        @audio.win
        alert(_('You are at the finish line. Congratulations!'), true)
      elsif winner != nil
        alert(_('The bot is at the finish line.'), true)
      else
        alert(_('The deck ran out. Draw.'), true)
      end
    end

    def show_help
      display_text([
        _('The goal is to be the first to cover the target distance exactly, without overshooting.'),
        _('Distance cards (25/50/75/100/200 miles) move you forward once your car is started and nothing blocks it.'),
        _('Hazard cards are played against an opponent: stall the engine, empty the tank, flat tire, accident, U-turn, speed limit, skip a turn.'),
        _('Remedy cards fix your own car: start the engine, refuel, fix the tire, repair after accident, end of U-turn, end of speed limit.'),
        _('Safety cards are played on yourself once and permanently block one kind of hazard. Playing one for the first time keeps your turn.'),
        _("If a card can't take effect (for example, refueling a full tank), it is simply discarded and the turn passes on."),
        _('During the game: F2 — the last move, F3 — your distance and whether you can move. Escape — end the game.')
      ].join("\n\n"), header: _('Rules'))
    end
  end
end
