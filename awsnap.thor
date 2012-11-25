require 'right_aws'
require 'yaml'
require 'time'
require 'chronic'

module Awsnap
  module Common
    API_HARD_LIMIT = 2000
    API_SAFE_LIMIT = 500

    def ec2
      access_key_id = ENV['AWS_ACCESS_KEY_ID']
      secret_access_key = ENV['AWS_SECRET_ACCESS_KEY']
      @@ec2 ||= RightAws::Ec2.new(access_key_id, secret_access_key)
    end

    def rule_set
      config = YAML::load_file(File.expand_path('./config/rules.yml'))
      config['rules'].each{|rule| rule}
    end

    def rule_supported? rule
      false
      true if rule.include? 'per_day' || 'per_week' || 'per_month' || 'per_year'
    end

    def create_snapshots volumes
      volumes.each do |volume|
        puts ec2.create_snapshot volume
      end
    end

    def delete_snapshots snapshots, options={}
      if options[:dry]
        snapshots.each_with_index {|s,i|
          if options[:verbose]
            if s.kind_of? Hash
              puts "#{i+1}: #{s[:aws_id]}"
            else
              puts "#{i+1}: #{s}"
            end
          end
        }
        puts "If this were not a test, #{snapshots.count} snapshots would have been destroyed."
      else
        if snapshots.count > API_SAFE_LIMIT
          snapshots = snapshots.drop(snapshots.count - API_SAFE_LIMIT)
          puts "WARNING: AWS API limit is #{API_HARD_LIMIT} per hour."
          puts "Deleting #{API_SAFE_LIMIT} snapshots during this run."
        end

        snapshots.each do |snapshot|
          ec2.delete_snapshot snapshot
          puts "Deleted #{snapshot}"
        end
      end
    end

    def retrieve_snapshots volume
      if volume
        snapshots = ec2.describe_snapshots filters: {"volume-id" => volume}
      else
        snapshots = ec2.describe_snapshots
      end
      puts snapshots
    end

    def prune_snapshots options={}
      if rule_set
        @per_hour, @per_day, @per_week, @per_month, @per_year = 0
        cutoff_date = Date.today

        if options[:dump]
          snapshots = ec2.describe_snapshots
          serialized = Marshal.dump snapshots
          File.open('./dumps/snapshots.txt', 'w') {|f| f.write serialized }
        end

        if options[:fixed]
          snapshots = Marshal.load(File.read('./dumps/snapshots.txt'))
        else
          snapshots = ec2.describe_snapshots
        end

        if options[:regex]
          filtered_snapshots = snapshots.keep_if{|s|
            (s[:tags]["Name"] &&
            !s[:tags]["Name"].scan(/#{options[:regex]}/i).empty?) ||
            (s[:aws_description] &&
            !s[:aws_description].scan(/#{options[:regex]}/i).empty?)
          }
        end

        filtered_snapshots = filtered_snapshots.map{|s| s[:aws_id]}
        delete_snapshots filtered_snapshots, options
      else
        puts "Add some rules to config/rules.yml"
      end
    end
  end

  class Snapshot < Thor
    include Thor::Actions
    include Common

    desc :find_by_volume, "Find snapshots created from a given volume"
    method_options volume: :string
    def find_by_volume
      retrieve_snapshots options[:volume]
    end

    desc :create, "Create snapshot for given volume(s)"
    method_options volumes: :array, required: true
    def create
      create_snapshots options[:volumes]
    end

    desc :delete, "Delete collection of snapshots"
    method_options snapshots: :array, required: true
    method_options dry: :boolean
    method_options verbose: :boolean
    def delete
      snapshots = options[:snapshots]
      delete_snapshots(snapshots, {dry: options[:dry], verbose: options[:verbose]})
    end

    desc :prune, "Prune snapshots with cron-style rules and regex matching."
    method_options dry: :boolean, default: true
    method_options fixed: :boolean
    method_options dump: :boolean
    method_options regex: :string
    def prune
      prune_snapshots({dry: options[:dry], fixed: options[:fixed],
                      dump: options[:dump], regex: options[:regex]})
    end
  end
end
