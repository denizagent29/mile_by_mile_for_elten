# frozen_string_literal: true

module MileByMile
  # Карточка противодействия вредительству. Играется только на себя.
  class RemedyCard < Card
    TYPES = %i[start refuel repair_tire repair turn_forward remove_speed_limit].freeze

    NAMES = {
      start: 'Завестись',
      refuel: 'Налить бензин',
      repair_tire: 'Накачать колесо',
      repair: 'Починиться после аварии',
      turn_forward: 'Развернуться вперёд',
      remove_speed_limit: 'Убрать ограничение скорости'
    }.freeze

    # какой тип вредительства лечит эта карточка
    CURES = {
      start: :stall,
      refuel: :empty_tank,
      repair_tire: :flat_tire,
      repair: :accident,
      turn_forward: :turned_back,
      remove_speed_limit: :speed_limit
    }.freeze

    attr_reader :type

    def initialize(type, name: nil)
      raise ArgumentError, "неизвестный тип противодействия: #{type}" unless TYPES.include?(type)

      super(name || NAMES.fetch(type))
      @type = type
    end

    def cures
      CURES.fetch(type)
    end

    def self_only?
      true
    end
  end
end
