#!/usr/bin/env ruby
require 'aws-sdk'
require 'yaml'
require 'trollop'
require 'securerandom'

opts = Trollop::options do
  opt :instance_type, "Instance type", :type => :string, :default => "c4.large", :short => "-t", :multi => false
  opt :num_instances, "Number of instances", :type => :int, :default => 1, :short => "-n", :multi => false
  opt :dry_run, "Dry run (do not actually spawn instance)", :type => :bool, :default => true, :short => "-d", :multi => false
  opt :price_check, "Check spot pricing but do not spawn instances", :type => :bool, :default => false, :short => "-p", :multi => false 
  opt :ami, "AMI ID for spot instances", :type => :string, :default => nil, :short => "-a", :multi => false
  opt :list_instance_types, "List available instance types", :type => :bool, :default => false, :multi => false
  opt :multiplier, "Specify spot instance pricing multiplier (default 1.5)", :type => :float, :default => 1.5, :multi => false
  version "v0.1"
end
if (opts[:list_instance_types])
  puts "t1.micro, m1.small, m1.medium, m1.large, m1.xlarge, m3.medium, m3.large, m3.xlarge, m3.2xlarge, m4.large, m4.xlarge, m4.2xlarge, m4.4xlarge, m4.10xlarge, t2.nano, t2.micro, t2.small, t2.medium, t2.large, m2.xlarge, m2.2xlarge, m2.4xlarge, cr1.8xlarge, i2.xlarge, i2.2xlarge, i2.4xlarge, i2.8xlarge, hi1.4xlarge, hs1.8xlarge, c1.medium, c1.xlarge, c3.large, c3.xlarge, c3.2xlarge, c3.4xlarge, c3.8xlarge, c4.large, c4.xlarge, c4.2xlarge, c4.4xlarge, c4.8xlarge, cc1.4xlarge, cc2.8xlarge, g2.2xlarge, cg1.4xlarge, r3.large, r3.xlarge, r3.2xlarge, r3.4xlarge, r3.8xlarge, d2.xlarge, d2.2xlarge, d2.4xlarge, d2.8xlarge"
  exit
end
if !(opts[:price_check]) and (opts[:ami].nil?)
  Trollop::die :ami, "is required"
end
if !(File.exist?("./credentials.yml"))
  Trollop::die "credentials.yml must exist in the current directory"
end

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
create_spot_token = SecureRandom.hex
#fedora_images = ec2.describe_images({ executable_users: ['all'], filters: [{name: "name", values: ["*Fedora-Cloud-Base-23*PV-standard*"]}] })
#fedora_image_id = fedora_images.images.collect{ |x| [x.creation_date, x.image_id] }.sort_by{ |date, id| id}.first[1]
spot_price_current = ec2.describe_spot_price_history({
  start_time: Time.now,
  end_time: Time.now,
  instance_types: [opts[:instance_type]]
})
current_spots = spot_price_current.spot_price_history.collect { |x| [x.spot_price, x.availability_zone, x.timestamp] }.sort_by { |price, zone, time| time}.uniq { |price, zone, time| zone }.sort_by { |price, zone, time| price}
avgprice = current_spots.each.collect { |price, zone, time| price }.inject(0.0) { |sum, ea| sum + ea.to_f } / current_spots.length
avgprice = avgprice.round(4)
current_spots.each do |price, zone, time|
  puts "Zone " + zone + ": " + price
end
puts "Average Price: " + avgprice.to_s
new_price = avgprice.to_f * opts[:multiplier]
new_price = new_price.round(4)
puts "Chosen Price: " + new_price.to_s
spot_zone = current_spots.first[1]
puts "Chosen Zone: " + spot_zone
if (opts[:price_check])
  exit
end
response_create = ec2.request_spot_instances({
  dry_run: opts[:dry_run],
  client_token: create_spot_token,
  spot_price: new_price.to_s,
  instance_count: opts[:num_instances],
  type: "one-time",
  availability_zone_group: spot_zone,
  launch_specification: {
      placement: {
        availability_zone: spot_zone
      },
      image_id: opts[:ami],
      key_name: "aws",
      security_group_ids: ["sg-6d878307"],
      instance_type: opts[:instance_type],
      monitoring: {
        enabled: true,
      }
    },
})
if (opts[:dry_run])
  exit
end
req_id = response_create.spot_instance_requests[0].spot_instance_request_id
ec2.wait_until(:spot_instance_request_fulfilled, spot_instance_request_ids: [ req_id ]) do |waiter|
  waiter.delay = 2
  waiter.before_attempt do |attempts|
    print "Attempt #" + (attempts + 1).to_s + "... "
  end
  waiter.before_wait do |attempts, response|
    puts response.spot_instance_requests[0].status.code
  end
end
new_instance = ec2.describe_instances({
  filters: [
  {
    name: "spot-instance-request-id",
    values: [req_id]
  }]
})
the_instance = new_instance.reservations[0].instances.each do |instance|
  puts "New Instance " + instance.instance_id
  puts "Public IP: " + instance.public_ip_address
  puts "Private IP: " + instance.private_ip_address
end
puts "done"
