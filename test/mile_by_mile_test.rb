# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/mile_by_mile'

class MileByMileTest < Minitest::Test
  include MileByMile

  def setup
    @p1 = Player.new('Deniz')
    @p2 = Player.new('Ludub')
    @game = Game.new([@p1, @p2], distance_target: 1000)
    @game.instance_variable_set(:@current_index, 0)
  end

  # Сумма по поштучному перечислению карточек в правилах даёт 107
  # (без опциональной карты) и 108 (с ней) — итоговое число 105/106
  # в тексте правил указано неточно, реализация строго следует
  # именно перечислению количеств по типам карт.
  def test_deck_size
    assert_equal 107, Deck.new.size
  end

  def test_deck_size_with_optional_card
    assert_equal 108, Deck.new(include_remove_all_safeties: true).size
  end

  def test_cannot_move_without_start
    card = DistanceCard.new(25)
    @p1.hand << card
    @game.play(card) # уходит в отбой, машина не сдвинулась
    assert_equal 0, @p1.car.distance
    assert_equal @p2, @game.current_player
  end

  def test_start_then_move
    start = RemedyCard.new(:start)
    d25 = DistanceCard.new(25)
    @p1.hand.concat([start, d25])

    @game.play(start) # ход сохраняется? нет, старт это Завестись без вредительства - уходит в отбой и ход передаётся
    assert @p1.car.running?
  end

  def test_hazard_and_remedy_cycle
    start = RemedyCard.new(:start)
    @p1.hand << start
    @game.play(start)
    # теперь ход у p2
    flat = HazardCard.new(:flat_tire)
    @p2.hand << flat
    @game.play(flat, target: @p1)
    refute @p1.car.running?
    assert @p1.car.stalled_by?(:flat_tire)

    repair = RemedyCard.new(:repair_tire)
    @p1.hand << repair
    @game.play(repair)
    refute @p1.car.stalled_by?(:flat_tire)
  end

  def test_safety_blocks_hazard_and_keeps_turn
    safety = SafetyCard.new(:flat_tire)
    d25 = DistanceCard.new(25)
    @p1.hand.concat([safety, d25])

    @game.play(safety)
    assert_equal @p1, @game.current_player # ход сохранён после первой защиты

    start = RemedyCard.new(:start)
    @p1.hand << start
    @game.play(start)
    # «Завестись» — карточка противодействия, ход передаётся в любом случае
    assert_equal @p2, @game.current_player
  end

  def test_speed_limit_restricts_to_25_or_50
    start = RemedyCard.new(:start)
    @p1.hand << start
    @game.play(start)

    limit = HazardCard.new(:speed_limit)
    @p2.hand << limit
    @game.play(limit, target: @p1)

    d75 = DistanceCard.new(75)
    @p1.hand << d75
    @game.play(d75) # превышение лимита - уходит в отбой, не сдвинулась
    assert_equal 0, @p1.car.distance
  end

  def test_exact_finish_required
    @p1.car.instance_variable_set(:@distance, 950)
    @p1.car.instance_variable_set(:@running, true)
    d75 = DistanceCard.new(75)
    @p1.hand << d75
    @game.play(d75) # 950+75 > 1000, уходит в отбой, машина не сдвинулась
    assert_equal 950, @p1.car.distance
    assert_equal @p2, @game.current_player
  end

  def test_horse_deck_renames_cards
    deck = Variants::HorseDeck.new
    names = []
    until deck.empty?
      c = deck.draw
      names << c.name
    end
    assert_includes names, 'Saddle up'
    assert_includes names, 'Thrown from the saddle'
    assert_includes names, 'Hunger immunity'
  end

  def test_team_shares_car
    team = Team.new('Джаз-бэнд', %w[Deniz Ludub])
    assert_same team.players[0].car, team.players[1].car
  end

  def test_stall_on_already_stopped_car_wastes_not_raises
    stall = HazardCard.new(:stall)
    @p2.hand << stall
    @game.instance_variable_set(:@current_index, 1) # ход у p2
    # p1's car уже не заведена (стартовое состояние) — раньше тут падало исключение
    @game.play(stall, target: @p1)
    assert_equal @p1, @game.current_player
  end

  def test_turn_forward_while_stalled_wastes_not_raises
    start = RemedyCard.new(:start)
    @p1.hand << start
    @game.play(start) # p1 заведена, ход у p2

    turned = HazardCard.new(:turned_back)
    @p2.hand << turned
    @game.play(turned, target: @p1) # p1 развёрнута, ход у p1

    flat = HazardCard.new(:flat_tire)
    @p1.hand << flat
    # тайком глушим свою же машину для теста: играем прокол на себя невозможно,
    # эмулируем состояние напрямую
    @p1.car.apply_hazard!(:flat_tire)

    turn_forward = RemedyCard.new(:turn_forward)
    @p1.hand << turn_forward
    # раньше здесь падало исключение вместо ухода карты в отбой
    @game.play(turn_forward)
    assert @p1.car.reversed?
  end
end
