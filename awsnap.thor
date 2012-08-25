require 'right_aws'
require 'yaml'

module Awsnap
  module Common
    def credentials
      YAML::load_file(File.expand_path('./config/credentials.yml'))
    end

    def create_snapshot(volumes)
        access_key_id = credentials['access_key_id']
        secret_access_key = credentials['secret_access_key']
        raws = RightAws::Ec2.new(access_key_id, secret_access_key)
        volumes.each do |volume|
          raws.create_snapshot(volume)
        end
    end
  end

  class Snapshot < Thor
    include Thor::Actions
    include Common

    desc :create, "Create snapshot for given volume(s)"
    method_options volumes: :array, required: true
    def create
      create_snapshot options[:volumes]
    end
  end
end
