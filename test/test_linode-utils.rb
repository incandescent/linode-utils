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
  
  should "construct Linode config" do
    config = LinodeUtils::LinodeConfig.build LinodeUtils.init_api do
      label "My favorite config"
      
      kernel /Latest 2\.6 Paravirt(?!.*x86_64.*)/
      
      comment "first comment"
      disk 0, :root_device => true
      
      comment "second comment"
      disk 1
    end
    p config.to_hash
  end
end
