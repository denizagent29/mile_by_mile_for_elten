# frozen_string_literal: true

module MileByMile
  # Управляет ходом партии: очередь ходов, применение карт, проверка правил, победа.
  class Game
    RuleViolation = Car::RuleViolation

    attr_reader :players, :deck, :discard_pile, :distance_target, :current_index

    def initialize(players, distance_target: 1000, include_remove_all_safeties: false, deck_class: Deck)
      raise ArgumentError, 'need at least 2 players' if players.size < 2

      @players = players
      @distance_target = distance_target
      @deck = deck_class.new(include_remove_all_safeties: include_remove_all_safeties).shuffle!
      @discard_pile = []
      @deck.deal(@players, 6)
      @current_index = rand(@players.size)
    end

    def current_player
      players[current_index]
    end

    def winner
      players.find { |p| p.car.distance == distance_target }
    end

    def finished?
      !winner.nil? || deck.empty?
    end

    # card   — карта из руки текущего игрока
    # target — игрок-цель, обязателен для HazardCard и RemoveAllSafetiesCard
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
      player.draw(deck)
      advance_turn!
    end

    # успешно сыграна: в отбой, добор карты, ход следующему
    def discard_played(player, card)
      player.discard(card, discard_pile)
      player.draw(deck)
      advance_turn!
    end

    # успешная первая защита: в отбой, добор карты, ход СОХРАНЯЕТСЯ
    def discard_keep_turn(player, card)
      player.discard(card, discard_pile)
      player.draw(deck)
    end

    def play_distance(player, card)
      car = player.car
      return discard_wasted(player, card) unless car.moving?
      return discard_wasted(player, card) if car.speed_limited? && card.miles > 50

      if car.reversed?
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
        return discard_wasted(player, card) if car.running?

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
        # всегда можно сыграть, если нет защиты
      end

      tcar.apply_hazard!(card.type)
      discard_played(player, card)
    end

    def play_remove_all_safeties(player, card, target)
      raise RuleViolation, 'a target is required' unless target
      raise RuleViolation, 'no such player in this game' unless players.include?(target)

      target.car.clear_safeties!
      discard_played(player, card)
    end

    def advance_turn!
      loop do
        @current_index = (@current_index + 1) % players.size
        break unless current_player.car.consume_skip_turn!
      end
    end
  end
end
