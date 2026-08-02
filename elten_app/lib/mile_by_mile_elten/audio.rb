# frozen_string_literal: true

module MileByMileElten
  # Обёртка над play_app_sound. Ассеты лежат плоско в elten_app/audio/
  # (Elten грузит только верхний уровень папки Audio, без подпапок — см.
  # collect_physical_sound_assets/add_sound_asset в elten3, оба используют
  # File.basename без директории как ключ поиска). Поэтому все файлы
  # переименованы в плоские уникальные имена по схеме:
  #   <variant>_<0|25|50|75|100|200>   — озвучка карт движения
  #   <variant>_bibip                  — старт мотора
  #   <variant>_welcome                — начало партии/раунда
  #   <variant>_fail_<key>             — вредительство применилось к цели
  #   <variant>_success_<key>          — противодействие сработало
  #   prot_<key>                       — защита выставлена (общая для всех вариантов)
  #   wow                              — победа (общая)
  # variant: cars | horses
  # key:     ready(stall) tank(empty_tank) tire(flat_tire) wheel(turned_back)
  #          seat(accident) speed(speed_limit) pass(skip_turn)
  class Audio
    include MileByMile

    SOUND_KEY = {
      stall: 'ready',
      empty_tank: 'tank',
      flat_tire: 'tire',
      turned_back: 'wheel',
      accident: 'seat',
      speed_limit: 'speed',
      skip_turn: 'pass'
    }.freeze

    attr_accessor :variant

    def initialize(program, variant: :cars)
      @program = program
      @variant = variant
    end

    def play(name, volume: 100, pan: 50, pitch: 100)
      return false if name.nil?

      @program.play_app_sound(name.to_s, volume: volume, pan: pan, pitch: pitch)
    rescue Exception => e
      Log.warning("MileByMile sound #{name} failed: #{e.class}: #{e.message}") if defined?(Log)
      false
    end

    def welcome
      play("#{@variant}_welcome")
    end

    # звук проигрывается при розыгрыше карты игроком/ботом (по центру)
    def card_played(card)
      play(sound_name_for(card))
    end

    # тот же звук, что и card_played, но с панорамой вправо — по просьбе:
    # взятие карты перед ходом звучит будто тянешь её из колоды справа
    def card_drawn(card)
      play(sound_name_for(card), pan: 82, volume: 70)
    end

    def win
      play('wow')
    end

    private

    def sound_name_for(card)
      case card
      when DistanceCard then "#{@variant}_#{card.miles}"
      when HazardCard then "#{@variant}_fail_#{SOUND_KEY.fetch(card.type, 'ready')}"
      when RemedyCard then "#{@variant}_success_#{SOUND_KEY.fetch(card.cures, 'ready')}"
      when SafetyCard then "prot_#{SOUND_KEY.fetch(card.type, 'ready')}"
      when RemoveAllSafetiesCard then "#{@variant}_bibip"
      end
    end
  end
end
