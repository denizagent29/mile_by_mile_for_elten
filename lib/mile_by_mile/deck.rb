# frozen_string_literal: true

module MileByMile
  # Игровая колода: 105 карточек, или 106 с опциональной «Снять все защиты».
  class Deck
    HAZARD_TYPES = %i[stall empty_tank flat_tire accident turned_back speed_limit].freeze
    REMEDY_TYPES = %i[refuel repair_tire repair turn_forward remove_speed_limit].freeze

    def initialize(include_remove_all_safeties: false)
      @cards = build(include_remove_all_safeties)
    end

    def shuffle!
      @cards.shuffle!
      self
    end

    def deal(players, count = 6)
      count.times do
        players.each { |p| p.hand << draw }
      end
      self
    end

    def draw
      @cards.pop
    end

    def size
      @cards.size
    end

    def empty?
      @cards.empty?
    end

    private

    def build(include_remove_all_safeties)
      cards = []

      cards.concat(Array.new(10) { DistanceCard.new(25) })
      cards.concat(Array.new(10) { DistanceCard.new(50) })
      cards.concat(Array.new(10) { DistanceCard.new(75) })
      cards.concat(Array.new(12) { DistanceCard.new(100) })
      cards.concat(Array.new(6) { DistanceCard.new(200) })

      cards.concat(Array.new(10) { RemedyCard.new(:start) })
      REMEDY_TYPES.each { |t| cards.concat(Array.new(4) { RemedyCard.new(t) }) }

      HAZARD_TYPES.each { |t| cards.concat(Array.new(2) { HazardCard.new(t) }) }
      cards.concat(Array.new(10) { HazardCard.new(:skip_turn) })

      (HAZARD_TYPES + [:skip_turn]).each { |t| cards << SafetyCard.new(t) }

      cards << RemoveAllSafetiesCard.new if include_remove_all_safeties

      cards
    end
  end
end
