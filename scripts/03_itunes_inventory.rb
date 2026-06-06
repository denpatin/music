#!/usr/bin/env ruby
require_relative "lib/common"
include Music

CONNECTOR = /\A(.*?)(?:├── |└── )(.*)\z/

artist = album = nil
records = []

File.foreach(ITUNES, encoding: "UTF-8").with_index do |raw, i|
  line = raw.chomp
  next if i.zero?
  m = line.match(CONNECTOR)
  next unless m
  prefix, name = m[1], m[2].strip
  depth = prefix.length / 4

  case depth
  when 0
    artist = name; album = nil
  when 1
    album = name
  when 2
    if name =~ /\A(\d+)-(\d+)\s+(.*)\z/
      disc, track, title = $1, $2, $3
    elsif name =~ /\A(\d+)\s+(.*)\z/
      disc, track, title = nil, $1, $2
    else
      disc, track, title = nil, nil, name
    end
    next if title.strip.empty?
    records << {
      "source" => "itunes_match",
      "artist" => artist,
      "album"  => album,
      "disc"   => disc,
      "track"  => track,
      "title"  => title.strip,
      "key"    => track_key(artist, title),
    }
  end
end

write_json("itunes.json", records)
puts "iTunes Match: #{records.size} tracks"
puts "  unique by key: #{records.map { |r| r['key'] }.uniq.size}"
puts "  artists: #{records.map { |r| r['artist'] }.uniq.size}"
puts "  -> build/itunes.json"
