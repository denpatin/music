#!/usr/bin/env ruby
require "find"

if ARGV.include?("--flatten")
  lines = STDIN.read.lines.map(&:chomp)
  lines.shift if lines.first == "Music Library"
  parsed = []
  lines.each do |line|
    m = line.match(/\A((?:(?:│   )|(?:    ))*)(?:├── |└── )(.*)\z/)
    next unless m
    parsed << [m[1].length / 4, m[2]]
  end
  stack = []
  out = []
  parsed.each_with_index do |(depth, name), i|
    stack = stack[0, depth]
    stack[depth] = name
    nxt = parsed[i + 1]
    out << stack.join("\u0001") if nxt.nil? || nxt[0] <= depth
  end
  puts out.sort.uniq
  exit
end

MEDIA = ["~/Music/Music/Media.localized", "~/Music/Music/Media"]
        .map { |p| File.expand_path(p) }
        .find { |p| Dir.exist?(p) }
abort "media folder not found" unless MEDIA

ROOTS = ["Music", "Apple Music"].map { |d| File.join(MEDIA, d) }.select { |d| Dir.exist?(d) }
AUDIO = /\.(mp3|m4a|m4p|aac|wav|flac|alac|aif|aiff|ogg|opus|wma)\z/i
BUNDLE = /\.movpkg\z/i

def strip_ext(name)
  name.sub(AUDIO, "").sub(BUNDLE, "")
end

def insert(tree, parts)
  node = tree
  parts.each { |p| node = (node[p] ||= {}) }
end

def walk(dir, rel, tree)
  Dir.children(dir).sort.each do |name|
    next if name.start_with?(".")
    path = File.join(dir, name)
    if File.directory?(path)
      if name =~ BUNDLE
        insert(tree, rel + [strip_ext(name)])
      else
        walk(path, rel + [name], tree)
      end
    elsif name =~ AUDIO
      insert(tree, rel + [strip_ext(name)])
    end
  end
end

def render(node, prefix, out)
  keys = node.keys.sort
  keys.each_with_index do |k, i|
    last = i == keys.size - 1
    out << "#{prefix}#{last ? '└── ' : '├── '}#{k}\n"
    child = node[k]
    render(child, prefix + (last ? "    " : "│   "), out) unless child.empty?
  end
end

tree = {}
ROOTS.each { |r| walk(r, [], tree) }

out = +"Music Library\n"
render(tree, "", out)
print out
