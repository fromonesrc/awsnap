require 'debugger'
require 'right_aws'
require 'yaml'
require 'time'
require 'chronic'

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
        ec2.create_snapshot volume
      end
    end

    def prune_snapshots options={}
      if rule_set
        @per_hour, @per_day, @per_week, @per_month, @per_year = 0
        cutoff_date = Date.today

        if options[:fixed]
          # snapshots = ec2.describe_snapshots
          # serialized = Marshal.dump(snapshots)
          # File.open('./fixtures/snapshots_dump.txt', 'w') {|f| f.write(serialized) }

          snapshots = Marshal.load File.read('./fixtures/snapshots_dump.txt')
        else
          snapshots = ec2.describe_snapshots
        end

        snapshots.reverse!
        snapshots = snapshots.drop 6990

        debugger
        rule_set.each do |rules|
          rules.each do |k,v|
            if rule_supported? k
              instance_variable_set("@#{k.to_sym}", v)
            elsif k.include? 'days-ago'
              cutoff_date = Chronic.parse("#{v} days ago").to_date
            else
              p "Rule '#{k}' is not supported"
            end
          end

          #group snapshots by date
          snapshots = snapshots.group_by{|v|
            Time.parse(v[:aws_started_at]).to_date
          }

          debugger
          #remove snapshots from array if we do not want to delete them
          snapshots.each do |group|
            group.keep_if{|snapshot|
              started_at = Date.parse(snapshot[:aws_started_at])
              started_at < cutoff_date
            }
            group.drop_while{|i| i < @per_day } if @per_day
          end

          #remove snapshots where the count per timeframe is higher than needed
          debugger

          # debugger
          # snapshots = snapshots.each do |group|
            # snapshot.drop_while{|i| i < @per_day} if @per_day
          # end
          # break snapshots started_at into chunks of days
          # count snapshots for day chunk
          # drop excess snapshots

        end
        delete_snapshots(snapshots, options)
      else
        p "Add some rules to config/rules.yml"
      end
    end

    def delete_snapshots(filtered_snapshots, options={})
      filtered_snapshots

      if options[:dry]
        filtered_snapshots.each_with_index {|s,i|
          if options[:verbose]
            if s.kind_of? Hash
              p "#{i+1}: #{s[:aws_id]}"
            else
              p "#{i+1}: #{s}"
            end
          end
        }
        p "If this were not a test, #{filtered_snapshots.count} snapshots would have been destroyed."
      else
        filtered_snapshots.each do |snapshot|
          ec2.delete_snapshot snapshot
        end
      end
    end

    def retrieve_snapshots volume=nil
      if volume
        snapshots = ec2.describe_snapshots(filters: {'volume-id' => volume})
      else
        snapshots = ec2.describe_snapshots
      end
      snapshots
    end
  end

  class Snapshot < Thor
    include Thor::Actions
    include Common

    desc :find_by_volume, "Find snapshots created from a base volume"
    method_options volume: :string
    method_options filter: :string
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
    method_options dry: :boolean
    method_options fixed: :boolean
    def prune
      prune_snapshots({dry: options[:dry], fixed: options[:fixed]})
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
