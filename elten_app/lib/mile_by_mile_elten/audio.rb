# frozen_string_literal: true

module MileByMileElten
  # Обёртка над play_app_sound. Имена звуковых файлов ниже — контракт с
  # набором звуков, который будет добавлен в audio/ ассеты приложения:
  #   start.ogg, distance.ogg, remedy.ogg, safety.ogg,
  #   hazard_stall.ogg, hazard_empty_tank.ogg, hazard_flat_tire.ogg,
  #   hazard_accident.ogg, hazard_turned_back.ogg, hazard_speed_limit.ogg,
  #   hazard_skip_turn.ogg, remove_all_safeties.ogg, wasted.ogg,
  #   your_turn.ogg, bot_turn.ogg, win.ogg, lose.ogg, draw.ogg
  class Audio
    include MileByMile

    SOUND_FOR_HAZARD = {
      stall: 'hazard_stall',
      empty_tank: 'hazard_empty_tank',
      flat_tire: 'hazard_flat_tire',
      accident: 'hazard_accident',
      turned_back: 'hazard_turned_back',
      speed_limit: 'hazard_speed_limit',
      skip_turn: 'hazard_skip_turn'
    }.freeze

    def initialize(program)
      @program = program
    end

    def play(name, volume: 100, pan: 50)
      @program.play_app_sound(name.to_s, volume: volume, pan: pan)
    rescue Exception => e
      Log.warning("MileByMile sound #{name} failed: #{e.class}: #{e.message}") if defined?(Log)
      false
    end

    def card_played(card)
      case card
      when DistanceCard then play('distance')
      when RemedyCard then play('remedy')
      when SafetyCard then play('safety')
      when HazardCard then play(SOUND_FOR_HAZARD.fetch(card.type, 'hazard_stall'))
      when RemoveAllSafetiesCard then play('remove_all_safeties')
      end
    end

    def wasted
      play('wasted')
    end

    def your_turn
      play('your_turn')
    end

    def bot_turn
      play('bot_turn')
    end

    def win
      play('win')
    end

    def lose
      play('lose')
    end

    def draw
      play('draw')
    end
  end
end
