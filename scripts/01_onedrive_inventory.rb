#!/usr/bin/env ruby
require_relative "lib/common"
include Music

dump = load_json(File.join(BUILD, "onedrive_tags.json"))

def parse_filename(fname)
  base = fname.sub(/\.mp3\z/i, "")
  base = base.tr("_", " ").gsub(/\s+/, " ").strip
  stripped = base.sub(/\A\d{1,3}[.\-)\s]+/, "")
  if stripped =~ /\A(.+?)\s*[\-\u2013\u2014]\s*(.+)\z/
    artist = $1.strip
    title  = $2.strip
    return [artist, title] unless artist.empty? || title.empty?
  end
  [nil, stripped]
end

def mojibake?(str)
  return false if str.nil? || str.empty?
  bad = str.chars.count { |c| "¦ТБГДЕЖЗИЙ".include?(c) || c.ord == 0x00A6 }
  bad >= 3
end

records = dump.map do |h|
  fname = h["FileName"]
  path  = File.join(h["Directory"] || ONEDRIVE, fname)
  artist = first_present(h, "Artist", "Band", "AlbumArtist")
  title  = first_present(h, "Title")
  album  = first_present(h, "Album")
  album_artist = first_present(h, "AlbumArtist", "Band")
  composer = first_present(h, "Composer")
  track  = first_present(h, "TrackNumber", "Track")&.to_s&.split("/")&.first
  year   = year_of(h["Year"], h["RecordingTime"], h["ContentCreateDate"], h["Date"])
  genre  = first_present(h, "Genre")
  cover  = !h["Picture"].nil?

  needs_salvage = artist.nil? || title.nil?
  fn_artist, fn_title = parse_filename(fname)
  if needs_salvage
    artist ||= fn_artist
    title  ||= fn_title
  end

  {
    "source"       => "onedrive",
    "path"         => path,
    "filename"     => fname,
    "artist"       => artist,
    "title"        => title,
    "album"        => album,
    "album_artist" => album_artist,
    "composer"     => composer,
    "track"        => track,
    "year"         => year,
    "genre"        => genre,
    "has_cover"    => cover,
    "needs_salvage"=> needs_salvage,
    "mojibake_name"=> mojibake?(fname),
    "fn_artist"    => fn_artist,
    "fn_title"     => fn_title,
    "key"          => (artist && title) ? track_key(artist, title) : nil,
  }
end

write_json("onedrive.json", records)

salvage = records.select { |r| r["needs_salvage"] }
no_cover = records.count { |r| !r["has_cover"] }
puts "OneDrive: #{records.size} files"
puts "  with key (artist+title): #{records.count { |r| r["key"] }}"
puts "  need salvage (empty tags): #{salvage.size}"
puts "  of those mojibake names: #{salvage.count { |r| r["mojibake_name"] }}"
puts "  without cover: #{no_cover}"
puts "  -> build/onedrive.json"
