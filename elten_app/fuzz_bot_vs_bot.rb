# frozen_string_literal: true

require_relative '../lib/mile_by_mile'
require_relative 'lib/mile_by_mile_elten/bot'

include MileByMile

GAMES = (ARGV[0] || 300).to_i
crashes = 0

GAMES.times do |i|
  distance = [700, 1000].sample
  p1 = Player.new('Bot1')
  p2 = Player.new('Bot2')
  game = Game.new([p1, p2], distance_target: distance)
  bot1 = MileByMileElten::Bot.new(game, p1)
  bot2 = MileByMileElten::Bot.new(game, p2)

  turns = 0
  begin
    until game.finished?
      turns += 1
      raise 'бесконечная партия' if turns > 5000

      current = game.current_player
      bot = current.equal?(p1) ? bot1 : bot2
      card, target = bot.choose_move
      break if card.nil? # рука и колода пусты одновременно

      game.play(card, target: target)
    end
  rescue StandardError => e
    crashes += 1
    puts "ИГРА ##{i} УПАЛА: #{e.class}: #{e.message}"
    puts e.backtrace.first(5)
  end
end

puts "Готово: #{GAMES} игр бот-против-бота, крашей: #{crashes}"
exit(crashes.zero? ? 0 : 1)
