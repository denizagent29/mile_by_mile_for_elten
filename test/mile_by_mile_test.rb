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

  # Колода как в ухе: 25/50/75 по 10, 100×12, 200×4 — итого 105 карт,
  # 106 с опциональной «Снять все защиты».
  def test_deck_size
    assert_equal 105, Deck.new.size
  end

  def test_deck_size_with_optional_card
    assert_equal 106, Deck.new(include_remove_all_safeties: true).size
  end

  def test_deck_has_four_200_mile_cards
    count = 0
    deck = Deck.new
    until deck.empty?
      c = deck.draw
      count += 1 if c.is_a?(DistanceCard) && c.miles == 200
    end
    assert_equal 4, count
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
    # стартовый игрок берёт седьмую карту
    assert_equal [6, 7], [a.hand.size, b.hand.size].sort
    # каждая колода полного состава; у стартового игрока на карту меньше
    assert_equal [Deck.new.size - 7, Deck.new.size - 6], [a.deck.size, b.deck.size].sort
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

    # карту добирает не сыгравший A, а B — в начале своего хода
    assert_equal before_a, a.deck.size
    assert_equal before_b - 1, b.deck.size
  end

  def test_separate_decks_play_out_hand_then_finish
    a = Player.new('A')
    b = Player.new('B')
    game = Game.new([a, b], distance_target: 10_000, deck_mode: :separate)
    # колоды пусты, но в руках ещё карты — игроки доигрывают руку
    a.deck.instance_variable_set(:@cards, [])
    b.deck.instance_variable_set(:@cards, [])
    refute game.finished?
    # как только ВСЕМ нечего брать и нечего ходить — партия окончена
    a.hand.clear
    refute game.finished? # у B ещё есть карты в руке — игра продолжается
    b.hand.clear
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

  def test_starter_gets_seventh_card
    hands = @game.players.map { |p| p.hand.size }.sort
    assert_equal [6, 7], hands
  end

  def test_repair_after_accident_does_not_restart_engine
    start = RemedyCard.new(:start)
    @p1.hand << start
    @game.play(start) # p1 заведена

    accident = HazardCard.new(:accident)
    @p2.hand << accident
    @game.play(accident, target: @p1) # p1 в аварии
    refute @p1.car.running?
    assert @p1.car.stalled_by?(:accident)

    repair = RemedyCard.new(:repair)
    @p1.hand << repair
    @game.play(repair)
    refute @p1.car.stalled_by?(:accident)
    refute @p1.car.running? # починка не заводит мотор — нужно «Завестись»
  end

  def test_start_requires_tank_tire_seat_ok
    [[:empty_tank, RemedyCard.new(:start)],
     [:flat_tire, RemedyCard.new(:start)],
     [:accident, RemedyCard.new(:start)]].each do |hazard, _card_class|
      p = Player.new('X')
      game = Game.new([p, @p2], distance_target: 1000)
      game.instance_variable_set(:@current_index, 0)
      p.car.apply_hazard!(hazard)
      start = RemedyCard.new(:start)
      p.hand << start
      assert_equal :wasted, game.play(start)
      refute p.car.running?
    end
  end

  def test_reversed_move_discards_when_distance_less_than_card
    @p1.car.instance_variable_set(:@distance, 30)
    @p1.car.instance_variable_set(:@running, true)
    @p1.car.instance_variable_set(:@reversed, true)
    d50 = DistanceCard.new(50)
    @p1.hand << d50
    assert_equal :wasted, @game.play(d50)
    assert_equal 30, @p1.car.distance
  end

  # «Пропуск хода»: цель пропускает ровно один ход — следующий. advance_turn!
  # съедает пропуск сразу, поэтому после розыгрыша ход снова у p1, а следующая
  # обычная карта p1 передаёт ход p2 как обычно (никакого двойного пропуска).
  def test_skip_turn_skips_targets_next_turn
    skip1 = HazardCard.new(:skip_turn)
    @p1.hand << skip1
    @game.play(skip1, target: @p2)
    assert_equal 0, @p2.car.skip_turns
    assert_equal @p1, @game.current_player

    d25 = DistanceCard.new(25)
    @p1.hand << d25
    @game.play(d25)
    assert_equal @p2, @game.current_player
  end

  def test_deck_refill_keeps_last_discarded
    deck = Deck.new
    deck.instance_variable_set(:@cards, [])
    c1 = DistanceCard.new(25)
    c2 = DistanceCard.new(50)
    pile = [c1, c2]
    assert deck.refill_from(pile)
    assert_equal 1, deck.size
    assert_equal [c2], pile # последняя сброшенная остаётся в сбросе
  end

  def test_game_continues_after_deck_exhaustion_via_refill
    game = Game.new([@p1, @p2], distance_target: 1000)
    game.deck.instance_variable_set(:@cards, [])
    game.discard_pile.concat([DistanceCard.new(25), DistanceCard.new(50)])
    refute game.finished?

    start = RemedyCard.new(:start)
    @p1.hand << start
    game.instance_variable_set(:@current_index, 0)
    game.play(start)
    refute game.deck.empty? # колода наполнилась из сброса
    assert_equal 1, game.discard_pile.size
  end

  # Мультиплеер: один и тот же сид у хоста и соперника даёт идентичную
  # партию — один первый ходящий, одинаковые руки и одинаковый порядок колоды.
  def test_seed_gives_identical_games
    seed = 42
    gh, hh, oh = seeded_game(seed)
    gg, hg, og = seeded_game(seed)

    assert_equal gh.current_player.name, gg.current_player.name
    assert_equal hh.hand.map(&:name), hg.hand.map(&:name)
    assert_equal oh.hand.map(&:name), og.hand.map(&:name)
    assert_equal gh.deck.instance_variable_get(:@cards).map(&:name),
                 gg.deck.instance_variable_get(:@cards).map(&:name)
  end

  # Разные сиды дают разные партии (тасовка реально зависит от сида).
  def test_different_seeds_differ
    gh, = seeded_game(1)
    gg, = seeded_game(2)
    refute_equal gh.deck.instance_variable_get(:@cards).map(&:name),
                 gg.deck.instance_variable_get(:@cards).map(&:name)
  end

  # apply_move воспроизводит ход по (card_index, target) на приёмной стороне.
  # Движок берёт current_player сам — как в реальном мультиплеере, где фаза
  # обоих клиентов совпадает.
  def test_apply_move_reproduces_play
    p1 = Player.new('Host')
    p2 = Player.new('Guest')
    game = Game.new([p1, p2], distance_target: 1000)
    game.instance_variable_set(:@current_index, 0)
    start = RemedyCard.new(:start)
    p1.hand << start
    idx = p1.hand.index(start)
    assert_equal :played, game.apply_move(idx, nil)
    assert p1.car.running?
  end

  # Хост и гость: скриптовая последовательность ходов применяется к обоим
  # движкам, состояния совпадают после каждого шага.
  def test_host_and_guest_stay_in_sync
    seed = 12345
    gh, hh, oh = seeded_game(seed)
    gg, hg, og = seeded_game(seed)

    sig = lambda do |g, h, o|
      [g.current_player.name, h.hand.map(&:name), o.hand.map(&:name),
       g.deck.instance_variable_get(:@cards).size, h.car.distance,
       h.car.running?, o.car.distance, o.car.running?,
       h.car.skip_turns, o.car.skip_turns]
    end

    [[0, nil], [1, :opponent], [2, nil], [0, :opponent], [1, nil], [2, nil]].each do |idx, target|
      assert_equal gh.apply_move(idx, target), gg.apply_move(idx, target)
      assert_equal sig.call(gh, hh, oh), sig.call(gg, hg, og)
    end
  end

  def seeded_game(seed)
    p1 = Player.new('Host')
    p2 = Player.new('Guest')
    game = Game.new([p1, p2], distance_target: 1000, deck_mode: :shared, deck_copies: 3, seed: seed)
    [game, p1, p2]
  end
end
