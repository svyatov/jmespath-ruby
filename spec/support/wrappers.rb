# frozen_string_literal: true

class Arrayish
  def initialize(value)
    @value = value
  end

  def to_ary
    @value
  end
end

class Hashish
  def initialize(value)
    @value = value
  end

  def to_hash
    @value
  end
end
