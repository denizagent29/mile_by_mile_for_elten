# frozen_string_literal: true

module MileByMile
  # Управляет ходом партии: очередь ходов, применение карт, проверка правил, победа.
  class Game
    RuleViolation = Car::RuleViolation

    attr_reader :players, :deck, :discard_pile, :distance_target, :current_index

    def initialize(players, distance_target: 1000, include_remove_all_safeties: false, deck_class: Deck, deck_mode: :shared, deck_copies: 1)
      raise ArgumentError, 'need at least 2 players' if players.size < 2
      raise ArgumentError, "unknown deck_mode: #{deck_mode}" unless %i[shared separate].include?(deck_mode)
      deck_copies = deck_copies.to_i
      raise ArgumentError, 'deck_copies must be at least 1' if deck_copies < 1

      @players = players
      @distance_target = distance_target
      @deck_mode = deck_mode
      @discard_pile = []
      if deck_mode == :separate
        # своя колода у каждого игрока: раздача и добор идут из своей колоды
        @deck = nil
        players.each do |player|
          player.deck = deck_class.new(include_remove_all_safeties: include_remove_all_safeties).shuffle!
          6.times { player.hand << player.deck.draw }
        end
      else
        @deck = deck_class.new(include_remove_all_safeties: include_remove_all_safeties, copies: deck_copies).shuffle!
        @deck.deal(@players, 6)
      end
      @current_index = rand(@players.size)
      # стартовый игрок берёт седьмую карту (как в ухе)
      draw_for(current_player)
    end

    def current_player
      players[current_index]
    end

    def winner
      players.find { |p| p.car.distance == distance_target }
    end

    def finished?
      # колода бесконечно пополняется из сброса, так что партия заканчивается
      # только победой — либо тупиком, когда всем нечего брать и ходить
      !winner.nil? || stuck?
    end

    # card   — карта из руки текущего игрока
    # target — игрок-цель, обязателен для HazardCard и RemoveAllSafetiesCard
    # Возвращает :played (сыграна, ход уходит), :kept_turn (сыграна, ход
    # остаётся — первая защита) или :wasted (уходит в отбой как неприменимая).
    def play(card, target: nil)
      raise RuleViolation, 'the game is over' if finished?

      player = current_player
      raise RuleViolation, 'this card is not in hand' unless player.has_card?(card)
      raise RuleViolation, 'a hazard card cannot be played on yourself' if card.opponent_only? && target == player
      raise RuleViolation, 'this card can only be played on yourself' if card.self_only? && !target.nil? && target != player

      case card
      when DistanceCard then play_distance(player, card)
      when RemedyCard then play_remedy(player, card)
      when SafetyCard then play_safety(player, card)
      when RemoveAllSafetiesCard then play_remove_all_safeties(player, card, target)
      when HazardCard then play_hazard(player, card, target)
      else
        raise RuleViolation, "unknown card type: #{card.class}"
      end
    end

    private

    # уходит в отбой, ход передаётся следующему (использовано впустую)
    def discard_wasted(player, card)
      player.discard(card, discard_pile)
      advance_turn!
      :wasted
    end

    # успешно сыграна: в отбой, ход следующему (карту доберёт новый игрок
    # в начале своего хода)
    def discard_played(player, card)
      player.discard(card, discard_pile)
      advance_turn!
      :played
    end

    # успешная первая защита: в отбой, добор карты, ход СОХРАНЯЕТСЯ
    def discard_keep_turn(player, card)
      player.discard(card, discard_pile)
      draw_for(player)
      :kept_turn
    end

    def play_distance(player, card)
      car = player.car
      return discard_wasted(player, card) unless car.moving?
      return discard_wasted(player, card) if car.speed_limited? && card.miles > 50

      if car.reversed?
        # задним ходом можно ехать не дальше уже набранной дистанции —
        # иначе карта уходит в отбой (как в ухе)
        return discard_wasted(player, card) if car.distance < card.miles

        car.move!(card.miles)
        return discard_played(player, card)
      end

      new_distance = car.distance + card.miles
      return discard_wasted(player, card) if new_distance > distance_target

      car.move!(card.miles)
      discard_played(player, card)
    end

    def play_remedy(player, card)
      car = player.car
      hazard_type = card.cures

      case hazard_type
      when :turned_back
        return discard_wasted(player, card) unless car.reversed?
        return discard_wasted(player, card) unless car.running?

        car.apply_remedy!(card.type)
        discard_played(player, card)
      when :stall
        # «Завестись» можно, только если бак, колёса и место в порядке
        # (как в ухе) — иначе карта уходит в отбой
        return discard_wasted(player, card) if car.running?
        return discard_wasted(player, card) if car.stalled_by?(:empty_tank)
        return discard_wasted(player, card) if car.stalled_by?(:flat_tire)
        return discard_wasted(player, card) if car.stalled_by?(:accident)

        car.apply_remedy!(card.type)
        discard_played(player, card)
      else
        return discard_wasted(player, card) unless car.stalled_by?(hazard_type)

        car.apply_remedy!(card.type)
        discard_played(player, card)
      end
    end

    def play_safety(player, card)
      car = player.car
      is_new = car.add_safety(card.type)

      if is_new
        discard_keep_turn(player, card)
      else
        discard_wasted(player, card)
      end
    end

    def play_hazard(player, card, target)
      raise RuleViolation, 'a hazard card needs a target' unless target
      raise RuleViolation, 'no such player in this game' unless players.include?(target)

      tcar = target.car
      return discard_wasted(player, card) if tcar.safety?(card.type)

      case card.type
      when :stall
        return discard_wasted(player, card) unless tcar.running?
      when :empty_tank, :flat_tire
        return discard_wasted(player, card) if tcar.stalled_by?(card.type)
      when :speed_limit
        return discard_wasted(player, card) if tcar.speed_limited?
      when :accident, :turned_back
        return discard_wasted(player, card) unless tcar.moving?
      when :skip_turn
        # всегда можно сыграть, если нет защиты; пропуски копятся и стакаются
      end

      tcar.apply_hazard!(card.type)
      if card.type == :skip_turn
        # ухо: карта «пропуск хода» перескакивает через цель сразу (та теряет
        # ход прямо сейчас), а накопленный счётчик сработает, когда очередь
        # дойдёт до цели — то есть цель пропускает ход ещё раз
        player.discard(card, discard_pile)
        @current_index = (@players.index(target) + 1) % players.size
        consume_skips_for_current!
        draw_for(current_player)
        :played
      else
        discard_played(player, card)
      end
    end

    def play_remove_all_safeties(player, card, target)
      raise RuleViolation, 'a target is required' unless target
      raise RuleViolation, 'no such player in this game' unless players.include?(target)

      target.car.clear_safeties!
      discard_played(player, card)
    end

    def draw_deck_for(player)
      @deck_mode == :separate ? player.deck : @deck
    end

    # добор с автопополнением колоды из сброса, когда она пуста
    def draw_for(player)
      deck = draw_deck_for(player)
      deck.refill_from(discard_pile) if deck.empty?
      player.draw(deck)
    end

    # партия в тупике: нечего брать (колода пуста и не пополняется) и ни у
    # кого нет карт в руке — дальше ходов не будет
    def stuck?
      return false if discard_pile.size >= 2

      players.all? { |p| draw_deck_for(p).empty? && p.hand.empty? }
    end

    # ход переходит следующему; тот сразу добирает карту до полной руки —
    # седьмая берётся перед своим ходом, а не сразу после хода соперника
    def advance_turn!
      @current_index = (@current_index + 1) % players.size
      consume_skips_for_current!
      draw_for(current_player)
    end

    # перескакиваем через текущего игрока, пока у него есть накопленные
    # пропуски хода — каждый визит съедает один пропуск
    def consume_skips_for_current!
      while current_player.car.consume_skip_turn!
        @current_index = (@current_index + 1) % players.size
      end
    end
  end
end
