require 'linode'
require 'linode_utils/java_properties'

module LinodeUtils
  LINODE_PROPS_FILE = File.expand_path("~/.linoderc")
  PUB_KEY_FILE = File.expand_path("~/.ssh/id_rsa.pub")

  def self.read_user_linoderc
    JavaProperties.new(LINODE_PROPS_FILE).properties
  end
  
  def self.read_user_ssh_pub_key
    File.new(PUB_KEY_FILE).read
  end
  
  # Takes a module, and curries all public instance methods on it
  # with the given args
  # The argument must be a module and it should be stateless!
  def self.curry_module(mod, *curried_args)
    m = Module.new do
      include mod

      public
      
      mod.public_instance_methods.each do |m|
        #puts "Defining #{m.to_sym}"
        a = define_method(m.to_sym) do |*args|
          # if the leading args are the same value and type
          # as the curried args, discard them
          for val in curried_args do
            break if args.empty?
            args.shift if val.eql? args[0]
          end
          super(*(curried_args + args))
        end
      end

    end
  end

  def self.select_swap(swap = true)
    Proc.new { |disk| (disk.table[:type] == "swap") == swap }
  end
  
  def self.select_readonly(readonly = true)
    Proc.new { |disk| (disk.isreadonly == 0) == readonly }
  end

  def self.get_linode_by_label(api, label)
    puts "Looking for linode with label '#{label}'"
    api.linode.list.each do |n|
      if n.label == label
        return n
      end
    end
    nil
  end

  # this needs some curry... http://rubymurray.rubyforge.org/
  module LinodeOperations
    
    def shutdown_linode(api, id)
      job_id = api.linode.shutdown(:LinodeID => id).jobid

      puts "Waiting for Linode to shut down..."

      wait_for_jobs(api, id, job_id) do
        puts "Current linode status: " + (linode = api.linode.list(:LinodeID => id)[0]).status.to_s
      end

      puts "Linode has shut down"
    end
    
    def get_disks(api, linode_id)
      api.linode.disk.list(:linodeid => linode_id)
    end

    def delete_disks(api, linode_id, disks)
      job_ids = disks.map do |disk|
        puts "Deleting disk #{disk.to_s}"
        api.linode.disk.delete(:linodeid => linode_id, :diskid => disk.diskid).jobid
      end
      
      p "Job ids"
      p job_ids
      puts "Waiting for disks to be deleted..."
      wait_for_jobs(api, linode_id, *job_ids)
    end

    def delete_non_swap_disks(api, linode_id)
      puts "Removing all non-swap disks..."
      delete_disks(api, linode_id, get_disks(api, linode_id).select(&LinodeUtils.select_swap(false)).select(&LinodeUtils.select_readonly(false)))
    end

    def wait_for_jobs(l, linode_id, *job_ids)
      success = true
      while  job_ids.length > 0 do
        yield if block_given?
        sleep(5)
        jobs = l.linode.job.list(:LinodeID => linode_id)
        #p job_ids
        Array.new(job_ids).each do |job_id|
          raise ArgumentError.new("nil job id") if job_id.nil?
          print '.'
          #p "Current job: " + job_id.to_s
          run_jobs = jobs.select { |j| j.jobid == job_id }
          #p "Run jobs: " + run_jobs.to_s
          completed_jobs = run_jobs.select { |cj| !cj.host_finish_dt.nil? && cj.host_finish_dt != "" }
          #p "Completed jobs: " + completed_jobs.to_s
          if run_jobs.empty? or completed_jobs.length > 0
            completed_jobs.each do |c| 
              #p "Completed job"
              success = (c.host_success == 1)
              puts "Job #{c.jobid} completed " + (success  ? "" : "un") + "successfully"
              job_ids.delete(c.jobid)
              success &= success
            end
          end
        end
      end
      success
    end
  end
end

class Machine
  # This is a group which is used as a failsafe to prevent inadvertent destruction
  # of the wrong linode!
  # Add api-accessible linodes to this LPM group
  AUTOMATABLE_DISPLAY_GROUP = "automatable"
  
  attr_reader :api, :label, :linode

  def initialize(api, label)
    @api = api
    @label = label
    @linode = LinodeUtils.get_linode_by_label(api, label)
    raise "Could not find Linode #{name}" if @linode.nil?
    if @linode.lpm_displaygroup != AUTOMATABLE_DISPLAY_GROUP
      raise "Linode is not in the api-accessible group #{AUTOMATABLE_DISPLAY_GROUP}!"
    end
    puts "Loaded Linode #{@linode.linodeid}:"
    y @linode
    
    self.extend LinodeUtils.curry_module(LinodeUtils::LinodeOperations, @api, @linode.linodeid)
  end
  
  def shutdown
    puts "Shutting down Linode #{@label} (#{@linode.linodeid})..."
    Machine.shutdown_linode(api, @linode.linodeid)
    reload
  end
  
  def reload
    list = api.linode.list(:linodedid => linode.linodeid)
    raise "Error reloading linode state" if list.nil? or list.empty? or list[0].nil?
    @linode = list[0]
  end
  
  def delete_non_swap_disks
    Machine.delete_non_swap_disks
  end
  
  #def used_disk_space
  #  size = 0
  #  get_disks.select(LinodeUtils.select_swap(false)).each do |disk|
  #    size += disk.size
  #  end
  #  size
  #end
end
