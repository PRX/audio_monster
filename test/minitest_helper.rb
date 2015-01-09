$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'audio_monster'

require 'minitest'
require 'minitest/autorun'
require 'minitest/spec'
require 'minitest/mock'

def out_file(o)
  File.expand_path(File.dirname(__FILE__) + '/tmp/' + o)
end

def in_file(i)
  File.expand_path(File.dirname(__FILE__) + '/files/' + i)
end
