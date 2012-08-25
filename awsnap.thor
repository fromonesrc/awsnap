require 'right_aws'
require 'yaml'

module Awsnap
  module Common
    def credentials
      YAML::load_file(File.expand_path('./config/credentials.yml'))
    end

    def raws
      access_key_id = credentials['access_key_id']
      secret_access_key = credentials['secret_access_key']
      RightAws::Ec2.new(access_key_id, secret_access_key)
    end

    def create_snapshots(volumes)
      volumes.each do |volume|
        raws.create_snapshot(volume)
      end
    end

    def delete_snapshots(snapshots)
      snapshots.each do |snapshot|
        raws.delete_snapshot(snapshot)
      end
    end
  end

  class Snapshot < Thor
    include Thor::Actions
    include Common

    desc :create, "Create snapshot for given volume(s)"
    method_options volumes: :array, aliases: '-v', required: true
    def create
      create_snapshot options[:volumes]
    end

    desc :delete, "Delete snapshots with cron-like rules"
    method_options snapshots: :array, required: true
    method_options yearly: :boolean, aliases: 'annually -a -y'
    method_options monthly: :boolean, aliases: '-m'
    method_options weekly: :boolean, aliases: '-w'
    method_options daily: :boolean, aliases: '-d'
    method_options hourly: :boolean, aliases: '-h'
    method_options rules: :string, aliases: '-r'
    def delete
      delete_snapshot options[:snapshots]
    end
  end
end
