# -*- encoding: utf-8 -*-

require 'mkmf'
require 'logger'

module AudioMonster

  module Configuration

    # constants
    FILE_SUCCESS       = /\S+: (MP2|MPEG ADTS, layer II, v1), \S+ kBits, \S+ kHz, (JStereo|Stereo|Mono|2x Monaural|Dual-Ch|Monaural|JntStereo)/
    MP3VAL_WARNING_RE  = /WARNING/
    MP3VAL_ERROR_RE    = /ERROR/
    MP3VAL_IGNORE_RE   = /(^Done!|Non-layer-III frame encountered. See related INFO message for details.|No supported tags in the file|It seems that file is truncated or there is garbage at the end of the file|MPEG stream error, resynchronized successfully)/
    MPCK_ERROR_RE      = /(mpck:|errors)/
    MPCK_IGNORE_RE     = /errors(\s*)(CRC error|none)/
    LAME_SUCCESS_RE    = /0/
    LAME_ERROR_RE      = /fatal error/
    SOX_ERROR_RE       = /error:/
    TWOLAME_SUCCESS_RE = /0/

    # Allowable values for mp2 (MPEG1 layer II)
    MP2_BITRATES = [32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384]
    MP2_SAMPLE_RATES =  ['32000', '44100', '48000']
    TWOLAME_MODES = ['s', 'j', 'd', 'm', 'a'] # (s)tereo, (j)oint, (d)ual, (m)ono or (a)uto

    # Allowable values for mp3 (MPEG1 layer III)
    MP3_SAMPLE_RATES =  ['32000', '44100', '48000']
    MP3_BITRATES = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
    LAME_MODES = ['j', 's', 'f', 'd', 'm'] #  (j)oint, (s)imple stereo, (f)orce, (d)dual-mono, (m)ono

    #  by default, using the PRSS date format, but this is not the actual cart chunk (AES46-2002) standard
    AES46_2002_DATE_FORMAT = '%Y-%m-%d'
    PRSS_DATE_FORMAT       = '%Y/%m/%d'

    AES46_2002_TIME_FORMAT = '%H:%M:%S'

    BINARIES_KEYS = [:file, :ffmpeg, :flac, :lame, :mpck, :mp3val, :sox, :soxi, :madplay, :twolame].freeze

    VALID_OPTIONS_KEYS = ([
      :logger,
      :bin_dir,
      :tmp_dir,
      :debug
    ] + BINARIES_KEYS).freeze

    attr_accessor *VALID_OPTIONS_KEYS

    def self.included(base)

      def current_options
        @current_options ||= {}
      end

      def current_options=(opts)
        @current_options = opts
      end

      VALID_OPTIONS_KEYS.each do |key|
        define_method "#{key}=" do |arg|
          self.instance_variable_set("@#{key}", arg)
          self.current_options.merge!({:"#{key}" => arg})
        end
      end

      base.extend(ClassMethods)
    end

    module ClassMethods

      def keys
        VALID_OPTIONS_KEYS
      end

    end

    def options
      options = {}
      VALID_OPTIONS_KEYS.each { |k| options[k] = send(k) }
      options
    end

    def apply_configuration(opts={})
      options = AudioMonster.options.merge(opts)
      self.current_options = options
      VALID_OPTIONS_KEYS.each do |key|
        send("#{key}=", options[key])
      end
    end

    # Convenience method to allow for global setting of configuration options
    def configure
      yield self
    end

    def set_mkmf_log(logfile=File::NULL)
      MakeMakefile::Logging.instance_variable_set(:@logfile, logfile)
    end

    def check_binaries
      old_mkmf_log = MakeMakefile::Logging.instance_variable_get(:@logfile)
      set_mkmf_log

      BINARIES_KEYS.each { |bin| find_executable(bin.to_s) }

      set_mkmf_log(old_mkmf_log)
    end

    # Reset configuration options to their defaults
    def reset!
      self.debug   = ENV['DEBUG']
      self.logger  = Logger.new(STDOUT)
      self.bin_dir = nil
      self.tmp_dir = '/tmp/audio_monster'
      self.file    = 'file'
      self.ffmpeg  = 'ffmpeg'
      self.flac    = 'flac'
      self.lame    = 'lame'
      self.mpck    = 'mpck'
      self.mp3val  = 'mp3val'
      self.sox     = 'sox'
      self.soxi    = 'soxi'
      self.madplay = 'madplay'
      self.twolame = 'twolame'
      self
    end

    def bin(name)
      "#{bin_dir}#{name}"
    end

    # # detect the sox version to deal wth changes in comand line options after 14.1.0
    # # http://sox.sourceforge.net/Docs/FAQ
    # def configure_sox
    #   sox_version = `#{bin(:sox)} --version`
    #   version = /^.*SoX v(\d*)\.(\d*)\.(\d*)/.match(sox_version) || []

    #   if (version.size > 0) && (version[1].to_i < 14) || ((version[1].to_i == 14) && (version[2].to_i < 1))
    #     self.sox_16_bits = '-w'
    #     self.sox_8_bits = '-b'
    #   else
    #     self.sox_16_bits = '-b 16'
    #     self.sox_8_bits = '-b 8'
    #   end
    # end

    def self.extended(base)
      base.reset!
    end
  end
end
