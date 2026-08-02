# frozen_string_literal: true

module MileByMile
  # Состояние машины (или общей машины команды).
  class Car
    IMMOBILIZING = %i[stall empty_tank flat_tire accident].freeze

    attr_reader :distance

    def initialize
      @distance = 0
      @running = false
      @active_hazards = {} # IMMOBILIZING типы => true
      @safeties = {}
      @speed_limited = false
      @reversed = false
      @skip_next_turn = false
    end

    def running?
      @running
    end

    # заведена и ничего не мешает ехать прямо сейчас
    def moving?
      running? && @active_hazards.empty?
    end

    def stalled_by?(type)
      @active_hazards.key?(type)
    end

    def reversed?
      @reversed
    end

    def speed_limited?
      @speed_limited
    end

    def safety?(type)
      @safeties.key?(type)
    end

    def add_safety(type)
      already_had = safety?(type)
      @safeties[type] = true
      !already_had
    end

    def clear_safeties!
      @safeties.clear
    end

    def skip_next_turn?
      @skip_next_turn
    end

    # применяется на цель (соперника)
    def apply_hazard!(type)
      case type
      when *IMMOBILIZING
        @active_hazards[type] = true
        @running = false
      when :turned_back
        @reversed = true
      when :speed_limit
        @speed_limited = true
      when :skip_turn
        @skip_next_turn = true
      else
        raise ArgumentError, "неизвестное вредительство: #{type}"
      end
    end

    # применяется игроком на себя
    def apply_remedy!(type)
      case type
      when :start
        @running = true
        @active_hazards.delete(:stall)
      when :refuel
        @active_hazards.delete(:empty_tank)
      when :repair_tire
        @active_hazards.delete(:flat_tire)
      when :repair
        @active_hazards.delete(:accident)
        @running = true
      when :turn_forward
        raise RuleViolation, 'the car must be repaired and started first' unless running?

        @reversed = false
      when :remove_speed_limit
        @speed_limited = false
      else
        raise ArgumentError, "неизвестное противодействие: #{type}"
      end
    end

    def move!(miles)
      raise RuleViolation, 'the car cannot move' unless moving?
      raise RuleViolation, 'speed limit: only 25 or 50 miles allowed' if speed_limited? && miles > 50

      @distance = reversed? ? [@distance - miles, 0].max : @distance + miles
    end

    # съедает разовый пропуск хода, возвращает true если ход был пропущен
    def consume_skip_turn!
      return false unless @skip_next_turn

      @skip_next_turn = false
      true
    end

    class RuleViolation < StandardError; end
  end
end
