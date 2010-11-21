require 'helper'

class TestLinodeUtils < Test::Unit::TestCase
  module Source
    def say_hello(greeting, name)
      "#{greeting} #{name}"
    end
  end

  should "currying" do
    class A
      extend LinodeUtils::curry_module(Source, "hola")
    end
    assert_equal "hola ruby", A.say_hello("ruby")
  end
end
