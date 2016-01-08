#!/usr/bin/env ruby
require 'yaml'
require 'aws-sdk'
require 'trollop'
require 'securerandom'

credentialfile = begin
  YAML.load(File.read('credentials.yml'))
rescue ArgumentError => e
  Trollop::die "Invalid credentials file."
end
Aws.config[:region] = "us-east-1"
ec2 = Aws::EC2::Client.new(
  access_key_id: credentialfile[:access_key_id],
  secret_access_key: credentialfile[:secret_access_key]
)

opts = Trollop::options do
  opt :id, "Image ID", :type => :strings, :short => "-i", :multi => true
  opt :owner, "AMI owner", :type => :strings, :multi => true
  opt :filter, "Filter specification", :type => :strings, :multi => true, :short => "-f"
  version "v0.1"
end

describe_images_struct = Hash.new()

if (opts[:id].length != 0)
  image_ids = opts[:id].collect { |x| x[0] }
  describe_images_struct.store(:image_ids, image_ids)
end

if (opts[:owner].length != 0)
  owners = opts[:owner].collect { |x| x[0] }
  describe_images_struct.store(:owners, owners)
end

if (opts[:filter].length != 0)
  filters = []
  opts[:filter].collect { |x| x[0].split('=') }.each { |filter| filters.push({ name: filter[0], values: [filter[1]]}) }
  describe_images_struct.store(:filters, filters)
end

puts describe_images_struct.inspect()
if (describe_images_struct == [])
  Trollop::die "One of id, owner, or filter must be specified!"
end
resp = ec2.describe_images(describe_images_struct)
resp.images.each do |image|
  puts image.name
  puts image.description
end
