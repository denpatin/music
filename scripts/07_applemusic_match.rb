#!/usr/bin/env ruby
require_relative "lib/common"
require "net/http"
require "uri"
include Music

COMMIT  = ARGV.include?("--commit")
LIMIT   = (ARGV.find { |a| a.start_with?("--limit=") }&.split("=", 2)&.last ||
           (i = ARGV.index("--limit")) && ARGV[i + 1])&.to_i
API     = "https://api.music.apple.com"
DEV_TOK = ENV["APPLE_MUSIC_DEV_TOKEN"]
USR_TOK = ENV["APPLE_MUSIC_USER_TOKEN"]
MATCH_CACHE = File.join(BUILD, "applemusic_matched.json")
MISS_CACHE  = File.join(BUILD, "applemusic_missed.json")
COMMITTED   = File.join(BUILD, "applemusic_committed.json")
SAVE_EVERY  = 25
THROTTLE    = 0.2

class RateLimitError < StandardError; end

def fail_with_instructions(msg)
  warn "ERROR: #{msg}\n"
  warn <<~TXT
    How to get tokens (free, while an Apple Music subscription is active):
      1. Open https://music.apple.com in Safari/Chrome and sign in.
      2. Open DevTools -> Network tab.
      3. Click any track/section to trigger requests to amp-api.music.apple.com.
      4. Pick any such request -> Headers -> Request Headers:
           - authorization: Bearer eyJ...   -> DEV_TOKEN (without the word "Bearer")
           - media-user-token: A...          -> USER_TOKEN
      5. In the shell (fish):
           set -x APPLE_MUSIC_DEV_TOKEN  "eyJ..."
           set -x APPLE_MUSIC_USER_TOKEN "A..."
      6. Run the script again.
    Tokens last a few weeks; if expired, repeat the steps.
  TXT
  exit 1
end

fail_with_instructions("missing APPLE_MUSIC_DEV_TOKEN")  if DEV_TOK.nil? || DEV_TOK.empty?
fail_with_instructions("missing APPLE_MUSIC_USER_TOKEN") if USR_TOK.nil? || USR_TOK.empty?

def http_get(path)
  uri = URI("#{API}#{path}")
  req = Net::HTTP::Get.new(uri)
  apply_headers(req)
  do_request(uri, req)
end

def http_post(path)
  uri = URI("#{API}#{path}")
  req = Net::HTTP::Post.new(uri)
  apply_headers(req)
  do_request(uri, req)
end

def apply_headers(req)
  req["Authorization"]    = "Bearer #{DEV_TOK}"
  req["Music-User-Token"] = USR_TOK
  req["Origin"]           = "https://music.apple.com"
  req["Accept"]           = "application/json"
end

def do_request(uri, req, attempt = 0)
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 30) { |h| h.request(req) }
  case res.code.to_i
  when 200, 201, 202
    res
  when 429, 500, 502, 503
    raise RateLimitError, "rate limited (#{res.code})" if attempt >= 4
    wait = (res["Retry-After"]&.to_i || (2**attempt)).clamp(1, 30)
    warn "\n  rate limited (#{res.code}), waiting #{wait}s (attempt #{attempt + 1}/4)..."
    sleep wait
    do_request(uri, req, attempt + 1)
  when 401, 403
    fail_with_instructions("token rejected (#{res.code}). Likely expired - refresh it.")
  else
    warn "  HTTP #{res.code} for #{uri.request_uri[0, 80]}"
    res
  end
end

sf_res = http_get("/v1/me/storefront")
STOREFRONT = (JSON.parse(sf_res.body)["data"]&.first&.dig("id")) rescue nil
fail_with_instructions("could not determine storefront - check tokens") unless STOREFRONT
puts "Storefront: #{STOREFRONT}  |  mode: #{COMMIT ? 'COMMIT (adding to library)' : 'DRY-RUN (report only)'}"

def search_by_isrc(isrc)
  return nil if isrc.nil? || isrc.strip.empty?
  res = http_get("/v1/catalog/#{STOREFRONT}/songs?filter[isrc]=#{URI.encode_www_form_component(isrc)}&limit=1")
  return nil unless res.code.to_i == 200
  JSON.parse(res.body)["data"]&.first
end

def search_by_text(artist, title)
  term = URI.encode_www_form_component("#{primary_artist(artist)} #{title}")
  res = http_get("/v1/catalog/#{STOREFRONT}/search?types=songs&limit=5&term=#{term}")
  return nil unless res.code.to_i == 200
  songs = JSON.parse(res.body).dig("results", "songs", "data") || []
  songs.find do |s|
    a = s.dig("attributes", "artistName"); t = s.dig("attributes", "name")
    similar_track?(artist, title, a, t)
  end
