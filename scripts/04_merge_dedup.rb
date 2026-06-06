#!/usr/bin/env ruby
require_relative "lib/common"
include Music

onedrive = load_json(File.join(BUILD, "onedrive.json"))
spotify  = load_json(File.join(BUILD, "spotify.json"))
itunes   = load_json(File.join(BUILD, "itunes.json"))

merged = {}

add = lambda do |rec, src|
  key = rec["key"]
  next if key.nil? || key.strip.empty?
  m = (merged[key] ||= {
    "key" => key, "sources" => [], "have_file" => false,
    "artist" => nil, "title" => nil, "album" => nil, "album_artist" => nil,
    "composer" => nil, "year" => nil, "track" => nil, "disc" => nil,
    "genre" => nil, "has_cover" => nil, "path" => nil,
    "spotify_uri" => nil, "isrc" => nil, "cover_url" => nil,
  })
  m["sources"] << src
  fill = ->(k, v) { m[k] = v if (m[k].nil? || m[k].to_s.strip == "") && v && v.to_s.strip != "" }
  %w[artist title album album_artist composer year track disc genre].each { |k| fill.(k, rec[k]) }
  if src == "onedrive"
    m["have_file"] = true
    m["path"]      = rec["path"]
    m["has_cover"] = rec["has_cover"]
  end
  fill.("spotify_uri", rec["spotify_uri"])
  fill.("isrc", rec["isrc"])
  fill.("cover_url", rec["cover_url"])
end

onedrive.each { |r| add.(r, "onedrive") }
spotify.each  { |r| add.(r, "spotify") }
itunes.each   { |r| add.(r, "itunes_match") }

records = merged.values
records.each { |m| m["sources"] = m["sources"].uniq }

headers = %w[have_file sources artist title album album_artist composer year disc track genre has_cover spotify_uri isrc cover_url path key]
to_row = ->(m) { h = m.dup; h["sources"] = m["sources"].join("+"); h }

write_csv("catalog_master.csv", records.map(&to_row), headers)

acquire = records.reject { |m| m["have_file"] }
ah = %w[sources artist title album year spotify_uri isrc cover_url key]
write_csv("to_acquire.csv", acquire.map(&to_row), ah)

stats = {
  "unique_total"          => records.size,
  "have_physical_file"    => records.count { |m| m["have_file"] },
  "need_to_acquire"       => acquire.size,
  "only_onedrive"         => records.count { |m| m["sources"] == ["onedrive"] },
  "only_spotify"          => records.count { |m| m["sources"] == ["spotify"] },
  "only_itunes"           => records.count { |m| m["sources"] == ["itunes_match"] },
  "onedrive+spotify"      => records.count { |m| (m["sources"]&"onedrive spotify".split).size==2 && !m["sources"].include?("itunes_match") },
  "in_all_three"          => records.count { |m| m["sources"].size == 3 },
  "acquire_from_spotify"  => acquire.count { |m| m["sources"].include?("spotify") },
  "acquire_itunes_only"   => acquire.count { |m| m["sources"] == ["itunes_match"] },
}
write_json("stats.json", stats)

puts "MASTER CATALOG (deduplicated): #{stats['unique_total']} tracks"
puts "  have physical file (OneDrive): #{stats['have_physical_file']}"
puts "  to add from Apple Music:       #{stats['need_to_acquire']}"
puts "  ├─ present in Spotify:          #{stats['acquire_from_spotify']}"
puts "  └─ old iTunes Match only:       #{stats['acquire_itunes_only']}"
puts "Overlaps:"
puts "  OneDrive only: #{stats['only_onedrive']}"
puts "  Spotify only:  #{stats['only_spotify']}"
puts "  iTunes only:   #{stats['only_itunes']}"
puts "  in all three:  #{stats['in_all_three']}"
puts "-> build/catalog_master.csv, build/to_acquire.csv, build/stats.json"
