require 'minitest_helper'

describe AudioMonster do

  it 'has a version number' do
    ::AudioMonster::VERSION.wont_be_nil
  end

  it 'has configuration options' do
    AudioMonster.options.wont_be_nil
  end

end
