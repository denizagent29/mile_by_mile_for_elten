# frozen_string_literal: true

module MileByMile
  # Карточка движения (мили). 25, 50, 75, 100, 200.
  class DistanceCard < Card
    VALID_MILES = [25, 50, 75, 100, 200].freeze

    attr_reader :miles

    def initialize(miles)
      raise ArgumentError, "недопустимое значение миль: #{miles}" unless VALID_MILES.include?(miles)

      super("#{miles} миль")
      @miles = miles
    end
  end
end
