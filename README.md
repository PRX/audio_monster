# AudioMonster

AudioMonster manipulates and transcodes audio.
It wraps a number of different command line binaries such as sox, lame, flac, twolame, and ffmpeg.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'audio_monster'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install audio_monster

## Usage

AudioMonster can be configured to use a specific tempfile directory.
It can also be configured to use a binary directory, or you can configure each binary.
It will default to logging to STDOUT, or a logger can be configured.

For convenience, all methods can be called from the AudioMonster module.

The `monster_test.rb` contains examples of method calls.

## Contributing

1. Fork it ( https://github.com/[my-github-username]/audio_monster/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
