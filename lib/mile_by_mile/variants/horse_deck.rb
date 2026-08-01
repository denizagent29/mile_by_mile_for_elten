# frozen_string_literal: true

module MileByMile
  module Variants
    # Разновидность «На лошадях». Правила идентичны, отличаются только
    # названия части карточек (см. таблицу соответствий в правилах).
    # Карточки, не указанные в таблице, полностью совпадают с оригиналом.
    class HorseDeck < Deck
      HAZARD_NAMES = {
        stall: 'Скинуть с седла',
        empty_tank: 'Голод',
        flat_tire: 'Сбить подкову',
        accident: 'Усталость'
      }.freeze

      REMEDY_NAMES = {
        start: 'Оседлать',
        refuel: 'Покормить',
        repair_tire: 'Подковать',
        repair: 'Отдых'
      }.freeze

      SAFETY_NAMES = {
        stall: 'Защита от падений с седла',
        empty_tank: 'Защита от голода',
        flat_tire: 'Защита от потери подковы',
        accident: 'Защита от усталости'
      }.freeze

      private

      def build(include_remove_all_safeties)
        super.each { |card| rename(card) }
      end

      def rename(card)
        new_name =
          case card
          when HazardCard then HAZARD_NAMES[card.type]
          when RemedyCard then REMEDY_NAMES[card.type]
          when SafetyCard then SAFETY_NAMES[card.type]
          end

        card.instance_variable_set(:@name, new_name) if new_name
      end
    end
  end
end
