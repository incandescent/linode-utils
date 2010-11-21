require 'linode'
require 'linode_utils/java_properties'
require 'logger'
require 'sha1'

module LinodeUtils
  LOG = Logger.new(STDOUT)
  LOG.level = Logger::DEBUG
  
  LINODE_PROPS_FILE = File.expand_path("~/.linoderc")
  PUB_KEY_FILE = File.expand_path("~/.ssh/id_rsa.pub")

  CRITERIA_NONSWAP = Proc.new { |disk| disk.table[:type] != "swap" }
  CRITERIA_WRITABLE = Proc.new { |disk| disk.isreadonly == 0 }

  def self.read_user_linoderc
    JavaProperties.new(LINODE_PROPS_FILE).properties
  end
  
  def self.read_user_ssh_pub_key
    File.new(PUB_KEY_FILE).read
  end
  
  def self.secure_password
    srand
    seed = "--#{rand(10000)}--#{Time.now}--"
    Digest::SHA1.hexdigest(seed)[0,20]
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
            if val.eql? args[0]
              #LOG.debug "Discarding provided curried arg: " + args[0].to_s
              args.shift
            end
          end
          super(*(curried_args + args))
        end
      end

    end
  end

  def self.get_linode_by_label(api, label)
    LOG.debug "Looking for linode with label '#{label}'"
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

      LOG.debug "Waiting for Linode to shut down..."

      wait_for_jobs(api, id, job_id) do
        LOG.debug "Current linode status: " + (linode = api.linode.list(:LinodeID => id)[0]).status.to_s
      end

      LOG.debug "Linode has shut down"
    end
    
    def get_disks(api, linode_id)
      api.linode.disk.list(:linodeid => linode_id)
    end

    def delete_disks(api, linode_id, disks)
      LOG.debug "Deleting disks: " + disks.to_s
      job_ids = disks.map do |disk|
        LOG.debug "Deleting disk #{disk.to_s}"
        api.linode.disk.delete(:linodeid => linode_id, :diskid => disk.diskid).jobid
      end
      
      LOG.debug "Job ids" + job_ids.to_s
      LOG.debug "Waiting for disks to be deleted..."
      wait_for_jobs(api, linode_id, *job_ids)
    end

    def delete_non_swap_disks(api, linode_id)
      LOG.debug "Removing all non-swap disks..."
      disks = get_disks(api, linode_id)
      LOG.debug "disks: " + disks.to_s
      writable_non_swap_disks = disks.select(&CRITERIA_WRITABLE).select(&CRITERIA_NONSWAP)
      delete_disks(api, linode_id, writable_non_swap_disks)
    end
    
    def delete_configs(api, linode_id)
      LOG.debug "Deleting configurations..."

      api.linode.config.list(:LinodeID => linode_id).each do |config|
        LOG.debug "Deleting config #{config.label}..."
        api.linode.config.delete(:LinodeID => linode_id, :ConfigID => config.configid)
      end
    end

    def used_disk_space(api, linode)
      size = 0
      disks = get_disks(api, linode)
      LOG.debug "Disks: " + disks.to_s
      disks.each do |disk|
        size += disk.size
        LOG.debug "Size: " + size.to_s
      end
      size
    end
    
    def create_disk_from_stackscript(api, linode_id, options)
      LOG.debug "Creating disk..."
      
      LOG.debug "options: " + options.inspect
      
      size = options.delete(:size)
      distro = options.delete(:distro)
      stackscriptid = options.delete(:stackscriptid)
            
      raise ArgumentError.new(":size, :distro and :stackscriptid options must be specified") if size.nil? or distro.nil? or stackscriptid.nil?
      
      rootPass = options.delete(:rootPass) || LinodeUtils.secure_password


      distros = api.avail.distributions.select do |d|
        LOG.debug distro.class.to_s
        case distro
          when String then d.label == distro
          when Regexp then d.label =~ distro
          else raise ArgumentError.new(":distro option must be String or Regex")
        end
      end

      raise "Could not find Distro matching #{distro}" if distros.empty?

      options.delete_if do |key, value|
        value.nil?
      end

      params = {
        :LinodeID => linode_id,
        :DistributionID => distros[0].distributionid,
        :Size => size,
        :Label => "Disk generated via api",
        :rootPass => rootPass
      }

      if stackscriptid
        params[:StackScriptID] = stackscriptid
        params[:Label] = "Disk generated from Stack Script #{stackscriptid}"
        if options.size > 0
          LOG.debug "StackScript vars: " + options.inspect
          params[:StackScriptUDFResponses] = options.to_json  
        end
      end

      LOG.debug "Params: " + params.inspect

      disk = api.linode.disk.createfromstackscript(params)

      LOG.debug "Waiting for disk creation..."

      LOG.debug "Disk job id: #{disk.jobid}"

      raise "Some jobs failed" unless wait_for_jobs(api, linode_id, disk.jobid)
  
      disk.diskid
    end
  
  
    def wait_for_jobs(l, linode_id, *job_ids)
      success = true
      LOG.debug "Waiting for jobs: " + job_ids.to_s
      while job_ids.length > 0 do
        yield if block_given?
        LOG.debug "Sleeping"
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
              LOG.debug "Job #{c.jobid} completed " + (success  ? "" : "un") + "successfully"
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
  LOG = LinodeUtils::LOG
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
    LOG.info "Loaded Linode #{@linode.linodeid}:"
    y @linode
    
    # extend ourselves with versions of the LinodeUtils::LinodeOperations fuctions curried
    # with the api and linode_id arguments
    self.extend LinodeUtils.curry_module(LinodeUtils::LinodeOperations, @api, @linode.linodeid)
  end
  
  def shutdown
    LOG.info "Shutting down Linode #{@label} (#{@linode.linodeid})..."
    Machine.shutdown_linode(api, @linode.linodeid)
    reload
  end
  
  def reload
    list = api.linode.list(:linodedid => linode.linodeid)
    raise "Error reloading linode state" if list.nil? or list.empty? or list[0].nil?
    @linode = list[0]
  end
end
