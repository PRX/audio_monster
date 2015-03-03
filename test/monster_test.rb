require 'minitest_helper'

describe AudioMonster::Monster do

  let(:monster) { AudioMonster::Monster.new(logger: Logger.new('/dev/null')) }

  before {
    FileUtils.mkdir_p(out_dir)
  }

  it 'measures loudness' do
    info = monster.loudness_info(in_file('test_long.wav'))
    ['integrated_loudness', 'loudness_range', 'true_peak'].
    each { |t| info[t].wont_be_nil }
    info['integrated_loudness']['i'].must_equal -18.5
    info['loudness_range']['lra'].must_equal 7.1
    info['true_peak']['peak'].must_equal -2.1
  end

  it 'can create an mp2 from a wav file' do
    # try to create the mp2
    monster.encode_mp2_from_wav(in_file('test_long.wav'), out_file('out.mp2')).wont_be_nil

    # now parse it and test that the info is right
    mp2_info = Mp3Info.new(out_file('out.mp2'))
    mp2_info.bitrate.must_equal 128
  end

  it 'can validate an mpeg audio file\'s attributes' do
    validations = {
      :version=>2,
      :layer=>3,
      :channel_mode=>['Joint Stereo', 'Stereo'],
      :channels=>2,
      :sample_rate=>'<= 44000',
      :bit_rate=>'< 100',
      :per_channel_bit_rate=>'>= 256'
    }

    errors, info = monster.validate_mpeg(in_file('test_long.mp2'), validations)
    # puts "\n\nerrors: " + errors.inspect
    # puts "\n\ninfo: " + info.inspect
    errors.keys.must_equal validations.keys
  end

  it 'should encode an mp2 from a mono wav' do
    # try to create the mp2
    monster.encode_mp2_from_wav(in_file('test_long.wav'), out_file('out_mono.mp2')).must_equal true

    # now parse it and test that the info is right
    mp2_info = Mp3Info.new(out_file('out_mono.mp2'))

    mp2_info.mpeg_version.must_equal 1
    mp2_info.layer.must_equal 2
    mp2_info.bitrate.must_equal 128
    mp2_info.samplerate.must_equal 44100
    mp2_info.channel_mode.must_equal 'Single Channel'
    mp2_info.header[:padding].must_equal false
  end

  it 'should encode an mp2 from a stereo wav' do
    # try to create the mp2
    monster.encode_mp2_from_wav(in_file('test_stereo.wav'), out_file('out_stereo.mp2')).must_equal true

    # now parse it and test that the info is right
    mp2_info = Mp3Info.new(out_file('out_stereo.mp2'))

    mp2_info.mpeg_version.must_equal 1
    mp2_info.layer.must_equal 2
    mp2_info.bitrate.must_equal 256
    mp2_info.samplerate.must_equal 44100
    mp2_info.channel_mode.must_equal "Stereo"
    mp2_info.header[:padding].must_equal false
  end

  it 'should get the length using soxi' do
    info = monster.info_for_mpeg(in_file('test_long.mp2'))
    info[:length].must_equal 48
  end

  it 'should get info for ogg file' do
    info = monster.info_for_ogg(in_file('test.ogg'))
    info[:length].to_i.must_equal 12
    info[:content_type].must_equal "audio/ogg"
  end


  it 'should create a wav wrapped mp2' do
    start_at = '2010-06-19T00:00:00-04:00'
    end_at = DateTime.parse(start_at) + 6.days
    options = {}
    options[:title]           = "REMIX Episode 1"
    options[:artist]          = "PRX REMIX"
    options[:cut_id]          = "12345"
    options[:start_at]        = start_at
    options[:end_at]          = end_at
    options[:producer_app_id] = 'PRX'
    options[:no_pad_byte]     = false
    wave_file = out_file('test_long.wav')
    monster.create_wav_wrapped_mp2(in_file('test_long.mp2'), out_file('test_long.wav'), options)

    wave = NuWav::WaveFile.parse(wave_file)

    wave.chunks[:cart].title.must_equal "REMIX Episode 1"
    wave.chunks[:cart].artist.must_equal "PRX REMIX"
    wave.chunks[:cart].cut_id.must_equal "12345"
    wave.chunks[:cart].start_date.must_equal "2010/06/19"
    wave.chunks[:cart].start_time.must_equal "00:00:00"
    wave.chunks[:cart].end_date.must_equal "2010/06/25"
    wave.chunks[:cart].end_time.must_equal "00:00:00"
    wave.chunks[:cart].producer_app_id.must_equal "PRX"
  end

  it 'can slice a section out of an audio file' do
    monster.slice_wav(in_file('test_long.wav'), out_file('slice.wav'), 10, 5).wont_be_nil
    slice_wav = NuWav::WaveFile.parse(out_file('slice.wav'))
    slice_wav.duration.must_equal 5
  end

  it 'can create a temp file with a really long name' do
    base_file_name = ('abc' * 100) + '.extension'
    file = AudioMonster.create_temp_file(base_file_name)
    File.basename(file.path)[0, 64].must_equal Digest::SHA256.hexdigest(base_file_name)
    File.extname(file.path).must_equal '.exten'
  end
end
