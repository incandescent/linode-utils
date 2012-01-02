#!/usr/bin/env ruby

require 'rubygems'
gem 'thor'
gem 'linode'
gem 'linode-utils'
require 'thor'
require 'linode'
require 'linode-utils'

class LinodeCommand < Thor
  desc "boot {nodename}", "shutdown node config"
  method_options :wait => :boolean
  def boot(name)
  end

  desc "boot {nodename}", "shutdown node config"
  method_options :wait => :boolean
  def boot(name)
  end

  desc "deprovision {nodename}", "shutdown and delete node disks and config"
  method_options :group => :string
  def deprovision(name, opts)
    puts "Deprovisioning #{name}"
    puts opts["group"]
  end

  desc "provision {nodename} {configfile}", "provision a node with specified config"
  def provision(name, config_file, opts)
    puts "Hello"
  end
end

LinodeCommand.start
