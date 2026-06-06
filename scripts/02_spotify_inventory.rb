#!/usr/bin/env ruby
require_relative "lib/common"
include Music

by_key = {}
membership = {}
order = []

Dir.glob(File.join(SPOTIFY, "*.csv")).sort.each do |file|
  playlist = File.basename(file, ".csv")
  CSV.foreach(file, headers: true) do |row|
    title  = row["Track Name"]
    artist = row["Artist Name(s)"]
    next if title.nil? || artist.nil?
    key = track_key(artist, title)

    unless by_key.key?(key)
      by_key[key] = {
        "source"       => "spotify",
        "spotify_uri"  => row["Track URI"],
        "title"        => title,
        "artist"       => artist,
        "album"        => row["Album Name"],
        "album_artist" => row["Album Artist Name(s)"],
        "year"         => year_of(row["Album Release Date"]),
        "disc"         => row["Disc Number"],
        "track"        => row["Track Number"],
        "duration_ms"  => row["Track Duration (ms)"],
        "isrc"         => row["ISRC"],
        "cover_url"    => row["Album Image URL"],
        "key"          => key,
      }
      order << key
    end
    (membership[key] ||= []) << playlist
  end
end

uniq = order.map { |k| by_key[k] }
write_json("spotify.json", uniq)

playlists = order.map do |k|
  { "key" => k, "title" => by_key[k]["title"], "artist" => by_key[k]["artist"],
    "playlists" => membership[k].uniq }
end
write_json("spotify_playlists.json", playlists)

total_rows = membership.values.sum(&:size)
puts "Spotify: #{total_rows} rows across all playlists"
puts "  unique tracks: #{uniq.size}"
puts "  playlists: #{Dir.glob(File.join(SPOTIFY, '*.csv')).size}"
puts "  -> build/spotify.json, build/spotify_playlists.json"
