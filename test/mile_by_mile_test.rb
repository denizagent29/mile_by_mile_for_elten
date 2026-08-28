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

  def test_separate_decks_each_player_has_own
    a = Player.new('A')
    b = Player.new('B')
    game = Game.new([a, b], distance_target: 1000, deck_mode: :separate)
    refute_nil a.deck
    refute_nil b.deck
    refute_same a.deck, b.deck
    assert_equal 6, a.hand.size
    assert_equal 6, b.hand.size
    # каждая колода полного состава и не пуста после раздачи
    assert_equal Deck.new.size - 6, a.deck.size
    assert_equal Deck.new.size - 6, b.deck.size
  end

  def test_separate_decks_draw_from_own_deck
    a = Player.new('A')
    b = Player.new('B')
    game = Game.new([a, b], distance_target: 1000, deck_mode: :separate)
    before_a = a.deck.size
    before_b = b.deck.size

    start = RemedyCard.new(:start)
    a.hand << start
    game.instance_variable_set(:@current_index, 0)
    game.play(start) # успешно сыграна, ход переходит B

    # A добрал из СВОЕЙ колоды
    assert_equal before_a - 1, a.deck.size
    assert_equal before_b, b.deck.size
  end

  def test_separate_decks_play_out_hand_then_finish
    a = Player.new('A')
    b = Player.new('B')
    game = Game.new([a, b], distance_target: 10_000, deck_mode: :separate)
    # колоды пусты, но в руках ещё карты — игроки доигрывают руку
    a.deck.instance_variable_set(:@cards, [])
    b.deck.instance_variable_set(:@cards, [])
    refute game.finished?
    # как только игроку нечего брать и нечего ходить — партия окончена
    a.hand.clear
    assert game.finished?
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
