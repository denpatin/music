#!/usr/bin/env ruby
require_relative "lib/common"
include Music

data = load_json(File.join(BUILD, "spotify_playlists.json"))

playlists = Hash.new { |h, k| h[k] = [] }
data.each do |t|
  t["playlists"].each { |pl| playlists[pl] << { "artist" => primary_artist(t["artist"]), "title" => t["title"] } }
end

dir = File.join(BUILD, "playlists_clean")
require "fileutils"
FileUtils.mkdir_p(dir)
playlists.each do |name, tracks|
  File.open(File.join(dir, "#{name}.tsv"), "w") do |f|
    tracks.each { |t| f.puts "#{t['artist']}\t#{t['title']}" }
  end
end

def as_escape(str)
  str.to_s.gsub("\\", "\\\\\\\\").gsub('"', '\"')
end

lines = []
lines << 'tell application "Music"'
lines << '  set src to library playlist 1'
playlists.each do |name, tracks|
  lines << "  if not (exists user playlist \"#{as_escape(name)}\") then make new user playlist with properties {name:\"#{as_escape(name)}\"}"
  lines << "  set pl to user playlist \"#{as_escape(name)}\""
  tracks.each do |t|
    a = as_escape(t["artist"]); ti = as_escape(t["title"])
    lines << "  try"
    lines << "    set m to (every track of src whose name is \"#{ti}\" and artist contains \"#{a}\")"
    lines << "    repeat with tk in m"
    lines << "      duplicate tk to pl"
    lines << "    end repeat"
    lines << "  end try"
  end
end
lines << 'end tell'
File.write(File.join(BUILD, "make_playlists.applescript"), lines.join("\n"))

puts "Playlists: #{playlists.size}"
playlists.sort_by { |_, v| -v.size }.first(5).each { |n, v| puts "  #{n}: #{v.size}" }
puts "-> build/playlists_clean/*.tsv"
puts "-> build/make_playlists.applescript (run AFTER import)"
