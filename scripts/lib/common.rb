require "json"
require "csv"
require "find"
require "digest"

module Music
  ROOT       = File.expand_path("../..", __dir__)
  BUILD      = File.join(ROOT, "build")
  ONEDRIVE   = "/Users/denpatin/OneDrive/MUSIC"
  SPOTIFY    = File.join(ROOT, "spotify_playlists")
  ITUNES     = File.join(ROOT, "itunes_match_list")

  module_function

  def norm(str)
    s = str.to_s.unicode_normalize(:nfkd)
    s = s.chars.reject { |c| c.ord >= 0x300 && c.ord <= 0x36F }.join
    s = s.downcase
    s = s.gsub(/\b(feat|ft)\.?\b.*$/, " ")
    s = s.gsub(/[\(\[][^\)\]]*remaster[^\)\]]*[\)\]]/i, " ")
    s = s.gsub(/-\s*remaster(ed)?\b.*$/i, " ")
    s = s.gsub(/[^\p{L}\p{N}]+/u, " ")
    s = s.gsub(/\s+/, " ").strip
    s
  end

  def track_key(artist, title)
    "#{norm(primary_artist(artist))}\u0001#{norm(title)}"
  end

  def primary_artist(artist)
    a = artist.to_s
    a = a.split(/\s*[,;]\s*/).first.to_s
    a = a.split(/\s+(?:feat\.?|ft\.?|&|x|vs\.?)\s+/i).first.to_s
    a.strip
  end

  def load_json(path)
    JSON.parse(File.read(path))
  end

  def write_json(name, data)
    path = File.join(BUILD, name)
    File.write(path, JSON.pretty_generate(data))
    path
  end

  def write_csv(name, rows, headers)
    path = File.join(BUILD, name)
    CSV.open(path, "w", write_headers: true, headers: headers) do |csv|
      rows.each { |r| csv << headers.map { |h| r[h] } }
    end
    path
  end

  def first_present(h, *keys)
    keys.each do |k|
      v = h[k]
      return v if v && v.to_s.strip != ""
    end
    nil
  end

  def year_of(*vals)
    vals.compact.each do |v|
      m = v.to_s.match(/(\d{4})/)
      return m[1] if m
    end
    nil
  end

  def similar_track?(a1, t1, a2, t2)
    nt1 = norm(t1); nt2 = norm(t2)
    return false if nt1.empty? || nt2.empty?
    title_ok = nt1 == nt2 || nt1.include?(nt2) || nt2.include?(nt1)
    return false unless title_ok
    na1 = norm(primary_artist(a1)); na2 = norm(primary_artist(a2))
    return true if na1.empty? || na2.empty?
    na1 == na2 || na1.include?(na2) || na2.include?(na1) ||
      (na1.split & na2.split).any?
  end
end
