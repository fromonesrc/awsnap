require 'right_aws'
require 'yaml'

module Awsnap
  module Common
    def credentials
      YAML::load_file(File.expand_path('./config/credentials.yml'))
    end

    def ec2
      access_key_id = credentials['access_key_id']
      secret_access_key = credentials['secret_key_id']
      @@ec2 ||= RightAws::Ec2.new(access_key_id, secret_access_key)
    end

    def rules
      config = YAML::load_file(File.expand_path('./config/rules.yml'))
      rules = config['rules'].each{|rule| rule}
      p rules
    end

    def create_snapshots volumes
      volumes.each do |volume|
        ec2.create_snapshot volume
      end
    end

    def delete_snapshots(snapshots=nil, options={})
      rules = options[:rules]
      filtered_snapshots = []
      if snapshots && rules
        snapshots = snapshots.each{|snapshot| {'snapshot-id' => snapshot}}.join(',')
        ec2.describe_snapshots(filters: rules).each do |snapshot|
          filtered_snapshots << snapshot
        end
      elsif snapshots
        filtered_snapshots = snapshots
      elsif rules
        ec2.describe_snapshots(filters: rules).each do |snapshot|
          filtered_snapshots << snapshot
        end
      else
        p "Must provide a snapshot or rule set"
      end

      if options[:dry]
        filtered_snapshots.each_with_index {|s,i| p "#{i+1}: #{s}"}
        p "If this were not a test, those snapshots would have been deleted."
      elsif filtered_snapshots.size > 1
        filtered_snapshots.each do |snapshot|
          ec2.delete_snapshot snapshot
        end
      else
        ec2.delete_snapshot snapshots.first
      end
    end

    def retrieve_snapshots rules={}
      if rules.present?
        snapshots = ec2.describe_snapshots(filters: {'volume-id' => rules})
      else
        snapshots = ec2.describe_snapshots
      end
      snapshots.map{|snapshot| snapshot[:aws_id]}.join(',')
    end
  end

  class Snapshot < Thor
    include Thor::Actions
    include Common

    desc :find_by_volume, "Find snapshots created from a base volume"
    method_option volume: :string, aliases: 'v'
    method_option filter: :string, aliases: 'f'
    def find_by_volume
      p retrieve_snapshots(options[:filter])
    end

    desc :create, "Create snapshot for given volume(s)"
    method_option volumes: :array, aliases: 'v', required: true
    method_option region: :string, aliases: 'r', default: 'us-east-1a'
    def create
      create_snapshot options[:volumes]
    end

    desc :prune, "Prune snapshots with cron-style rules."
    #default: all for 24 hours, daily for two weeks, weekly prior
    #(* 24h) (1/d) (1/w)
    #* * 1
    method_option yearly: :boolean, aliases: 'annually a y'
    method_option monthly: :boolean, aliases: 'm'
    method_option weekly: :boolean, aliases: 'w'
    method_option daily: :boolean, aliases: 'd'
    method_option hourly: :boolean, aliases: 'h'
    method_option rules: :string
    method_options dry: :boolean
    def prune
      rules
      # delete_snapshots retrieve_snapshots({
        # rules: options[:rules],
        # dry: options[:dry]})
    end

    desc :delete, "Delete collection of snapshots"
    method_options snapshots: :array, required: true
    method_options dry: :boolean
    def delete
      snapshots = options[:snapshots]
      delete_snapshots snapshots, {dry: options[:dry]}
      rescue Exception
        p "something went wrong"
    end
  end
end
