# frozen_string_literal: true

module MileByMile
  # Карточка защиты от вредительства. Играется только на себя, эффект постоянный.
  class SafetyCard < Card
    TYPES = %i[stall empty_tank flat_tire accident turned_back speed_limit skip_turn].freeze

    NAMES = {
      stall: 'Защита от глушения мотора',
      empty_tank: 'Защита от слива бензина',
      flat_tire: 'Защита от прокола колёс',
      accident: 'Защита от аварий',
      turned_back: 'Защита от разворота',
      speed_limit: 'Защита от ограничения скорости',
      skip_turn: 'Защита от пропуска хода'
    }.freeze

    attr_reader :type

    def initialize(type, name: nil)
      raise ArgumentError, "неизвестный тип защиты: #{type}" unless TYPES.include?(type)

      super(name || NAMES.fetch(type))
      @type = type
    end

    def self_only?
      true
    end
  end
end
