require 'spec_helper'
require 'elba/client'

describe Elba::Client do
  let(:region)     { 'eu-west-1' }
  let(:access)     { 'JUST_TESTING' }
  let(:connection) { Fog::AWS::ELB.new(aws_access_key_id: access, region: region) }

  let(:elb) do
    connection.tap do |c|
      # creates an ELB if none have been created yet
      c.create_load_balancer([region], 'elba-test') if c.load_balancers.empty?
    end.load_balancers.last
  end

  let(:ec2)      { Fog::Compute::AWS.new(aws_access_key_id: access, region: region) }
  let(:instance) { ec2.servers.create region: region }

  subject { described_class.new connection }

  describe 'interface' do
    it 'responds to attach' do
      subject.should.respond_to? :attach
    end

    it 'responds to detach' do
      subject.should.respond_to? :detach
    end
  end

  describe '#attach' do
    context 'no load balancer specified' do
      it 'raises an error if no load balancers are available' do
        expect { subject.attach(nil, nil) }.to raise_error described_class::NoLoadBalancerAvailable
      end

      it 'raises an error if more than 1 load balancers available' do
        subject.stub load_balancers: [double, double]
        expect { subject.attach(nil, nil) }.to raise_error described_class::MultipleLoadBalancersAvailable
      end
    end

    context 'load balancer specified' do
      it 'raises an error if the load balancer can\'t be fond' do
        expect {
          subject.attach(instance, 'unknown')
        }.to raise_error described_class::LoadBalancerNotFound
      end

      it 'raises an error if instance is already attached to the load balancer' do
        # makes sure the instance is ready before playing with it!
        instance.wait_for { ready? }
        subject.attach(instance.id, elb.id)

        expect {
          subject.attach(instance.id, elb.id)
        }.to raise_error described_class::InstanceAlreadyAttached
      end

      it 'returns true if instance has been successfuly added' do
        subject.attach(instance.id, elb.id).should be_true
      end

      it 'returns false if instance can\'t be added' do
        elb.class.any_instance.stub :register_instances

        subject.attach(instance.id, elb.id).should be_false
      end
    end
  end

  describe '#detach' do
    it 'raises an error if the instance is not attached to any elb'  do
      expect {
        subject.detach instance.id
      }.to raise_error described_class::LoadBalancerNotFound
    end

    it 'returns the elb name if instance has been removed from its load balancer' do
      subject.attach(instance.id, elb.id)

      subject.detach(instance.id).should eql elb.id
    end

    it 'returns nil if instance can\'t be removed from its load balancer' do
      subject.attach(instance.id, elb.id)
      elb.class.any_instance.stub :deregister_instances

      subject.detach(instance.id).should be_nil
    end
  end
end
