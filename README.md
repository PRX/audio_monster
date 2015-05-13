# AudioMonster

AudioMonster manipulates and transcodes audio.
It wraps a number of different command line binaries such as sox, lame, flac, twolame, and ffmpeg.

## Dependencies

The following binary tools are required. They are available via most OS package managers. 

For OS X use homebrew:

```
brew install lame
brew install flac
brew install sox
brew install twolame --frontend
brew install madplay
brew install mp3val
brew install ffmpeg
```

For Redhat/CentOS use yum:

NOTE that some multimedia RPMs are available only via particular repositories. See e.g.
http://wiki.centos.org/TipsAndTricks/MultimediaOnCentOS7

```
yum install lame
yum install flac
yum install sox 
yum install twolame 
yum install madplay
yum install mp3val
yum install ffmpeg
yum install libsndfile-devel libsndfile-utils
```

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
