# -*- encoding: utf-8 -*-

require "audio_monster/version"

require 'active_support/all'
require 'open3'
require 'timeout'
require 'mp3info'
require 'logger'
require 'nu_wav'
require 'tempfile'
require 'mimemagic'
require 'digest/sha2'

module AudioMonster

  class Monster
    include Configuration
    include ::NuWav

    def initialize(options={})
      apply_configuration(options)
      check_binaries if ENV['AUDIO_MONSTER_DEBUG']
    end

    def tone_detect(path, tone, threshold=0.05, min_time=0.5)
      ranges = []

      tone      = tone.to_i
      threshold = threshold.to_f
      min_time  = min_time.to_f
      normalized_wav_dat = nil

      begin

        normalized_wav_dat = create_temp_file(path + '.dat')
        normalized_wav_dat.close

        command = "#{bin(:sox)} '#{path}' '#{normalized_wav_dat.path}' channels 1 rate 200 bandpass #{tone} 3 gain 6"
        out, err = run_command(command)
        current_range = nil

        File.foreach(normalized_wav_dat.path) do |row|
          next if row[0] == ';'

          data = row.split.map(&:to_f)
          time = data[0]
          energy = data[1].abs()

          if energy >= threshold
            if !current_range
              current_range = {start: time, finish: time, min: energy, max: energy}
            else
              current_range[:finish] = time
              current_range[:min] = [current_range[:min], energy].min
              current_range[:max] = [current_range[:max], energy].max
            end
          else
            if current_range && ((current_range[:finish] + min_time.to_f) < time)
              ranges << current_range
              current_range = nil
            end
          end
        end

        if current_range
          ranges << current_range
        end

      ensure
        normalized_wav_dat.close rescue nil
        normalized_wav_dat.unlink rescue nil
      end

      ranges
    end

    def silence_detect(path, threshold=0.001, min_time=2.0)
      ranges = []
      # puts "\n#{Time.now} tone_detect(path, tone): #{path}, #{tone}\n"

      threshold = threshold.to_f
      min_time  = min_time.to_f
      normalized_wav_dat = nil

      begin

        normalized_wav_dat = create_temp_file(path + '.dat')
        normalized_wav_dat.close

        command = "#{bin(:sox)} '#{path}' '#{normalized_wav_dat.path}' channels 1 rate 1000 norm"
        out, err = run_command(command)

        current_range = nil

        File.foreach(normalized_wav_dat.path) do |row|
          next if row[0] == ';'

          data = row.split.map(&:to_f)
          time = data[0]
          energy = data[1].abs()

          if energy < threshold
            if !current_range
              current_range = {start: time, finish: time, min: energy, max: energy}
            else
              current_range[:finish] = time
              current_range[:min] = [current_range[:min], energy].min
              current_range[:max] = [current_range[:max], energy].max
            end
          else
            next unless current_range
            ranges << current_range if ((current_range[:finish] - current_range[:start]) > min_time.to_f)
            current_range = nil
          end
        end

        if current_range && ((current_range[:finish] - current_range[:start]) > min_time.to_f)
          ranges << current_range
        end

      ensure
        normalized_wav_dat.close rescue nil
        normalized_wav_dat.unlink rescue nil
      end

      ranges
    end

    def encode_wav_pcm_from_mpeg(original_path, wav_path, options={})
      logger.info "encode_wav_pcm_from_mpeg: #{original_path}, #{wav_path}, #{options.inspect}"
      # check to see if there is an original
      check_local_file(original_path)

      logger.debug "encode_wav_pcm_from_mpeg: start"
      command = "#{bin(:madplay)} -Q -i --output=wave:'#{wav_path}' '#{original_path}'"

      out, err = run_command(command)

      # check to see if there is a file created, or don't go on.
      check_local_file(wav_path)
      return [out, err]
    end

    def encode_wav_pcm_from_flac(original_path, wav_path, options={})
      logger.info "encode_wav_pcm_from_flac: #{original_path}, #{wav_path}, #{options.inspect}"
      # check to see if there is an original
      check_local_file(original_path)

      logger.debug "encode_wav_pcm_from_mpeg: start"
      command = "#{bin(:flac)} -s -f --decode '#{original_path}' --output-name='#{wav_path}'"
      out, err = run_command(command)

      # check to see if there is a file created, or don't go on.
      check_local_file(wav_path)
      return [out, err]
    end

    alias encode_wav_pcm_from_mp2 encode_wav_pcm_from_mpeg
    alias encode_wav_pcm_from_mp3 encode_wav_pcm_from_mpeg

    # experimental...should work on any ffmpeg compatible file
    def decode_audio(original_path, wav_path, options={})
      # check to see if there is an original
      logger.info "decode_audio: #{original_path}, #{wav_path}, #{options.inspect}"
      check_local_file(original_path)

      # if the file extension is banged up, try to get from options, or guess at 'mov'
      input_format = ''
      if options[:source_format] || (File.extname(original_path).length != 4)
        input_format = options[:source_format] ? "-f #{options[:source_format]}" : '-f mov'
      end

      channels = options[:channels] ? options[:channels].to_i : 2
      sample_rate = options[:sample_rate] ? options[:sample_rate].to_i : 44100
      logger.debug "decode_audio: start"
      command = "#{bin(:ffmpeg)} -nostats -loglevel warning -vn -i '#{original_path}' -acodec pcm_s16le -ac #{channels} -ar #{sample_rate} -y -f wav '#{wav_path}'"

      out, err = run_command(command)

      # check to see if there is a file created, or don't go on.
      check_local_file(wav_path)
      return [out, err]
    end

    def info_for_mpeg(mpeg_path, info = nil)
      logger.debug "info_for_mpeg: start"
      length = audio_file_duration(mpeg_path)
      info ||= Mp3Info.new(mpeg_path)
      result = {
        :size         => File.size(mpeg_path),
        :content_type => 'audio/mpeg',
        :channel_mode => info.channel_mode,
        :bit_rate     => info.bitrate,
        :length       => [info.length.to_i, length.to_i].max,
        :sample_rate  => info.samplerate,
        :version      => info.mpeg_version, # mpeg specific
        :layer        => info.layer # mpeg specific
      }

      # indicate this can be GC'd
      info = nil

      result
    end

    alias info_for_mp2 info_for_mpeg
    alias info_for_mp3 info_for_mpeg

    def info_for_wav(wav_file_path)
      wf = WaveFile.parse(wav_file_path)
      fmt = wf.chunks[:fmt]
      {
        :size         => File.size(wav_file_path),
        :content_type => 'audio/vnd.wave',
        :channel_mode => fmt.number_of_channels <= 1 ? 'Mono' : 'Stereo',
        :bit_rate     => (fmt.byte_rate * 8) / 1000, #kilo bytes per sec
        :length       => wf.duration,
        :sample_rate  => fmt.sample_rate
      }
    end

    def info_for_audio(path)
      {
        :size         => File.size(path),
        :content_type => (MimeMagic.by_path(path) || MimeMagic.by_magic(path)).to_s,
        :channel_mode => audio_file_channels(path) <= 1 ? 'Mono' : 'Stereo',
        :bit_rate     => audio_file_bit_rate(path),
        :length       => audio_file_duration(path),
        :sample_rate  => audio_file_sample_rate(path)
      }
    end

    def audio_file_duration(path)
      audio_file_info(path, 'D').to_f
    end

    def audio_file_channels(path)
      audio_file_info(path, 'c').to_i
    end

    def audio_file_sample_rate(path)
      audio_file_info(path, 'r').to_i
    end

    def audio_file_bit_rate(path)
      audio_file_info(path, 'B').to_i
    end

    def audio_file_info(path, flag)
      check_local_file(path)
      out, err = run_command("#{bin(:soxi)} -V0 -#{flag} '#{path}'", :nice=>'n', :echo_return=>false)
      out.chomp
    end

    # valid options
    # :sample_rate
    # :bit_rate
    # :per_channel_bit_rate
    # :channel_mode
    # :protect
    # :copyright
    # :original
    # :emphasis
    def encode_mp2_from_wav(original_path, mp2_path, options={})
      check_local_file(original_path)

      options.to_options!
      # parse the wave to see what values to use if not overridden by the options
      wf = WaveFile.parse(original_path)
      fmt = wf.chunks[:fmt]

      wav_sample_size = fmt.sample_bits

      # twolame can only handle up to 16 for floating point (seems to convert to 16 internaly anyway)
      # "Note: the 32-bit samples are currently scaled down to 16-bit samples internally."
      # libtwolame.h  twolame_encode_buffer_float32 http://www.twolame.org/doc/twolame_8h.html#8e77eb0f22479f8ec1bd4f1b042f9cd9
      if (fmt.compression_code.to_i == PCM_FLOATING_COMPRESSION && fmt.sample_bits > 32)
        wav_sample_size = 16
      end

      # input options
      prefix_command = ''
      raw_input      = ''
      sample_rate    = "--samplerate #{fmt.sample_rate}"
      sample_bits    = "--samplesize #{wav_sample_size}"
      channels       = "--channels #{fmt.number_of_channels}"
      input_path     = "'#{original_path}'"

      # output options
      mp2_sample_rate = if MP2_SAMPLE_RATES.include?(options[:sample_rate].to_s)
        options[:sample_rate]
      elsif MP2_SAMPLE_RATES.include?(fmt.sample_rate.to_s)
        fmt.sample_rate.to_s
      else
        '44100'
      end

      if mp2_sample_rate.to_i != fmt.sample_rate.to_i
        prefix_command = "#{bin(:sox)} '#{original_path}' -t raw -r #{mp2_sample_rate} - | "
        input_path = '-'
        raw_input = '--raw-input'
      end

      mode = if TWOLAME_MODES.include?(options[:channel_mode])
        options[:channel_mode] #use the channel mode from the options if specified
      elsif fmt.number_of_channels <= 1
        'm' # default to monoaural for 1 channel input
      else
        's' # default to joint stereo for 2 channel input
      end
      channel_mode = "--mode #{mode}"

      kbps = if options[:per_channel_bit_rate]
        options[:per_channel_bit_rate].to_i * ((mode == 'm') ? 1 : 2)
      elsif options[:bit_rate]
        options[:bit_rate].to_i
      else
        0
      end

      kbps = if MP2_BITRATES.include?(kbps)
        kbps
      elsif mode == 'm' || (mode =='a' && fmt.number_of_channels <= 1)
        128 # default for monoaural is 128 kbps
      else
        256 # default for stereo/dual channel is 256 kbps
      end
      bit_rate = "--bitrate #{kbps}"

      downmix = (mode == 'm' && fmt.number_of_channels > 1) ? '--downmix' : ''

      # default these headers when options not present
      protect = (options.key?(:protect) && !options[:protect] ) ? '' : '--protect'
      copyright = (options.key?(:copyright) && !options[:copyright] ) ? '' : '--copyright'
      original = (options.key?(:original) && !options[:original] ) ? '--non-original' : '--original'
      emphasis = (options.key?(:emphasis)) ? "--deemphasis #{options[:emphasis]}" : '--deemphasis n'

      ##
      # execute the command
      ##
      input_options = "#{raw_input} #{sample_rate} #{sample_bits} #{channels}"
      output_options = "#{channel_mode} #{bit_rate} #{downmix} #{protect} #{copyright} #{original} #{emphasis}"

      command = "#{prefix_command} #{bin(:twolame)} -t 0 #{input_options} #{output_options} #{input_path} '#{mp2_path}'"
      out, err = run_command(command)
      unless out.split("\n").last =~ TWOLAME_SUCCESS_RE
        raise "encode_mp2_from_wav - twolame response on transcoding was not recognized as a success, #{out}, #{err}"
      end

      # make sure there is a file at the end of this
      check_local_file(mp2_path)

      true
    end

    # valid options
    # :sample_rate
    # :bit_rate
    # :channel_mode
    def encode_mp3_from_wav(original_path, mp3_path, options={})
      logger.info "encode_mp3_from_wav: #{original_path}, #{mp3_path}, #{options.inspect}"

      check_local_file(original_path)

      options.to_options!
      # parse the wave to see what values to use if not overridden by the options
      wf = WaveFile.parse(original_path)
      fmt = wf.chunks[:fmt]

      input_path = '-'

      mp3_sample_rate = if MP3_SAMPLE_RATES.include?(options[:sample_rate].to_s)
        options[:sample_rate].to_s
      elsif MP3_SAMPLE_RATES.include?(fmt.sample_rate.to_s)
        logger.debug "sample_rate:  fmt.sample_rate = #{fmt.sample_rate}"
        fmt.sample_rate.to_s
      else
        '44100'
      end
      logger.debug "mp3_sample_rate: #{options[:sample_rate]}, #{fmt.sample_rate}"

      mode = if LAME_MODES.include?(options[:channel_mode])
        options[:channel_mode] #use the channel mode from the options if specified
      elsif fmt.number_of_channels <= 1
        'm' # default to monoaural for 1 channel input
      else
        'j' # default to joint stereo for 2 channel input
      end
      channel_mode = "-m #{mode}"

      # if mono selected, but input is in stereo, need to specify downmix to 1 channel for sox
      downmix = (mode == 'm' && fmt.number_of_channels > 1) ? '-c 1' : ''

      # if sample rate different, change that as well in sox before piping to lame
      resample = (mp3_sample_rate.to_i != fmt.sample_rate.to_i) ? "-r #{mp3_sample_rate} " : ''
      logger.debug "resample: #{resample} from comparing #{mp3_sample_rate} #{fmt.sample_rate}"

      # output to wav (-t wav) has a warning
      # '/usr/local/bin/sox wav: Length in output .wav header will be wrong since can't seek to fix it'
      # that messsage can safely be ignored, wa output is easier/safer for lame to recognize, so worth ignoring this message
      prefix_command = "#{bin(:sox)} '#{original_path}' -t wav #{resample} #{downmix} - | "

      kbps = if options[:per_channel_bit_rate]
        options[:per_channel_bit_rate].to_i * ((mode == 'm') ? 1 : 2)
      elsif options[:bit_rate]
        options[:bit_rate].to_i
      else
        0
      end

      kbps = if MP3_BITRATES.include?(kbps)
        kbps
      elsif mode == 'm'
        128 # default for monoaural is 128 kbps
      else
        256 # default for stereo/dual channel is 256 kbps
      end
      bit_rate = "--cbr -b #{kbps}"

      ##
      # execute the command
      ##
      output_options = "#{channel_mode} #{bit_rate}"

      command = "#{prefix_command} #{bin(:lame)} -S #{output_options} #{input_path} '#{mp3_path}'"

      out, err = run_command(command)

      unless out.split("\n")[-1] =~ LAME_SUCCESS_RE
        raise "encode_mp3_from_wav - lame completion unsuccessful: #{out}"
      end

      err.split("\n").each do |l|
        if l =~ LAME_ERROR_RE
          raise "encode_mp3_from_wav - lame response had fatal error: #{l}"
        end
      end
      logger.debug "encode_mp3_from_wav: end!"

      check_local_file(mp3_path)

      true
    end

    def encode_ogg_from_wav(original_path, result_path, options={})
      logger.info("encode_ogg_from_wav: original_path: #{original_path}, result_path: #{result_path}, options: #{options.inspect}")

      check_local_file(original_path)

      options.to_options!
      # parse the wave to see what values to use if not overridden by the options
      wf = WaveFile.parse(original_path)
      fmt = wf.chunks[:fmt]

      sample_rate = if MP3_SAMPLE_RATES.include?(options[:sample_rate].to_s)
        options[:sample_rate].to_s
      elsif MP3_SAMPLE_RATES.include?(fmt.sample_rate.to_s)
        logger.debug "sample_rate:  fmt.sample_rate = #{fmt.sample_rate}"
        fmt.sample_rate.to_s
      else
        '44100'
      end
      logger.debug "sample_rate: #{options[:sample_rate]}, #{fmt.sample_rate}"

      mode = if LAME_MODES.include?(options[:channel_mode])
        options[:channel_mode] #use the channel mode from the options if specified
      elsif fmt.number_of_channels <= 1
        'm' # default to monoaural for 1 channel input
      else
        'j' # default to joint stereo for 2 channel input
      end

      # can directly set # of channels, 16 or less
      # otherwise fallback on the mode, like mpegs
      # or 2 if all else fails
      channels = if (options[:channels].to_i > 0 )
        [options[:channels].to_i, 16].min
      else
        (mode && (mode == 'm')) ? 1 : 2
      end

      kbps = if options[:per_channel_bit_rate]
        options[:per_channel_bit_rate].to_i * channels
      elsif options[:bit_rate]
        options[:bit_rate].to_i
      else
        0
      end

      bit_rate = (MP3_BITRATES.include?(kbps) ? kbps : 96).to_s + "k"

      command = "#{bin(:ffmpeg)} -nostats -loglevel warning -vn -i '#{original_path}' -acodec libvorbis -ac #{channels} -ar #{sample_rate} -ab #{bit_rate} -y -f ogg '#{result_path}'"

      out, err = run_command(command)

      check_local_file(result_path)

      return true
    end

    # need start_at, ends_on
    def create_wav_wrapped_mpeg(mpeg_path, result_path, options={})
      options.to_options!

      start_at = get_datetime_for_option(options[:start_at])
      end_at = get_datetime_for_option(options[:end_at])

      wav_wrapped_mpeg = NuWav::WaveFile.from_mpeg(mpeg_path)
      cart = wav_wrapped_mpeg.chunks[:cart]
      cart.title = options[:title] || File.basename(mpeg_path)
      cart.artist = options[:artist]
      cart.cut_id = options[:cut_id]
      cart.producer_app_id = options[:producer_app_id] if options[:producer_app_id]
      cart.start_date = start_at.strftime(PRSS_DATE_FORMAT)
      cart.start_time = start_at.strftime(AES46_2002_TIME_FORMAT)
      cart.end_date = end_at.strftime(PRSS_DATE_FORMAT)
      cart.end_time = end_at.strftime(AES46_2002_TIME_FORMAT)

      # pass in the options used by NuWav -
      # :no_pad_byte - when true, will not add the pad byte to the data chunk
      nu_wav_options = options.slice(:no_pad_byte)
      wav_wrapped_mpeg.to_file(result_path, nu_wav_options)

      check_local_file(result_path)

      return true
    end

    def get_datetime_for_option(d)
      return DateTime.now unless d
      d.respond_to?(:strftime) ? d : DateTime.parse(d.to_s)
    end

    alias create_wav_wrapped_mp2 create_wav_wrapped_mpeg
    alias create_wav_wrapped_mp3 create_wav_wrapped_mpeg

    def add_cart_chunk_to_wav(wave_path, result_path, options={})
      wave = NuWav::WaveFile.parse(wave_path)
      unless wave.chunks[:cart]
        cart = CartChunk.new
        now = Time.now
        today = Date.today
        later = today << 12

        cart.title                = options[:title] || File.basename(wave_path)
        cart.artist               = options[:artist]
        cart.cut_id               = options[:cut_id]

        cart.version              = options[:version] || '0101'
        cart.producer_app_id      = options[:producer_app_id] || 'ContentDepot'
        cart.producer_app_version = options[:producer_app_version] || '1.0'
        cart.level_reference      = options[:level_reference] || 0
        cart.tag_text             = options[:tag_text] || "\r\n"
        cart.start_date           = (options[:start_at] || today).strftime(PRSS_DATE_FORMAT)
        cart.start_time           = (options[:start_at] || now).strftime(AES46_2002_TIME_FORMAT)
        cart.end_date             = (options[:end_at] || later).strftime(PRSS_DATE_FORMAT)
        cart.end_time             = (options[:end_at] || now).strftime(AES46_2002_TIME_FORMAT)

        wave.chunks[:cart] = cart
      end

      wave.to_file(result_path)

      check_local_file(result_path)

      return true
    end

    def slice_wav(wav_path, out_path, start, length)
      check_local_file(wav_path)

      wav_info = info_for_wav(wav_path)
      logger.debug "slice_wav: wav_info:#{wav_info.inspect}"

      command = "#{bin(:sox)} -t wav '#{wav_path}' -t wav '#{out_path}' trim #{start} #{length}"
      out, err = run_command(command)
      response = out + err
      response.split("\n").each{ |out| raise("slice_wav: cut file error: '#{response}' on:\n #{command}") if out =~ SOX_ERROR_RE }

      check_local_file(out_path)
      out_path
    end

    def cut_wav(wav_path, out_path, length, fade=5)
      logger.info "cut_wav: wav_path:#{wav_path}, length:#{length}, fade:#{fade}"

      wav_info = info_for_wav(wav_path)
      logger.debug "cut_wav: wav_info:#{wav_info.inspect}"

      new_length = [wav_info[:length].to_i, length].min
      fade_length = [wav_info[:length].to_i, fade].min

      # find out if the wav file is stereo or mono as this needs to match the starting wav
      channels = wav_info[:channel_mode] == 'Mono' ? 1 : 2
      sample_rate = wav_info[:sample_rate]

      command = "#{bin(:sox)} -t wav '#{wav_path}' -t raw -s -b 16 -c #{channels} - trim 0 #{new_length} | #{bin(:sox)} -t raw -r #{sample_rate} -s -b 16 -c #{channels} - -t wav '#{out_path}' fade h 0 #{new_length} #{fade_length}"
      out, err = run_command(command)
      response = out + err
      response.split("\n").each{ |out| raise("cut_wav: cut file error: '#{response}' on:\n #{command}") if out =~ SOX_ERROR_RE }
    end

    def concat_wavs(in_paths, out_path)
      first_wav_info = info_for_wav(in_paths.first)
      channels = first_wav_info[:channel_mode] == 'Mono' ? 1 : 2
      sample_rate = first_wav_info[:sample_rate]
      tmp_files = []

      concat_paths = in_paths.inject("") {|cmd, path|
        concat_path = path
        wav_info = info_for_wav(concat_path)
        current_channels = wav_info[:channel_mode] == 'Mono' ? 1 : 2
        current_sample_rate = wav_info[:sample_rate]
        if current_channels != channels || current_sample_rate != sample_rate

          concat_file = create_temp_file(path)
          concat_file.close

          concat_path = concat_file.path
          command = "#{bin(:sox)} -t wav #{path} -t wav -c #{channels} -r #{sample_rate} '#{concat_path}'"
          out, err = run_command(command)
          response = out + err
          response.split("\n").each{ |out| raise("concat_wavs: create temp file error: '#{response}' on:\n #{command}") if out =~ SOX_ERROR_RE }
          tmp_files << concat_file
        end
        cmd << "-t wav '#{concat_path}' "
      }
      command = "#{bin(:sox)} #{concat_paths} -t wav '#{out_path}'"
      out, err = run_command(command)

      response = out + err
      response.split("\n").each{ |out| raise("concat_wavs: concat files error: '#{response}' on:\n #{command}") if out =~ SOX_ERROR_RE }
    ensure
      tmp_files.each do |tf|
        tf.close rescue nil
        tf.unlink rescue nil
      end
      tmp_files = nil
    end

    def append_wav_to_wav(wav_path, append_wav_path, out_path, add_length, fade_length=5)
      append_wav_info = info_for_wav(append_wav_path)
      raise "append wav is not sufficiently long enough (#{append_wav_info[:length]}) to add length (#{add_length})" if append_wav_info[:length].to_i < add_length

      append_length = [append_wav_info[:length].to_i, (add_length - 1)].min

      append_fade_length = [append_wav_info[:length].to_i, fade_length].min

      # find out if the wav file is stereo or mono as this needs to match the starting wav
      wav_info = info_for_wav(wav_path)
      channels = wav_info[:channel_mode] == 'Mono' ? 1 : 2
      sample_rate = wav_info[:sample_rate]
      append_file = nil

      begin
        append_file = create_temp_file(append_wav_path)
        append_file.close

        # create the wav to append
        command = "#{bin(:sox)} -t wav '#{append_wav_path}' -t raw -s -b 16 -c #{channels} - trim 0 #{append_length} | #{bin(:sox)} -t raw -r #{sample_rate} -s -b 16 -c #{channels} - -t raw - fade h 0 #{append_length} #{append_fade_length} | #{bin(:sox)} -t raw -r #{sample_rate} -s -b 16 -c #{channels} - -t wav '#{append_file.path}' pad 1 0"
        out, err = run_command(command)
        response = out + err
        response.split("\n").each{ |out| raise("append_wav_to_wav: create append file error: '#{response}' on:\n #{command}") if out =~ SOX_ERROR_RE }

        # append the files to out_file
        command = "#{bin(:sox)} -t wav '#{wav_path}' -t wav '#{append_file.path}' -t wav '#{out_path}'"
        out, err = run_command(command)
        response = out + err
        response.split("\n").each{ |out| raise("append_wav_to_wav: create append file error: '#{response}' on:\n #{command}") if out =~ SOX_ERROR_RE }
      ensure
        append_file.close rescue nil
        append_file.unlink rescue nil
      end

      return true
    end

    def append_mp3_to_wav(wav_path, mp3_path, out_path, add_length, fade_length=5)
      # raise "append_mp3_to_wav: Can't find file to create mp3 preview of: #{mp3_path}" unless File.exist?(mp3_path)

      mp3info = Mp3Info.new(mp3_path)
      raise "mp3 is not sufficiently long enough (#{mp3info.length.to_i}) to add length (#{add_length})" if mp3info.length.to_i < add_length
      append_length = [mp3info.length.to_i, (add_length - 1)].min
      append_fade_length = [mp3info.length.to_i, fade_length].min


      # find out if the wav file is stereo or mono as this meeds to match the wav from the mp3
      wavinfo = info_for_wav(wav_path)
      channels = wavinfo[:channel_mode] == 'Mono' ? 1 : 2
      sample_rate = wavinfo[:sample_rate]
      append_file = nil

      begin
        append_file = create_temp_file(mp3_path)
        append_file.close

        # create  the mp3 to append
        command = "#{bin(:madplay)} -q -o wave:- '#{mp3_path}' - | #{bin(:sox)} -t wav - -t raw -s -b 16 -c #{channels} - trim 0 #{append_length} | #{bin(:sox)} -t raw -r #{sample_rate} -s -b 16 -c #{channels} - -t wav - fade h 0 #{append_length} #{append_fade_length} | #{bin(:sox)} -t wav - -t wav '#{append_file.path}' pad 1 0"
        out, err = run_command(command)
        response = out + err
        response.split("\n").each{ |out| raise("append_mp3_to_wav: create append file error: '#{response}' on:\n #{command}") if out =~ SOX_ERROR_RE }

        # append the files to out_filew
        command = "#{bin(:sox)} -t wav '#{wav_path}' -t wav '#{append_file.path}' -t wav '#{out_path}'"
        out, err = run_command(command)
        response = out + err
        response.split("\n").each{ |out| raise("append_mp3_to_wav: create append file error: '#{response}' on:\n #{command}") if out =~ SOX_ERROR_RE }
      ensure
        append_file.close rescue nil
        append_file.unlink rescue nil
      end

      return true
    end

    def normalize_wav(wav_path, out_path, level=-9)
      logger.info "normalize_wav: wav_path:#{wav_path}, level:#{level}"
      command = "#{bin(:sox)} -t wav '#{wav_path}' -t wav '#{out_path}' gain -n #{level.to_i}"
      out, err = run_command(command)
      response = out + err
      response.split("\n").each{ |out| raise("normalize_wav: normalize audio file error: '#{response}' on:\n #{command}") if out =~ SOX_ERROR_RE }
    end

    def validate_mpeg(audio_file_path, options)
      @errors = {}

      options = HashWithIndifferentAccess.new(options)

      info = mp3info_validation(audio_file_path, options)

      # there are condtions where this spews output uncontrollably - so lose it for now: AK on 20080915
      #   e.g. mpck:/home/app/mediajoint/tmp/audio_monster/prxfile-66097_111955868219902-0:3366912:read error
      # mpck_validation(audio_file_path, errors) if errors.size <= 0

      # if the format seems legit, check the audio itself
      mp3val_validation(audio_file_path, options)

      return @errors, info
    end

    alias validate_mp2 validate_mpeg
    alias validate_mp3 validate_mpeg

    MAX_FILENAME_LENGTH = 160
    MAX_EXTENSION_LENGTH = 6

    def create_temp_file(base_file_name=nil, bin_mode=true)
      file_name = File.basename(base_file_name)
      file_name = Digest::SHA256.hexdigest(base_file_name) if file_name.length > MAX_FILENAME_LENGTH
      file_ext = File.extname(base_file_name)[0, MAX_EXTENSION_LENGTH]

      FileUtils.mkdir_p(tmp_dir) unless File.exists?(tmp_dir)
      tmp = Tempfile.new([file_name, file_ext], tmp_dir)
      tmp.binmode if bin_mode
      tmp
    end

    protected

    # Validation methods
    def add_error(attribute, message)
      @errors ||= {}
      @errors[attribute] = [] unless @errors[attribute]
      @errors[attribute] << message
    end

    def valid_operator(op)
      [">=", "<=", "==", "=", ">", "<"].include?(op) ? (op == "=" ? "==" : op) : ">="
    end

    def files_validation(audio_file_path, errors)
      response = run_command("#{FILE} '#{audio_file_path}'", :echo_return=>false).chomp
      logger.debug("'file' on #{audio_file_path}. Response: #{response}")
      unless response =~ FILE_SUCCESS
        response =~ /.*: /
        add_error(:file, "is not a valid mp2 file, we think it's a '#{$'}'")
      end
    end

    def mp3info_validation(audio_file_path, options)
      info = nil

      begin
        info = Mp3Info.new(audio_file_path)
      rescue Mp3InfoError => err
        add_error(:file, "is not a valid mpeg audio file.")
        return
      end

      if options[:version]
        version = options[:version].to_i
        mpeg_version = info.mpeg_version.to_i
        add_error(:version, "must be mpeg version #{version}, but audio version is #{mpeg_version}") unless mpeg_version == version
      end

      if options[:layer]
        layer = options[:layer].to_i
        mpeg_layer = info.layer.to_i
        add_error(:layer, "must be mpeg layer #{layer}, but audio layer is #{mpeg_layer}") unless mpeg_layer == layer
      end

      if options[:channel_mode]
        cm_list = options[:channel_mode].to_a
        add_error(:channel_mode, "channel mode must be one of (#{cm_list.to_sentence})") unless cm_list.include?(info.channel_mode)
      end

      if options[:channels]
        channels = options[:channels].to_i
        mpeg_channels = "Single Channel" == info.channel_mode ? 1 : 2
        add_error(:channels, "must have channel count of #{channels}, but audio is #{mpeg_channels}") unless mpeg_channels == channels
      end

      # only certain rates are valid for different layer/versions, but don't add that right now
      if options[:sample_rate]
        sample_rate = 44100
        op = ">="
        mpeg_sample_rate = info.samplerate.to_i
        if options[:sample_rate].match(' ')
          op, sample_rate = options[:sample_rate].split(' ')
          sample_rate = sample_rate.to_i
          op = valid_operator(op)
        else
          sample_rate = options[:sample_rate].to_i
        end
        add_error(:sample_rate, "sample rate should be #{op} #{sample_rate}, but is #{mpeg_sample_rate}") unless eval("#{mpeg_sample_rate} #{op} #{sample_rate}")
      end

      if options[:bit_rate]
        bit_rate = 128
        op = ">="
        mpeg_bit_rate = info.bitrate.to_i
        if options[:bit_rate].match(' ')
          op, bit_rate = options[:bit_rate].split(' ')
          bit_rate = bit_rate.to_i
          op = valid_operator(op)
        else
          bit_rate = options[:bit_rate].to_i
        end
        add_error(:bit_rate, "bit rate should be #{op} #{bit_rate}, but is #{mpeg_bit_rate}") unless eval("#{mpeg_bit_rate} #{op} #{bit_rate}")
      end

      if options[:per_channel_bit_rate]
        per_channel_bit_rate = 128
        op = ">="
        mpeg_channels = "Single Channel" == info.channel_mode ? 1 : 2
        mpeg_per_channel_bit_rate = info.bitrate.to_i / mpeg_channels

        if options[:per_channel_bit_rate].match(' ')
          op, per_channel_bit_rate = options[:per_channel_bit_rate].split(' ')
          per_channel_bit_rate = per_channel_bit_rate.to_i
          op = valid_operator(op)
        else
          per_channel_bit_rate = options[:per_channel_bit_rate].to_i
        end
        add_error(:per_channel_bit_rate, "per channel bit rate should be #{op} #{per_channel_bit_rate}, but is #{mpeg_per_channel_bit_rate}, and channels = #{mpeg_channels}") unless eval("#{mpeg_per_channel_bit_rate} #{op} #{per_channel_bit_rate}")
      end
      info_for_mpeg(audio_file_path, info)
    end

    def mp3val_validation(audio_file_path, options)
      warning = false
      error = false
      out, err = run_command("#{bin(:mp3val)} -si '#{audio_file_path}'", :echo_return=>false)
      lines = out.split("\n")
      lines.each { |o|
        if (o =~ MP3VAL_IGNORE_RE)
          next
        elsif (o =~ MP3VAL_WARNING_RE)
          add_error(:file, "is not a valid mpeg file, there were serious warnings when validating the audio.") unless warning
          warning = true
        elsif (o =~ MP3VAL_ERROR_RE)
          add_error(:file, "is not a valid mpeg file, there were errors when validating the audio.") unless error
          error = true
        else
          next
        end
      }
    end

    # Pass the command to run, and a timeout
    def run_command(command, options={})
      timeout = options[:timeout] || 7200

      # default to adding a nice 13 if nothing specified
      nice = if options.key?(:nice)
        (options[:nice] == 'n') ? '' : "nice -n #{options[:nice]} "
      else
        'nice -n 19 '
      end

      echo_return = (options.key?(:echo_return) && !options[:echo_return]) ? '' : '; echo $?'

      cmd = "#{nice}#{command}#{echo_return}"

      logger.info "run_command: #{cmd}"
      begin
        result = Timeout::timeout(timeout) {
          Open3::popen3(cmd) do |i,o,e|
            out_str = ""
            err_str = ""
            i.close # important!
            o.sync = true
            e.sync = true
            o.each{|line|
              out_str << line
              line.chomp!
              logger.debug "stdout:    #{line}"
            }
            e.each { |line|
              err_str << line
              line.chomp!
              logger.debug "stderr:    #{line}"
            }
            return out_str, err_str
          end
        }
      rescue Timeout::Error => toe
        logger.error "run_command:Timeout Error - running command, took longer than #{timeout} seconds to execute: '#{cmd}'"
        raise toe
      end
    end

    def mpck_validation(audio_file_path, options)
      errors= []
      # validate using mpck
      response = run_command("nice -n 19 #{bin(:mpck)} #{audio_file_path}")
      response.split("\n").each { |o|
        if ((o =~ MPCK_ERROR_RE) && !(o =~ MPCK_IGNORE_RE))
          errors << "is not a valid mp2 file. The file is bad according to the 'mpck' audio check."
        end
      }

      errors
    end

    def method_missing(name, *args, &block)
      if name.to_s.starts_with?('encode_wav_pcm_from_')
        decode_audio(*args)
      elsif name.to_s.starts_with?('info_for_')
        info_for_audio(*args)
      else
        super
      end
    end

    protected

    def check_local_file(file_path)
      raise "File missing or 0 length: #{file_path}" unless (File.size?(file_path).to_i > 0)
    end

    def get_lame_channel_mode(channel_mode)
      ["Stereo", "JStereo"].include?(channel_mode) ? "j" : "m"
    end

  end
end
