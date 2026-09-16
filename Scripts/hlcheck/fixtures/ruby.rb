#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'lib/helpers'
load "config.rb"

# Documentation for the module.
module Atelier
  # Documentation for the class,
  # spanning two lines.
  class Session < Base
    include Comparable
    extend Forwardable
    attr_reader :name, :root
    attr_accessor :title

    VERSION = "1.2.3"
    MAX_TABS = 9
    @@count = 0

    # Documentation for the constructor.
    def initialize(name, root = Dir.pwd, *args, opts: {}, **rest, &block)
      @name = name
      @root = root
      @@count += 1
      super()
    end

    def self.create(name)
      new(name)
    end

    def title=(value)
      @title = value.to_s
    end

    def <=>(other)
      name <=> other.name
    end

    def to_s
      "Session #{@name} at #{root.upcase}\n\té"
    end

    private

    def helper
      yield if block_given?
      return nil unless defined?(@root)
    end
  end
end

# Not a doc comment: followed by a blank line and an assignment.

counter = 0

def free_function(x, y = 2.5, z: 0x1f)
  result = x ** 2 + y * 0b1010 - 1_000 / 3.0e-2 % 7
  result <<= 1
  ratio = 3r + 2i
  if result > 10 && x != y || !z
    puts "big"
  elsif result == 0
    puts 'zero'
  else
    print `ls`
  end

  case x
  when 1, 2 then :small
  when Integer
    :int
  else
    :other
  end

  case [x, y]
  in [Integer => a, Float]
    a
  in { name: String => n }
    n
  end

  for i in 0..3 do
    next if i.odd?
    break
  end
  while x < 100 do x *= 2 end
  until x.zero? do x -= 1 end
  begin
    raise ArgumentError, "bad" if x.nil?
  rescue ArgumentError, TypeError => e
    warn e.message
    retry if false
  ensure
    x&.freeze
  end
  return x
end

adder = ->(a, b) { a + b }
doubler = Proc.new { |v| v * 2 }
[1, 2, 3].each_with_index do |item, idx|
  puts "#{item}: #{idx}"
end
[1, 2, 3].map(&:to_s)
hash = { key: "value", "str" => 1, :sym => nil, other: true }
hash[:key] = false
words = %w(alpha beta)
syms = %i(one two)
re = /^[a-z]+\d*$/i
matched = "abc" =~ re
ch = ?a
str = <<~HEREDOC
  Heredoc #{hash[:key]} text
HEREDOC
$stdout.puts __FILE__, __LINE__, __method__, ENV["HOME"], ARGV
alias_method :old, :new_name
alias old2 new_name
undef old2
Atelier::Session.create("x").title = "T"
obj = Atelier::Session.new("y")
puts obj.name, Math::PI, self, nil
flag = true and false
other = not(flag) or flag
value = flag ? 1 : 2
