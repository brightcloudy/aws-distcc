#!/usr/bin/env ruby
require 'aws-sdk'
require 'yaml'
require 'securerandom'

Aws.config.update({
  region: 'us-east-1',
  credentials: Aws::Credentials.new('AKIAIJDIDZRZQLPL445Q', 'UY2V8Eec4IttE7KETmpNR+ykbM7+qVU41QB4tukc')
})
ec2 = Aws::EC2::Client.new(region: 'us-east-1')
