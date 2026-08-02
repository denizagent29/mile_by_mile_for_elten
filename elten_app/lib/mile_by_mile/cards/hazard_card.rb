# frozen_string_literal: true

module MileByMile
  # Карточка вредительства. Играется только на соперника.
  class HazardCard < Card
    TYPES = %i[stall empty_tank flat_tire accident turned_back speed_limit skip_turn].freeze

    NAMES = {
      stall: 'Заглушить мотор',
      empty_tank: 'Слить бензин',
      flat_tire: 'Проколоть колесо',
      accident: 'Авария',
      turned_back: 'Развернуть назад',
      speed_limit: 'Ограничить скорость',
      skip_turn: 'Пропустит ход'
    }.freeze

    attr_reader :type

    def initialize(type, name: nil)
      raise ArgumentError, "неизвестный тип вредительства: #{type}" unless TYPES.include?(type)

      super(name || NAMES.fetch(type))
      @type = type
    end

    def opponent_only?
      true
    end

    # аварию и разворот назад нельзя сыграть против того,
    # чья машина не заведена или не на ходу
    def requires_target_moving?
      %i[accident turned_back].include?(type)
    end
  end
end
