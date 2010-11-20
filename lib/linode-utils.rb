require 'linode'
require 'linode_utils/java_properties'

class Machine
  attr_reader :api

  def initialize(api)
    @api = api
  end
  
  
end

module LinodeUtils
  LINODE_PROPS_FILE = File.expand_path("~/.linoderc")
  PUB_KEY_FILE = File.expand_path("~/.ssh/id_rsa.pub")

  def self.read_user_linoderc
    JavaProperties.new(LINODE_PROPS_FILE).properties
  end
  
  def self.read_user_ssh_pub_key
    File.new(PUB_KEY_FILE).read
  end
end
