#!/usr/bin/env ruby
require_relative "lib/common"
include Music

onedrive = load_json(File.join(BUILD, "onedrive.json"))

by_key = Hash.new { |h, k| h[k] = [] }
onedrive.each { |r| by_key[r["key"]] << r }
dups = by_key.values.select { |g| g.size > 1 }
dup_rows = []
dups.each do |g|
  g.each_with_index do |r, i|
    dup_rows << { "group" => r["key"], "n" => i + 1,
                  "artist" => r["artist"], "title" => r["title"],
                  "filename" => r["filename"] }
  end
end
write_csv("onedrive_duplicates.csv", dup_rows,
          %w[group n artist title filename])

salvage = onedrive.select { |r| r["needs_salvage"] }
srows = salvage.map do |r|
  { "filename" => r["filename"],
    "mojibake" => r["mojibake_name"] ? "YES" : "",
    "proposed_artist" => r["fn_artist"],
    "proposed_title"  => r["fn_title"],
    "confidence" => r["mojibake_name"] ? "low" : (r["fn_artist"] ? "high" : "medium") }
end
write_csv("salvage_review.csv", srows,
          %w[filename mojibake proposed_artist proposed_title confidence])

nocov = onedrive.reject { |r| r["has_cover"] }
write_csv("no_cover.csv",
          nocov.map { |r| { "artist" => r["artist"], "title" => r["title"], "filename" => r["filename"] } },
          %w[artist title filename])

puts "OneDrive internal duplicates: #{dups.size} groups, #{dup_rows.size} files"
dups.first(8).each { |g| puts "  • #{g[0]['artist']} — #{g[0]['title']}  (#{g.size}): #{g.map { |x| x['filename'] }.join('  |  ')}" }
puts
puts "Files with empty tags (salvage): #{salvage.size}"
puts "  high confidence (has 'Artist - Title'): #{srows.count { |r| r['confidence'] == 'high' }}"
puts "  mojibake (needs manual review): #{srows.count { |r| r['confidence'] == 'low' }}"
puts
puts "Without cover: #{nocov.size}"
puts "-> build/onedrive_duplicates.csv, build/salvage_review.csv, build/no_cover.csv"
