require 'right_aws'

class Awsnap < Thor
  include Thor::Actions

  desc :create_snapshots, "create snapshot VOLUME_ID"
  method_option :volumes, :type=>:string, :required=>true
  def create_snapshots
    volumes.each{|vol|
      create_snapshot(vol)
    }
  end

  desc "delete old snapshots"
  def delete_snapshots

  end
end