end

matched   = File.exist?(MATCH_CACHE) ? load_json(MATCH_CACHE) : {}
missed    = File.exist?(MISS_CACHE)  ? load_json(MISS_CACHE)  : {}
committed = File.exist?(COMMITTED)   ? load_json(COMMITTED)   : []

def save_match_state(matched, missed)
  write_json("applemusic_matched.json", matched)
  write_json("applemusic_missed.json", missed)
  write_csv("applemusic_unmatched.csv", missed.values,
            %w[artist title album isrc sources key])
end

def commit_chunk(ids, committed)
  return if ids.empty?
  ids.each_slice(50) do |chunk|
    http_post("/v1/me/library?ids[songs]=#{chunk.join(',')}")
    committed.concat(chunk)
    write_json("applemusic_committed.json", committed)
    sleep THROTTLE
  end
end

rows = []
CSV.foreach(File.join(BUILD, "to_acquire.csv"), headers: true) { |r| rows << r }
pending = rows.reject { |r| matched.key?(r["key"]) || missed.key?(r["key"]) }
if LIMIT && LIMIT > 0 && pending.size > LIMIT
  pending = pending.first(LIMIT)
  puts "To match: #{rows.size} total | already done: #{rows.size - (rows.reject { |r| matched.key?(r['key']) || missed.key?(r['key']) }).size} | this run (--limit): #{pending.size}"
else
  puts "To match: #{rows.size} total | already done: #{rows.size - pending.size} | pending: #{pending.size}"
end

committed_set = committed.to_set

if COMMIT
  backlog = matched.values.map { |m| m["id"] }.uniq.reject { |id| committed_set.include?(id) }
  unless backlog.empty?
    puts "Committing #{backlog.size} already-matched tracks not yet in library..."
    begin
      commit_chunk(backlog, committed)
      backlog.each { |id| committed_set << id }
    rescue RateLimitError => e
      puts "\n#{e.message}. Committed progress saved. Re-run with --commit to resume."
      exit 2
    end
  end
end

processed = 0
commit_buf = []
begin
  pending.each do |r|
    key = r["key"]
    artist = r["artist"]; title = r["title"]; isrc = r["isrc"]
    song = search_by_isrc(isrc) || search_by_text(artist, title)
    processed += 1
    if song
      matched[key] = {
        "id"     => song["id"],
        "title"  => song.dig("attributes", "name"),
        "artist" => song.dig("attributes", "artistName"),
        "album"  => song.dig("attributes", "albumName"),
        "isrc"   => song.dig("attributes", "isrc"),
        "via"    => (isrc && song.dig("attributes", "isrc") == isrc) ? "isrc" : "text",
      }
      if COMMIT && !committed_set.include?(song["id"])
        commit_buf << song["id"]
        committed_set << song["id"]
      end
    else
      missed[key] = { "artist" => artist, "title" => title, "album" => r["album"],
                      "isrc" => isrc, "sources" => r["sources"], "key" => key }
    end
    if processed % SAVE_EVERY == 0
      save_match_state(matched, missed)
      if COMMIT
        commit_chunk(commit_buf, committed)
        commit_buf = []
      end
    end
    sleep THROTTLE
    print "\r  processed: #{processed}/#{pending.size}  matched: #{matched.size}  committed: #{committed.size}  unmatched: #{missed.size}   " if processed % 5 == 0
  end
rescue RateLimitError => e
  save_match_state(matched, missed)
  if processed.zero? && committed.empty?
    puts "\n#{e.message} on the first request. Quota still exhausted - wait longer (try 1-2 hours), then re-run."
  else
    puts "\n#{e.message}. Progress saved (#{processed} matched this run, #{committed.size} in library). Re-run the same command to resume."
  end
  exit 2
end
puts

save_match_state(matched, missed)
if COMMIT
  begin
    commit_chunk(commit_buf, committed)
  rescue RateLimitError => e
    puts "\n#{e.message}. Committed progress saved. Re-run with --commit to resume."
    exit 2
  end
end

puts "Matched against Apple catalog: #{matched.size}"
puts "  by ISRC: #{matched.values.count { |m| m['via'] == 'isrc' }}"
puts "  by text: #{matched.values.count { |m| m['via'] == 'text' }}"
puts "Unmatched: #{missed.size}  -> build/applemusic_unmatched.csv"

if COMMIT
  puts "In library (cloud entries): #{committed.size}"
  puts "Done. Build playlists: osascript build/make_playlists.applescript"
else
  puts "\nDRY-RUN: nothing added. Review build/applemusic_matched.json and unmatched,"
  puts "then run with --commit to add matched tracks to the library."
end
