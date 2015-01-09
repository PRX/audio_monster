$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'audio_monster'

require 'minitest'
require 'minitest/autorun'
require 'minitest/spec'
require 'minitest/mock'
require 'fileutils'

def out_dir
  File.expand_path(File.join(File.dirname(__FILE__), 'tmp'))
end

def out_file(o)
  File.join(out_dir, o)
end

def in_dir
  File.expand_path(File.join(File.dirname(__FILE__), 'files'))
end

def in_file(i)
  File.join(in_dir, i)
end
