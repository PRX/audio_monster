# -*- encoding: utf-8 -*-

require 'audio_monster/version'
require 'audio_monster/configuration'
require 'audio_monster/monster'

module AudioMonster
  extend Configuration

  def self.monster
    @_monster ||= AudioMonster::Monster.new
  end

  # delegate to the monster inside
  def self.method_missing(method, *args, &block)
    monster.send(method, *args)
  end
end
